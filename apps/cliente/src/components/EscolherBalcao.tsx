import { ActivityIndicator, Modal, Pressable, ScrollView, Text, View } from 'react-native';

import { cores, espaco, raio } from '@/lib/tema';
import type { CozinhaParaPedir } from '@/lib/tipos';

/** «1,2 km» (uma casa decimal, vírgula) */
export const textoDistancia = (km: number) => `${km.toLocaleString('pt-PT', { maximumFractionDigits: 1, minimumFractionDigits: km < 10 ? 1 : 0 })} km`;

/**
 * Botão do título com o balcão de onde se está a pedir («📍 Viana ▾»): a primeira decisão fica no topo,
 * antes das campanhas e do cardápio, em vez de aparecer a meio da página.
 */
export function BotaoBalcao({ nome, aoCarregar, estreito = false }: { nome: string; aoCarregar: () => void; estreito?: boolean }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`A pedir de ${nome}. Toca para mudar`}
      hitSlop={6}
      onPress={aoCarregar}
      style={{
        flexDirection: 'row',
        alignItems: 'center',
        borderWidth: 1.5,
        borderColor: cores.marca,
        borderRadius: 16,
        paddingHorizontal: 10,
        paddingVertical: 4,
        maxWidth: estreito ? 120 : 150,
        marginRight: estreito ? 8 : 12,
      }}>
      <Text numberOfLines={1} style={{ color: cores.marca, fontWeight: '700', fontSize: 13, flexShrink: 1 }}>
        {`📍 ${nome}`}
      </Text>
      <Text style={{ color: cores.marca, fontWeight: '700', fontSize: 13 }}> ▾</Text>
    </Pressable>
  );
}

/** Lista dos balcões (mais perto primeiro) para escolher de onde pedir */
export function FolhaBalcoes({
  visivel,
  cozinhas,
  actual,
  referencia,
  aoPertoDeMim,
  aLocalizar = false,
  erroLocalizacao,
  aoEscolher,
  aoFechar,
}: {
  visivel: boolean;
  cozinhas: CozinhaParaPedir[];
  actual: string | null;
  /** De onde se medem as distâncias: «de ti» (GPS) ou «de Casa · Maianga» (morada principal) */
  referencia?: string | null;
  /** «Perto de mim»: ordenar pela posição do telemóvel (para quem está fora de casa) */
  aoPertoDeMim?: () => void;
  aLocalizar?: boolean;
  erroLocalizacao?: string | null;
  aoEscolher: (id: string) => void;
  aoFechar: () => void;
}) {
  const comDistancia = cozinhas.some((c) => c.distancia_km != null);
  return (
    <Modal visible={visivel} transparent animationType="slide" onRequestClose={aoFechar} statusBarTranslucent>
      <Pressable onPress={aoFechar} style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.45)', justifyContent: 'flex-end' }}>
        <Pressable
          onPress={() => {}}
          style={{ backgroundColor: cores.fundo, borderTopLeftRadius: 16, borderTopRightRadius: 16, padding: espaco.l, gap: espaco.s, maxHeight: '75%' }}>
          <Text style={{ fontSize: 18, fontWeight: '700', color: cores.texto }}>📍 De onde queres pedir?</Text>
          {comDistancia && (
            <Text style={{ color: cores.textoSuave, marginTop: -espaco.xs }}>{referencia ? `Mais perto ${referencia} primeiro` : 'Mais perto primeiro'}</Text>
          )}
          {aoPertoDeMim && (
            <Pressable
              accessibilityRole="button"
              disabled={aLocalizar}
              onPress={aoPertoDeMim}
              style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.s, paddingVertical: espaco.s }}>
              {aLocalizar ? <ActivityIndicator color={cores.marca} /> : <Text style={{ fontSize: 16 }}>🧭</Text>}
              <Text style={{ color: cores.marca, fontWeight: '700', fontSize: 15 }}>Estou noutro sítio: usar a minha localização</Text>
            </Pressable>
          )}
          {erroLocalizacao ? <Text style={{ color: cores.erro }}>{erroLocalizacao}</Text> : null}
          <ScrollView contentContainerStyle={{ gap: espaco.s, paddingBottom: espaco.l }}>
            {cozinhas.map((c) => {
              const escolhida = c.cozinha_id === actual;
              return (
                <Pressable
                  key={c.cozinha_id}
                  accessibilityRole="button"
                  accessibilityState={{ selected: escolhida }}
                  onPress={() => aoEscolher(c.cozinha_id)}
                  style={{
                    flexDirection: 'row',
                    alignItems: 'center',
                    gap: espaco.s,
                    padding: espaco.m,
                    borderRadius: raio,
                    borderWidth: 1.5,
                    borderColor: escolhida ? cores.marca : cores.linha,
                    backgroundColor: escolhida ? cores.marcaClara : cores.fundo,
                  }}>
                  <Text style={{ flex: 1, fontSize: 16, fontWeight: escolhida ? '700' : '500', color: escolhida ? cores.marcaEscura : cores.texto }}>
                    {(escolhida ? '✓ ' : '') + c.nome}
                  </Text>
                  {c.distancia_km != null && <Text style={{ color: cores.textoSuave }}>{textoDistancia(c.distancia_km)}</Text>}
                </Pressable>
              );
            })}
          </ScrollView>
        </Pressable>
      </Pressable>
    </Modal>
  );
}
