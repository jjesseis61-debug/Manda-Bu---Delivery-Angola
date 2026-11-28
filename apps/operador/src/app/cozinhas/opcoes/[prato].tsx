import { useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Switch, Text, View } from 'react-native';

import { FotoEditavel } from '@/components/FotoEditavel';
import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { alterarParametros, apagarGrupoOpcoes, apagarOpcao, definirFotoOpcao, guardarGrupoOpcoes, guardarOpcao, lerGruposOpcoes, lerModeloMontavel, lerProdutos } from '@/lib/api';
import { componentesParaGuardar, formatarKz, mensagemErro, unidadePorDefeito } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { GrupoOpcoesPrato, ProdutoStock, RecipienteBalcao } from '@/lib/tipos';

/** recipiente: '' = automático; undefined = servidor ainda sem a coluna (não se envia) */
type GrupoEditado = { id?: string; nome: string; minimo: string; maximo: string; ordem: string; recipiente?: RecipienteBalcao | '' };
type ComponenteEditado = { produto_id: string; quantidade: string; unidade: string };
type OpcaoEditada = {
  id?: string;
  grupo_id: string;
  nome: string;
  preco_extra: string;
  disponivel: boolean;
  ordem: string;
  componentes: ComponenteEditado[];
  foto_url: string | null;
  /** undefined = servidor ainda sem a coluna (não se envia) */
  contar_stock?: boolean;
  /** '' = o do grupo; undefined = servidor ainda sem a coluna */
  recipiente?: RecipienteBalcao | '';
};

/** Recipientes do balcão do cliente (cada comida no recipiente em que se serve de verdade) */
const RECIPIENTES: { valor: RecipienteBalcao; rotulo: string }[] = [
  { valor: 'panela', rotulo: 'Panela' },
  { valor: 'barro', rotulo: 'Panela de barro' },
  { valor: 'tigela', rotulo: 'Tigela' },
  { valor: 'cartucho', rotulo: 'Cartucho (fritos)' },
  { valor: 'travessa', rotulo: 'Travessa (grelhados)' },
  { valor: 'saladeira', rotulo: 'Saladeira' },
  { valor: 'malga', rotulo: 'Malga (sopa)' },
  { valor: 'cesto', rotulo: 'Cesto (pão)' },
  { valor: 'molheira', rotulo: 'Molheira' },
  { valor: 'taca', rotulo: 'Taça (sobremesa)' },
  { valor: 'fruteira', rotulo: 'Fruteira' },
  { valor: 'copo', rotulo: 'Copo (sumo)' },
  { valor: 'lata', rotulo: 'Lata ou garrafa' },
];
const nomeRecipiente = (r: string | null | undefined) => RECIPIENTES.find((x) => x.valor === r)?.rotulo.toLowerCase() ?? null;

const numero = (t: string) => t.replace(/\D/g, '');

