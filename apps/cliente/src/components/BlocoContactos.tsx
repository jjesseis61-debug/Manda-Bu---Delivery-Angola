import { Linking, Text } from 'react-native';

import { Botao, Cartao, Linha } from '@/components/ui';
import { urlEmail, urlTelefone, urlWhatsapp } from '@/lib/contactos';
import { cores } from '@/lib/tema';
import type { Contacto } from '@/lib/tipos';

/** Contactos com botões para ligar, abrir o WhatsApp ou escrever um email (só os que estiverem preenchidos) */
export function BlocoContactos({ contacto, titulo }: { contacto: Contacto; titulo?: string }) {
  const abrir = (url: string) => Linking.openURL(url).catch(() => undefined);
  return (
    <Cartao>
      {titulo && <Text style={{ fontWeight: '700', color: cores.texto }}>{titulo}</Text>}
      {contacto.horario && <Linha esquerda="Horário" direita={contacto.horario} />}
      {contacto.morada && <Linha esquerda="Morada" direita={contacto.morada} />}
      {contacto.telefone && <Botao titulo={`Ligar ${contacto.telefone}`} variante="secundario" aoCarregar={() => abrir(urlTelefone(contacto.telefone!))} />}
      {contacto.whatsapp && <Botao titulo="WhatsApp" variante="whatsapp" aoCarregar={() => abrir(urlWhatsapp(contacto.whatsapp!))} />}
      {contacto.email && <Botao titulo={`Email ${contacto.email}`} variante="leve" aoCarregar={() => abrir(urlEmail(contacto.email!))} />}
    </Cartao>
  );
}

/** Há alguma coisa para mostrar? */
export function temContacto(c: Contacto | null | undefined): c is Contacto {
  return !!c && !!(c.telefone || c.whatsapp || c.email || c.horario || c.morada);
}
