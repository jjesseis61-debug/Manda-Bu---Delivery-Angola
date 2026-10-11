import { useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Text, View } from 'react-native';

import { ACarregar, Aviso, Cartao, Ecra, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { historicoPedido } from '@/lib/api';
import { descreverEvento, formatarData, formatarKz, mensagemErro, nomeEstadoPedido } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { HistoricoPedido } from '@/lib/tipos';

/** Histórico do pedido: quem fez cada passo, do pedido ao fecho da caixa e ao extrato */
export default function HistoricoPedidoEcra() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [h, setH] = useState<HistoricoPedido | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    if (id) historicoPedido(id).then(setH, (e) => setErro(mensagemErro(e)));
  }, [id]);

  return (
    <Ecra>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {!h && !erro && <ACarregar />}
      {h && (
        <>
          <Cartao>
            <Text style={{ fontWeight: '700', fontSize: 16 }}>{h.cliente ?? 'Cliente'}</Text>
            <Linha esquerda="Estado" direita={nomeEstadoPedido[h.estado] ?? h.estado} />
            <Linha esquerda="Valor" direita={formatarKz(h.valor)} forte />
            {h.cozinha && <Linha esquerda="Cozinha" direita={h.cozinha} />}
            {h.entregador && <Linha esquerda="Entregou" direita={h.entregador} />}
            {h.caixa && <Linha esquerda="Caixa" direita={h.caixa} />}
            {(h.parcelas ?? []).map((p, i) => (
              <Text key={i} style={{ color: cores.textoSuave }}>
                {p.metodo}: {formatarKz(p.valor)}
                {p.referencia ? ` · ref. ${p.referencia}` : ''}
              </Text>
            ))}
          </Cartao>
          <Subtitulo>Passo a passo</Subtitulo>
          {h.eventos.length === 0 && <Paragrafo suave>Sem registos.</Paragrafo>}
          {h.eventos.map((e, i) => (
            <View key={i} style={{ gap: espaco.xs, borderLeftWidth: 3, borderLeftColor: cores.marca, paddingLeft: espaco.s }}>
              <Text style={{ color: cores.textoSuave }}>{formatarData(e.em, true)}</Text>
              <Text style={{ fontWeight: '600' }}>{descreverEvento(e.acao, e.detalhe)}</Text>
              <Text style={{ color: cores.textoSuave }}>{e.quem ?? 'sistema'}</Text>
            </View>
          ))}
        </>
      )}
    </Ecra>
  );
}