/** I9. Opções de um prato montável: grupos (Base, Acompanhamentos, Extras) com mínimo e máximo, e as opções com preço extra */
export default function OpcoesPrato() {
  const { prato, nome } = useLocalSearchParams<{ prato: string; nome?: string }>();
  const [grupos, setGrupos] = useState<GrupoOpcoesPrato[] | null>(null);
  const [grupo, setGrupo] = useState<GrupoEditado | null>(null);
  const [opcao, setOpcao] = useState<OpcaoEditada | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  // Confirmação do que se guardou e em que grupo (para não se perder uma opção no grupo errado)
  const [guardado, setGuardado] = useState<string | null>(null);
  const [produtos, setProdutos] = useState<ProdutoStock[] | null>(null);
  const [procura, setProcura] = useState('');
  const [ocupado, setOcupado] = useState(false);
  // Administrador (parâmetros): este prato passa a ser o modelo copiado para as cozinhas novas
  const { pode } = useSessao();
  const podeModelo = pode('plataforma.parametros');
  const [modelo, setModelo] = useState<string | null | undefined>(undefined);

  const carregar = useCallback(() => {
    lerGruposOpcoes(String(prato))
      .then(setGrupos)
      .catch((e) => setErro(mensagemErro(e)));
    if (podeModelo) lerModeloMontavel().then(setModelo).catch(() => setModelo(undefined));
  }, [prato, podeModelo]);
  useEffect(carregar, [carregar]);

  // Produtos do stock: só quando se edita uma opção (para os ingredientes)
  useEffect(() => {
    if (opcao && produtos === null) lerProdutos().then(setProdutos).catch(() => setProdutos([]));
  }, [opcao, produtos]);
  const nomeGrupo = (id: string) => grupos?.find((g) => g.id === id)?.nome ?? 'grupo';
  const nomeProduto = (id: string) => produtos?.find((p) => p.id === id)?.nome ?? 'Produto';
  // Contar o stock só faz sentido com um produto de longo prazo nos ingredientes (é o que tem movimentos)
  const temLongoPrazo = !!opcao?.componentes.some((c) => produtos?.find((p) => p.id === c.produto_id)?.tipo_estoque === 'Longo Prazo');
  // O servidor já tem a coluna quando alguma opção lida a traz
  const comColunaStock = !!grupos?.some((g) => g.opcoes.some((o) => o.contar_stock !== undefined));
  const comColunaRecipiente = !!grupos?.some((g) => g.recipiente !== undefined);
  const encontrados =
    procura.trim().length >= 2
      ? (produtos ?? [])
          .filter((p) => p.nome.toLowerCase().includes(procura.trim().toLowerCase()))
          .filter((p) => !opcao?.componentes.some((c) => c.produto_id === p.id))
          .slice(0, 6)
      : [];

  async function correr(f: () => Promise<void>) {
    setErro(null);
    setGuardado(null);
    setOcupado(true);
    try {
      await f();
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  const minimo = Number(grupo?.minimo || 0);
  const maximo = Number(grupo?.maximo || 0);
  const grupoValido = grupo !== null && grupo.nome.trim() !== '' && maximo >= 1 && maximo <= 20 && minimo <= maximo;

  return (
    <Guarda permissoes={['cozinhas.gerir', 'cardapio.gerir']}>
      <Ecra>
        {nome && <Subtitulo>{nome}</Subtitulo>}
        {podeModelo && modelo !== undefined && (grupos?.length ?? 0) > 0 && (
          modelo === String(prato) ? (
            <Aviso tipo="sucesso">Este é o prato modelo: é copiado (desactivado) para cada cozinha nova.</Aviso>
          ) : (
            <Botao
              titulo="⭐ Usar como modelo para as cozinhas novas"
              variante="leve"
              aCarregar={ocupado}
              aoCarregar={() => correr(() => alterarParametros({ cardapio_modelo_montavel: String(prato) }))}
            />
          )
        )}
        <Paragrafo suave>
          O cliente monta o prato escolhendo opções em cada grupo. Com mínimo 1 o grupo é obrigatório; o preço extra soma ao
          preço do prato. Só aparece aos clientes com o interruptor &quot;pratos_montaveis&quot; ligado.
        </Paragrafo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {guardado && <Aviso tipo="sucesso">{guardado}</Aviso>}
        {grupos === null && !erro && <ACarregar />}
        {grupos?.length === 0 && <Paragrafo suave>Este prato ainda não tem opções.</Paragrafo>}

        {grupos?.map((g) => (
          <Cartao key={g.id}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
              <Text style={{ fontWeight: '700', fontSize: 16, flex: 1 }}>{g.nome}</Text>
              <Text style={{ color: cores.textoSuave }}>
                {g.minimo === 0 ? 'opcional' : `mín. ${g.minimo}`} · máx. {g.maximo}
                {g.recipiente ? ` · ${nomeRecipiente(g.recipiente)}` : ''}
              </Text>
            </View>
            {g.opcoes.map((o) => (
              <View key={o.id} style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.s }}>
                <Text style={{ flex: 1, color: o.disponivel ? cores.texto : cores.textoSuave }}>
                  {o.nome}
                  {o.preco_extra > 0 ? ` · +${formatarKz(o.preco_extra)}` : ''}
                  {o.disponivel ? '' : ' · esgotada'}
                  {o.contar_stock ? ' · conta stock' : ''}
                  {o.recipiente ? ` · ${nomeRecipiente(o.recipiente)}` : ''}
                </Text>
                <Botao
                  titulo="Editar"
                  variante="texto"
                  aoCarregar={() =>
                    setOpcao({
                      ...o,
                      preco_extra: String(o.preco_extra),
                      ordem: String(o.ordem),
                      componentes: (o.componentes ?? []).map((c) => ({ ...c, quantidade: String(c.quantidade) })),
                      foto_url: o.foto_url ?? null,
                      recipiente: o.recipiente === undefined ? undefined : (o.recipiente ?? ''),
                    })
                  }
                />
              </View>
            ))}
            <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
              <Botao
                titulo="Nova opção"
                variante="secundario"
                aoCarregar={() =>
                  setOpcao({ grupo_id: g.id, nome: '', preco_extra: '0', disponivel: true, ordem: '0', componentes: [], foto_url: null, ...(comColunaStock ? { contar_stock: false } : {}), ...(comColunaRecipiente ? { recipiente: '' as const } : {}) })
                }
              />
              <Botao
                titulo="Editar grupo"
                variante="texto"
                aoCarregar={() =>
                  setGrupo({
                    id: g.id,
                    nome: g.nome,
                    minimo: String(g.minimo),
                    maximo: String(g.maximo),
                    ordem: String(g.ordem),
                    recipiente: g.recipiente === undefined ? undefined : (g.recipiente ?? ''),
                  })
                }
              />
            </View>
          </Cartao>
        ))}

        {opcao && (
          <Cartao>
            <Subtitulo>
              {opcao.id ? 'Editar opção' : 'Nova opção'} em «{nomeGrupo(opcao.grupo_id)}»
            </Subtitulo>
            <Campo rotulo="Nome (ex.: Funge, Ovo estrelado)" value={opcao.nome} onChangeText={(t) => setOpcao({ ...opcao, nome: t })} />
            <Campo
              rotulo="Preço extra (Kz, 0 se não acrescenta)"
              value={opcao.preco_extra}
              keyboardType="number-pad"
              onChangeText={(t) => setOpcao({ ...opcao, preco_extra: numero(t) })}
            />
            <Campo rotulo="Ordem" value={opcao.ordem} keyboardType="number-pad" onChangeText={(t) => setOpcao({ ...opcao, ordem: numero(t) })} />
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
              <Text>Disponível (desligar quando esgotar)</Text>
              <Switch thumbColor="#FFFFFF"
                value={opcao.disponivel}
                onValueChange={(v) => setOpcao({ ...opcao, disponivel: v })}
                trackColor={{ true: cores.marca, false: cores.contorno }}
              />
            </View>
            <Text style={{ fontWeight: '700', marginTop: espaco.s }}>Ingredientes (descontam stock)</Text>
            <Paragrafo suave>
              Por cada prato com esta opção (ex.: Ovo estrelado: 1 un de ovo). Somam aos ingredientes da receita do prato.
            </Paragrafo>
            {opcao.componentes.map((c, i) => (
              <View key={c.produto_id} style={{ flexDirection: 'row', alignItems: 'flex-end', gap: espaco.s }}>
                <View style={{ flex: 2 }}>
                  <Text>{nomeProduto(c.produto_id)}</Text>
                </View>
                <View style={{ flex: 1 }}>
                  <Campo
                    rotulo="Quantidade gasta por prato"
                    value={c.quantidade}
                    keyboardType="decimal-pad"
                    onChangeText={(t) =>
                      setOpcao({
                        ...opcao,
                        componentes: opcao.componentes.map((x, j) => (j === i ? { ...x, quantidade: t.replace(/[^\d.,]/g, '') } : x)),
                      })
                    }
                  />
                </View>
                <View style={{ flex: 1 }}>
                  <Campo
                    rotulo="Unidade"
                    value={c.unidade}
                    autoCapitalize="none"
                    onChangeText={(t) =>
                      setOpcao({ ...opcao, componentes: opcao.componentes.map((x, j) => (j === i ? { ...x, unidade: t } : x)) })
                    }
                  />
                </View>
                <Botao
                  titulo="Tirar"
                  variante="texto"
                  aoCarregar={() => setOpcao({ ...opcao, componentes: opcao.componentes.filter((_, j) => j !== i) })}
                />
              </View>
            ))}
            {opcao.contar_stock !== undefined && (
              <View style={{ gap: espaco.xs }}>
                <Text style={{ fontWeight: '700' }}>Contar o stock (latas, garrafas)</Text>
                {temLongoPrazo ? (
                  <>
                    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: espaco.s }}>
                      <Text style={{ flex: 1 }}>Mostrar ao cliente quantas restam</Text>
                      <Switch thumbColor="#FFFFFF"
                        value={opcao.contar_stock}
                        onValueChange={(v) => setOpcao({ ...opcao, contar_stock: v })}
                        trackColor={{ true: cores.marca, false: cores.contorno }}
                      />
                    </View>
                    <Paragrafo suave>
                      O cliente vê quantas restam («Restam 4») e, quando acabam, «Hoje não há». Conta as entradas no stock da cozinha
                      menos os pedidos ainda por entregar: sem entradas registadas, a opção aparece como «Hoje não há».
                    </Paragrafo>
                  </>
                ) : (
                  <Paragrafo suave>
                    Ainda não se pode ligar: junta primeiro, nos ingredientes abaixo, o produto de longo prazo que se gasta (ex.: Gasosa
                    lata, 1 un). O produto tem de existir no stock da cozinha, com as entradas registadas.
                  </Paragrafo>
                )}
              </View>
            )}
            {opcao.recipiente !== undefined && (
              <View style={{ gap: espaco.xs }}>
                <Text style={{ fontWeight: '700' }}>Recipiente no balcão do cliente</Text>
                <Escolha
                  opcoes={[{ valor: '' as RecipienteBalcao | '', rotulo: 'Igual ao grupo' }, ...RECIPIENTES]}
                  valor={opcao.recipiente}
                  aoMudar={(v) => setOpcao({ ...opcao, recipiente: v })}
                />
                <Paragrafo suave>Só quando esta opção se serve noutro recipiente (ex.: a batata frita num grupo de tigelas vai em cartucho).</Paragrafo>
              </View>
            )}
            {opcao.componentes.length < 20 && (
              <Campo rotulo="Adicionar ingrediente (escreve o nome do produto)" value={procura} onChangeText={setProcura} />
            )}
            {encontrados.map((p) => (
              <Botao
                key={p.id}
                titulo={`+ ${p.nome}`}
                variante="texto"
                aoCarregar={() => {
                  setOpcao({
                    ...opcao,
                    componentes: [...opcao.componentes, { produto_id: p.id, quantidade: '', unidade: unidadePorDefeito(p.categoria_medida) }],
                  });
                  setProcura('');
                }}
              />
            ))}
            {procura.trim().length >= 2 && encontrados.length === 0 && produtos !== null && (
              <Paragrafo suave>
                Nenhum produto com esse nome no stock. A opção guarda-se na mesma; para contar latas, o produto tem de ser registado
                primeiro no stock (longo prazo, por unidade).
              </Paragrafo>
            )}
            {opcao.id ? (
              <FotoEditavel
                tipo="opcoes"
                id={opcao.id}
                url={opcao.foto_url}
                aoGravar={async (u) => {
                  await definirFotoOpcao(opcao.id as string, u);
                  setOpcao({ ...opcao, foto_url: u });
                }}
              />
            ) : (
              <Paragrafo suave>Guarda a opção primeiro para lhe pôr uma foto.</Paragrafo>
            )}
            <Botao
              titulo="Guardar opção"
              aCarregar={ocupado}
              desactivado={!opcao.nome.trim()}
              aoCarregar={() =>
                correr(async () => {
                  const { recipiente: _r, ...resto } = opcao;
                  await guardarOpcao({
                    ...resto,
                    nome: opcao.nome.trim(),
                    preco_extra: Number(opcao.preco_extra || 0),
                    ordem: Number(opcao.ordem || 0),
                    componentes: componentesParaGuardar(opcao.componentes),
                    ...(opcao.contar_stock === undefined ? {} : { contar_stock: opcao.contar_stock && temLongoPrazo }),
                    ...(opcao.recipiente === undefined ? {} : { recipiente: opcao.recipiente || null }),
                  });
                  const nome = opcao.nome.trim();
                  setOpcao(null);
                  setTimeout(() => setGuardado(`«${nome}» guardada no grupo «${nomeGrupo(opcao.grupo_id)}».`), 0);
                })
              }
            />
            {opcao.id && (
              <Botao
                titulo="Apagar opção"
                variante="texto"
                aoCarregar={() =>
                  correr(async () => {
                    await apagarOpcao(opcao.id as string);
                    setOpcao(null);
                  })
                }
              />
            )}
            <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setOpcao(null)} />
          </Cartao>
        )}

        {grupo ? (
          <Cartao>
            <Subtitulo>{grupo.id ? 'Editar grupo' : 'Novo grupo'}</Subtitulo>
            <Campo rotulo="Nome do grupo (ex.: Base, Acompanhamentos, Extras)" value={grupo.nome} onChangeText={(t) => setGrupo({ ...grupo, nome: t })} />
            <Campo
              rotulo="Mínimo de escolhas (0 = opcional)"
              value={grupo.minimo}
              keyboardType="number-pad"
              onChangeText={(t) => setGrupo({ ...grupo, minimo: numero(t) })}
            />
            <Campo
              rotulo="Máximo de escolhas"
              value={grupo.maximo}
              keyboardType="number-pad"
              onChangeText={(t) => setGrupo({ ...grupo, maximo: numero(t) })}
            />
            <Campo rotulo="Ordem" value={grupo.ordem} keyboardType="number-pad" onChangeText={(t) => setGrupo({ ...grupo, ordem: numero(t) })} />
            {grupo.recipiente !== undefined && (
              <View style={{ gap: espaco.xs }}>
                <Text style={{ fontWeight: '700' }}>Recipiente no balcão do cliente</Text>
                <Escolha
                  opcoes={[{ valor: '' as RecipienteBalcao | '', rotulo: 'Automático (pelo nome)' }, ...RECIPIENTES]}
                  valor={grupo.recipiente}
                  aoMudar={(v) => setGrupo({ ...grupo, recipiente: v })}
                />
                <Paragrafo suave>
                  Automático: a app escolhe pelo nome (batata frita em cartucho, salada em saladeira, sopa em malga, pudim em taça, fruta
                  na fruteira…). Sopa, pão e molho ficam ao lado do prato; sobremesa e fruta no prato da sobremesa; bebidas no tabuleiro.
                </Paragrafo>
              </View>
            )}
            {!grupoValido && grupo.nome.trim() !== '' && <Aviso>O máximo tem de ser de 1 a 20 e não pode ser menor que o mínimo.</Aviso>}
            <Botao
              titulo="Guardar grupo"
              aCarregar={ocupado}
              desactivado={!grupoValido}
              aoCarregar={() =>
                correr(async () => {
                  await guardarGrupoOpcoes({
                    id: grupo.id,
                    cardapio_id: String(prato),
                    nome: grupo.nome.trim(),
                    minimo,
                    maximo,
                    ordem: Number(grupo.ordem || 0),
                    ...(grupo.recipiente === undefined ? {} : { recipiente: grupo.recipiente || null }),
                  });
                  setGrupo(null);
                })
              }
            />
            {grupo.id && (
              <Botao
                titulo="Apagar grupo"
                variante="texto"
                aoCarregar={() =>
                  correr(async () => {
                    await apagarGrupoOpcoes(grupo.id as string);
                    setGrupo(null);
                  })
                }
              />
            )}
            <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setGrupo(null)} />
          </Cartao>
        ) : (
          <Botao
            titulo="Novo grupo de opções"
            variante="secundario"
            aoCarregar={() =>
              setGrupo({ nome: '', minimo: '1', maximo: '1', ordem: String(grupos?.length ?? 0), ...(comColunaRecipiente ? { recipiente: '' as const } : {}) })
            }
          />
        )}
      </Ecra>
    </Guarda>
  );
}
