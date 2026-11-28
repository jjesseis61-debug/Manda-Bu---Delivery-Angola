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

export function escaparHtml(texto: string): string {
  return texto.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] as string);
}
