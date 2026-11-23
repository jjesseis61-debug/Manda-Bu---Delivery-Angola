// Talões do pedido (impressora de talões 58/80 mm, Wi-Fi ou PDF):
// - COZINHA: o que preparar: pratos com as opções uma por linha, ingredientes a tirar e observações. Sem preços.
// - ENTREGA: para o estafeta: cliente, telefone, morada, pratos, valores e o que receber.
import { escaparHtml } from './exportar';
import { formatarData, formatarKz } from './formatar';
import type { PedidoOperador } from './tipos';

type ItemPedido = PedidoOperador['itens'][number];

/** Prato do pedido separado em nome, opções e ingredientes tirados (o servidor junta tudo no nome) */
export function detalharItem(i: ItemPedido): { nome: string; opcoes: string[]; sem: string[] } {
  const opcoes = (i.opcoes ?? []).map((o) => o.nome);
  const tirou = (i.componentes_excluidos?.length ?? 0) > 0;
  // O servidor acrescenta "(opções; sem X, Y)" no fim do nome; só se tira quando sabemos que foi ele
  const m = opcoes.length > 0 || tirou ? /^(.*) \(([^()]*)\)$/.exec(i.nome) : null;
  const nome = m ? m[1] : i.nome;
  const sem = m
    ? (m[2].split('; ').find((parte) => parte.startsWith('sem ')) ?? '')
        .slice(4)
        .split(', ')
        .filter(Boolean)
    : [];
  return { nome, opcoes, sem };
}

/** Número curto para chamar o pedido em voz alta na cozinha */
export function numeroCurto(pedidoId: string): string {
  return pedidoId.replace(/-/g, '').slice(0, 6).toUpperCase();
}

const estilo = `
  <style>
    @page { margin: 3mm; }
    body { font-family: -apple-system, Roboto, Arial, sans-serif; font-size: 13px; color: #000; margin: 0; }
    h1 { font-size: 18px; text-align: center; margin: 0 0 2px; letter-spacing: 1px; }
    .num { font-size: 22px; font-weight: 800; text-align: center; margin: 0 0 6px; }
    .linha { border-top: 1px dashed #000; margin: 6px 0; }
    .prato { font-weight: 700; font-size: 15px; margin-top: 4px; }
    .op { padding-left: 14px; }
    .sem { padding-left: 14px; font-weight: 700; }
    .obs { border: 2px solid #000; padding: 4px; font-weight: 700; margin-top: 6px; }
    .dir { display: flex; justify-content: space-between; }
    .total { font-size: 17px; font-weight: 800; }
    .peq { font-size: 11px; }
  </style>`;

function cabecalho(titulo: string, p: PedidoOperador): string {
  return `
    <h1>${titulo}</h1>
    <p class="num">#${numeroCurto(p.pedido_id)}</p>
    <div>Pedido: ${escaparHtml(formatarData(p.criado_em, true))}</div>
    ${p.hora_prometida ? `<div><b>Entregar até: ${escaparHtml(formatarData(p.hora_prometida, true))}</b></div>` : ''}
    <div>Cliente: ${escaparHtml(p.cliente_nome)}</div>`;
}

function observacoes(p: PedidoOperador): string {
  return p.observacoes ? `<div class="obs">OBS: ${escaparHtml(p.observacoes)}</div>` : '';
}

export function htmlTalaoCozinha(p: PedidoOperador): string {
  const pratos = p.itens
    .map((i) => {
      const d = detalharItem(i);
      return `
        <div class="prato">${i.qtd}× ${escaparHtml(d.nome)}</div>
        ${d.opcoes.map((o) => `<div class="op">- ${escaparHtml(o)}</div>`).join('')}
        ${d.sem.map((s) => `<div class="sem">SEM ${escaparHtml(s)}</div>`).join('')}`;
    })
    .join('');
  return `<html><head><meta charset="utf-8">${estilo}</head><body>
    ${cabecalho('COZINHA', p)}
    <div class="linha"></div>
    ${pratos}
    ${observacoes(p)}
    <div class="linha"></div>
    <div class="peq">Impresso ${escaparHtml(formatarData(new Date().toISOString(), true))}</div>
  </body></html>`;
}

export function htmlTalaoEntrega(p: PedidoOperador): string {
  const morada = [p.ponto_tipo === 'empresa' ? 'Empresa' : 'Casa', p.ponto_referencia, p.zona_nome].filter(Boolean).join(' · ');
  const pratos = p.itens
    .map((i) => {
      const d = detalharItem(i);
      const detalhe = [...d.opcoes, ...d.sem.map((s) => `sem ${s}`)].join(', ');
      return `
        <div class="dir"><span>${i.qtd}× ${escaparHtml(d.nome)}</span><span>${formatarKz(i.qtd * i.preco_unitario)}</span></div>
        ${detalhe ? `<div class="op peq">${escaparHtml(detalhe)}</div>` : ''}`;
    })
    .join('');
  const valores = [
    `<div class="dir"><span>Subtotal</span><span>${formatarKz(p.subtotal)}</span></div>`,
    `<div class="dir"><span>Entrega</span><span>${formatarKz(p.taxa_entrega)}</span></div>`,
    p.desconto_indicacao > 0 ? `<div class="dir"><span>Desconto</span><span>−${formatarKz(p.desconto_indicacao)}</span></div>` : '',
    p.credito_indicacao_usado > 0 ? `<div class="dir"><span>Saldo usado</span><span>−${formatarKz(p.credito_indicacao_usado)}</span></div>` : '',
  ].join('');
  return `<html><head><meta charset="utf-8">${estilo}</head><body>
    ${cabecalho('ENTREGA', p)}
    ${p.cliente_telefone ? `<div>Tel: +244 ${escaparHtml(p.cliente_telefone)}</div>` : ''}
    <div><b>Morada: ${escaparHtml(morada)}</b></div>
    <div class="linha"></div>
    ${pratos}
    <div class="linha"></div>
    ${valores}
    <div class="dir total"><span>A RECEBER</span><span>${formatarKz(p.a_pagar)}</span></div>
    <div class="peq">Pago na entrega.</div>
    ${observacoes(p)}
  </body></html>`;
}
