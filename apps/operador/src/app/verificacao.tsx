import { useFocusEffect } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { Linking, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { confirmarTodos, ganhosEmVerificacao, reverGanho } from '@/lib/api';
import { formatarData, formatarKz, mensagemErro, nomeMotivo } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { GanhoVerificacao } from '@/lib/tipos';

/** O2. Ganhos em verificação, agrupados por indicador */
export default function Verificacao() {
  const [ganhos, setGanhos] = useState<GanhoVerificacao[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aAnular, setAAnular] = useState<string | null>(null);
  const [motivo, setMotivo] = useState('');
  const [ocupado, setOcupado] = useState<string | null>(null);

  const carregar = useCallback(() => {
    ganhosEmVerificacao()
      .then(setGanhos)
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  const grupos = useMemo(() => {
    const m = new Map<string, GanhoVerificacao[]>();
    for (const g of ganhos ?? []) m.set(g.indicador_id, [...(m.get(g.indicador_id) ?? []), g]);
    return [...m.values()];
  }, [ganhos]);

  async function accao(chave: string, f: () => Promise<unknown>) {
    setErro(null);
    setOcupado(chave);
    try {
      await f();
      setAAnular(null);
      setMotivo('');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(null);
    }
  }

  return (
    <Guarda permissoes={['indicacoes.verificar']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!ganhos && !erro && <ACarregar />}
        {ganhos && ganhos.length === 0 && <Paragrafo suave>Não há ganhos à espera de verificação.</Paragrafo>}
        {grupos.map((lista) => {
          const ind = lista[0];
          return (
            <View key={ind.indicador_id} style={{ gap: espaco.s }}>
              <Subtitulo>
                {ind.indicador_nome}
                {ind.indicador_nivel === 'embaixador' ? ' ★' : ''} · {lista.length} ganhos ·{' '}
                {formatarKz(lista.reduce((s, g) => s + g.valor, 0))}
              </Subtitulo>
              {ind.numero_indicador && <Paragrafo suave>Número de levantamento: {ind.numero_indicador}</Paragrafo>}
              {lista.map((g) => (
                <Cartao key={g.ganho_id}>
                  <Text style={{ fontWeight: '700' }}>
                    {formatarKz(g.valor)} · {nomeMotivo[g.motivo ?? ''] ?? g.motivo}
                  </Text>
                  <Text>Indicado: {g.indicado_nome}</Text>
                  <Text style={{ color: cores.textoSuave }}>
                    {formatarData(g.criado_em, true)} · dispositivo {g.pedido_dispositivo ?? '—'}
                    {g.pagador_distinto ? ' · pago por outra pessoa' : ''}
                  </Text>
                  {g.numero_indicado && <Text>Número de levantamento do indicado: {g.numero_indicado}</Text>}
                  {g.ponto_lat !== null && g.ponto_lng !== null && (
                    <Text
                      style={{ color: cores.marca, fontWeight: '600' }}
                      onPress={() => Linking.openURL(`https://maps.google.com/?q=${g.ponto_lat},${g.ponto_lng}`)}>
                      Ver local ({g.ponto_tipo === 'empresa' ? 'trabalho' : 'casa'}
                      {g.ponto_referencia ? `: ${g.ponto_referencia}` : ''}) no mapa
                    </Text>
                  )}
                  {aAnular === g.ganho_id ? (
                    <>
                      <Campo rotulo="Motivo da anulação (obrigatório)" value={motivo} onChangeText={setMotivo} multiline />
                      <Botao
                        titulo="Anular ganho"
                        aCarregar={ocupado === g.ganho_id}
                        desactivado={!motivo.trim()}
                        aoCarregar={() => accao(g.ganho_id, () => reverGanho(g.ganho_id, 'anular', motivo.trim()))}
                      />
                      <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAAnular(null)} />
                    </>
                  ) : (
                    <View style={{ flexDirection: 'row', gap: espaco.s }}>
                      <View style={{ flex: 1 }}>
                        <Botao
                          titulo="Confirmar"
                          aCarregar={ocupado === g.ganho_id}
                          aoCarregar={() => accao(g.ganho_id, () => reverGanho(g.ganho_id, 'confirmar'))}
                        />
                      </View>
                      <View style={{ flex: 1 }}>
                        <Botao titulo="Anular" variante="secundario" aoCarregar={() => setAAnular(g.ganho_id)} />
                      </View>
                    </View>
                  )}
                </Cartao>
              ))}
              {lista.length > 1 && (
                <Botao
                  titulo={`Confirmar todos de ${ind.indicador_nome.split(' ')[0]}`}
                  variante="secundario"
                  aCarregar={ocupado === ind.indicador_id}
                  aoCarregar={() => accao(ind.indicador_id, () => confirmarTodos(ind.indicador_id))}
                />
              )}
            </View>
          );
        })}
      </Ecra>
    </Guarda>
  );
}
