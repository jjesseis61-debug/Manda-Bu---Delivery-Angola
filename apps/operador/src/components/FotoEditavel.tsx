import { useState } from 'react';
import { Image, Text, View } from 'react-native';

import { Aviso, Botao } from '@/components/ui';
import { mensagemErro } from '@/lib/formatar';
import { apagarFotoPublica, apagarFotoReceita, enviarFotoPublica, enviarFotoReceita, escolherFoto } from '@/lib/fotos';
import { cores, espaco } from '@/lib/tema';

/**
 * Foto de um prato ou de uma cozinha: tirar, escolher da galeria, trocar e remover.
 *
 * Com `id` (registo já existente) envia a foto logo e `aoGravar` guarda o novo endereço (ou null).
 * Sem `id` (prato novo, ainda por gravar) fica em modo adiado: só escolhe a foto, mostra a
 * pré-visualização local e entrega o endereço local em `aoEscolherLocal`; quem usa o componente
 * envia a foto depois de criar o registo.
 */
export function FotoEditavel({
  tipo,
  id,
  url,
  aoGravar,
  localUri,
  aoEscolherLocal,
}: {
  tipo: 'pratos' | 'cozinhas' | 'receitas';
  id?: string;
  url?: string | null;
  aoGravar?: (url: string | null) => Promise<void>;
  localUri?: string | null;
  aoEscolherLocal?: (uri: string | null) => void;
}) {
  const [ocupado, setOcupado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const adiado = !id;
  const previa = url ?? localUri ?? null;

  async function trocar(origem: 'camera' | 'galeria') {
    setErro(null);
    try {
      const uri = await escolherFoto(origem);
      if (!uri) return;
      if (adiado) {
        aoEscolherLocal?.(uri);
        return;
      }
      setOcupado(true);
      const nova = tipo === 'receitas' ? await enviarFotoReceita(id as string, uri) : await enviarFotoPublica(tipo, id as string, uri);
      await aoGravar?.(nova);
      if (tipo === 'receitas') await apagarFotoReceita(url);
      else await apagarFotoPublica(url);
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  async function remover() {
    setErro(null);
    if (adiado) {
      aoEscolherLocal?.(null);
      return;
    }
    setOcupado(true);
    try {
      await aoGravar?.(null);
      if (tipo === 'receitas') await apagarFotoReceita(url);
      else await apagarFotoPublica(url);
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  return (
    <View style={{ gap: espaco.s }}>
      <Text style={{ fontWeight: '700' }}>Foto</Text>
      {previa ? (
        <Image source={{ uri: previa }} style={{ width: '100%', aspectRatio: 4 / 3, borderRadius: 8 }} accessibilityLabel="Foto" />
      ) : (
        <Text style={{ color: cores.textoSuave }}>Sem foto. Os clientes vêem a foto no cardápio.</Text>
      )}
      {adiado && previa && <Text style={{ color: cores.textoSuave }}>A foto é enviada quando guardares o prato.</Text>}
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
        <View style={{ flex: 1 }}>
          <Botao titulo="Tirar foto" variante="leve" aCarregar={ocupado} aoCarregar={() => trocar('camera')} />
        </View>
        <View style={{ flex: 1 }}>
          <Botao titulo="Da galeria" variante="leve" desactivado={ocupado} aoCarregar={() => trocar('galeria')} />
        </View>
      </View>
      {previa && <Botao titulo="Remover foto" variante="texto" desactivado={ocupado} aoCarregar={remover} />}
    </View>
  );
}
