import { Modal, Pressable, Text, View } from 'react-native';

import { Botao } from '@/components/ui';
import { cores, espaco, raio } from '@/lib/tema';

/**
 * Diálogo de confirmação com o visual da marca (substitui o Alert nativo, que o Android não deixa pintar).
 * O botão de confirmar fica a vermelho para dar peso à acção; o de cancelar é discreto.
 */
export function Confirmar({
  visivel,
  titulo,
  mensagem,
  textoConfirmar = 'Confirmar',
  textoCancelar = 'Cancelar',
  aoConfirmar,
  aoCancelar,
}: {
  visivel: boolean;
  titulo: string;
  mensagem?: string;
  textoConfirmar?: string;
  textoCancelar?: string;
  aoConfirmar: () => void;
  aoCancelar: () => void;
}) {
  return (
    <Modal visible={visivel} transparent animationType="fade" onRequestClose={aoCancelar} statusBarTranslucent>
      <Pressable
        onPress={aoCancelar}
        style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', justifyContent: 'center', padding: espaco.l }}>
        {/* Pressable interior "engole" o toque para não fechar ao tocar no cartão */}
        <Pressable
          onPress={() => {}}
          style={{ backgroundColor: cores.fundo, borderRadius: raio, padding: espaco.l, gap: espaco.m, maxWidth: 420, width: '100%', alignSelf: 'center' }}>
          <Text style={{ fontSize: 18, fontWeight: '700', color: cores.texto }}>{titulo}</Text>
          {mensagem ? <Text style={{ fontSize: 15, color: cores.textoSuave }}>{mensagem}</Text> : null}
          <View style={{ flexDirection: 'row', justifyContent: 'flex-end', gap: espaco.s, marginTop: espaco.s }}>
            <Botao titulo={textoCancelar} variante="texto" aoCarregar={aoCancelar} />
            <Botao titulo={textoConfirmar} aoCarregar={aoConfirmar} />
          </View>
        </Pressable>
      </Pressable>
    </Modal>
  );
}
