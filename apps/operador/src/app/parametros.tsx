import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Switch, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { alterarFuncionalidade, alterarParametros, lerFuncionalidades, lerParametros } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';

/** Parâmetros editáveis na app (secção 9). Valores em Kz, dias, metros ou contagens. */
const CAMPOS: { grupo: string; chaves: [string, string][] }[] = [
  {
    grupo: 'Indicação',
    chaves: [
      ['ganho_por_pedido', 'Ganho por pedido (Kz)'],
      ['duracao_dias', 'Duração do período (dias)'],
      ['desconto_indicado', 'Desconto do indicado (Kz)'],
      ['limite_verificacao_semanal', 'Limite semanal sem verificação (Kz)'],
      ['levantamento_minimo', 'Levantamento mínimo (Kz)'],
      ['limite_parcelamento', 'Parcelar acima de (Kz)'],
      ['limiar_embaixador', 'Indicados activos para Embaixador'],
    ],
  },
  {
    grupo: 'Anti-fraude',
    chaves: [
      ['raio_mesmo_local_m', 'Raio do mesmo local (m)'],
      ['max_indicados_por_local', 'Máx. indicados por local'],
      ['max_descontos_por_local', 'Máx. descontos por local'],
    ],
  },
  {
    grupo: 'Prova social',
    chaves: [
      ['tamanho_top', 'Tamanho do top'],
      ['limiar_intervalos', 'Mostrar intervalos a partir de'],
      ['tamanho_intervalo', 'Tamanho do intervalo (Kz)'],
      ['pessoas_como_tu_min', '"Pessoas como tu": mínimo'],
      ['pessoas_como_tu_max', '"Pessoas como tu": máximo'],
      ['contador_minimo', 'Contador da zona: mínimo'],
    ],
  },
  {
    grupo: 'Avaliações e equipa',
    chaves: [
      ['prazo_avaliacao_dias', 'Prazo para avaliar (dias)'],
      ['avaliacoes_minimo', 'Avaliações mínimas para mostrar média'],
      ['tolerancia_entrega_min', 'Tolerância de entrega (min)'],
    ],
  },
];

/** O5. Parâmetros e funcionalidades (interruptores), com confirmação */
export default function Parametros() {
  const [originais, setOriginais] = useState<Record<string, unknown> | null>(null);
  const [valores, setValores] = useState<Record<string, string>>({});
  const [funcs, setFuncs] = useState<{ chave: string; activa: boolean }[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [confirmar, setConfirmar] = useState<{ tipo: 'parametros' } | { tipo: 'func'; chave: string; activa: boolean } | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    Promise.all([lerParametros(), lerFuncionalidades()])
      .then(([p, f]) => {
        setOriginais(p);
        setValores(Object.fromEntries(Object.entries(p).map(([k, v]) => [k, String(v ?? '')])));
        setFuncs(f);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  const alterados: Record<string, number> = {};
  for (const g of CAMPOS)
    for (const [k] of g.chaves)
      if (originais && valores[k] !== String(originais[k])) alterados[k] = Number(valores[k]);
  const invalidos = Object.values(alterados).some((v) => !Number.isInteger(v) || v < 0);

  async function aplicar() {
    if (!confirmar) return;
    setErro(null);
    setSucesso(null);
    setOcupado(true);
    try {
      if (confirmar.tipo === 'parametros') await alterarParametros(alterados);
      else await alterarFuncionalidade(confirmar.chave, confirmar.activa);
      setSucesso('Alteração guardada e registada na auditoria.');
      setConfirmar(null);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  const caixaConfirmar = confirmar && (
    <Cartao estilo={{ borderWidth: 2, borderColor: cores.destaque }}>
      <Text style={{ fontWeight: '700' }}>
        {confirmar.tipo === 'parametros'
          ? `Confirmar ${Object.keys(alterados).length} alteração(ões)? Aplica-se aos novos pedidos e ligações.`
          : `${confirmar.activa ? 'Ligar' : 'Desligar'} a funcionalidade "${confirmar.chave}"?`}
      </Text>
      <Botao titulo="Confirmar" aCarregar={ocupado} aoCarregar={aplicar} />
      <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setConfirmar(null)} />
    </Cartao>
  );

  return (
    <Guarda permissoes={['plataforma.parametros']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
        {!originais && !erro && <ACarregar />}
        {originais && (
          <>
            <Subtitulo>Funcionalidades</Subtitulo>
            <Paragrafo suave>Cada funcionalidade nova só se liga depois de testada.</Paragrafo>
            <Cartao>
              {funcs.map((f) => (
                <View key={f.chave} style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                  <Text>{f.chave}</Text>
                  <Switch
                    value={f.activa}
                    onValueChange={(v) => setConfirmar({ tipo: 'func', chave: f.chave, activa: v })}
                    trackColor={{ true: cores.marca, false: cores.linha }}
                  />
                </View>
              ))}
            </Cartao>
            {confirmar?.tipo === 'func' && caixaConfirmar}

            {CAMPOS.map((g) => (
              <View key={g.grupo} style={{ gap: espaco.s }}>
                <Subtitulo>{g.grupo}</Subtitulo>
                {g.chaves.map(([k, rotulo]) => (
                  <Campo
                    key={k}
                    rotulo={rotulo}
                    value={valores[k] ?? ''}
                    keyboardType="number-pad"
                    onChangeText={(t) => setValores((v) => ({ ...v, [k]: t.replace(/\D/g, '') }))}
                  />
                ))}
              </View>
            ))}
            {confirmar?.tipo === 'parametros' ? (
              caixaConfirmar
            ) : (
              <Botao
                titulo="Guardar parâmetros"
                desactivado={Object.keys(alterados).length === 0 || invalidos}
                aoCarregar={() => setConfirmar({ tipo: 'parametros' })}
              />
            )}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
