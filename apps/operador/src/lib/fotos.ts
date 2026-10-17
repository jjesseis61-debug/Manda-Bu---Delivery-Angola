// Fotos dos pratos e das cozinhas: escolher (câmara ou galeria), reduzir para JPEG e enviar para o
// bucket público `fotos-pratos`. O endereço público fica no prato ou na cozinha.
import { ImageManipulator, SaveFormat } from 'expo-image-manipulator';
import * as DocumentPicker from 'expo-document-picker';
import * as ImagePicker from 'expo-image-picker';

import { supabase } from './supabase';

export const BUCKET_FOTOS_PRATOS = 'fotos-pratos';
const LARGURA_MAXIMA = 1200;

/** Abre a câmara ou a galeria (recorte 4:3) e devolve a foto reduzida, ou null se cancelar.
 *  Sem recorte (comprovativos): a imagem inteira, para se ler a referência e o valor. */
export async function escolherFoto(origem: 'camera' | 'galeria', recortar = true): Promise<string | null> {
  const permissao =
    origem === 'camera'
      ? await ImagePicker.requestCameraPermissionsAsync()
      : await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (!permissao.granted) throw new Error('permissao_fotos');
  const opcoes: ImagePicker.ImagePickerOptions = recortar
    ? { mediaTypes: ['images'], allowsEditing: true, aspect: [4, 3], quality: 1 }
    : { mediaTypes: ['images'], allowsEditing: false, quality: 1 };
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

// ---------------------------------------------------------------- comprovativos de pagamento
// Bucket privado `comprovativos`: <pedido_id>/<data>.jpg. Envia quem entrega; vê quem confere a caixa.
export const BUCKET_COMPROVATIVOS = 'comprovativos';

export function caminhoComprovativo(pedidoId: string, agora: Date = new Date(), n = 0): string {
  return `${pedidoId}/${agora.getTime()}${n ? `-${n}` : ''}.jpg`;
}

/** Envia a foto do comprovativo de um pedido e devolve o caminho no bucket (vai na parcela) */
export async function enviarComprovativo(pedidoId: string, uri: string, n = 0): Promise<string> {
  const caminho = caminhoComprovativo(pedidoId, new Date(), n);
  const dados = await (await fetch(uri)).arrayBuffer();
  const { error } = await supabase.storage
    .from(BUCKET_COMPROVATIVOS)
    .upload(caminho, dados, { contentType: 'image/jpeg', upsert: false });
  if (error) throw error;
  return caminho;
}

/** Endereço temporário (10 min) para ver a foto de um comprovativo */
export async function enderecoComprovativo(caminho: string): Promise<string | null> {
  const { data } = await supabase.storage.from(BUCKET_COMPROVATIVOS).createSignedUrl(caminho, 600);
  return data?.signedUrl ?? null;
}

// ---------------------------------------------------------------- extratos
// Bucket privado `extratos`: <extrato_id>/<data>.pdf|jpg. Só quem tem financas.conferir envia e vê.
export const BUCKET_EXTRATOS = 'extratos';

export type FicheiroEscolhido = { uri: string; tipo: 'application/pdf' | 'image/jpeg' | 'image/png' };

/** Escolhe o extrato no telemóvel (PDF ou imagem); null se cancelar */
export async function escolherFicheiroExtrato(): Promise<FicheiroEscolhido | null> {
  const r = await DocumentPicker.getDocumentAsync({ type: ['application/pdf', 'image/*'], copyToCacheDirectory: true });
  if (r.canceled || !r.assets[0]) return null;
  const a = r.assets[0];
  const tipo = a.mimeType === 'application/pdf' || a.name?.toLowerCase().endsWith('.pdf')
    ? 'application/pdf'
    : a.mimeType === 'image/png' ? 'image/png' : 'image/jpeg';
  return { uri: a.uri, tipo };
}

export function caminhoExtrato(extratoId: string, tipo: FicheiroEscolhido['tipo'], agora: Date = new Date()): string {
  const ext = tipo === 'application/pdf' ? 'pdf' : tipo === 'image/png' ? 'png' : 'jpg';
  return `${extratoId}/${agora.getTime()}.${ext}`;
}

/** Envia o ficheiro do extrato e devolve o caminho no bucket */
export async function enviarExtrato(extratoId: string, ficheiro: FicheiroEscolhido): Promise<string> {
  const caminho = caminhoExtrato(extratoId, ficheiro.tipo);
  const dados = await (await fetch(ficheiro.uri)).arrayBuffer();
  const { error } = await supabase.storage.from(BUCKET_EXTRATOS).upload(caminho, dados, { contentType: ficheiro.tipo, upsert: false });
  if (error) throw error;
  return caminho;
}
