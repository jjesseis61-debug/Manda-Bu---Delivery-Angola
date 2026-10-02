import * as Clipboard from 'expo-clipboard';
import { useState } from 'react';
import { Linking, Share, Text, View } from 'react-native';

import { registarPartilha } from '@/lib/api';
import { linkConvite } from '@/lib/convite';
import { mensagemConvite } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';

import { Botao } from './ui';

/** Código com Copiar e Partilhar no WhatsApp (mensagem N1 + link de convite) */
export function PartilharCodigo({ mostrarCodigo = true }: { mostrarCodigo?: boolean }) {
  const { perfil, parametros, ligada } = useSessao();
  const [copiado, setCopiado] = useState(false);

  if (!ligada('indicacao') || !perfil?.codigo || !parametros) return null;
  const codigo = perfil.codigo;
  const mensagem = mensagemConvite(codigo, parametros.desconto_indicado, linkConvite(codigo));

  async function partilhar() {
    void registarPartilha().catch(() => undefined);
    const whatsapp = `whatsapp://send?text=${encodeURIComponent(mensagem)}`;
    if (await Linking.canOpenURL(whatsapp).catch(() => false)) {
      await Linking.openURL(whatsapp);
    } else {
      await Share.share({ message: mensagem });
    }
  }

  async function copiar() {
    await Clipboard.setStringAsync(codigo);
    setCopiado(true);
    setTimeout(() => setCopiado(false), 2000);
  }

  return (
    <View style={{ gap: 10 }}>
      {mostrarCodigo && (
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
          <Text style={{ fontSize: 28, fontWeight: '800', letterSpacing: 2, color: cores.texto }}>{codigo}</Text>
          <Botao titulo={copiado ? 'Copiado' : 'Copiar'} variante="secundario" aoCarregar={copiar} />
        </View>
      )}
      <Botao titulo="Partilhar no WhatsApp" variante="whatsapp" aoCarregar={partilhar} />
    </View>
  );
}
