import { Linking, Share } from 'react-native';

import { registarPartilha } from './api';
import { linkPartilhaPrato } from './convite';
import { EMPRESA } from './empresa';
import { mensagemPartilhaPrato } from './formatar';

export type ConvitePartilha = { codigo: string; desconto: number; minimo?: number };

/**
 * Partilha um prato no WhatsApp (abre o WhatsApp com a mensagem pronta); se o WhatsApp não existir,
 * cai no menu de partilha nativo. O link aponta para a página do prato (foto + nome + preço na
 * pré-visualização). Com o código de convite de quem partilha, o link leva-o (`?r=`), a mensagem
 * diz o desconto do amigo e a partilha conta para o painel do embaixador.
 */
export async function partilharPrato(nome: string, cardapioId: string, convite?: ConvitePartilha | null): Promise<void> {
  const mensagem = mensagemPartilhaPrato(nome, EMPRESA.nome, linkPartilhaPrato(cardapioId, convite?.codigo), convite);
  if (convite) void registarPartilha().catch(() => undefined);
  const whatsapp = `whatsapp://send?text=${encodeURIComponent(mensagem)}`;
  if (await Linking.canOpenURL(whatsapp).catch(() => false)) {
    await Linking.openURL(whatsapp).catch(() => undefined);
  } else {
    await Share.share({ message: mensagem }).catch(() => undefined);
  }
}
