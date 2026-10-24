// Comprovativo do pedido em PDF (via impressão). É um documento informativo — NÃO é fatura fiscal
// (em Angola a fatura sai de software certificado; é emitida na cozinha, na entrega).
import * as Print from 'expo-print';
import * as Sharing from 'expo-sharing';
import { Platform } from 'react-native';

import { formatarKz } from './formatar';
import type { Pedido } from './tipos';

function esc(texto: string): string {
  return texto.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] as string);
}

function linha(esquerda: string, direita: string, forte = false): string {
  const peso = forte ? 'font-weight:700;border-top:1px solid #ddd;' : '';
  return `<tr><td style="padding:4px 0;${peso}">${esc(esquerda)}</td><td style="padding:4px 0;text-align:right;${peso}">${esc(direita)}</td></tr>`;
}

function html(pedido: Pedido, cliente: { nome?: string; telefone?: string | null }): string {
  const total = pedido.subtotal + pedido.taxa_entrega - pedido.desconto_indicacao;
  const pago = total - pedido.credito_indicacao_usado - (pedido.pago_pacote ?? 0) - (pedido.valor_empresa ?? 0);
  const quando = new Date(pedido.entregue_em ?? pedido.criado_em).toLocaleString('pt-PT', { dateStyle: 'short', timeStyle: 'short' });
  const numero = pedido.id.slice(0, 8).toUpperCase();

  const itens = pedido.itens
    .map((i) => linha(`${i.qtd}× ${i.nome}`, formatarKz(i.qtd * i.preco_unitario)))
    .join('');
  const extras = [
    linha('Entrega', formatarKz(pedido.taxa_entrega)),
    pedido.desconto_indicacao > 0 ? linha('Desconto de convite', `−${formatarKz(pedido.desconto_indicacao)}`) : '',
    pedido.credito_indicacao_usado > 0 ? linha('Saldo do Convida e Ganha', `−${formatarKz(pedido.credito_indicacao_usado)}`) : '',
    (pedido.pago_pacote ?? 0) > 0 ? linha('Pago com o pacote', `−${formatarKz(pedido.pago_pacote)}`) : '',
    (pedido.valor_empresa ?? 0) > 0 ? linha('Pago pela empresa', `−${formatarKz(pedido.valor_empresa)}`) : '',
    linha('Valor pago', formatarKz(pago), true),
  ].join('');

  return `<!doctype html><html lang="pt"><head><meta charset="utf-8">
<style>
  body { font-family: -apple-system, Roboto, Arial, sans-serif; color: #1a1a1a; padding: 28px; }
  h1 { font-size: 20px; margin: 0; }
  .marca { color: #C8102E; font-weight: 800; }
  .aviso { background: #fff6e5; border: 1px solid #f0c674; border-radius: 8px; padding: 10px 12px; margin: 16px 0; font-size: 13px; }
  .meta { color: #555; font-size: 13px; margin: 2px 0; }
  table { width: 100%; border-collapse: collapse; margin-top: 14px; font-size: 14px; }
  .rodape { margin-top: 24px; color: #777; font-size: 12px; }
</style></head><body>
  <h1><span class="marca">Manda Bué</span> — Delivery Angola</h1>
  <p class="meta">Comprovativo do pedido</p>
  <div class="aviso"><b>Documento informativo — não é fatura fiscal.</b> A fatura é emitida na cozinha, na entrega.</div>
  <p class="meta">Pedido n.º <b>${esc(numero)}</b></p>
  <p class="meta">Data: ${esc(quando)}</p>
  ${cliente.nome ? `<p class="meta">Cliente: ${esc(cliente.nome)}</p>` : ''}
  ${cliente.telefone ? `<p class="meta">Telefone: ${esc(cliente.telefone)}</p>` : ''}
  <table>${itens}${extras}</table>
  <p class="rodape">Preços com IVA incluído, quando aplicável. Obrigado por pedires na Manda Bué.</p>
</body></html>`;
}

/** Gera o comprovativo em PDF e abre a partilha (ou a impressão, na web). */
export async function comprovativoPedidoPdf(pedido: Pedido, cliente: { nome?: string; telefone?: string | null }): Promise<void> {
  const conteudo = html(pedido, cliente);
  if (Platform.OS === 'web') {
    await Print.printAsync({ html: conteudo });
    return;
  }
  const { uri } = await Print.printToFileAsync({ html: conteudo });
  await Sharing.shareAsync(uri, { mimeType: 'application/pdf', dialogTitle: `Comprovativo ${pedido.id.slice(0, 8).toUpperCase()}`, UTI: 'com.adobe.pdf' });
}
