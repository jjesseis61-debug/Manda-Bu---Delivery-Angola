// Exportação de relatórios: CSV (partilhado ou descarregado) e PDF (via impressão).
import { File, Paths } from 'expo-file-system';
import * as Print from 'expo-print';
import * as Sharing from 'expo-sharing';
import { Platform } from 'react-native';

export async function exportarCsv(nome: string, conteudo: string) {
  // BOM para o Excel abrir os acentos correctamente
  const texto = '﻿' + conteudo;
  if (Platform.OS === 'web') {
    const url = URL.createObjectURL(new Blob([texto], { type: 'text/csv;charset=utf-8' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = nome;
    a.click();
    URL.revokeObjectURL(url);
    return;
  }
  const ficheiro = new File(Paths.cache, nome);
  ficheiro.create({ overwrite: true });
  ficheiro.write(texto);
  await Sharing.shareAsync(ficheiro.uri, { mimeType: 'text/csv', dialogTitle: nome, UTI: 'public.comma-separated-values-text' });
}

export async function exportarPdf(html: string) {
  if (Platform.OS === 'web') {
    await Print.printAsync({ html });
    return;
  }
  const { uri } = await Print.printToFileAsync({ html });
  await Sharing.shareAsync(uri, { mimeType: 'application/pdf', UTI: 'com.adobe.pdf' });
}

/**
 * Imprime um talão. No Android há três degraus, para nunca ficar sem saída:
 * 1) gera o PDF do talão; 2) manda-o para a janela de impressão do sistema (impressora Wi-Fi,
 * de talões via serviço de impressão, ou "Guardar como PDF"); 3) se a impressão directa falhar,
 * abre "Partilhar" com o PDF (RawBT, outra app de impressão, WhatsApp).
 * Se tudo falhar, lança um erro com o motivo real (não o genérico "verifica a ligação").
 */
export async function imprimirHtml(html: string) {
  const cancelou = (e: unknown) => /did not complete|cancel/i.test(String((e as Error)?.message ?? e));
  if (Platform.OS === 'web') {
    await Print.printAsync({ html });
    return;
  }
  let uri: string;
  try {
    ({ uri } = await Print.printToFileAsync({ html }));
  } catch (e) {
    throw new Error(`Não foi possível preparar o talão: ${String((e as Error)?.message ?? e)}`);
  }
  try {
    await Print.printAsync({ uri });
    return;
  } catch (e) {
    if (cancelou(e)) return; // cancelar a impressão não é um erro
    if (await Sharing.isAvailableAsync()) {
      await Sharing.shareAsync(uri, { mimeType: 'application/pdf', UTI: 'com.adobe.pdf', dialogTitle: 'Imprimir talão' });
      return;
    }
    throw new Error(`Não foi possível imprimir: ${String((e as Error)?.message ?? e)}`);
  }
}

export function escaparHtml(texto: string): string {
  return texto.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] as string);
}
