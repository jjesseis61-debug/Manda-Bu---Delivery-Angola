import type { Contacto } from './tipos';

// Dados da empresa mostrados na app. Preencher antes de publicar nas lojas:
// a Google Play e a App Store pedem um contacto para questões de privacidade.
export const EMPRESA = {
  nome: 'Cozinha da Alexandra',
  contactoPrivacidade: process.env.EXPO_PUBLIC_CONTACTO_PRIVACIDADE ?? '',
  actualizadaEm: '2 de Outubro de 2026',
  /** I12: como pagar um pacote (número Multicaixa Express / Unitel Money, morada da loja) */
  instrucoesPagamento: process.env.EXPO_PUBLIC_INSTRUCOES_PAGAMENTO ?? '',
};

// Contacto de ajuda mostrado no ecrã de entrar — ANTES do login e, por isso, também
// offline. Vem da config da app (não do servidor, que exige sessão). Se as variáveis
// não estiverem preenchidas, o bloco simplesmente não aparece (temContacto === false).
export const CONTACTO_AJUDA: Contacto = {
  telefone: process.env.EXPO_PUBLIC_CONTACTO_TELEFONE?.trim() || null,
  whatsapp: process.env.EXPO_PUBLIC_CONTACTO_WHATSAPP?.trim() || null,
  horario: process.env.EXPO_PUBLIC_CONTACTO_HORARIO?.trim() || null,
  email: null,
  morada: null,
};
