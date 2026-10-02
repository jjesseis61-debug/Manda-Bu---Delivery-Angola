import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, Switch, Text, View } from 'react-native';

import { CampoCodigo } from '@/components/CampoCodigo';
import { Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { criarPedido, lerEnderecos, lerSaldo, orcamento as pedirOrcamento, usarCredito } from '@/lib/api';
import { type LinhaCarrinho, useCarrinho } from '@/lib/carrinho';
import { novoId } from '@/lib/dispositivo';
import { formatarKz, mensagemCodigo, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Endereco, Orcamento } from '@/lib/tipos';

/** O que segue para o servidor: o prato, a quantidade e os ids das opções (o preço é calculado lá) */
function itemDoPedido(l: LinhaCarrinho) {
  return { cardapio_id: l.item.id, qtd: l.qtd, ...(l.opcoes.length > 0 ? { opcoes: l.opcoes.map((o) => o.id) } : {}) };
}

/** Checkout: endereço, orçamento do servidor, código de convite (C2) e saldo do programa */
export default function Carrinho() {
  const router = useRouter();
  const { perfil, ligada } = useSessao();
  const carrinho = useCarrinho();
  const [enderecos, setEnderecos] = useState<Endereco[] | null>(null);
  const [pontoId, setPontoId] = useState<string | null>(null);
  const [orc, setOrc] = useState<Orcamento | null>(null);
  const [erroOrc, setErroOrc] = useState<string | null>(null);
  const [saldo, setSaldo] = useState(0);
  const [usarSaldo, setUsarSaldo] = useState(false);
  const [observacoes, setObservacoes] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [aEnviar, setAEnviar] = useState(false);
  const [versao, setVersao] = useState(0);
  // Id do pedido, mantido entre tentativas: retentar depois de uma falha de rede não cria outro pedido.
  // Muda quando mudam os pratos, o endereço ou o grupo, porque passa a ser outro pedido.
  const idPedido = useRef<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      lerEnderecos()
        .then((e) => {
          setEnderecos(e);
          setPontoId((actual) => actual ?? e[0]?.ponto_entrega_id ?? null);
        })
        .catch((e) => setErro(mensagemErro(e)));
      if (perfil && ligada('indicacao')) {
        lerSaldo(perfil.cliente_id)
          .then((s) => setSaldo(s?.saldo_disponivel ?? 0))
          .catch(() => setSaldo(0));
      }
    }, [perfil, ligada]),
  );

  // Pedido de grupo (C13): o ponto é o do grupo; não se escolhe endereço
  const grupo = ligada('pedidos_grupo') ? carrinho.grupo : null;

  // O valor a pagar vem sempre do servidor (preços do cardápio, taxa da zona, desconto confirmado)
  useEffect(() => {
    setOrc(null);
    setErroOrc(null);
    if ((!pontoId && !grupo) || carrinho.linhas.length === 0) return;
    pedirOrcamento(
      carrinho.linhas.map(itemDoPedido),
      grupo ? null : pontoId,
      grupo?.grupoId ?? null,
      carrinho.cozinhaActual?.id ?? null,
    )
      .then(setOrc)
      .catch((e) => setErroOrc(mensagemErro(e)));
  }, [carrinho.linhas, pontoId, grupo, carrinho.cozinhaActual?.id, versao]);

  useEffect(() => {
    idPedido.current = null;
  }, [carrinho.linhas, pontoId, grupo]);

  const valorSaldo = orc && usarSaldo ? Math.min(saldo, orc.total) : 0;

  async function confirmar() {
    if (!perfil || (!pontoId && !grupo) || !orc) return;
    setErro(null);
    setAEnviar(true);
    try {
      idPedido.current ??= novoId();
      const id = await criarPedido({
        id: idPedido.current,
        clienteId: perfil.cliente_id,
        pontoEntregaId: grupo ? null : pontoId,
        grupoId: grupo?.grupoId ?? null,
        cozinhaId: grupo ? null : (carrinho.cozinhaActual?.id ?? null),
        itens: carrinho.linhas.map(itemDoPedido),
        observacoes,
      });
      let saldoFalhou = false;
      if (valorSaldo > 0) {
        await usarCredito(id, valorSaldo).catch(() => {
          saldoFalhou = true;
        });
      }
      carrinho.limpar();
      if (grupo) router.replace({ pathname: '/grupo/[codigo]', params: { codigo: grupo.codigo } });
      else router.replace({ pathname: '/pedido/[id]', params: { id, fim: '1', ...(saldoFalhou ? { saldo: 'falhou' } : {}) } });
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAEnviar(false);
    }
  }

  if (carrinho.linhas.length === 0) {
    return (
      <Ecra>
        <Paragrafo suave>O carrinho está vazio.</Paragrafo>
        <Botao titulo="Ver o cardápio" aoCarregar={() => router.replace('/inicio')} />
      </Ecra>
    );
  }

  return (
    <Ecra>
      {ligada('multi_cozinha') && carrinho.cozinhaActual && <Subtitulo>{carrinho.cozinhaActual.nome}</Subtitulo>}
      {carrinho.linhas.map((l) => (
        <View key={l.chave} style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.m }}>
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 15 }}>{l.item.nome}</Text>
            {l.opcoes.length > 0 && <Text style={{ color: cores.textoSuave }}>{l.opcoes.map((o) => o.nome).join(', ')}</Text>}
          </View>
          <Pressable accessibilityLabel="Menos" onPress={() => carrinho.alterar(l.chave, l.qtd - 1)} hitSlop={8}>
            <Text style={{ fontSize: 22, color: cores.marca, width: 24, textAlign: 'center' }}>−</Text>
          </Pressable>
          <Text style={{ fontSize: 16, fontWeight: '600', minWidth: 20, textAlign: 'center' }}>{l.qtd}</Text>
          <Pressable accessibilityLabel="Mais" onPress={() => carrinho.alterar(l.chave, l.qtd + 1)} hitSlop={8}>
            <Text style={{ fontSize: 22, color: cores.marca, width: 24, textAlign: 'center' }}>+</Text>
          </Pressable>
        </View>
      ))}

      {grupo && (
        <Cartao>
          <Text style={{ fontWeight: '700' }}>Pedido de grupo · entrega às {grupo.hora}</Text>
          <Paragrafo suave>Chega com os pedidos dos colegas, no local do grupo.</Paragrafo>
          <Botao titulo="Pedir só para mim" variante="texto" aoCarregar={() => carrinho.definirGrupo(null)} />
        </Cartao>
      )}
      {!grupo && <Subtitulo>Entregar em</Subtitulo>}
      {!grupo && enderecos && enderecos.length === 0 && (
        <Aviso>Ainda não tens endereços de entrega.</Aviso>
      )}
      {!grupo && enderecos && enderecos.length > 0 && (
        <Escolha
          opcoes={enderecos.map((e) => ({
            valor: e.ponto_entrega_id,
            rotulo: `${e.nome ?? 'Endereço'}${e.pontos_entrega?.zonas?.nome ? ` · ${e.pontos_entrega.zonas.nome}` : ''}`,
          }))}
          valor={pontoId ?? ''}
          aoMudar={setPontoId}
        />
      )}
      {!grupo && <Botao titulo="Adicionar endereço" variante="texto" aoCarregar={() => router.push('/enderecos/novo')} />}

      {/* C2: no checkout do 1.º pedido; depois de ligar, o orçamento é pedido de novo ao servidor */}
      <CampoCodigo aoLigar={() => setVersao((v) => v + 1)} />

      {erroOrc && <Aviso tipo="erro">{erroOrc}</Aviso>}
      {orc && (
        <Cartao>
          <Linha esquerda="Subtotal" direita={formatarKz(orc.subtotal)} />
          {grupo ? (
            <Linha
              esquerda="Entrega (dividida no fecho do grupo)"
              direita={orc.taxa_grupo_estimada ? `cerca de ${formatarKz(orc.taxa_grupo_estimada)}` : formatarKz(0)}
            />
          ) : (
            <Linha esquerda={`Entrega${orc.zona_nome ? ` (${orc.zona_nome})` : ''}`} direita={formatarKz(orc.taxa_entrega)} />
          )}
          {orc.desconto > 0 && (
            <Linha esquerda="Desconto de convite" direita={`−${formatarKz(orc.desconto)}`} />
          )}
          {valorSaldo > 0 && <Linha esquerda="Saldo do Convida e Ganha" direita={`−${formatarKz(valorSaldo)}`} />}
          <Linha esquerda="A pagar na entrega" direita={formatarKz(orc.total - valorSaldo)} forte />
          {orc.motivo_desconto === 'limite_local' && (
            <Text style={{ color: cores.aviso, fontSize: 13 }}>{mensagemCodigo('limite_local')}</Text>
          )}
        </Cartao>
      )}

      {ligada('indicacao') && saldo > 0 && orc && (
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
          <Text style={{ fontSize: 15, flex: 1 }}>Usar saldo do Convida e Ganha ({formatarKz(saldo)})</Text>
          <Switch value={usarSaldo} onValueChange={setUsarSaldo} trackColor={{ true: cores.marca }} />
        </View>
      )}

      <Campo
        rotulo="Observações para a cozinha ou o entregador (opcional)"
        value={observacoes}
        onChangeText={setObservacoes}
        multiline
        maxLength={300}
      />
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Botao titulo="Confirmar pedido" aoCarregar={confirmar} aCarregar={aEnviar} desactivado={!orc || (!pontoId && !grupo)} />
      <Paragrafo suave>
        {grupo
          ? 'Pagas na entrega. A tua parte da entrega fica fixa quando o grupo fechar.'
          : 'Pagas na entrega. O valor final é confirmado pelo servidor.'}
      </Paragrafo>
    </Ecra>
  );
}
