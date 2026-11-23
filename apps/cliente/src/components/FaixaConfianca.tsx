import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Linking, Pressable, Text, View } from 'react-native';

import { urlTelefone, urlWhatsapp } from '@/lib/contactos';
import { CONTACTO_AJUDA } from '@/lib/empresa';
import { useSessao } from '@/lib/sessao';
import { fraseBairro, frasesFaixa, lerPontualidade, type Pontualidade } from '@/lib/faixa';
import { cores, espaco, raio } from '@/lib/tema';

// A pontualidade muda devagar: lê-se uma vez por abertura da app
let cache: Pontualidade | null | undefined;

/**
 * Faixa de confiança: "Pagas na entrega · Comida de casa · <3.ª frase>". A 3.ª frase só promete
 * o tempo quando o servidor confirma que se cumpre; com contador do bairro, alterna com ele.
 */
export function FaixaConfianca({
  contador,
  bairro,
  agendado = false,
}: {
  contador?: number | null;
  bairro?: string | null;
  agendado?: boolean;
}) {
  const router = useRouter();
  // Com conta: a Ajuda da app. O visitante (sem conta) não tem a Ajuda: fala connosco pelo
  // WhatsApp (ou liga), o mesmo contacto da página de entrada; sem contacto, a frase fica sem ligação.
  const { perfil, ligada } = useSessao();
  const contactoVisitante = CONTACTO_AJUDA.whatsapp
    ? urlWhatsapp(CONTACTO_AJUDA.whatsapp)
    : CONTACTO_AJUDA.telefone
      ? urlTelefone(CONTACTO_AJUDA.telefone)
      : null;
  const abrirAjuda = perfil
    ? // Com conta: o assistente (se ligado) ou os contactos (WhatsApp/ligar): nunca um toque sem resposta
      () => router.push(ligada('agente_atendimento') ? '/ajuda' : '/contactos')
    : contactoVisitante
      ? () => void Linking.openURL(contactoVisitante).catch(() => undefined)
      : null;
  const [pont, setPont] = useState<Pontualidade | null>(cache ?? null);
  const [vez, setVez] = useState(0);
  const social = fraseBairro(contador, bairro);

  useEffect(() => {
    if (cache !== undefined) return;
    let vivo = true;
    lerPontualidade().then((p) => {
      cache = p;
      if (vivo) setPont(p);
    });
    return () => {
      vivo = false;
    };
  }, []);

  useEffect(() => {
    if (!social) return;
    const t = setInterval(() => setVez((v) => v + 1), 4000);
    return () => clearInterval(t);
  }, [social]);

  const frases = frasesFaixa(pont, social, vez, agendado);
  return (
    <View
      accessibilityRole="summary"
      style={{
        flexDirection: 'row',
        borderWidth: 1,
        borderColor: cores.marca,
        borderRadius: raio,
        backgroundColor: '#fff',
        paddingVertical: espaco.s,
      }}>
      {frases.map((f, i) => {
        const conteudo = (
          <>
            <Text style={{ fontSize: 18 }}>{f.icone}</Text>
            <Text style={{ fontSize: 12, fontWeight: '700', color: cores.texto, textAlign: 'center' }}>{f.texto}</Text>
          </>
        );
        const estilo = {
          flex: 1,
          alignItems: 'center' as const,
          gap: 2,
          paddingHorizontal: 4,
          borderLeftWidth: i === 0 ? 0 : 1,
          borderLeftColor: cores.linha,
        };
        return f.ajuda && abrirAjuda ? (
          <Pressable key={i} accessibilityRole="link" accessibilityLabel="Problema? Resolvemos. Falar connosco" onPress={abrirAjuda} style={estilo}>
            {conteudo}
          </Pressable>
        ) : (
          <View key={i} style={estilo}>
            {conteudo}
          </View>
        );
      })}
    </View>
  );
}
