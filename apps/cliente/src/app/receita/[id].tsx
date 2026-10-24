import { Redirect, useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Image, Text } from 'react-native';

import { ACarregar, Aviso, Botao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { lerReceita, receitaAbriu, receitaTocouPedir } from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, raio } from '@/lib/tema';
import type { Receita } from '@/lib/tipos';

export default function ReceitaDetalhe() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { carregado, ligada } = useSessao();
  const carrinho = useCarrinho();
  const [receita, setReceita] = useState<Receita | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    lerReceita(id)
      .then((r) => {
        setReceita(r);
        if (r) void receitaAbriu(id); // métrica: abriu a receita
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [id]);

  if (!carregado) return <ACarregar />;
  if (!ligada('receitas')) return <Redirect href="/inicio" />;
  if (erro) return <Ecra><Aviso tipo="erro">{erro}</Aviso></Ecra>;
  if (!receita) return <ACarregar />;

  // CTA: "a [cozinha] faz por ti" — escolhe essa cozinha e leva ao cardápio
  function pedir() {
    if (!receita?.cozinha_id) return;
    void receitaTocouPedir(receita.id); // métrica: tocou em "Pedir"
    carrinho.definirCozinha({ id: receita.cozinha_id, nome: receita.cozinha_nome ?? 'A cozinha' });
    router.push('/inicio');
  }

  return (
    <Ecra>
      {receita.foto_url ? (
        <Image source={{ uri: receita.foto_url }} style={{ width: '100%', aspectRatio: 4 / 3, borderRadius: raio }} accessibilityLabel={receita.titulo} />
      ) : null}
      <Subtitulo>{receita.titulo}</Subtitulo>
      {receita.resumo ? <Text style={{ color: cores.textoSuave }}>{receita.resumo}</Text> : null}
      <Paragrafo>{receita.corpo}</Paragrafo>
      {receita.cozinha_id && (
        <Botao titulo={`Não queres cozinhar? ${receita.cozinha_nome ?? 'A cozinha'} faz por ti — Pedir`} aoCarregar={pedir} />
      )}
    </Ecra>
  );
}
