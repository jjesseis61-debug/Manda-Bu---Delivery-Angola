// Ligações dos contactos públicos: telefone (tel:), WhatsApp (wa.me, com o indicativo de Angola se faltar) e email
export function urlTelefone(t: string): string {
  return `tel:${t.replace(/\s/g, '')}`;
}

export function urlWhatsapp(t: string): string {
  let numero = t.replace(/\D/g, '');
  if (numero.length === 9 && numero.startsWith('9')) numero = `244${numero}`;
  return `https://wa.me/${numero}`;
}

export function urlEmail(e: string): string {
  return `mailto:${e.trim()}`;
}
