import { Redirect, useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Image, Pressable, Text, View } from 'react-native';

import { ACarregar, Aviso, Botao, Ecra, Paragrafo, Subtitulo, Titulo } from '@/components/ui';
import { lerComponentes, lerItemCardapio, lerOpcoes } from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { alternar, gruposEmFalta, gruposEsgotados, opcoesEscolhidas, precoMontado, regraGrupo } from '@/lib/opcoes';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import type { ComponentePrato, GrupoOpcoes, ItemCardapio } from '@/lib/tipos';

/**
 * I9. Montar o prato: uma escolha por grupo (ou várias, até ao máximo), tirar ingredientes da receita (o que se
 * tira não se paga) e o preço a actualizar. O servidor volta a validar e calcula o preço a pagar.
 */
export default function MontarPrato() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { carregado, ligada } = useSessao();
  const carrinho = useCarrinho();
  const [item, setItem] = useState<ItemCardapio | null | undefined>(undefined);
  const [grupos, setGrupos] = useState<GrupoOpcoes[]>([]);
  const [escolhidas, setEscolhidas] = useState<string[]>([]);
  const [componentes, setComponentes] = useState<ComponentePrato[]>([]);
  const [tirados, setTirados] = useState<string[]>([]);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([lerItemCardapio(String(id)), lerOpcoes([String(id)]), lerComponentes([String(id)]).catch(() => [])])
      .then(([i, g, c]) => {
        setItem(i);
        // Só se pode tirar ingredientes quando a receita tem mais do que um (não se tira tudo)
        setComponentes(c.length > 1 ? c : []);
        // Grupos opcionais sem opções disponíveis não aparecem; os obrigatórios ficam para mostrar que esgotaram
        setGrupos(g.filter((x) => x.opcoes.length > 0 || x.minimo > 0));
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
  const semEstes = componentes.filter((c) => tirados.includes(c.produto_id));
  const esgotados = gruposEsgotados(grupos);
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
      {componentes.length > 0 && (
        <View style={{ gap: espaco.s }}>
          <Subtitulo>Ingredientes</Subtitulo>
          <Text style={{ color: cores.textoSuave }}>Toca para tirar o que não queres. O que tiras não pagas.</Text>
          {componentes.map((c) => {
            const tirado = tirados.includes(c.produto_id);
            // Fica sempre pelo menos um ingrediente
            const ultimo = !tirado && tirados.length >= componentes.length - 1;
            return (
              <Pressable
                key={c.produto_id}
                accessibilityRole="checkbox"
                accessibilityLabel={`Tirar ${c.nome}`}
                accessibilityState={{ checked: tirado, disabled: ultimo }}
                disabled={ultimo}
                onPress={() => setTirados((t) => (tirado ? t.filter((x) => x !== c.produto_id) : [...t, c.produto_id]))}
                style={{
                  flexDirection: 'row',
                  alignItems: 'center',
                  gap: espaco.m,
                  padding: espaco.m,
                  borderRadius: raio,
                  borderWidth: 1,
                  borderColor: tirado ? cores.marca : cores.linha,
                  opacity: ultimo ? 0.45 : 1,
                }}>
                <Text style={{ color: cores.marca, fontSize: 18 }}>{tirado ? '☒' : '☐'}</Text>
                <Text style={{ flex: 1, fontSize: 15, textDecorationLine: tirado ? 'line-through' : 'none' }}>{c.nome}</Text>
                {c.valor > 0 && <Text style={{ color: cores.textoSuave }}>{tirado ? '−' : ''}{formatarKz(c.valor)}</Text>}
              </Pressable>
            );
          })}
        </View>
      )}
      {esgotados.length > 0 ? (
        <Aviso>{`Esgotado de momento: não há nenhuma opção disponível em ${esgotados.join(', ')}.`}</Aviso>
      ) : (
        faltam.length > 0 && <Paragrafo suave>Falta escolher: {faltam.join(', ')}.</Paragrafo>
      )}
      <Botao
        titulo={esgotados.length > 0 ? 'Esgotado' : `Adicionar · ${formatarKz(precoMontado(item.preco, opcoes, semEstes))}`}
        desactivado={faltam.length > 0 || esgotados.length > 0}
        aoCarregar={() => {
          carrinho.adicionar(item, opcoes, semEstes);
          // Aberto por link não há ecrã anterior: segue para o início
          if (router.canGoBack()) router.back();
          else router.replace('/inicio');
        }}
      />
    </Ecra>
  );
}
