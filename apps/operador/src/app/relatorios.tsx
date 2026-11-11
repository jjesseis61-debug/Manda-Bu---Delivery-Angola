import { useFocusEffect } from 'expo-router';
import { useCallback, useState, type ReactNode } from 'react';
import { Pressable, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo } from '@/components/ui';
import { lerCozinhas, relatorioComparativo, relatorioCozinhaDetalhado } from '@/lib/api';
import { escaparHtml, exportarCsv, exportarPdf } from '@/lib/exportar';
import { formatarDia, formatarKz, mensagemErro, paraCsv } from '@/lib/formatar';
import {
  htmlRelatorio,
  indicadores,
  linhasCsvRelatorio,
  nomeDiaSemana,
  periodoRel,
  type PeriodoRel,
  type RelatorioDetalhado,
} from '@/lib/relatorio';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Cozinha, LinhaComparativo } from '@/lib/tipos';

function percentagem(v: number | null | undefined) {
  return v === null || v === undefined ? '—' : `${String(v).replace('.', ',')}%`;
}

const COMPARAR = 'comparar';

function linhasComparativo(inicio: string, fim: string, l: LinhaComparativo[]) {
  return [
    ['Período', `${inicio} a ${fim}`],
    ['Pedidos da app entregues e pagos no período'],
    [],
    ['Cozinha', 'Estado', 'Pedidos', 'Vendas (Kz)', 'Ticket médio (Kz)', 'Cancelados', 'Clientes', 'Clientes novos',
     'Novos por indicação', 'Entregas a horas (%)', 'Média das avaliações', 'Avaliações'],
    ...l.map((c) => [c.nome, c.estado, c.pedidos, c.vendas, c.ticket_medio, c.cancelados, c.clientes, c.clientes_novos,
                     c.clientes_indicacao, c.pct_a_horas, c.media_avaliacao, c.avaliacoes]),
  ];
}

function htmlTabela(titulo: string, linhas: (string | number | null)[][]) {
  const corpo = linhas
    .map((l) => (l.length ? `<tr>${l.map((c) => `<td>${escaparHtml(String(c ?? '—'))}</td>`).join('')}</tr>` : '<tr><td>&nbsp;</td></tr>'))
    .join('');
  return `<html><head><meta charset="utf-8"><style>
    body{font-family:sans-serif;padding:24px} h1{color:#B5121B} td{padding:4px 8px;border-bottom:1px solid #eee;font-size:12px}
  </style></head><body><h1>${escaparHtml(titulo)}</h1><table>${corpo}</table></body></html>`;
}

/** Secção recolhível: abre só o que interessa */
function Seccao({ titulo, children, aberta = false }: { titulo: string; children: ReactNode; aberta?: boolean }) {
  const [aberto, setAberto] = useState(aberta);
  return (
    <Cartao estilo={{ gap: espaco.xs }}>
      <Pressable accessibilityRole="button" onPress={() => setAberto(!aberto)}>
        <Text style={{ fontWeight: '700', fontSize: 16, color: cores.texto }}>
          {aberto ? '▾' : '▸'} {titulo}
        </Text>
      </Pressable>
      {aberto && <View style={{ gap: espaco.xs }}>{children}</View>}
    </Cartao>
  );
}

const nada = <Paragrafo suave>Sem dados no período.</Paragrafo>;

