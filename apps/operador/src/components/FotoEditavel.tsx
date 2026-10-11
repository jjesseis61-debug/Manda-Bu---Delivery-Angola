import { useState } from 'react';
import { Image, Text, View } from 'react-native';

import { Aviso, Botao } from '@/components/ui';
import { mensagemErro } from '@/lib/formatar';
import { apagarFotoPublica, enviarFotoPublica, escolherFoto } from '@/lib/fotos';
import { cores, espaco } from '@/lib/tema';

/**
 * Foto de um prato ou de uma cozinha: tirar, escolher da galeria, trocar e remover.
 * `aoGravar` grava logo o novo endereço (ou null) no registo; a foto antiga é apagada depois.
 */
export function FotoEditavel({
  tipo,
  id,
  url,
  aoGravar,
}: {
  tipo: 'pratos' | 'cozinhas';
  id: string;
  url: string | null | undefined;
  aoGravar: (url: string | null) => Promise<void>;
}) {
  const [ocupado, setOcupado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  async function trocar(origem: 'camera' | 'galeria') {
    setErro(null);
    try {
      const uri = await escolherFoto(origem);
      if (!uri) return;
      setOcupado(true);
      const nova = await enviarFotoPublica(tipo, id, uri);
      await aoGravar(nova);
      await apagarFotoPublica(url);
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  async function remover() {
    setErro(null);
    setOcupado(true);
    try {
      await aoGravar(null);
      await apagarFotoPublica(url);
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  return (
    <View style={{ gap: espaco.s }}>
      <Text style={{ fontWeight: '700' }}>Foto</Text>
      {url ? (
        <Image source={{ uri: url }} style={{ width: '100%', aspectRatio: 4 / 3, borderRadius: 8 }} accessibilityLabel="Foto" />
      ) : (
        <Text style={{ color: cores.textoSuave }}>Sem foto. Os clientes vêem a foto no cardápio.</Text>
      )}
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
        <View style={{ flex: 1 }}>
          <Botao titulo="Tirar foto" variante="leve" aCarregar={ocupado} aoCarregar={() => trocar('camera')} />
        </View>
        <View style={{ flex: 1 }}>
          <Botao titulo="Da galeria" variante="leve" desactivado={ocupado} aoCarregar={() => trocar('galeria')} />
        </View>
      </View>
      {url && <Botao titulo="Remover foto" variante="texto" desactivado={ocupado} aoCarregar={remover} />}
    </View>
  );
}
