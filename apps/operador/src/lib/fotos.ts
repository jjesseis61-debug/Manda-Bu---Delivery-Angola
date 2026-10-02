// Fotos dos pratos e das cozinhas: escolher (câmara ou galeria), reduzir para JPEG e enviar para o
// bucket público `fotos-pratos`. O endereço público fica no prato ou na cozinha.
import { ImageManipulator, SaveFormat } from 'expo-image-manipulator';
import * as ImagePicker from 'expo-image-picker';

import { supabase } from './supabase';

export const BUCKET_FOTOS_PRATOS = 'fotos-pratos';
const LARGURA_MAXIMA = 1200;

/** Abre a câmara ou a galeria (recorte quadrado 4:3) e devolve a foto reduzida, ou null se cancelar */
export async function escolherFoto(origem: 'camera' | 'galeria'): Promise<string | null> {
  const permissao =
    origem === 'camera'
      ? await ImagePicker.requestCameraPermissionsAsync()
      : await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (!permissao.granted) throw new Error('permissao_fotos');
  const opcoes: ImagePicker.ImagePickerOptions = { mediaTypes: ['images'], allowsEditing: true, aspect: [4, 3], quality: 1 };
  const r = origem === 'camera' ? await ImagePicker.launchCameraAsync(opcoes) : await ImagePicker.launchImageLibraryAsync(opcoes);
  if (r.canceled || !r.assets[0]) return null;
  const a = r.assets[0];
  const contexto = ImageManipulator.manipulate(a.uri);
  if (a.width > LARGURA_MAXIMA) contexto.resize({ width: LARGURA_MAXIMA });
  const imagem = await contexto.renderAsync();
  const final = await imagem.saveAsync({ format: SaveFormat.JPEG, compress: 0.75 });
  return final.uri;
}

/** Caminho no bucket: pratos/<id>/<data>.jpg ou cozinhas/<id>/<data>.jpg (um nome novo de cada vez, sem cache antiga) */
export function caminhoFoto(tipo: 'pratos' | 'cozinhas', id: string, agora: Date = new Date()): string {
  return `${tipo}/${id}/${agora.getTime()}.jpg`;
}

/** Caminho no bucket a partir do endereço público, ou null se o endereço não for deste bucket */
export function caminhoDoEndereco(url: string | null | undefined): string | null {
  if (!url) return null;
  const marca = `/object/public/${BUCKET_FOTOS_PRATOS}/`;
  const i = url.indexOf(marca);
  return i >= 0 ? decodeURIComponent(url.slice(i + marca.length).split('?')[0]) : null;
}

/** Envia a foto e devolve o endereço público */
export async function enviarFotoPublica(tipo: 'pratos' | 'cozinhas', id: string, uri: string): Promise<string> {
  const caminho = caminhoFoto(tipo, id);
  const dados = await (await fetch(uri)).arrayBuffer();
  const { error } = await supabase.storage
    .from(BUCKET_FOTOS_PRATOS)
    .upload(caminho, dados, { contentType: 'image/jpeg', upsert: false });
  if (error) throw error;
  return supabase.storage.from(BUCKET_FOTOS_PRATOS).getPublicUrl(caminho).data.publicUrl;
}

/** Apaga do bucket a foto antiga (se for deste bucket); falhas não impedem a troca */
export async function apagarFotoPublica(url: string | null | undefined): Promise<void> {
  const caminho = caminhoDoEndereco(url);
  if (caminho) await supabase.storage.from(BUCKET_FOTOS_PRATOS).remove([caminho]).then(() => undefined, () => undefined);
}
