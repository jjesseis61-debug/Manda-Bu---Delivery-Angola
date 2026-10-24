import { Redirect, useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Image, Pressable, Text } from 'react-native';

import { ACarregar, Aviso, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { lerReceitas } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import type { ReceitaResumo } from '@/lib/tipos';

/** Cozinha de casa: receitas angolanas (texto + 1 foto) que terminam num botão de pedir. */
export default function Receitas() {
  const router = useRouter();
  const { carregado, ligada } = useSessao();
  const [lista, setLista] = useState<ReceitaResumo[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!ligada('receitas')) return;
      lerReceitas()
        .then(setLista)
        .catch((e) => setErro(mensagemErro(e)));
    }, [ligada]),
  );

  if (!carregado) return <ACarregar />;
  if (!ligada('receitas')) return <Redirect href="/inicio" />;
  if (erro && !lista) return <Ecra><Aviso tipo="erro">{erro}</Aviso></Ecra>;
  if (!lista) return <ACarregar />;

  return (
    <Ecra>
      {lista.length === 0 && <Paragrafo suave>Ainda não há receitas por aqui. Volta em breve 🍲</Paragrafo>}
      {lista.map((r) => (
        <Pressable key={r.id} onPress={() => router.push({ pathname: '/receita/[id]', params: { id: r.id } })}>
          <Cartao>
            {r.foto_url ? (
              <Image source={{ uri: r.foto_url }} style={{ width: '100%', aspectRatio: 4 / 3, borderRadius: raio, marginBottom: espaco.s }} accessibilityLabel={r.titulo} />
            ) : null}
            <Text style={{ fontSize: 16, fontWeight: '700', color: cores.texto }}>{r.titulo}</Text>
            {r.resumo ? <Text style={{ color: cores.textoSuave }}>{r.resumo}</Text> : null}
          </Cartao>
        </Pressable>
      ))}
    </Ecra>
  );
}
