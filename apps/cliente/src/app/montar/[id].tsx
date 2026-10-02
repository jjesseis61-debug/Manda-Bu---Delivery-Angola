import { Redirect, useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Image, Pressable, Text, View } from 'react-native';

import { ACarregar, Aviso, Botao, Ecra, Paragrafo, Subtitulo, Titulo } from '@/components/ui';
import { lerItemCardapio, lerOpcoes } from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { alternar, gruposEmFalta, opcoesEscolhidas, precoMontado, regraGrupo } from '@/lib/opcoes';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import type { GrupoOpcoes, ItemCardapio } from '@/lib/tipos';

/** I9. Montar o prato: uma escolha por grupo (ou várias, até ao máximo) e o preço a actualizar */
export default function MontarPrato() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { carregado, ligada } = useSessao();
  const carrinho = useCarrinho();
  const [item, setItem] = useState<ItemCardapio | null | undefined>(undefined);
  const [grupos, setGrupos] = useState<GrupoOpcoes[]>([]);
  const [escolhidas, setEscolhidas] = useState<string[]>([]);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([lerItemCardapio(String(id)), lerOpcoes([String(id)])])
      .then(([i, g]) => {
        setItem(i);
        setGrupos(g.filter((x) => x.opcoes.length > 0));
      })
      .catch((e) => {
        setErro(mensagemErro(e));
        setItem(null);
      });
  }, [id]);

  // Aberto por link: espera pelos interruptores antes de decidir
  if (!carregado) return <ACarregar />;
  if (!ligada('pratos_montaveis')) return <Redirect href="/inicio" />;
  if (item === undefined) return <ACarregar />;
  if (item === null) return <Ecra><Aviso tipo="erro">{erro ?? 'Este prato já não está disponível.'}</Aviso></Ecra>;

  const opcoes = opcoesEscolhidas(grupos, escolhidas);
  const faltam = gruposEmFalta(grupos, escolhidas);

  return (
    <Ecra>
      {item.foto_url ? (
        <Image source={{ uri: item.foto_url }} style={{ width: '100%', aspectRatio: 4 / 3, borderRadius: raio }} accessibilityLabel={item.nome} />
      ) : null}
      <Titulo>{item.nome}</Titulo>
      {item.descricao && <Paragrafo suave>{item.descricao}</Paragrafo>}
      {grupos.map((g) => {
        const noGrupo = g.opcoes.filter((o) => escolhidas.includes(o.id)).length;
        return (
          <View key={g.id} style={{ gap: espaco.s }}>
            <Subtitulo>{g.nome}</Subtitulo>
            <Text style={{ color: cores.textoSuave }}>{regraGrupo(g)}</Text>
            {g.opcoes.map((o) => {
              const marcada = escolhidas.includes(o.id);
              const cheio = !marcada && g.maximo > 1 && noGrupo >= g.maximo;
              return (
                <Pressable
                  key={o.id}
                  accessibilityRole={g.maximo === 1 ? 'radio' : 'checkbox'}
                  accessibilityState={{ checked: marcada, disabled: cheio }}
                  onPress={() => setEscolhidas((e) => alternar(g, e, o.id))}
                  style={{
                    flexDirection: 'row',
                    alignItems: 'center',
                    gap: espaco.m,
                    padding: espaco.m,
                    borderRadius: raio,
                    borderWidth: 1,
                    borderColor: marcada ? cores.marca : cores.linha,
                    opacity: cheio ? 0.45 : 1,
                  }}>
                  <Text style={{ color: cores.marca, fontSize: 18 }}>{g.maximo === 1 ? (marcada ? '●' : '○') : marcada ? '☑' : '☐'}</Text>
                  <Text style={{ flex: 1, fontSize: 15 }}>{o.nome}</Text>
                  {o.preco_extra > 0 && <Text style={{ color: cores.textoSuave }}>+{formatarKz(o.preco_extra)}</Text>}
                </Pressable>
              );
            })}
          </View>
        );
      })}
      {faltam.length > 0 && <Paragrafo suave>Falta escolher: {faltam.join(', ')}.</Paragrafo>}
      <Botao
        titulo={`Adicionar · ${formatarKz(precoMontado(item.preco, opcoes))}`}
        desactivado={faltam.length > 0}
        aoCarregar={() => {
          carrinho.adicionar(item, opcoes);
          // Aberto por link não há ecrã anterior: segue para o início
          if (router.canGoBack()) router.back();
          else router.replace('/inicio');
        }}
      />
    </Ecra>
  );
}
