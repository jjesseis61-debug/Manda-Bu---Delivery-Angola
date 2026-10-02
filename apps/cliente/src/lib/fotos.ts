// Fotos das avaliações (I7): reduzir para JPEG, enviar para o bucket privado e obter
// endereços temporários para mostrar. O servidor decide o nome do ficheiro e quem o vê.
import { ImageManipulator, SaveFormat } from 'expo-image-manipulator';
import * as ImagePicker from 'expo-image-picker';

import { supabase } from './supabase';

export const BUCKET_FOTOS = 'fotos-avaliacoes';
const LARGURA_MAXIMA = 1280;

/** Abre a galeria e devolve até `maximo` fotos já reduzidas para JPEG (uri local) */
export async function escolherFotos(maximo: number): Promise<string[]> {
  if (maximo <= 0) return [];
  const permissao = await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (!permissao.granted) return [];
  const r = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ['images'],
    allowsMultipleSelection: maximo > 1,
    selectionLimit: maximo,
    quality: 1,
  });
  if (r.canceled) return [];
  const fotos: string[] = [];
  for (const a of r.assets.slice(0, maximo)) {
    const contexto = ImageManipulator.manipulate(a.uri);
    if (a.width > LARGURA_MAXIMA) contexto.resize({ width: LARGURA_MAXIMA });
    const imagem = await contexto.renderAsync();
    const final = await imagem.saveAsync({ format: SaveFormat.JPEG, compress: 0.7 });
    fotos.push(final.uri);
  }
  return fotos;
}

/** Envia o ficheiro para o caminho que o servidor atribuiu à foto */
export async function enviarFoto(caminho: string, uri: string): Promise<void> {
  const dados = await (await fetch(uri)).arrayBuffer();
  const { error } = await supabase.storage.from(BUCKET_FOTOS).upload(caminho, dados, {
    contentType: 'image/jpeg',
    upsert: false,
  });
  if (error) throw error;
}

/** Endereços temporários (1 hora) das fotos que a sessão pode ver */
export async function enderecosFotos(caminhos: string[]): Promise<Record<string, string>> {
  if (caminhos.length === 0) return {};
  const { data, error } = await supabase.storage.from(BUCKET_FOTOS).createSignedUrls(caminhos, 3600);
  if (error) throw error;
  const r: Record<string, string> = {};
  for (const d of data ?? []) if (d.path && d.signedUrl) r[d.path] = d.signedUrl;
  return r;
}
