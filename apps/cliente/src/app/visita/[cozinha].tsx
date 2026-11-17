import { Redirect, Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Image, Pressable, ScrollView, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Confirmar } from '@/components/Confirmar';
import { LoginNecessario } from '@/components/LoginNecessario';
import { FaixaConfianca } from '@/components/FaixaConfianca';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { useCarrinho } from '@/lib/carrinho';
import { formatarKz, mensagemErro, textoEntregaGratis } from '@/lib/formatar';
import { precoMontado } from '@/lib/opcoes';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import {
  entregaVisitante,
  lerCardapioVisitante,
  lerZonaVisitante,
  type CardapioVisitante,
  type PratoCardapioVisitante,
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
 * Cardápio da cozinha para quem chegou por um link sem conta. Escolhe os pratos, vê o carrinho
 * (guardado 24 h) e só ao carregar em «Pedir» entra com o número; depois volta ao carrinho,
 * onde o servidor calcula a entrega e os descontos.
 */
export default function CardapioVisita() {
  const { cozinha } = useLocalSearchParams<{ cozinha: string }>();
  const router = useRouter();
  const { carregado, sessao, perfil } = useSessao();
  const carrinho = useCarrinho();
  const [dados, setDados] = useState<CardapioVisitante | null | undefined>(undefined);
  const [erro, setErro] = useState<string | null>(null);
  const [troca, setTroca] = useState<PratoCardapioVisitante | null>(null);
  const [pedirConta, setPedirConta] = useState(false);
  // Bairro escolhido em «Ver o cardápio primeiro» (pelo link partilhado não há: a entrega vem depois)
  const [zona, setZona] = useState<ZonaVisitante | null>(null);
  const rolagem = useRef<ScrollView>(null);

  useEffect(() => {
    lerZonaVisitante().then(setZona, () => undefined);
  }, []);

  useEffect(() => {
    let vivo = true;
    lerCardapioVisitante(String(cozinha ?? ''))
      .then((d) => vivo && setDados(d))
      .catch((e) => {
        if (!vivo) return;
        setErro(mensagemErro(e));
        setDados(null);
      });
    return () => {
      vivo = false;
    };
  }, [cozinha]);

  if (!carregado) return <ACarregar />;
  // Já tem conta: o cardápio normal
  if (sessao && perfil) return <Redirect href="/inicio" />;
  if (dados === undefined) return <ACarregar />;
  if (dados === null)
    return (
      <Ecra>
        <Aviso tipo="erro">{erro ?? 'Esta cozinha não está a aceitar pedidos agora.'}</Aviso>
        <Botao titulo="Entrar ou criar conta" aoCarregar={() => router.replace('/entrar')} />
      </Ecra>
    );

  const daCozinha = carrinho.cozinhaActual?.id === dados.cozinha.id;
  const linhas = daCozinha ? carrinho.linhas : [];
  const pratos = linhas.reduce((s, l) => s + l.qtd * precoMontado(l.item.preco, l.opcoes, l.tirados), 0);
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

  function escolher(p: PratoCardapioVisitante) {
    if (p.montar) {
      router.push({ pathname: '/montar/[id]', params: { id: p.id } });
      return;
    }
    if (!daCozinha && carrinho.quantidade > 0) {
      setTroca(p);
      return;
    }
    colocar(p);
  }

  function colocar(p: PratoCardapioVisitante) {
    if (!dados) return;
    if (!daCozinha) carrinho.definirCozinha(dados.cozinha);
    const { esgotado: _e, montar: _m, ...item } = p;
    carrinho.adicionar(item);
  }


  const nPratos = linhas.reduce((s, l) => s + l.qtd, 0);

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: cores.fundo }} edges={['bottom', 'left', 'right']}>
      <Stack.Screen options={{ title: dados.cozinha.nome }} />
      <ScrollView ref={rolagem} contentContainerStyle={{ padding: espaco.l, paddingBottom: espaco.xl * 2, gap: espaco.m }}>
      <FaixaConfianca />
      {/* A entrega do bairro escolhido, logo à vista (pelo link partilhado ainda não há bairro) */}
      {zona && (
        <Text style={{ color: cores.textoSuave }}>
          🛵 Entrega para {zona.nome}: {zona.taxa > 0 ? formatarKz(zona.taxa) : 'grátis'}
          {zona.taxa > 0 && zona.entrega_gratis_acima ? ` · grátis a partir de ${formatarKz(zona.entrega_gratis_acima)}` : ''}
        </Text>
      )}
      {dados.pratos.length === 0 && <Paragrafo suave>Hoje esta cozinha ainda não tem pratos no cardápio.</Paragrafo>}
      {dados.pratos.map((p) => {
        const noCarrinho = linhas.filter((l) => l.item.id === p.id).reduce((s, l) => s + l.qtd, 0);
        return (
          <Pressable
            key={p.id}
            accessibilityRole="button"
            accessibilityLabel={`${p.nome}, ${formatarKz(p.preco)}`}
            disabled={p.esgotado}
            onPress={() => escolher(p)}>
            <Cartao estilo={{ flexDirection: 'row', gap: espaco.m, alignItems: 'center', opacity: p.esgotado ? 0.5 : 1 }}>
              {p.foto_url ? (
                <Image source={{ uri: p.foto_url }} style={{ width: 72, height: 72, borderRadius: raio }} accessibilityIgnoresInvertColors />
              ) : null}
              <View style={{ flex: 1, gap: 2 }}>
                <Text style={{ fontSize: 16, fontWeight: '700', color: cores.texto }}>{p.nome}</Text>
                {p.descricao ? (
                  <Text style={{ color: cores.textoSuave }} numberOfLines={2}>
                    {p.descricao}
                  </Text>
                ) : null}
                <Text style={{ fontWeight: '800', color: cores.texto }}>
                  {p.esgotado ? 'Esgotado' : `${p.montar ? 'Desde ' : ''}${formatarKz(p.preco)}`}
                </Text>
              </View>
              {!p.esgotado && (
                <Text style={{ color: cores.marca, fontWeight: '800' }}>{noCarrinho > 0 ? `${noCarrinho} ✓` : p.montar ? 'Escolher' : '+ Adicionar'}</Text>
              )}
            </Cartao>
          </Pressable>
        );
      })}

      {linhas.length > 0 && (
        <>
          <Subtitulo>O teu carrinho</Subtitulo>
          <Cartao estilo={{ gap: espaco.s }}>
            {linhas.map((l) => (
              <View key={l.chave} style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.s }}>
                <Text style={{ flex: 1, color: cores.texto }}>
                  {l.item.nome}
                  {l.opcoes.length > 0 ? ` · ${l.opcoes.map((o) => o.nome).join(', ')}` : ''}
                </Text>
                <BotaoQtd sinal="−" rotulo={`Tirar um ${l.item.nome}`} aoCarregar={() => carrinho.alterar(l.chave, l.qtd - 1)} />
                <Text style={{ minWidth: 20, textAlign: 'center', fontWeight: '700' }}>{l.qtd}</Text>
                <BotaoQtd sinal="+" rotulo={`Mais um ${l.item.nome}`} aoCarregar={() => carrinho.alterar(l.chave, l.qtd + 1)} />
              </View>
            ))}
            <Text style={{ color: cores.texto }}>Pratos: {formatarKz(pratos)}</Text>
            {zona && entrega ? (
              <>
                <Text style={{ color: cores.texto }}>
                  Entrega para {zona.nome}: {entrega.taxa > 0 ? formatarKz(entrega.taxa) : 'grátis'}
                </Text>
                {avisoGratis && <Paragrafo suave>{avisoGratis}</Paragrafo>}
                <Text style={{ fontWeight: '800', color: cores.texto }}>Total estimado: {formatarKz(total)}</Text>
                <Paragrafo suave>Confirmamos a entrega e os descontos com a tua morada, no passo seguinte.</Paragrafo>
              </>
            ) : (
              <>
                <Text style={{ fontWeight: '800', color: cores.texto }}>Total dos pratos: {formatarKz(pratos)}</Text>
                <Paragrafo suave>A entrega e os descontos são calculados no passo seguinte.</Paragrafo>
              </>
            )}
          </Cartao>
        </>
      )}

      <Botao titulo="💰 Convida amigos e ganha" variante="texto" aoCarregar={() => router.push('/ganhar')} />
      <LoginNecessario
        visivel={pedirConta}
        titulo="Só falta o teu número"
        motivo="Recebes um código por SMS ou WhatsApp para confirmar. O teu carrinho fica guardado."
        nota="Só usamos o teu número para os teus pedidos. Pagas na entrega."
        destino="/carrinho"
        aoFechar={() => setPedirConta(false)}
      />
      <Confirmar
        visivel={troca !== null}
        titulo="Trocar de cozinha?"
        mensagem={`O teu carrinho tem pratos de ${carrinho.cozinhaActual?.nome || 'outra cozinha'} e vai ficar vazio.`}
        textoConfirmar="Trocar e adicionar"
        aoConfirmar={() => {
          const p = troca;
          setTroca(null);
          if (p) colocar(p);
        }}
        aoCancelar={() => setTroca(null)}
      />
      </ScrollView>

      {/* Barra fixa do carrinho: sempre à vista depois do primeiro prato (o carrinho detalhado fica no fim da lista) */}
      {linhas.length > 0 && (
        <View
          style={{
            flexDirection: 'row',
            alignItems: 'center',
            gap: espaco.m,
            paddingHorizontal: espaco.l,
            paddingVertical: espaco.m,
            borderTopWidth: 1,
            borderTopColor: cores.linha,
            backgroundColor: cores.fundo,
          }}>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={`Ver o carrinho: ${nPratos} ${nPratos === 1 ? 'prato' : 'pratos'}, ${formatarKz(total)}`}
            onPress={() => rolagem.current?.scrollToEnd({ animated: true })}
            style={{ flex: 1 }}>
            <Text style={{ fontWeight: '800', color: cores.texto }}>
              🛒 {nPratos} {nPratos === 1 ? 'prato' : 'pratos'} · {formatarKz(total)}
            </Text>
            <Text style={{ color: cores.textoSuave, fontSize: 12 }}>{entrega ? 'Com a entrega · ver carrinho' : 'Ver carrinho'}</Text>
          </Pressable>
          <View style={{ minWidth: 130 }}>
            <Botao titulo="Pedir ›" aoCarregar={() => setPedirConta(true)} />
          </View>
        </View>
      )}
    </SafeAreaView>
  );
}