/** O9. Relatório detalhado por cozinha (dia ou datas à escolha) e comparativo entre cozinhas */
export default function Relatorios() {
  const { funcionario } = useSessao();
  const [cozinhas, setCozinhas] = useState<Cozinha[] | null>(null);
  const [cozinhaId, setCozinhaId] = useState<string | null>(null);
  const [periodo, setPeriodo] = useState<PeriodoRel>('hoje');
  const [de, setDe] = useState('');
  const [ate, setAte] = useState('');
  const [rel, setRel] = useState<RelatorioDetalhado | null>(null);
  const [comp, setComp] = useState<LinhaComparativo[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aCarregar, setACarregar] = useState(false);

  useFocusEffect(
    useCallback(() => {
      lerCozinhas()
        .then((cs) => {
          setCozinhas(cs);
          setCozinhaId((actual) => actual ?? cs[0]?.id ?? null);
        })
        .catch((e) => setErro(mensagemErro(e)));
    }, []),
  );

  const intervalo = periodoRel(periodo, new Date(), de, ate);
  const [inicio, fim] = intervalo ?? ['', ''];
  const nomeCozinha = cozinhas?.find((c) => c.id === cozinhaId)?.nome ?? '';

  function limpar() {
    setRel(null);
    setComp(null);
  }

  async function gerar() {
    if (!cozinhaId || !intervalo) return;
    setErro(null);
    setACarregar(true);
    try {
      if (cozinhaId === COMPARAR) setComp(await relatorioComparativo(inicio, fim));
      else setRel(await relatorioCozinhaDetalhado(cozinhaId, inicio, fim));
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setACarregar(false);
    }
  }

  async function exportar(tipo: 'csv' | 'pdf') {
    if (!rel) return;
    try {
      if (tipo === 'csv') await exportarCsv(`relatorio-${rel.inicio}-${rel.fim}.csv`, paraCsv(linhasCsvRelatorio(rel)));
      else await exportarPdf(htmlRelatorio(rel, funcionario?.nome ?? 'operador', new Date()));
    } catch (e) {
      setErro(mensagemErro(e));
    }
  }

  return (
    <Guarda permissoes={['relatorios.exportar']}>
      <Ecra>
        {!cozinhas && !erro && <ACarregar />}
        {cozinhas && cozinhas.length > 1 && cozinhaId && (
          <Escolha
            opcoes={[...cozinhas.map((c) => ({ valor: c.id, rotulo: c.nome })), { valor: COMPARAR, rotulo: 'Comparar cozinhas' }]}
            valor={cozinhaId}
            aoMudar={(v) => {
              setCozinhaId(v);
              limpar();
            }}
          />
        )}
        <Escolha<PeriodoRel>
          opcoes={[
            { valor: 'hoje', rotulo: 'Hoje' },
            { valor: 'ontem', rotulo: 'Ontem' },
            { valor: '7', rotulo: '7 dias' },
            { valor: 'mes', rotulo: 'Este mês' },
            { valor: 'mes_anterior', rotulo: 'Mês anterior' },
            { valor: 'datas', rotulo: 'Datas…' },
          ]}
          valor={periodo}
          aoMudar={(v) => {
            setPeriodo(v);
            limpar();
          }}
        />
        {periodo === 'datas' && (
          <View style={{ flexDirection: 'row', gap: espaco.s }}>
            <View style={{ flex: 1 }}>
              <Campo rotulo="De (aaaa-mm-dd)" value={de} onChangeText={(t) => { setDe(t); limpar(); }} placeholder="2026-11-01" maxLength={10} />
            </View>
            <View style={{ flex: 1 }}>
              <Campo rotulo="Até (aaaa-mm-dd)" value={ate} onChangeText={(t) => { setAte(t); limpar(); }} placeholder="2026-11-30" maxLength={10} />
            </View>
          </View>
        )}
        <Paragrafo suave>
          {intervalo
            ? `${cozinhaId === COMPARAR ? 'Todas as cozinhas' : nomeCozinha} · ${formatarDia(inicio)} a ${formatarDia(fim)}`
            : 'Escreve as datas (máximo 366 dias).'}
        </Paragrafo>
        <Botao titulo="Gerar relatório" aCarregar={aCarregar} desactivado={!cozinhaId || !intervalo} aoCarregar={gerar} />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {comp && (
          <>
            {comp.map((c) => (
              <Cartao key={c.cozinha_id}>
                <Linha esquerda={c.nome} direita={formatarKz(c.vendas)} forte />
                <Linha esquerda="Pedidos · ticket médio" direita={`${c.pedidos} · ${c.ticket_medio !== null ? formatarKz(c.ticket_medio) : '—'}`} />
                <Linha esquerda="Clientes · novos · por indicação" direita={`${c.clientes} · ${c.clientes_novos} · ${c.clientes_indicacao}`} />
                <Linha esquerda="Cancelados" direita={String(c.cancelados)} />
                <Linha esquerda="Entregas a horas" direita={percentagem(c.pct_a_horas)} />
                <Linha
                  esquerda="Média das avaliações"
                  direita={c.media_avaliacao === null ? `— (${c.avaliacoes})` : `${String(c.media_avaliacao).replace('.', ',')} (${c.avaliacoes})`}
                />
                {c.estado !== 'activa' && <Paragrafo suave>Cozinha {c.estado}</Paragrafo>}
              </Cartao>
            ))}
            <Botao
              titulo="Exportar CSV"
              variante="secundario"
              aoCarregar={() =>
                exportarCsv(`comparativo-${inicio}-${fim}.csv`, paraCsv(linhasComparativo(inicio, fim, comp))).catch((e) => setErro(mensagemErro(e)))
              }
            />
            <Botao
              titulo="Exportar PDF"
              variante="secundario"
              aoCarregar={() =>
                exportarPdf(htmlTabela('Manda Bué · Comparativo das cozinhas', linhasComparativo(inicio, fim, comp))).catch((e) =>
                  setErro(mensagemErro(e)),
                )
              }
            />
          </>
        )}
        {rel && (
          <>
            <Cartao estilo={{ gap: espaco.xs }}>
              {indicadores(rel).map((i, n) => (
                <Linha
                  key={i.rotulo}
                  forte={n === 0 || i.rotulo === 'A receber pela cozinha'}
                  esquerda={i.rotulo}
                  direita={i.variacao ? `${i.valor}  ${i.variacao}` : i.valor}
                />
              ))}
              <Paragrafo suave>▲/▼ comparado com o período anterior da mesma duração. Descontos de convite e saldo Convida são pagos pela plataforma.</Paragrafo>
            </Cartao>

            <Seccao titulo="Vendas no tempo">
              {rel.por_dia.length > 1 &&
                rel.por_dia.map((d) => <Linha key={d.dia} esquerda={formatarDia(d.dia)} direita={`${d.pedidos} · ${formatarKz(d.vendas)}`} />)}
              {rel.por_hora.length === 0 ? nada : <Text style={{ fontWeight: '700', color: cores.texto }}>Por hora (picos)</Text>}
              {rel.por_hora.map((h) => (
                <Linha key={h.hora} esquerda={`${h.hora}h–${h.hora + 1}h`} direita={`${h.pedidos} · ${formatarKz(h.vendas)}`} />
              ))}
              {rel.por_dia_semana && rel.por_dia_semana.length > 0 && <Text style={{ fontWeight: '700', color: cores.texto }}>Por dia da semana</Text>}
              {rel.por_dia_semana?.map((d) => (
                <Linha key={d.dow} esquerda={nomeDiaSemana(d.dow)} direita={`${d.pedidos} · ${formatarKz(d.vendas)}`} />
              ))}
            </Seccao>

            <Seccao titulo="Cardápio (o que vendemos)">
              {rel.pratos.length === 0 && nada}
              {rel.pratos.map((p) => (
                <Linha key={p.nome} esquerda={`${p.qtd}× ${p.nome}`} direita={`${formatarKz(p.receita)} · ${percentagem(p.pct)}`} />
              ))}
              {rel.opcoes_montados.length > 0 && (
                <Text style={{ fontWeight: '700', color: cores.texto }}>
                  Montados: opções mais escolhidas{rel.montado_valor_medio ? ` (valor médio ${formatarKz(rel.montado_valor_medio)})` : ''}
                </Text>
              )}
              {rel.opcoes_montados.slice(0, 10).map((o) => <Linha key={o.nome} esquerda={o.nome} direita={String(o.qtd)} />)}
              {rel.sem_vendas.length > 0 && <Paragrafo suave>Sem vendas no período: {rel.sem_vendas.join(', ')}</Paragrafo>}
            </Seccao>

            <Seccao titulo="Dinheiro e pagamentos">
              {rel.pagamentos.length === 0 && nada}
              {rel.pagamentos.map((p) => (
                <Linha key={p.metodo} esquerda={`${p.metodo} (${p.pedidos})`} direita={formatarKz(p.valor)} />
              ))}
              <Linha esquerda="Vendas líquidas (após descontos)" direita={formatarKz(rel.resumo.vendas_liquidas)} />
              <Paragrafo suave>Diferenças de caixa e comprovativos: ver Caixa e Conferência.</Paragrafo>
            </Seccao>

            <Seccao titulo="Operação e serviço">
              <Linha esquerda="Tempo médio até entregar" direita={rel.tempo_medio_min == null ? '—' : `${rel.tempo_medio_min} min`} />
              <Linha esquerda="Agendados · grupo/empresa" direita={`${rel.agendados} · ${rel.grupo_empresa}`} />
              {rel.cancelamentos_motivos.length > 0 && <Text style={{ fontWeight: '700', color: cores.texto }}>Cancelamentos por motivo</Text>}
              {rel.cancelamentos_motivos.map((c) => <Linha key={c.motivo} esquerda={c.motivo} direita={String(c.n)} />)}
              {rel.estafetas.length > 0 && <Text style={{ fontWeight: '700', color: cores.texto }}>Estafetas</Text>}
              {rel.estafetas.map((e) => (
                <Linha key={e.nome} esquerda={e.nome} direita={`${e.entregas} · a horas ${percentagem(e.a_horas_pct)}`} />
              ))}
              {rel.preparadores.length > 0 && <Text style={{ fontWeight: '700', color: cores.texto }}>Preparadores</Text>}
              {rel.preparadores.map((p) => <Linha key={p.nome} esquerda={p.nome} direita={String(p.pedidos)} />)}
            </Seccao>

            <Seccao titulo="Clientes e zonas">
              {rel.zonas.length === 0 && nada}
              {rel.zonas.map((z) => <Linha key={z.zona} esquerda={z.zona} direita={`${z.pedidos} · ${formatarKz(z.vendas)}`} />)}
            </Seccao>

            <Seccao titulo="Qualidade">
              {['5', '4', '3', '2', '1'].map((e) => (
                <Linha key={e} esquerda={'★'.repeat(Number(e))} direita={String(rel.estrelas[e] ?? 0)} />
              ))}
              <Linha esquerda="Reclamações (abertas)" direita={`${rel.reclamacoes} (${rel.reclamacoes_abertas})`} />
            </Seccao>

            <Seccao titulo="Convida e Ganha">
              <Linha esquerda="Pedidos com desconto de convite" direita={String(rel.convida.pedidos_com_desconto)} />
              <Linha esquerda="Desconto de convite · saldo usado" direita={`${formatarKz(rel.resumo.desconto_convite)} · ${formatarKz(rel.resumo.saldo_convida)}`} />
              <Linha esquerda="Comissões geradas aos convidantes" direita={formatarKz(rel.convida.comissoes_geradas)} />
              <Paragrafo suave>Custos suportados pela plataforma (não saem do valor a receber pela cozinha).</Paragrafo>
            </Seccao>

            <Botao titulo="Exportar CSV (Excel)" variante="secundario" aoCarregar={() => exportar('csv')} />
            <Botao titulo="Exportar PDF" variante="secundario" aoCarregar={() => exportar('pdf')} />
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
