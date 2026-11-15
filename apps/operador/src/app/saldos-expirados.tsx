import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Linking, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { relatorioSaldosExpirados, type RelatorioExpirados } from '@/lib/api';
import { exportarCsv } from '@/lib/exportar';
import { formatarData, formatarKz, mensagemErro, paraCsv } from '@/lib/formatar';
import { linhasCsvExpirados, periodoRel, type PeriodoRel } from '@/lib/relatorio';
import { cores, espaco } from '@/lib/tema';

/** Saldos do Convida que expiraram (validade) e o que vai expirar: resumo, por mês, por cliente, CSV */
export default function SaldosExpirados() {
  const [periodo, setPeriodo] = useState<PeriodoRel>('mes');
  const [de, setDe] = useState('');
  const [ate, setAte] = useState('');
  const [r, setR] = useState<RelatorioExpirados | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aCarregar, setACarregar] = useState(false);
  const intervalo = periodoRel(periodo, new Date(), de, ate);

  const carregar = useCallback(() => {
    if (!intervalo) return;
    setErro(null);
    setACarregar(true);
    relatorioSaldosExpirados(intervalo[0], intervalo[1])
      .then(setR)
      .catch((e) => setErro(mensagemErro(e)))
      .finally(() => setACarregar(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [intervalo?.[0], intervalo?.[1]]);
  useFocusEffect(carregar);

  return (
    <Guarda permissoes={['indicacoes.verificar']}>
      <Ecra>
        <Escolha<PeriodoRel>
          opcoes={[
            { valor: '7', rotulo: '7 dias' },
            { valor: 'mes', rotulo: 'Este mês' },
            { valor: 'mes_anterior', rotulo: 'Mês anterior' },
            { valor: 'datas', rotulo: 'Datas…' },
          ]}
          valor={periodo}
          aoMudar={setPeriodo}
        />
        {periodo === 'datas' && (
          <View style={{ flexDirection: 'row', gap: espaco.s }}>
            <View style={{ flex: 1 }}>
              <Campo rotulo="De (aaaa-mm-dd)" value={de} onChangeText={setDe} maxLength={10} />
            </View>
            <View style={{ flex: 1 }}>
              <Campo rotulo="Até (opcional)" value={ate} onChangeText={setAte} maxLength={10} />
            </View>
          </View>
        )}
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {aCarregar && !r && <ACarregar />}
        {r && (
          <>
            <Cartao estilo={{ gap: espaco.xs }}>
              <Subtitulo>Resumo do período</Subtitulo>
              <Paragrafo suave>
                {`Cada ganho vale ${r.validade_meses} meses. Gasta-se primeiro o mais antigo; só expira o que ficou por usar.`}
              </Paragrafo>
              <Linha esquerda="Total expirado" direita={formatarKz(r.resumo.total)} forte />
              <Linha esquerda="Clientes · expirações" direita={`${r.resumo.clientes} · ${r.resumo.expiracoes}`} />
              <Linha esquerda="Média · maior" direita={`${formatarKz(r.resumo.media)} · ${formatarKz(r.resumo.maior)}`} />
              <Linha esquerda="Avisados antes de expirar" direita={`${r.resumo.avisados} de ${r.resumo.expiracoes}`} />
              <Linha esquerda="Expirado desde sempre" direita={formatarKz(r.expirado_sempre)} />
              <Linha esquerda="Saldo activo de todos os clientes" direita={formatarKz(r.saldo_activo_total)} />
            </Cartao>

            <Cartao estilo={{ gap: espaco.xs }}>
              <Subtitulo>Vai expirar</Subtitulo>
              <Linha esquerda="Próximos 30 dias" direita={`${formatarKz(r.a_expirar.d30)} · ${r.a_expirar.clientes_30} clientes`} />
              <Linha esquerda="Próximos 60 dias" direita={`${formatarKz(r.a_expirar.d60)} · ${r.a_expirar.clientes_60} clientes`} />
              <Linha esquerda="Próximos 90 dias" direita={`${formatarKz(r.a_expirar.d90)} · ${r.a_expirar.clientes_90} clientes`} />
              {r.a_expirar_lista.length === 0 && <Paragrafo suave>Nada a expirar nos próximos 90 dias.</Paragrafo>}
              {r.a_expirar_lista.map((a) => (
                <View key={a.cliente_id} style={{ borderTopWidth: 1, borderTopColor: cores.linha, paddingTop: espaco.xs }}>
                  <Text style={{ fontWeight: '700', color: cores.texto }}>{a.nome}</Text>
                  <Text
                    style={{ color: cores.textoSuave }}
                    onPress={a.telefone ? () => Linking.openURL(`tel:+244${a.telefone}`) : undefined}>
                    {`${formatarKz(a.valor)} em 90 dias (${formatarKz(a.em_30_dias)} em 30)` +
                      (a.expira_em ? ` · a partir de ${formatarData(a.expira_em)}` : '') +
                      ` · saldo ${formatarKz(a.saldo)}` +
                      (a.telefone ? ` · ${a.telefone}` : '')}
                  </Text>
                </View>
              ))}
            </Cartao>

            <Cartao estilo={{ gap: espaco.xs }}>
              <Subtitulo>Por mês</Subtitulo>
              {r.por_mes.length === 0 && <Paragrafo suave>Nada expirou neste período.</Paragrafo>}
              {r.por_mes.map((m) => (
                <Linha key={m.mes} esquerda={m.mes} direita={`${formatarKz(m.valor)} · ${m.clientes} clientes`} />
              ))}
            </Cartao>

            <Cartao estilo={{ gap: espaco.xs }}>
              <Subtitulo>{`Expirações (${r.lista.length})`}</Subtitulo>
              {r.lista.map((l) => (
                <View key={l.id} style={{ borderTopWidth: 1, borderTopColor: cores.linha, paddingTop: espaco.xs }}>
                  <Text style={{ fontWeight: '700', color: cores.texto }}>
                    {`${formatarData(l.data)} · ${l.nome}${l.codigo ? ` · ${l.codigo}` : ''} · ${formatarKz(l.valor)}`}
                  </Text>
                  <Text style={{ color: cores.textoSuave }}>
                    {`Ganhos antigos ${formatarKz(l.ganhos_antigos)} · já usados ${formatarKz(l.usado)} · saldo antes ${formatarKz(l.saldo_antes)}` +
                      ` · ${l.avisado ? 'avisado antes' : 'sem aviso prévio'}` +
                      (l.telefone ? ` · ${l.telefone}` : '')}
                  </Text>
                </View>
              ))}
            </Cartao>

            <Botao
              titulo="⬇ Exportar tudo (CSV)"
              variante="secundario"
              aoCarregar={() =>
                exportarCsv(`saldos-expirados-${r.periodo.inicio}-${r.periodo.fim}.csv`, paraCsv(linhasCsvExpirados(r))).catch((e) =>
                  setErro(mensagemErro(e)),
                )
              }
            />
          </>
        )}
        <Botao titulo="Actualizar" variante="texto" aoCarregar={carregar} />
      </Ecra>
    </Guarda>
  );
}
