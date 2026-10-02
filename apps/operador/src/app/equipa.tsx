import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { lerCozinhas, lerReconhecimentos, metricasTurno, registarReconhecimento } from '@/lib/api';
import { diaLuanda, formatarDia, mensagemErro, nomePeriodo, nomeTipoReconhecimento, segundaFeira } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Cozinha, MetricaTurno, Periodo, Reconhecimento, TipoReconhecimento } from '@/lib/tipos';

/**
 * O8. Equipa: métricas da semana por turno de cozinha e reconhecimentos.
 * Sempre por turno, nunca por pessoa (sem rankings).
 */
export default function Equipa() {
  const { funcionario, pode } = useSessao();
  const reconhece = pode('equipa.reconhecer');
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [cozinhaId, setCozinhaId] = useState<string | null>(null);
  const [semana, setSemana] = useState<'esta' | 'passada'>('passada');
  const [metricas, setMetricas] = useState<MetricaTurno[] | null>(null);
  const [historico, setHistorico] = useState<Reconhecimento[]>([]);
  const [novo, setNovo] = useState<{ periodo: Periodo; tipo: TipoReconhecimento; nota: string } | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [aGuardar, setAGuardar] = useState(false);

  const dataSemana = segundaFeira(diaLuanda(), semana === 'esta' ? 0 : -1);

  useFocusEffect(
    useCallback(() => {
      lerCozinhas()
        .then((cs) => {
          const minhas = reconhece ? cs : cs.filter((c) => funcionario?.cozinhas_equipa.includes(c.id));
          setCozinhas(minhas);
          setCozinhaId((actual) => actual ?? minhas[0]?.id ?? null);
        })
        .catch((e) => setErro(mensagemErro(e)));
    }, [reconhece, funcionario]),
  );

  const carregar = useCallback(() => {
    if (!cozinhaId) return;
    setMetricas(null);
    Promise.all([metricasTurno(cozinhaId, dataSemana), lerReconhecimentos(cozinhaId)])
      .then(([m, r]) => {
        setMetricas(m);
        setHistorico(r);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [cozinhaId, dataSemana]);
  useFocusEffect(carregar);

  async function guardar() {
    if (!novo || !cozinhaId) return;
    setErro(null);
    setAGuardar(true);
    try {
      await registarReconhecimento({
        cozinhaId,
        semana: dataSemana,
        periodo: novo.periodo,
        tipo: novo.tipo,
        nota: novo.nota.trim() || null,
      });
      setNovo(null);
      setSucesso('Reconhecimento registado. Os membros do turno recebem a notificação.');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAGuardar(false);
    }
  }

  return (
    <Guarda permissoes={['equipa.reconhecer']} permitir={(f) => f.cozinhas_equipa.length > 0}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
        {cozinhas.length > 1 && cozinhaId && (
          <Escolha opcoes={cozinhas.map((c) => ({ valor: c.id, rotulo: c.nome }))} valor={cozinhaId} aoMudar={setCozinhaId} />
        )}
        <Escolha
          opcoes={[
            { valor: 'passada', rotulo: 'Semana passada' },
            { valor: 'esta', rotulo: 'Esta semana' },
          ]}
          valor={semana}
          aoMudar={setSemana}
        />
        <Paragrafo suave>Semana de {formatarDia(dataSemana)}</Paragrafo>

        {!metricas && !erro && <ACarregar />}
        {metricas && metricas.length === 0 && <Paragrafo suave>Sem turnos registados nesta semana.</Paragrafo>}
        {metricas?.map((m) => (
          <Cartao key={m.periodo}>
            <Text style={{ fontSize: 17, fontWeight: '700' }}>Turno da {nomePeriodo[m.periodo]?.toLowerCase()}</Text>
            <Linha2 rotulo="Entregas a horas" valor={m.entregas > 0 ? `${m.entregas_a_horas} de ${m.entregas}${m.pct_a_horas !== null ? ` (${String(m.pct_a_horas).replace('.', ',')}%)` : ''}` : '—'} />
            <Linha2 rotulo="Quebras registadas" valor={m.quebras > 0 ? `${m.quebras} (${String(m.quantidade_quebra).replace('.', ',')})` : 'nenhuma'} />
            <Linha2 rotulo="Diferença de caixa" valor={Number(m.diferenca_caixa) === 0 ? 'certa' : `${m.diferenca_caixa} Kz`} />
          </Cartao>
        ))}

        {reconhece && metricas && metricas.length > 0 && !novo && (
          <Botao titulo="Registar reconhecimento" aoCarregar={() => setNovo({ periodo: metricas[0].periodo, tipo: 'entregas_a_horas', nota: '' })} />
        )}
        {novo && (
          <Cartao>
            <Subtitulo>Reconhecer um turno</Subtitulo>
            <Escolha
              opcoes={(metricas ?? []).map((m) => ({ valor: m.periodo, rotulo: nomePeriodo[m.periodo] }))}
              valor={novo.periodo}
              aoMudar={(v) => setNovo({ ...novo, periodo: v })}
            />
            <Escolha
              opcoes={Object.entries(nomeTipoReconhecimento).map(([valor, rotulo]) => ({ valor: valor as TipoReconhecimento, rotulo }))}
              valor={novo.tipo}
              aoMudar={(v) => setNovo({ ...novo, tipo: v })}
            />
            <Campo rotulo="Nota (opcional)" value={novo.nota} onChangeText={(t) => setNovo({ ...novo, nota: t })} multiline />
            <Botao titulo="Guardar" aCarregar={aGuardar} aoCarregar={guardar} />
            <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setNovo(null)} />
          </Cartao>
        )}

        <Subtitulo>Reconhecimentos</Subtitulo>
        {historico.length === 0 && <Paragrafo suave>Ainda não há reconhecimentos.</Paragrafo>}
        {historico.map((r) => (
          <Cartao key={r.id}>
            <Text style={{ fontWeight: '700', color: cores.sucesso }}>
              {nomeTipoReconhecimento[r.tipo]} · turno da {nomePeriodo[r.periodo]?.toLowerCase()}
            </Text>
            <Text style={{ color: cores.textoSuave }}>Semana de {formatarDia(r.semana)}</Text>
            {r.nota && <Text>{r.nota}</Text>}
          </Cartao>
        ))}
      </Ecra>
    </Guarda>
  );
}

function Linha2({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: espaco.s }}>
      <Text>{rotulo}</Text>
      <Text style={{ fontWeight: '600' }}>{valor}</Text>
    </View>
  );
}
