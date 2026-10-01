import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { lerCozinhas, relatorioCozinha } from '@/lib/api';
import { escaparHtml, exportarCsv, exportarPdf } from '@/lib/exportar';
import { diaLuanda, formatarDia, inicioMesLuanda, mensagemErro, paraCsv } from '@/lib/formatar';
import type { Cozinha, Relatorio } from '@/lib/tipos';

type Periodo = '7' | '30' | 'mes';

function intervalo(p: Periodo): [string, string] {
  if (p === 'mes') return [inicioMesLuanda(), diaLuanda()];
  return [diaLuanda(-(Number(p) - 1)), diaLuanda()];
}

function percentagem(v: number | null | undefined) {
  return v === null || v === undefined ? '—' : `${String(v).replace('.', ',')}%`;
}

function linhasCsv(cozinha: string, inicio: string, fim: string, r: Relatorio) {
  return [
    ['Cozinha', cozinha],
    ['Período', `${inicio} a ${fim}`],
    [],
    ['Dia', 'Pedidos entregues'],
    ...r.pedidos_por_dia.map((d) => [d.dia, d.pedidos]),
    [],
    ['Clientes novos', r.clientes_novos],
    ['Clientes novos por indicação', r.clientes_indicacao],
    ['Retenção 30 dias (%)', r.retencao['30'] ?? null],
    ['Retenção 60 dias (%)', r.retencao['60'] ?? null],
    ['Retenção 90 dias (%)', r.retencao['90'] ?? null],
    ['Média das avaliações', r.media_avaliacao],
    ['Prato mais pedido', r.prato_mais_pedido?.nome ?? null],
    ['Quantidade do prato mais pedido', r.prato_mais_pedido?.quantidade ?? null],
  ];
}

function html(cozinha: string, inicio: string, fim: string, r: Relatorio) {
  const linhas = linhasCsv(cozinha, inicio, fim, r)
    .map((l) => (l.length ? `<tr>${l.map((c) => `<td>${escaparHtml(String(c ?? '—'))}</td>`).join('')}</tr>` : '<tr><td colspan="2">&nbsp;</td></tr>'))
    .join('');
  return `<html><head><meta charset="utf-8"><style>
    body{font-family:sans-serif;padding:24px} h1{color:#B5121B} td{padding:4px 12px;border-bottom:1px solid #eee}
  </style></head><body><h1>Manda Bué · Relatório da cozinha</h1><table>${linhas}</table></body></html>`;
}

/** O9. Relatório por cozinha, exportável em CSV e PDF */
export default function Relatorios() {
  const [cozinhas, setCozinhas] = useState<Cozinha[] | null>(null);
  const [cozinhaId, setCozinhaId] = useState<string | null>(null);
  const [periodo, setPeriodo] = useState<Periodo>('30');
  const [rel, setRel] = useState<Relatorio | null>(null);
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

  const [inicio, fim] = intervalo(periodo);
  const nomeCozinha = cozinhas?.find((c) => c.id === cozinhaId)?.nome ?? '';

  async function gerar() {
    if (!cozinhaId) return;
    setErro(null);
    setACarregar(true);
    try {
      setRel(await relatorioCozinha(cozinhaId, inicio, fim));
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setACarregar(false);
    }
  }

  async function exportar(tipo: 'csv' | 'pdf') {
    if (!rel) return;
    try {
      if (tipo === 'csv') await exportarCsv(`relatorio-${inicio}-${fim}.csv`, paraCsv(linhasCsv(nomeCozinha, inicio, fim, rel)));
      else await exportarPdf(html(nomeCozinha, inicio, fim, rel));
    } catch (e) {
      setErro(mensagemErro(e));
    }
  }

  return (
    <Guarda permissoes={['relatorios.exportar']}>
      <Ecra>
        {!cozinhas && !erro && <ACarregar />}
        {cozinhas && cozinhas.length > 1 && cozinhaId && (
          <Escolha opcoes={cozinhas.map((c) => ({ valor: c.id, rotulo: c.nome }))} valor={cozinhaId} aoMudar={(v) => { setCozinhaId(v); setRel(null); }} />
        )}
        <Escolha
          opcoes={[
            { valor: '7', rotulo: '7 dias' },
            { valor: '30', rotulo: '30 dias' },
            { valor: 'mes', rotulo: 'Este mês' },
          ]}
          valor={periodo}
          aoMudar={(v) => {
            setPeriodo(v);
            setRel(null);
          }}
        />
        <Paragrafo suave>
          {nomeCozinha} · {formatarDia(inicio)} a {formatarDia(fim)}
        </Paragrafo>
        <Botao titulo="Gerar relatório" aCarregar={aCarregar} desactivado={!cozinhaId} aoCarregar={gerar} />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {rel && (
          <>
            <Cartao>
              <Linha esquerda="Pedidos entregues" direita={String(rel.pedidos_por_dia.reduce((s, d) => s + d.pedidos, 0))} forte />
              <Linha esquerda="Clientes novos" direita={String(rel.clientes_novos)} />
              <Linha esquerda="· por indicação" direita={String(rel.clientes_indicacao)} />
              <Linha esquerda="Retenção 30 / 60 / 90 dias" direita={`${percentagem(rel.retencao['30'])} / ${percentagem(rel.retencao['60'])} / ${percentagem(rel.retencao['90'])}`} />
              <Linha esquerda="Média das avaliações" direita={rel.media_avaliacao === null ? '—' : String(rel.media_avaliacao).replace('.', ',')} />
              <Linha esquerda="Prato mais pedido" direita={rel.prato_mais_pedido ? `${rel.prato_mais_pedido.nome} (${rel.prato_mais_pedido.quantidade})` : '—'} />
            </Cartao>
            <Subtitulo>Pedidos por dia</Subtitulo>
            {rel.pedidos_por_dia.length === 0 && <Paragrafo suave>Sem pedidos entregues no período.</Paragrafo>}
            {rel.pedidos_por_dia.map((d) => (
              <Linha key={d.dia} esquerda={formatarDia(d.dia)} direita={String(d.pedidos)} />
            ))}
            <Botao titulo="Exportar CSV" variante="secundario" aoCarregar={() => exportar('csv')} />
            <Botao titulo="Exportar PDF" variante="secundario" aoCarregar={() => exportar('pdf')} />
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
