import { Linking, Share } from 'react-native';

import { linkPartilhaPrato } from './convite';
import { EMPRESA } from './empresa';
import { mensagemPartilhaPrato } from './formatar';

/**
 * Partilha um prato no WhatsApp (abre o WhatsApp com a mensagem pronta); se o WhatsApp não existir,
 * cai no menu de partilha nativo. O precoLabel já vem formatado pelo ecrã (preço exacto ou "desde …").
 * O link aponta para a página do prato (com foto na pré-visualização) e reencaminha para a app.
 */
export async function partilharPrato(nome: string, precoLabel: string, cardapioId: string): Promise<void> {
  const mensagem = mensagemPartilhaPrato(nome, precoLabel, EMPRESA.nome, linkPartilhaPrato(cardapioId));
  const whatsapp = `whatsapp://send?text=${encodeURIComponent(mensagem)}`;
  if (await Linking.canOpenURL(whatsapp).catch(() => false)) {
    await Linking.openURL(whatsapp).catch(() => undefined);
  } else {
    await Share.share({ message: mensagem }).catch(() => undefined);
  }
}
