import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Linking, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo } from '@/components/ui';
import { aprovarLevantamento, levantamentos, marcarPago, rejeitarLevantamento } from '@/lib/api';
import { formatarData, formatarKz, mensagemErro, nomeMetodo } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { LevantamentoOperador } from '@/lib/tipos';

type Filtro = 'por_tratar' | 'pago' | 'rejeitado';

/** O3. Levantamentos: aprovar, rejeitar (motivo) e marcar como pago (referência) */
export default function Levantamentos() {
  const [filtro, setFiltro] = useState<Filtro>('por_tratar');
  const [lista, setLista] = useState<LevantamentoOperador[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aberto, setAberto] = useState<{ id: string; accao: 'rejeitar' | 'pagar' } | null>(null);
  const [texto, setTexto] = useState('');
  const [ocupado, setOcupado] = useState<string | null>(null);

  const carregar = useCallback(() => {
    setLista(null);
    levantamentos(filtro === 'por_tratar' ? null : filtro)
      .then((l) => setLista(filtro === 'por_tratar' ? l.filter((x) => x.estado === 'pedido' || x.estado === 'aprovado') : l))
      .catch((e) => setErro(mensagemErro(e)));
  }, [filtro]);
  useFocusEffect(carregar);

  async function accao(id: string, f: () => Promise<unknown>) {
    setErro(null);
    setOcupado(id);
    try {
      await f();
      setAberto(null);
      setTexto('');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(null);
    }
  }

  return (
    <Guarda permissoes={['indicacoes.aprovar_pagamentos']}>
      <Ecra>
        <Escolha
          opcoes={[
            { valor: 'por_tratar', rotulo: 'Por tratar' },
            { valor: 'pago', rotulo: 'Pagos' },
            { valor: 'rejeitado', rotulo: 'Rejeitados' },
          ]}
          valor={filtro}
          aoMudar={setFiltro}
        />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista && lista.length === 0 && <Paragrafo suave>Nada nesta lista.</Paragrafo>}
        {lista?.map((l) => (
          <Cartao key={l.pagamento_id} estilo={l.primeiro_levantamento && l.estado !== 'pago' ? { borderWidth: 2, borderColor: cores.destaque } : undefined}>
            {l.primeiro_levantamento && l.estado !== 'pago' && (
              <Text style={{ color: cores.aviso, fontWeight: '700' }}>Primeiro levantamento: pagar hoje</Text>
            )}
            <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
              <Text style={{ fontWeight: '700', fontSize: 16 }}>
                {formatarKz(l.valor)}
                {l.total_parcelas && l.total_parcelas > 1 ? ` · parcela ${l.parcela}/${l.total_parcelas}` : ''}
              </Text>
              <Text style={{ fontWeight: '700' }}>{l.estado === 'pedido' ? 'Pedido' : l.estado === 'aprovado' ? 'Aprovado' : l.estado === 'pago' ? 'Pago' : 'Rejeitado'}</Text>
            </View>
            <Text>{l.indicador_nome}</Text>
            {l.indicador_telefone && (
              <Text style={{ color: cores.marca }} onPress={() => Linking.openURL(`tel:+244${l.indicador_telefone}`)}>
                Ligar {l.indicador_telefone}
              </Text>
            )}
            <Text style={{ color: cores.textoSuave }}>
              {nomeMetodo[l.metodo ?? ''] ?? l.metodo} para {l.numero_destino} · pedido em {formatarData(l.criado_em, true)}
            </Text>
            {l.referencia && <Text>Referência: {l.referencia}</Text>}
            {l.motivo_rejeicao && <Text style={{ color: cores.erro }}>{l.motivo_rejeicao}</Text>}

            {aberto?.id === l.pagamento_id ? (
              <>
                <Campo
                  rotulo={aberto.accao === 'pagar' ? 'Referência do pagamento (obrigatória)' : 'Motivo da rejeição (obrigatório)'}
                  value={texto}
                  onChangeText={setTexto}
                />
                <Botao
                  titulo={aberto.accao === 'pagar' ? 'Marcar como pago' : 'Rejeitar'}
                  desactivado={!texto.trim()}
                  aCarregar={ocupado === l.pagamento_id}
                  aoCarregar={() =>
                    accao(l.pagamento_id, () =>
                      aberto.accao === 'pagar' ? marcarPago(l.pagamento_id, texto.trim()) : rejeitarLevantamento(l.pagamento_id, texto.trim()),
                    )
                  }
                />
                <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
              </>
            ) : (
              (l.estado === 'pedido' || l.estado === 'aprovado') && (
                <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
                  {l.estado === 'pedido' && (
                    <View style={{ flex: 1 }}>
                      <Botao titulo="Aprovar" aCarregar={ocupado === l.pagamento_id} aoCarregar={() => accao(l.pagamento_id, () => aprovarLevantamento(l.pagamento_id))} />
                    </View>
                  )}
                  {l.estado === 'aprovado' && (
                    <View style={{ flex: 1 }}>
                      <Botao titulo="Marcar como pago" aoCarregar={() => setAberto({ id: l.pagamento_id, accao: 'pagar' })} />
                    </View>
                  )}
                  <View style={{ flex: 1 }}>
                    <Botao titulo="Rejeitar" variante="secundario" aoCarregar={() => setAberto({ id: l.pagamento_id, accao: 'rejeitar' })} />
                  </View>
                </View>
              )
            )}
          </Cartao>
        ))}
      </Ecra>
    </Guarda>
  );
}
