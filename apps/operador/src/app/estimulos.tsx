import { useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { Aviso, Botao, Campo, Cartao, Ecra, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { decidirEstimulo, estimulosDoMes, gerarEstimulos, pedirNovaAnalise } from '@/lib/api';
import { diaLuanda, formatarKz, mensagemErro, nomeMetrica } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { Estimulo, MetricasEstimulo } from '@/lib/tipos';

const MES = /^\d{4}-\d{2}$/;

/** Mês anterior ao de hoje (o que normalmente se fecha), em AAAA-MM */
function mesAnterior(): string {
  const [a, m] = diaLuanda().slice(0, 7).split('-').map(Number);
  return m === 1 ? `${a - 1}-12` : `${a}-${String(m - 1).padStart(2, '0')}`;
}

function numero(m: MetricasEstimulo, chave: string): string {
  const v = m?.[chave];
  if (v == null) return '—';
  return chave === 'pct_a_horas' ? `${v}%` : chave === 'gasto' || chave === 'valor_balcao' ? formatarKz(v) : String(v);
}

/**
 * Estímulos do mês (Albert Bandura): cada pessoa comparada consigo própria, com uma meta próxima e o
 * melhor registo da equipa como modelo. O bónus sugerido é pela meta combinada; o administrador decide.
 */
export default function Estimulos() {
  const [mes, setMes] = useState(mesAnterior());
  const [lista, setLista] = useState<Estimulo[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [edicao, setEdicao] = useState<Record<string, { mensagem: string; bonus: string }>>({});

  const periodo = () => mes.split('-').map(Number) as [number, number];

  async function correr(f: () => Promise<unknown>, mensagem?: string) {
    setErro(null);
    setSucesso(null);
    setOcupado(true);
    try {
      await f();
      if (mensagem) setSucesso(mensagem);
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  async function carregar() {
    const l = await estimulosDoMes(...periodo());
    setLista(l);
    setEdicao(Object.fromEntries(l.map((e) => [e.id, { mensagem: e.ia_mensagem ?? e.mensagem, bonus: String(e.bonus_sugerido) }])));
  }

  const ver = () => correr(carregar);
  const gerar = () =>
    correr(async () => {
      const n = await gerarEstimulos(...periodo());
      await carregar();
      setSucesso(n === 0 ? 'Sem actividade neste mês.' : `${n} estímulos propostos. A mensagem pessoal chega dentro de minutos.`);
    });
  const decidir = (e: Estimulo, aprovar: boolean) =>
    correr(async () => {
      const ed = edicao[e.id];
      await decidirEstimulo(e.id, aprovar, aprovar && ed?.bonus ? Number(ed.bonus) : null, aprovar ? ed?.mensagem ?? null : null);
      await carregar();
    }, aprovar ? `Aprovado: ${e.nome} recebe a mensagem.` : 'Descartado.');

  function metricas(e: Estimulo) {
    const chaves =
      e.tipo === 'cliente'
        ? ['pedidos', 'gasto']
        : ['entregas', 'pct_a_horas', 'estrelas', 'vendas_balcao', 'confirmados', 'reclamacoes_procedentes', 'comprovativos_rejeitados'].filter(
            (k) => (e.metricas.mes?.[k] ?? 0) !== 0 || (e.metricas.anterior?.[k] ?? 0) !== 0,
          );
    const nomes: Record<string, string> = {
      ...nomeMetrica,
      estrelas: 'estrelas (média)',
      gasto: 'gasto',
      reclamacoes_procedentes: 'reclamações com razão',
      comprovativos_rejeitados: 'comprovativos rejeitados',
    };
    return chaves.map((k) => (
      <Linha key={k} esquerda={nomes[k] ?? k} direita={`${numero(e.metricas.mes, k)}  (antes ${numero(e.metricas.anterior, k)})`} />
    ));
  }

  function cartao(e: Estimulo) {
    const ed = edicao[e.id] ?? { mensagem: e.mensagem, bonus: String(e.bonus_sugerido) };
    return (
      <Cartao key={e.id}>
        <Text style={{ fontWeight: '700' }}>
          {e.nome}
          {e.tipo === 'cliente' ? ' · cliente' : e.cargo ? ` · ${e.cargo}` : ''}
        </Text>
        {metricas(e)}
        {e.meta_anterior && (
          <Text style={{ color: e.meta_anterior.atingida ? cores.sucesso : cores.textoSuave }}>
            Meta do mês anterior: {e.meta_anterior.valor} {nomeMetrica[e.meta_anterior.metrica] ?? ''} ·{' '}
            {e.meta_anterior.atingida ? 'atingida' : 'não atingida'}
          </Text>
        )}
        {e.meta && (
          <Text>
            Próxima meta: {e.meta.valor}
            {e.meta.metrica === 'pct_a_horas' ? '% a horas' : ` ${nomeMetrica[e.meta.metrica] ?? ''}`}
          </Text>
        )}
        {e.estado === 'proposto' ? (
          <View style={{ gap: espaco.s }}>
            <Paragrafo suave>
              {e.ia_estado === 'analisada'
                ? 'Mensagem escrita pela análise automática (podes editar):'
                : e.ia_estado === 'indisponivel'
                  ? 'Análise automática indisponível: texto base (podes editar):'
                  : 'A personalizar a mensagem… (texto base):'}
            </Paragrafo>
            <Campo
              rotulo="Mensagem"
              value={ed.mensagem}
              onChangeText={(t) => setEdicao({ ...edicao, [e.id]: { ...ed, mensagem: t } })}
              maxLength={600}
              multiline
            />
            <Campo
              rotulo={e.tipo === 'cliente' ? 'Prémio (Kz)' : 'Bónus (Kz)'}
              value={ed.bonus}
              onChangeText={(t) => setEdicao({ ...edicao, [e.id]: { ...ed, bonus: t.replace(/\D/g, '') } })}
              keyboardType="number-pad"
            />
            <Botao titulo="Aprovar e enviar" aCarregar={ocupado} desactivado={!ed.mensagem.trim()} aoCarregar={() => decidir(e, true)} />
            <Botao titulo="Descartar" variante="secundario" aoCarregar={() => decidir(e, false)} />
            {e.ia_estado === 'indisponivel' && (
              <Botao
                titulo="Personalizar de novo"
                variante="texto"
                aoCarregar={() => correr(async () => { await pedirNovaAnalise('estimulo', e.id); await carregar(); })}
              />
            )}
          </View>
        ) : (
          <View style={{ gap: espaco.xs }}>
            <Text style={{ fontWeight: '700' }}>
              {e.estado === 'aprovado' ? `Aprovado${e.bonus ? ` · ${formatarKz(e.bonus)}` : ''}` : 'Descartado'}
              {e.decidido_por ? ` · por ${e.decidido_por}` : ''}
            </Text>
            {e.mensagem_final && <Text>{e.mensagem_final}</Text>}
          </View>
        )}
      </Cartao>
    );
  }

  const equipa = lista?.filter((e) => e.tipo === 'funcionario') ?? [];
  const clientes = lista?.filter((e) => e.tipo === 'cliente') ?? [];
  return (
    <Guarda permissoes={['equipa.gerir']}>
      <Ecra>
        <Paragrafo suave>
          Cada pessoa é comparada consigo própria no mês anterior e recebe uma meta pequena e alcançável. O bónus sugerido
          só aparece quando a meta combinada foi atingida. Ninguém recebe nada sem a tua aprovação.
        </Paragrafo>
        <Campo rotulo="Mês (AAAA-MM)" value={mes} onChangeText={setMes} maxLength={7} />
        <Botao titulo="Ver estímulos" desactivado={!MES.test(mes)} aCarregar={ocupado} aoCarregar={ver} />
        <Botao titulo="Gerar ou actualizar propostas" variante="secundario" desactivado={!MES.test(mes)} aoCarregar={gerar} />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
        {lista && lista.length === 0 && <Paragrafo suave>Ainda não há estímulos para este mês. Carrega em «Gerar».</Paragrafo>}
        {equipa.length > 0 && <Subtitulo>Equipa</Subtitulo>}
        {equipa.map(cartao)}
        {clientes.length > 0 && <Subtitulo>Clientes que mais compraram</Subtitulo>}
        {clientes.map(cartao)}
      </Ecra>
    </Guarda>
  );
}
