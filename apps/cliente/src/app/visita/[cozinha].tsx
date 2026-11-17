import { Redirect, Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Image, Pressable, Text, View } from 'react-native';

import { Confirmar } from '@/components/Confirmar';
import { FaixaConfianca } from '@/components/FaixaConfianca';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { useCarrinho } from '@/lib/carrinho';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { precoMontado } from '@/lib/opcoes';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import { guardarDestino, lerCardapioVisitante, type CardapioVisitante, type PratoCardapioVisitante } from '@/lib/visitante';

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
  const total = linhas.reduce((s, l) => s + l.qtd * precoMontado(l.item.preco, l.opcoes, l.tirados), 0);

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

  async function pedir() {
    setPedirConta(false);
    await guardarDestino('/carrinho');
    router.push('/entrar');
  }

  return (
    <Ecra>
      <Stack.Screen options={{ title: dados.cozinha.nome }} />
      <FaixaConfianca />
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
            <Text style={{ fontWeight: '800', color: cores.texto }}>Pratos: {formatarKz(total)}</Text>
            <Paragrafo suave>A entrega e os descontos são calculados no passo seguinte.</Paragrafo>
          </Cartao>
          <Botao titulo={`Pedir · ${formatarKz(total)}`} aoCarregar={() => setPedirConta(true)} />
        </>
      )}

      <Confirmar
        visivel={pedirConta}
        titulo="Só falta o teu número"
        mensagem="Para a cozinha e o entregador te encontrarem, entra com o teu número de telefone (recebes um código por SMS). O teu carrinho fica guardado."
        textoConfirmar="Continuar"
        aoConfirmar={() => void pedir()}
        aoCancelar={() => setPedirConta(false)}
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
    </Ecra>
  );
}
