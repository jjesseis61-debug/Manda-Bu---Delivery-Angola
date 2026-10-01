import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Pressable, Switch, Text, View } from 'react-native';

import { CampoCodigo } from '@/components/CampoCodigo';
import { Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { criarPedido, lerEnderecos, lerSaldo, orcamento as pedirOrcamento, usarCredito } from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { formatarKz, mensagemCodigo, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Endereco, Orcamento } from '@/lib/tipos';

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

  // O valor a pagar vem sempre do servidor (preços do cardápio, taxa da zona, desconto confirmado)
  useEffect(() => {
    setOrc(null);
    setErroOrc(null);
    if (!pontoId || carrinho.linhas.length === 0) return;
    pedirOrcamento(
      carrinho.linhas.map((l) => ({ cardapio_id: l.item.id, qtd: l.qtd })),
      pontoId,
    )
      .then(setOrc)
      .catch((e) => setErroOrc(mensagemErro(e)));
  }, [carrinho.linhas, pontoId, versao]);

  const valorSaldo = orc && usarSaldo ? Math.min(saldo, orc.total) : 0;

  async function confirmar() {
    if (!perfil || !pontoId || !orc) return;
    setErro(null);
    setAEnviar(true);
    try {
      const id = await criarPedido({
        clienteId: perfil.cliente_id,
        pontoEntregaId: pontoId,
        itens: carrinho.linhas.map((l) => ({ cardapio_id: l.item.id, qtd: l.qtd })),
        observacoes,
      });
      let saldoFalhou = false;
      if (valorSaldo > 0) {
        await usarCredito(id, valorSaldo).catch(() => {
          saldoFalhou = true;
        });
      }
      carrinho.limpar();
      router.replace({ pathname: '/pedido/[id]', params: { id, fim: '1', ...(saldoFalhou ? { saldo: 'falhou' } : {}) } });
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
      {carrinho.linhas.map((l) => (
        <View key={l.item.id} style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.m }}>
          <Text style={{ flex: 1, fontSize: 15 }}>{l.item.nome}</Text>
          <Pressable accessibilityLabel="Menos" onPress={() => carrinho.alterar(l.item.id, l.qtd - 1)} hitSlop={8}>
            <Text style={{ fontSize: 22, color: cores.marca, width: 24, textAlign: 'center' }}>−</Text>
          </Pressable>
          <Text style={{ fontSize: 16, fontWeight: '600', minWidth: 20, textAlign: 'center' }}>{l.qtd}</Text>
          <Pressable accessibilityLabel="Mais" onPress={() => carrinho.alterar(l.item.id, l.qtd + 1)} hitSlop={8}>
            <Text style={{ fontSize: 22, color: cores.marca, width: 24, textAlign: 'center' }}>+</Text>
          </Pressable>
        </View>
      ))}

      <Subtitulo>Entregar em</Subtitulo>
      {enderecos && enderecos.length === 0 && (
        <Aviso>Ainda não tens endereços de entrega.</Aviso>
      )}
      {enderecos && enderecos.length > 0 && (
        <Escolha
          opcoes={enderecos.map((e) => ({
            valor: e.ponto_entrega_id,
            rotulo: `${e.nome ?? 'Endereço'}${e.pontos_entrega?.zonas?.nome ? ` · ${e.pontos_entrega.zonas.nome}` : ''}`,
          }))}
          valor={pontoId ?? ''}
          aoMudar={setPontoId}
        />
      )}
      <Botao titulo="Adicionar endereço" variante="texto" aoCarregar={() => router.push('/enderecos/novo')} />

      {/* C2: no checkout do 1.º pedido; depois de ligar, o orçamento é pedido de novo ao servidor */}
      <CampoCodigo aoLigar={() => setVersao((v) => v + 1)} />

      {erroOrc && <Aviso tipo="erro">{erroOrc}</Aviso>}
      {orc && (
        <Cartao>
          <Linha esquerda="Subtotal" direita={formatarKz(orc.subtotal)} />
          <Linha esquerda={`Entrega${orc.zona_nome ? ` (${orc.zona_nome})` : ''}`} direita={formatarKz(orc.taxa_entrega)} />
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
      <Botao titulo="Confirmar pedido" aoCarregar={confirmar} aCarregar={aEnviar} desactivado={!orc || !pontoId} />
      <Paragrafo suave>Pagas na entrega. O valor final é confirmado pelo servidor.</Paragrafo>
    </Ecra>
  );
}
