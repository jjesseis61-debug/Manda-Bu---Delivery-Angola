import { useFocusEffect, useLocalSearchParams, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text } from 'react-native';

import { AcompanharEntrega } from '@/components/AcompanharEntrega';
import { PartilharCodigo } from '@/components/PartilharCodigo';
import { PessoasComoTu } from '@/components/PessoasComoTu';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { avaliacaoPermitida, cancelarPedido, lerPedido, minhaAvaliacao } from '@/lib/api';
import { formatarKz, mensagemErro, nomeEstadoPedido } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { Pedido } from '@/lib/tipos';

/** Estado do pedido; com fim=1 é o ecrã de fim de pedido (C6) */
export default function PedidoDetalhe() {
  const router = useRouter();
  const { id, fim, saldo, pacote } = useLocalSearchParams<{ id: string; fim?: string; saldo?: string; pacote?: string }>();
  const { ligada } = useSessao();
  const [pedido, setPedido] = useState<Pedido | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aCancelar, setACancelar] = useState(false);
  const [avaliacao, setAvaliacao] = useState<{ estrelas: number } | 'pode' | null>(null);

  const carregar = useCallback(() => {
    lerPedido(String(id))
      .then(async (p) => {
        setPedido(p);
        if (p?.estado === 'entregue_pago' && ligada('avaliacoes')) {
          const minha = await minhaAvaliacao(p.id);
          setAvaliacao(minha ?? ((await avaliacaoPermitida(p.id)) ? 'pode' : null));
        }
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [id, ligada]);
  useFocusEffect(carregar);

  if (erro) return <Ecra><Aviso tipo="erro">{erro}</Aviso></Ecra>;
  if (!pedido) return <ACarregar />;

  const total = pedido.subtotal + pedido.taxa_entrega - pedido.desconto_indicacao;
  const fimDePedido = fim === '1';

  return (
    <Ecra>
      {fimDePedido && (
        <Aviso tipo="sucesso">Pedido enviado! Avisamos-te quando estiver a caminho.</Aviso>
      )}
      {pacote === 'falhou' && <Aviso>Não foi possível pagar com o pacote neste pedido. Pagas na entrega.</Aviso>}
      {saldo === 'falhou' && <Aviso>Não foi possível usar o saldo neste pedido. Pagas o valor total na entrega.</Aviso>}

      <Cartao>
        <Text style={{ fontSize: 18, fontWeight: '700', color: cores.marca }}>{nomeEstadoPedido[pedido.estado]}</Text>
        {pedido.hora_prometida && (
          <Paragrafo suave>
            Entrega prevista: {new Date(pedido.hora_prometida).toLocaleTimeString('pt-PT', { hour: '2-digit', minute: '2-digit' })}
          </Paragrafo>
        )}
        {pedido.motivo_cancelamento && <Paragrafo suave>{pedido.motivo_cancelamento}</Paragrafo>}
      </Cartao>

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
        <Linha
          esquerda="A pagar na entrega"
          direita={formatarKz(total - pedido.credito_indicacao_usado - (pedido.pago_pacote ?? 0))}
          forte
        />
      </Cartao>

      {/* C9: avaliar até ao prazo; depois de avaliado mostra as estrelas dadas */}
      {avaliacao === 'pode' && <Botao titulo="Avaliar pedido" aoCarregar={() => router.push(`/avaliar/${pedido.id}`)} />}
      {avaliacao && avaliacao !== 'pode' && (
        <Paragrafo suave>
          A tua avaliação: <Text style={{ color: cores.destaque }}>{'★'.repeat(avaliacao.estrelas)}</Text>
        </Paragrafo>
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
