import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { Confirmar } from '@/components/Confirmar';
import { FaixaConfianca } from '@/components/FaixaConfianca';
import { Botao, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { useCarrinho } from '@/lib/carrinho';
import { formatarKz, textoEntregaGratis } from '@/lib/formatar';
import { precoMontado } from '@/lib/opcoes';
import { cores, espaco } from '@/lib/tema';
import {
  entregaVisitante,
  guardarDestino,
  guardarZonaVisitante,
  lerZonaVisitante,
  lerZonasVisitante,
  rotuloZona,
  type ZonaVisitante,
} from '@/lib/visitante';

function BotaoQtd({ sinal, rotulo, aoCarregar }: { sinal: string; rotulo: string; aoCarregar: () => void }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={rotulo}
      onPress={aoCarregar}
      hitSlop={8}
      style={{ width: 36, height: 36, borderRadius: 18, borderWidth: 1, borderColor: cores.marca, alignItems: 'center', justifyContent: 'center' }}>
      <Text style={{ color: cores.marca, fontSize: 18, fontWeight: '800' }}>{sinal}</Text>
    </Pressable>
  );
}

/**
 * Carrinho de quem ainda não tem conta (a app abre no Início para todos). Mostra os pratos, a
 * entrega estimada do bairro e o total; «Pedir» pede o número (SMS) e volta aqui, já com conta,
 * para a morada, o agendamento e a confirmação (o servidor calcula tudo).
 */
export function CarrinhoVisitante() {
  const router = useRouter();
  const carrinho = useCarrinho();
  const [zona, setZona] = useState<ZonaVisitante | null>(null);
  const [zonas, setZonas] = useState<ZonaVisitante[]>([]);
  const [pedirConta, setPedirConta] = useState(false);

  useEffect(() => {
    Promise.all([lerZonasVisitante().catch(() => [] as ZonaVisitante[]), lerZonaVisitante()]).then(([zs, z]) => {
      setZonas(zs);
      // A taxa vem sempre da lista actual (a guardada pode estar desactualizada)
      setZona(z ? (zs.find((x) => x.id === z.id) ?? null) : null);
    }, () => undefined);
  }, []);

  /** O bairro decide a taxa de entrega estimada (fica guardado 24 h) */
  function escolherZona(id: string) {
    const z = zonas.find((x) => x.id === id) ?? null;
    setZona(z);
    void guardarZonaVisitante(z);
  }

  if (carrinho.linhas.length === 0)
    return (
      <Ecra>
        <Paragrafo>O teu carrinho está vazio.</Paragrafo>
        <Botao titulo="Ver o cardápio" aoCarregar={() => router.replace('/inicio')} />
      </Ecra>
    );

  const pratos = carrinho.linhas.reduce((s, l) => s + l.qtd * precoMontado(l.item.preco, l.opcoes, l.tirados), 0);
  const entrega = zona ? entregaVisitante(zona, pratos) : null;
  const total = entrega ? entrega.total : pratos;
  const avisoGratis =
    zona && entrega
      ? textoEntregaGratis({
          entrega_gratis: entrega.taxa === 0 && zona.taxa > 0,
          entrega_gratis_acima: zona.entrega_gratis_acima,
          falta_entrega_gratis: entrega.falta,
        })
      : null;

  async function pedir() {
    setPedirConta(false);
    await guardarDestino('/carrinho');
    router.push({ pathname: '/entrar', params: { pedir: '1' } });
  }

  return (
    <Ecra>
      {carrinho.cozinhaActual?.nome ? <Subtitulo>{carrinho.cozinhaActual.nome}</Subtitulo> : null}
      <Cartao estilo={{ gap: espaco.s }}>
        {carrinho.linhas.map((l) => (
          <View key={l.chave} style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.s }}>
            <Text style={{ flex: 1, color: cores.texto }}>
              {l.item.nome.trim()}
              {l.opcoes.length > 0 ? ` · ${l.opcoes.map((o) => o.nome).join(', ')}` : ''}
            </Text>
            <BotaoQtd sinal="−" rotulo={`Tirar um ${l.item.nome}`} aoCarregar={() => carrinho.alterar(l.chave, l.qtd - 1)} />
            <Text style={{ minWidth: 20, textAlign: 'center', fontWeight: '700' }}>{l.qtd}</Text>
            <BotaoQtd sinal="+" rotulo={`Mais um ${l.item.nome}`} aoCarregar={() => carrinho.alterar(l.chave, l.qtd + 1)} />
          </View>
        ))}
      </Cartao>
      {zonas.length > 0 && (
        <View style={{ gap: espaco.s }}>
          <Text style={{ fontSize: 15, fontWeight: '700', color: cores.texto }}>🛵 Onde entregamos?</Text>
          <Escolha
            opcoes={zonas.map((z) => ({ valor: z.id, rotulo: (z.id === zona?.id ? '✓ ' : '') + rotuloZona(z, formatarKz) }))}
            valor={zona?.id ?? ''}
            aoMudar={escolherZona}
            horizontal
          />
        </View>
      )}
      <Cartao estilo={{ gap: espaco.xs }}>
        <Text style={{ color: cores.texto }}>Pratos: {formatarKz(pratos)}</Text>
        {zona && entrega ? (
          <>
            <Text style={{ color: cores.texto }}>Entrega para {zona.nome}: {entrega.taxa > 0 ? formatarKz(entrega.taxa) : 'grátis'}</Text>
            {avisoGratis && <Paragrafo suave>{avisoGratis}</Paragrafo>}
            <Text style={{ fontWeight: '800', color: cores.texto }}>Total estimado: {formatarKz(total)}</Text>
            <Paragrafo suave>Confirmamos a entrega e os descontos com a tua morada, no passo seguinte.</Paragrafo>
          </>
        ) : (
          <>
            <Text style={{ fontWeight: '800', color: cores.texto }}>Total dos pratos: {formatarKz(pratos)}</Text>
            <Paragrafo suave>A entrega e os descontos são calculados no passo seguinte, com a tua morada.</Paragrafo>
          </>
        )}
      </Cartao>
      <FaixaConfianca />
      <Botao titulo={`Pedir · ${formatarKz(total)}`} aoCarregar={() => setPedirConta(true)} />
      <Botao titulo="Continuar a escolher" variante="texto" aoCarregar={() => (router.canGoBack() ? router.back() : router.replace('/inicio'))} />
      <Confirmar
        visivel={pedirConta}
        titulo="Só falta o teu número"
        mensagem="Para a cozinha e o entregador te encontrarem, entra com o teu número de telefone (recebes um código por SMS). O teu carrinho fica guardado."
        textoConfirmar="Continuar"
        aoConfirmar={() => void pedir()}
        aoCancelar={() => setPedirConta(false)}
      />
    </Ecra>
  );
}
