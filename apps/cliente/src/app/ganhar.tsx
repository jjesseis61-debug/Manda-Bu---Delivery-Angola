import { Redirect, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Text, View } from 'react-native';

import { LoginNecessario } from '@/components/LoginNecessario';
import { ACarregar, Botao, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { lerCodigoPendente } from '@/lib/convite';
import { formatarKz, textoRegras, type RegrasConvida } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import { lerRegrasConvida } from '@/lib/visitante';

/**
 * «Convida e ganha» para quem ainda não tem conta: uma montra das regras (quanto ganhas, quanto
 * o amigo ganha, níveis). Sem conta não há código nem ganhos — o botão leva a criar conta e,
 * depois, volta ao Convida já com o código pronto a partilhar.
 */
export default function Ganhar() {
  const router = useRouter();
  const { carregado, sessao, perfil } = useSessao();
  const [regras, setRegras] = useState<RegrasConvida | null | undefined>(undefined);
  const [convidado, setConvidado] = useState(false);
  const [folha, setFolha] = useState(false);

  useEffect(() => {
    lerRegrasConvida().then(setRegras, () => setRegras(null));
    lerCodigoPendente().then((c) => setConvidado(!!c), () => undefined);
  }, []);

  if (!carregado) return <ACarregar />;
  // Já tem conta: o Convida verdadeiro, com o código e o saldo
  if (sessao && perfil) return <Redirect href="/convida" />;
  if (regras === undefined) return <ACarregar />;

  if (regras === null)
    return (
      <Ecra>
        <Paragrafo>O programa Convida e Ganha não está disponível de momento.</Paragrafo>
        <Botao titulo="Ver o cardápio" variante="secundario" aoCarregar={() => router.replace('/inicio')} />
      </Ecra>
    );

  const gpp = regras.ganho_por_pedido ?? 0;
  const bonus = regras.bonus_boas_vindas ?? 0;
  const desc = regras.desconto_indicado ?? 0;
  const niveis =
    regras.limiar_embaixador != null && regras.limiar_ouro != null && regras.ganho_por_pedido_embaixador != null && regras.ganho_por_pedido_ouro != null;

  return (
    <Ecra>
      {convidado && desc > 0 && (
        <Cartao estilo={{ backgroundColor: cores.marcaClara }}>
          <Text style={{ color: cores.marca, fontWeight: '700' }}>
            🎁 Já tens {formatarKz(desc)} de desconto no teu 1.º pedido, oferta de quem te convidou.
          </Text>
        </Cartao>
      )}
      <Cartao>
        <Subtitulo>Convida amigos e ganha</Subtitulo>
        <Text style={{ fontSize: 20, fontWeight: '800', color: cores.marca, lineHeight: 26 }}>
          Ganha {formatarKz(gpp)} por cada pedido dos teus amigos 🎉
        </Text>
        <View style={{ gap: 6, marginVertical: 4 }}>
          <Text style={{ color: cores.texto }}>1. Partilhas o teu código no WhatsApp.</Text>
          <Text style={{ color: cores.texto }}>2. O teu amigo pede e ganha {formatarKz(desc)} de desconto.</Text>
          <Text style={{ color: cores.texto }}>
            3. Ganhas {formatarKz(gpp)} por cada pedido dele{regras.comissao_primeiro_pedido ? '' : ', a partir do 2.º'}.
          </Text>
        </View>
        {bonus > 0 && (
          <View style={{ backgroundColor: cores.marcaClara, borderRadius: 8, padding: 10 }}>
            <Text style={{ color: cores.marca, fontWeight: '700' }}>🎁 Bónus de boas-vindas: +{formatarKz(bonus)} extra na tua primeira comissão.</Text>
          </View>
        )}
        <View style={{ borderWidth: 1, borderStyle: 'dashed', borderColor: cores.contorno, borderRadius: 8, padding: 12, alignItems: 'center' }}>
          <Text style={{ color: cores.textoSuave, textAlign: 'center' }}>🔒 O teu código aparece quando criares conta.</Text>
        </View>
        <Botao titulo="Criar conta e começar a ganhar" aoCarregar={() => setFolha(true)} />
        <Text style={{ color: cores.textoSuave, fontSize: 13 }}>Só ganhas com o teu código: partilhar o site sem ele não conta.</Text>
      </Cartao>

      {niveis && (
        <Cartao>
          <Subtitulo>Sobe de nível, ganha mais</Subtitulo>
          <Text style={{ color: cores.texto }}>• Normal: {formatarKz(gpp)} por pedido.</Text>
          <Text style={{ color: cores.texto }}>
            • Embaixador ({regras.limiar_embaixador} amigos ativos): {formatarKz(regras.ganho_por_pedido_embaixador!)} por pedido.
          </Text>
          <Text style={{ color: cores.texto }}>
            • Embaixador Ouro 🏆 ({regras.limiar_ouro} amigos ativos): {formatarKz(regras.ganho_por_pedido_ouro!)} por pedido.
          </Text>
        </Cartao>
      )}

      <Subtitulo>Como funciona</Subtitulo>
      {textoRegras(regras).map((frase) => (
        <Paragrafo key={frase} suave>
          {frase}
        </Paragrafo>
      ))}
      <Botao titulo="Ver o cardápio" variante="texto" aoCarregar={() => router.replace('/inicio')} />
      <LoginNecessario
        visivel={folha}
        titulo="Cria conta e começa a ganhar"
        motivo="O teu código de convite fica logo pronto a partilhar."
        destino="/convida"
        aoFechar={() => setFolha(false)}
      />
    </Ecra>
  );
}
