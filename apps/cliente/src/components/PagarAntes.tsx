import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text } from 'react-native';

import { Aviso, Botao, Campo, Cartao, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { meuPagamentoAntes, pagarAntes } from '@/lib/api';
import { EMPRESA } from '@/lib/empresa';
import { formatarKz, mensagemErro, nomeMetodoAntes } from '@/lib/formatar';
import { cores } from '@/lib/tema';
import type { MetodoAntes, PagamentoAntes } from '@/lib/tipos';

/**
 * Pedido de grupo em que cada um paga a sua parte: pagar antes por Multicaixa Express ou Unitel Money,
 * escrever a referência e esperar a confirmação das Finanças. O estafeta só cobra o que faltar.
 * Bandura: o passo seguinte sempre claro (a confirmar → confirmado; rejeitado com o motivo e o que fazer).
 */
export function PagarAntes({ pedidoId, aoMudar }: { pedidoId: string; aoMudar?: () => void }) {
  const [info, setInfo] = useState<PagamentoAntes | null>(null);
  const [metodo, setMetodo] = useState<MetodoAntes>('multicaixa_express');
  const [referencia, setReferencia] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [aEnviar, setAEnviar] = useState(false);

  const carregar = useCallback(() => {
    meuPagamentoAntes(pedidoId)
      .then(setInfo)
      .catch(() => setInfo(null)); // sem a função no servidor (ou sem grupo): não mostra nada
  }, [pedidoId]);
  useFocusEffect(carregar);

  if (!info || info.modo !== 'individual') return null;
  const u = info.ultimo;

  if (u?.estado === 'pendente') {
    return (
      <Cartao>
        <Subtitulo>⏳ Pagamento a confirmar</Subtitulo>
        <Text style={{ color: cores.texto }}>
          {formatarKz(u.valor)} por {nomeMetodoAntes[u.metodo]} · referência {u.referencia}
        </Text>
        <Paragrafo suave>Confirmamos assim que o dinheiro chegar. Se o estafeta chegar antes, mostra-lhe o comprovativo.</Paragrafo>
      </Cartao>
    );
  }

  if (info.pago_antes > 0 && !info.pode) {
    return <Aviso tipo="sucesso">✓ A tua parte está paga ({formatarKz(info.pago_antes)}). O estafeta não te cobra nada.</Aviso>;
  }

  if (!info.pode) return null;

  const referenciaValida = referencia.replace(/\s/g, '').length >= 4;

  async function enviar() {
    setErro(null);
    setAEnviar(true);
    try {
      await pagarAntes(pedidoId, metodo, referencia.trim());
      setReferencia('');
      carregar();
      aoMudar?.();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAEnviar(false);
    }
  }

  return (
    <Cartao>
      <Subtitulo>Paga já a tua parte: {formatarKz(info.falta)}</Subtitulo>
      {u?.estado === 'rejeitado' && (
        <Aviso tipo="erro">O pagamento anterior não foi aceite{u.motivo ? `: ${u.motivo}` : ''}. Confirma a referência e envia de novo.</Aviso>
      )}
      {info.pago_antes > 0 && <Paragrafo suave>Já pagaste {formatarKz(info.pago_antes)}; falta o resto.</Paragrafo>}
      <Paragrafo>
        {EMPRESA.instrucoesPagamento || 'Transfere por Multicaixa Express ou Unitel Money para o número da Cozinha da Alexandra.'} Depois
        escreve aqui a referência que aparece no comprovativo.
      </Paragrafo>
      <Escolha
        opcoes={(Object.keys(nomeMetodoAntes) as MetodoAntes[]).map((m) => ({ valor: m, rotulo: nomeMetodoAntes[m] }))}
        valor={metodo}
        aoMudar={(v) => setMetodo(v as MetodoAntes)}
      />
      <Campo rotulo="Referência da transferência" value={referencia} onChangeText={setReferencia} autoCapitalize="characters" />
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Botao titulo="Já paguei" aCarregar={aEnviar} desactivado={!referenciaValida} aoCarregar={enviar} />
      <Paragrafo suave>Se preferires, paga ao estafeta na entrega.</Paragrafo>
    </Cartao>
  );
}
