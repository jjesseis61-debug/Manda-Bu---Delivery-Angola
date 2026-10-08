import { useFocusEffect, useLocalSearchParams, useRouter } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Text, View } from 'react-native';

import { AcompanharEntrega } from '@/components/AcompanharEntrega';
import { PartilharCodigo } from '@/components/PartilharCodigo';
import { PessoasComoTu } from '@/components/PessoasComoTu';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { rotuloAgendamento } from '@/lib/agendar';
import { useCarrinho } from '@/lib/carrinho';
import { montarRepeticao } from '@/lib/repetir';
import {
  atrasoDoPedido,
  avaliacaoPermitida,
  cancelarPedido,
  fazerReclamacao,
  justificacaoCancelamento,
  lerPedido,
  minhaAvaliacao,
  minhasReclamacoes,
} from '@/lib/api';
import { corEstadoPedido, formatarKz, mensagemErro, nomeEstadoPedido } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { supabase } from '@/lib/supabase';
import { cores } from '@/lib/tema';
import type { AtrasoPedido, MinhaReclamacao, Pedido } from '@/lib/tipos';

/** Estado do pedido; com fim=1 é o ecrã de fim de pedido (C6) */
export default function PedidoDetalhe() {
  const router = useRouter();
  const { id, fim, saldo, pacote } = useLocalSearchParams<{ id: string; fim?: string; saldo?: string; pacote?: string }>();
  const { ligada } = useSessao();
  const carrinho = useCarrinho();
  const [aRepetir, setARepetir] = useState(false);
  const [pedido, setPedido] = useState<Pedido | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aCancelar, setACancelar] = useState(false);
  const [avaliacao, setAvaliacao] = useState<{ estrelas: number } | 'pode' | null>(null);
  const [atraso, setAtraso] = useState<AtrasoPedido | null>(null);
  const [justificacao, setJustificacao] = useState<string | null>(null);
  const [reclamacoes, setReclamacoes] = useState<MinhaReclamacao[]>([]);
  const [reclamar, setReclamar] = useState<string | null>(null);
  const [aEnviar, setAEnviar] = useState(false);
  const [erroReclamacao, setErroReclamacao] = useState<string | null>(null);

  const carregar = useCallback(() => {
    lerPedido(String(id))
      .then(async (p) => {
        setPedido(p);
        if (p && ['pendente', 'confirmado', 'em_preparacao', 'em_entrega'].includes(p.estado)) {
          setAtraso(await atrasoDoPedido(p.id).catch(() => null));
        } else {
          setAtraso(null);
        }
        setJustificacao(p?.estado === 'cancelado' ? await justificacaoCancelamento(p.id).catch(() => null) : null);
        if (p) setReclamacoes(await minhasReclamacoes(p.id).catch(() => []));
        if (p?.estado === 'entregue_pago' && ligada('avaliacoes')) {
          const minha = await minhaAvaliacao(p.id);
          setAvaliacao(minha ?? ((await avaliacaoPermitida(p.id)) ? 'pode' : null));
        }
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [id, ligada]);
  useFocusEffect(carregar);

  // Ao vivo (Supabase Realtime): quando o estado do pedido muda no servidor, recarrega sem esperar.
  // Complementa o push; a RLS garante que só recebemos mudanças do nosso próprio pedido.
  useEffect(() => {
    const canal = supabase
      .channel(`pedido-${id}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'pedidos', filter: `id=eq.${id}` }, () => carregar())
      .subscribe();
    return () => {
      void supabase.removeChannel(canal);
    };
  }, [id, carregar]);

  if (erro) return <Ecra><Aviso tipo="erro">{erro}</Aviso></Ecra>;
  if (!pedido) return <ACarregar />;

  const podeReclamar =
    pedido.estado !== 'pendente' &&
    Date.now() - new Date(pedido.criado_em).getTime() < 7 * 24 * 3600 * 1000 &&
    !reclamacoes.some((r) => r.origem === 'cliente');

  async function enviarReclamacao() {
    if (!pedido || reclamar === null) return;
    setAEnviar(true);
    setErroReclamacao(null);
    try {
      await fazerReclamacao(pedido.id, reclamar.trim());
      setReclamar(null);
      setReclamacoes(await minhasReclamacoes(pedido.id));
    } catch (e) {
      setErroReclamacao(mensagemErro(e));
    } finally {
      setAEnviar(false);
    }
  }

  async function pedirDeNovo() {
    if (!pedido) return;
    setErro(null);
    setARepetir(true);
    try {
      const { linhas, cozinha, faltam } = await montarRepeticao(pedido.itens);
      if (linhas.length === 0) {
        setErro('Os pratos deste pedido já não estão disponíveis.');
        return;
      }
      carrinho.repor(linhas, cozinha);
      router.push({ pathname: '/carrinho', params: faltam.length > 0 ? { faltam: faltam.join(', ') } : {} });
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setARepetir(false);
    }
  }

  const total = pedido.subtotal + pedido.taxa_entrega - pedido.desconto_indicacao;
  const fimDePedido = fim === '1';
  const terminado = ['entregue_pago', 'cancelado', 'estornado'].includes(pedido.estado);
  const agendadoFuturo = pedido.agendado_para && !terminado && new Date(pedido.agendado_para) > new Date();

  return (
    <Ecra>
      {fimDePedido && (
        <Aviso tipo="sucesso">Pedido enviado! Avisamos-te quando estiver a caminho.</Aviso>
      )}
      {pacote === 'falhou' && <Aviso>Não foi possível pagar com o pacote neste pedido. Pagas na entrega.</Aviso>}
      {saldo === 'falhou' && <Aviso>Não foi possível usar o saldo neste pedido. Pagas o valor total na entrega.</Aviso>}

      <Cartao>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
          <View style={{ width: 11, height: 11, borderRadius: 6, backgroundColor: corEstadoPedido[pedido.estado] }} />
          <Text style={{ fontSize: 18, fontWeight: '700', color: corEstadoPedido[pedido.estado] }}>{nomeEstadoPedido[pedido.estado]}</Text>
        </View>
        {agendadoFuturo && pedido.agendado_para && (
          <Paragrafo suave>Agendado para {rotuloAgendamento(pedido.agendado_para)}.</Paragrafo>
        )}
        {pedido.hora_prometida && !agendadoFuturo && (
          <Paragrafo suave>
            Entrega prevista: {new Date(pedido.hora_prometida).toLocaleTimeString('pt-PT', { hour: '2-digit', minute: '2-digit' })}
          </Paragrafo>
        )}
        {pedido.estado === 'cancelado' && (justificacao ?? pedido.motivo_cancelamento) && (
          <Paragrafo>{justificacao ?? pedido.motivo_cancelamento}</Paragrafo>
        )}
      </Cartao>

      {/* A resposta da cozinha à reclamação em destaque, logo ao abrir (não escondida no fundo) */}
      {reclamacoes
        .filter((r) => r.estado === 'resolvida' && r.resposta)
        .map((r) => (
          <Aviso key={r.id} tipo="sucesso">
            A cozinha respondeu à tua reclamação{r.texto ? ` ("${r.texto}")` : ''}: {r.resposta}
          </Aviso>
        ))}

      {atraso && (
        <Aviso>
          {atraso.motivo
            ? `O teu pedido vai atrasar${atraso.mais_minutos ? ` cerca de ${atraso.mais_minutos} minutos` : ''}: ${atraso.motivo}. Pedimos desculpa pela espera.`
            : 'O teu pedido está a demorar mais do que o previsto. Já avisámos a cozinha.'}
        </Aviso>
      )}

      {/* I11: estafeta no mapa enquanto o pedido está a caminho */}
      {pedido.estado === 'em_entrega' && ligada('acompanhamento_entrega') && (
        <AcompanharEntrega pedidoId={pedido.id} aoTerminar={carregar} />
      )}

      <Cartao>
        {pedido.itens.map((i, n) => (
          <Linha key={n} esquerda={`${i.qtd}× ${i.nome}`} direita={formatarKz(i.qtd * i.preco_unitario)} />
        ))}
        <Linha esquerda="Entrega" direita={formatarKz(pedido.taxa_entrega)} />
        {pedido.desconto_indicacao > 0 && <Linha esquerda="Desconto de convite" direita={`−${formatarKz(pedido.desconto_indicacao)}`} />}
        {pedido.credito_indicacao_usado > 0 && (
          <Linha esquerda="Saldo do Convida e Ganha" direita={`−${formatarKz(pedido.credito_indicacao_usado)}`} />
        )}
        {(pedido.pago_pacote ?? 0) > 0 && (
          <Linha
            esquerda={`Pago com o pacote (${pedido.refeicoes_pacote} ${pedido.refeicoes_pacote === 1 ? 'refeição' : 'refeições'})`}
            direita={`−${formatarKz(pedido.pago_pacote)}`}
          />
        )}
        {(pedido.valor_empresa ?? 0) > 0 && (
          <Linha esquerda="Pago pela empresa" direita={`−${formatarKz(pedido.valor_empresa)}`} />
        )}
        <Linha
          esquerda="A pagar na entrega"
          direita={formatarKz(total - pedido.credito_indicacao_usado - (pedido.pago_pacote ?? 0) - (pedido.valor_empresa ?? 0))}
          forte
        />
      </Cartao>
      <Paragrafo suave>
        Este é o resumo da tua encomenda, não é uma fatura. A fatura é emitida na cozinha, na entrega. Preços com IVA
        incluído, quando aplicável.
      </Paragrafo>

      {terminado && <Botao titulo="Pedir de novo" aCarregar={aRepetir} aoCarregar={pedirDeNovo} />}

      {/* C9: avaliar até ao prazo; depois de avaliado mostra as estrelas dadas */}
      {avaliacao === 'pode' && <Botao titulo="Avaliar pedido" aoCarregar={() => router.push(`/avaliar/${pedido.id}`)} />}
      {avaliacao && avaliacao !== 'pode' && (
        <Paragrafo suave>
          A tua avaliação: <Text style={{ color: cores.destaque }}>{'★'.repeat(avaliacao.estrelas)}</Text>
        </Paragrafo>
      )}

      {/* Reclamações ainda sem resposta: a resposta, quando chega, sobe para o aviso em destaque lá em cima (e N22) */}
      {reclamacoes
        .filter((r) => !(r.estado === 'resolvida' && r.resposta))
        .map((r) => (
          <Cartao key={r.id}>
            <Subtitulo>A tua reclamação</Subtitulo>
            {r.texto && <Paragrafo>{r.texto}</Paragrafo>}
            <Paragrafo suave>Recebemos. A cozinha vai ver o que aconteceu e responde-te em breve.</Paragrafo>
          </Cartao>
        ))}
      {podeReclamar && reclamar === null && (
        <Botao titulo="Tenho uma reclamação" variante="texto" aoCarregar={() => setReclamar('')} />
      )}
      {reclamar !== null && (
        <Cartao>
          <Campo
            rotulo="O que correu mal?"
            value={reclamar}
            onChangeText={setReclamar}
            maxLength={500}
            multiline
            placeholder="Por exemplo: faltou o sumo, chegou frio, demorou muito…"
          />
          {erroReclamacao && <Aviso tipo="erro">{erroReclamacao}</Aviso>}
          <Botao titulo="Enviar reclamação" desactivado={reclamar.trim().length < 5} aCarregar={aEnviar} aoCarregar={enviarReclamacao} />
          <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setReclamar(null)} />
        </Cartao>
      )}

      {pedido.estado === 'pendente' && (
        <Botao
          titulo="Cancelar pedido"
          variante="texto"
          aCarregar={aCancelar}
          aoCarregar={async () => {
            setACancelar(true);
            try {
              await cancelarPedido(pedido.id);
              carregar();
            } catch (e) {
              setErro(mensagemErro(e));
            } finally {
              setACancelar(false);
            }
          }}
        />
      )}

      {/* C6: resumo + "Pessoas como tu" + partilha do código (cada parte com o seu interruptor) */}
      {fimDePedido && ligada('pessoas_como_tu') && <PessoasComoTu />}
      {fimDePedido && ligada('indicacao') && (
        <>
          <Subtitulo>Convida os teus amigos</Subtitulo>
          <PartilharCodigo />
        </>
      )}
      {fimDePedido && <Botao titulo="Voltar ao início" variante="secundario" aoCarregar={() => router.replace('/inicio')} />}
    </Ecra>
  );
}
