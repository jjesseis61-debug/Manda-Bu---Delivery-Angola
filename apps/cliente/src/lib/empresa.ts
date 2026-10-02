// Dados da empresa mostrados na app. Preencher antes de publicar nas lojas:
// a Google Play e a App Store pedem um contacto para questões de privacidade.
export const EMPRESA = {
  nome: 'Manda Bué — Delivery Angola',
  contactoPrivacidade: process.env.EXPO_PUBLIC_CONTACTO_PRIVACIDADE ?? '',
  actualizadaEm: '2 de Outubro de 2026',
  /** I12: como pagar um pacote (número Multicaixa Express / Unitel Money, morada da loja) */
  instrucoesPagamento: process.env.EXPO_PUBLIC_INSTRUCOES_PAGAMENTO ?? '',
};
