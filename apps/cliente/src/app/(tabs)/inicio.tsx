import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useMemo, useRef, useState } from 'react';
import { Image, Pressable, RefreshControl, ScrollView, Text, View } from 'react-native';

import { CartaoConvida } from '@/components/CartaoConvida';
import { Confirmar } from '@/components/Confirmar';
import { ComoChegar } from '@/components/ComoChegar';
import { Aviso, Botao, Cartao, Escolha, Paragrafo, Subtitulo, estilos } from '@/components/ui';
import {
  contadorZona,
  cozinhaPadrao,
  cozinhasParaPedir,
  cozinhasPertoParaPedir,
  lerCardapio,
  lerEnderecos,
  lerComponentes,
  lerDoses,
  lerOpcoes,
  lerPedidos,
  mediasAvaliacoes,
  meusSelos,
  posicaoEntrega,
} from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { corEstadoPedido, formatarKz, formatarMedia, mensagemErro, nomeEstadoPedido } from '@/lib/formatar';
import { gruposEsgotados, precoMinimo } from '@/lib/opcoes';
import { montarRepeticao } from '@/lib/repetir';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import type { CozinhaParaPedir, Endereco, ItemCardapio, MediasAvaliacoes, MeusSelos, Pedido } from '@/lib/tipos';

const EM_ANDAMENTO = ['pendente', 'confirmado', 'em_preparacao', 'em_entrega'];

export default function Inicio() {
  const router = useRouter();
  const { ligada, perfil } = useSessao();
  const carrinho = useCarrinho();
  const [cardapio, setCardapio] = useState<ItemCardapio[] | null>(null);
  const [enderecos, setEnderecos] = useState<Endereco[]>([]);
  const [contador, setContador] = useState<number | null>(null);
  const [medias, setMedias] = useState<MediasAvaliacoes | null>(null);
  const [cozinhas, setCozinhas] = useState<CozinhaParaPedir[]>([]);
  // Troca de cozinha com carrinho cheio: confirma antes de esvaziar
  const [trocaPendente, setTrocaPendente] = useState<CozinhaParaPedir | null>(null);
  // Banner no topo: pedido ainda em andamento ("a tua entrega está a caminho, toca para acompanhar")
  const [pedidoActivo, setPedidoActivo] = useState<Pedido | null>(null);
  // "O teu habitual": o último pedido entregue, para repetir num toque (só quando não há pedido em curso)
  const [ultimoTerminado, setUltimoTerminado] = useState<Pedido | null>(null);
  const [aRepetir, setARepetir] = useState(false);
  // Cartão de selos (só com o interruptor 'selos' ligado)
  const [selos, setSelos] = useState<MeusSelos | null>(null);
  // Tempo do estafeta vindo do mapa (posição real), quando está a partilhar GPS; senão calcula-se da hora prometida
  const [minutosEstafeta, setMinutosEstafeta] = useState<number | null>(null);
  // I9: pratos com opções (abrem o ecrã de montar em vez de irem direito ao carrinho)
  const [montaveis, setMontaveis] = useState<Set<string>>(new Set());
  const [esgotados, setEsgotados] = useState<Set<string>>(new Set());
  /** Pratos montáveis com grupos obrigatórios: preço mais baixo possível ("desde ...") */
  const [desde, setDesde] = useState<Map<string, number>>(new Map());
  /** Doses que restam hoje (só os pratos em que a cozinha lançou doses) */
  const [doses, setDoses] = useState<Map<string, number>>(new Map());
  const cozinhaId = carrinho.cozinhaActual?.id ?? null;
  // Referência ao carrinho para o carregamento não depender de cada prato adicionado
  const carrinhoRef = useRef(carrinho);
  carrinhoRef.current = carrinho;
  const emGrupo = carrinho.grupo !== null;
  const [erro, setErro] = useState<string | null>(null);
  const [aActualizar, setAActualizar] = useState(false);

  const carregar = useCallback(async () => {
    setErro(null);
    try {
      // Endereços primeiro: o ponto de entrega serve para ordenar os balcões por proximidade
      const ends = await lerEnderecos(perfil?.cliente_id);
      const ponto = ends[0]?.ponto_entrega_id ?? null;
      // I8: com multi_cozinha, o cliente escolhe a cozinha; por defeito a primeira da lista (a mais perto)
      let escolhida = cozinhaId;
      if (ligada('multi_cozinha')) {
        const lista = ponto ? await cozinhasPertoParaPedir(ponto) : await cozinhasParaPedir();
        setCozinhas(lista);
        if (!emGrupo && (!escolhida || !lista.some((c) => c.cozinha_id === escolhida)) && lista[0]) {
          escolhida = lista[0].cozinha_id;
          carrinhoRef.current.definirCozinha({ id: lista[0].cozinha_id, nome: lista[0].nome });
        }
      } else {
        setCozinhas([]);
        // Sem multi_cozinha o servidor manda todos os pedidos para a cozinha padrão: só os pratos dela
        escolhida = await cozinhaPadrao();
      }
      const itens = await lerCardapio(escolhida);
      setCardapio(itens);
      setDoses(new Map(itens[0] ? (await lerDoses(itens[0].cozinha_id).catch(() => [])).map((d) => [d.cardapio_id, d.restantes]) : []));
      setEnderecos(ends);
      // I9: pratos com opções abrem o ecrã de montar; um grupo obrigatório sem opções disponíveis esgota o prato
      const [grupos, componentes] = ligada('pratos_montaveis')
        ? await Promise.all([lerOpcoes(itens.map((i) => i.id)), lerComponentes(itens.map((i) => i.id)).catch(() => [])])
        : [[], []];
      // Também se monta um prato cuja receita tem ingredientes que se podem tirar (mais do que um)
      const comIngredientes = itens.filter((i) => componentes.filter((c) => c.cardapio_id === i.id).length > 1).map((i) => i.id);
      setMontaveis(new Set([...grupos.filter((g) => g.opcoes.length > 0).map((g) => g.cardapio_id), ...comIngredientes]));
      setDesde(
        new Map(
          itens
            .map((i) => [i.id, i.preco, grupos.filter((g) => g.cardapio_id === i.id && g.minimo > 0)] as const)
            .filter(([, , gs]) => gs.length > 0)
            .map(([id, preco, gs]) => [id, precoMinimo(preco, gs)]),
        ),
      );
      setEsgotados(new Set(grupos.filter((g) => gruposEsgotados([g]).length > 0).map((g) => g.cardapio_id)));
      // C7: contador do bairro do endereço principal (o servidor devolve null abaixo do mínimo)
      const zona = ends[0]?.pontos_entrega?.zona_id;
      setContador(ligada('contadores_zona') && zona ? await contadorZona(zona) : null);
      // C10: média de cada prato (só com o mínimo de avaliações)
      setMedias(ligada('avaliacoes') && itens[0] ? await mediasAvaliacoes(itens[0].cozinha_id).catch(() => null) : null);
      // Banner de acompanhamento: o pedido mais recente que ainda está em andamento (lista vem por data desc)
      const pedidos = await lerPedidos(perfil?.cliente_id).catch(() => [] as Pedido[]);
      const activo = pedidos.find((p) => EM_ANDAMENTO.includes(p.estado)) ?? null;
      setPedidoActivo(activo);
      // Enquanto não há pedido em curso, propõe repetir o último entregue ("o teu habitual")
      setUltimoTerminado(activo ? null : pedidos.find((p) => p.estado === 'entregue_pago') ?? null);
      // Cartão de selos (null se o interruptor estiver desligado)
      setSelos(ligada('selos') ? await meusSelos().catch(() => null) : null);
      // Tempo real do estafeta (posição no mapa) enquanto está a caminho; cai para null se não houver GPS
      const posicao =
        activo?.estado === 'em_entrega' && ligada('acompanhamento_entrega')
          ? await posicaoEntrega(activo.id).catch(() => null)
          : null;
      setMinutosEstafeta(posicao?.activo ? (posicao.minutos ?? null) : null);
    } catch (e) {
      setErro(mensagemErro(e));
    }
  }, [ligada, cozinhaId, emGrupo]);

  useFocusEffect(
    useCallback(() => {
      void carregar();
    }, [carregar]),
  );

  // Tempo a mostrar no banner: o do mapa (estafeta) se existir, senão o que falta até à hora prometida.
  // Acima de 2 h (ex.: pedido agendado) não faz sentido em "minutos" — aí mostra-se a hora.
  const minutosBanner = useMemo(() => {
    if (minutosEstafeta != null) return minutosEstafeta;
    if (!pedidoActivo?.hora_prometida) return null;
    const m = Math.round((new Date(pedidoActivo.hora_prometida).getTime() - Date.now()) / 60000);
    return m > 0 && m <= 120 ? m : null;
  }, [minutosEstafeta, pedidoActivo]);

  // Trocar de cozinha esvazia o carrinho (os pratos são de outra cozinha): com carrinho cheio,
  // confirma antes de apagar, para uma escolha distraída não deitar fora o trabalho do cliente.
  // "Pedir de novo" a partir do início: repõe o carrinho com os pratos ainda disponíveis do último pedido
  async function pedirDeNovo(p: Pedido) {
    setErro(null);
    setARepetir(true);
    try {
      const { linhas, cozinha: coz, faltam } = await montarRepeticao(p.itens);
      if (linhas.length === 0) {
        setErro('Os pratos desse pedido já não estão disponíveis.');
        return;
      }
      carrinho.repor(linhas, coz);
      router.push({ pathname: '/carrinho', params: faltam.length > 0 ? { faltam: faltam.join(', ') } : {} });
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setARepetir(false);
    }
  }

  function trocarCozinha(id: string) {
    const c = cozinhas.find((x) => x.cozinha_id === id);
    if (!c || c.cozinha_id === cozinhaId) return;
    if (carrinho.quantidade > 0) setTrocaPendente(c);
    else carrinho.definirCozinha({ id: c.cozinha_id, nome: c.nome });
  }

  const categorias = useMemo(() => {
    const grupos = new Map<string, ItemCardapio[]>();
    for (const item of cardapio ?? []) {
      const chave = item.do_dia ? 'Prato do dia' : item.categoria || 'Cardápio';
      grupos.set(chave, [...(grupos.get(chave) ?? []), item]);
    }
    return [...grupos.entries()];
  }, [cardapio]);

  return (
    <View style={{ flex: 1, backgroundColor: cores.fundo }}>
      <ScrollView
        contentContainerStyle={[estilos.conteudo, { paddingBottom: 120 }]}
        refreshControl={
          <RefreshControl
            refreshing={aActualizar}
            onRefresh={async () => {
              setAActualizar(true);
              await carregar();
              setAActualizar(false);
            }}
          />
        }>
        {/* Momento de marca: uma saudação curta antes do cardápio */}
        <Text style={{ fontSize: 20, fontWeight: '800', color: cores.texto }}>
          {perfil?.primeiro_nome ? `Olá, ${perfil.primeiro_nome} 👋` : 'Olá 👋'}
        </Text>
        <Text style={{ color: cores.textoSuave, marginTop: -espaco.xs }}>O que vais almoçar hoje?</Text>
        {/* Banner: pedido em andamento — toca para acompanhar a entrega */}
        {pedidoActivo && (
          <Pressable
            accessibilityRole="button"
            onPress={() => router.push({ pathname: '/pedido/[id]', params: { id: pedidoActivo.id } })}>
            <View
              style={{
                backgroundColor: cores.fundoSuave,
                borderRadius: raio,
                borderLeftWidth: 4,
                borderLeftColor: corEstadoPedido[pedidoActivo.estado],
                padding: espaco.m,
                gap: 2,
              }}>
              <Text style={{ fontSize: 16, fontWeight: '700', color: corEstadoPedido[pedidoActivo.estado] }}>
                {pedidoActivo.estado === 'em_entrega' ? '🛵 A tua entrega está a caminho' : `Pedido ${nomeEstadoPedido[pedidoActivo.estado].toLowerCase()}`}
              </Text>
              {minutosBanner != null ? (
                <Text style={{ color: cores.texto, fontWeight: '600' }}>Chega daqui a ~{minutosBanner} min</Text>
              ) : pedidoActivo.hora_prometida ? (
                <Text style={{ color: cores.texto, fontWeight: '600' }}>
                  Entrega prevista: {new Date(pedidoActivo.hora_prometida).toLocaleTimeString('pt-PT', { hour: '2-digit', minute: '2-digit' })}
                </Text>
              ) : null}
              <Text style={{ color: cores.textoSuave }}>Toca para acompanhar o teu pedido.</Text>
            </View>
          </Pressable>
        )}
        {/* Cartão de selos: frete grátis a cada N pedidos (só com o interruptor 'selos' ligado) */}
        {selos && (
          <Cartao>
            {selos.tem_premio ? (
              <Text style={{ fontWeight: '700', color: cores.marca }}>🎟️ Tens frete grátis! Aplica-se no teu próximo pedido.</Text>
            ) : (
              <>
                <Text style={{ fontWeight: '700', color: cores.texto }}>🎟️ Cartão de selos: {selos.progresso}/{selos.necessarios}</Text>
                <Text style={{ color: cores.textoSuave }}>
                  {selos.faltam === 1 ? 'Falta 1 pedido' : `Faltam ${selos.faltam} pedidos`} para o próximo frete grátis.
                </Text>
              </>
            )}
          </Cartao>
        )}
        {/* "O teu habitual": repetir o último pedido entregue num toque (só sem pedido em curso e com o carrinho vazio) */}
        {ultimoTerminado && carrinho.quantidade === 0 && !carrinho.grupo && (
          <Cartao>
            <Text style={{ fontSize: 15, fontWeight: '700', color: cores.texto }}>O teu habitual</Text>
            <Text style={{ color: cores.textoSuave }}>
              {ultimoTerminado.itens.map((i) => `${i.qtd}× ${i.nome}`).join(', ')}
            </Text>
            <Botao titulo="Pedir de novo" aCarregar={aRepetir} aoCarregar={() => pedirDeNovo(ultimoTerminado)} />
          </Cartao>
        )}
        {/* Convida e Ganha: desconto do 1.º pedido / ganhos / convite (adapta-se ao estado) */}
        <CartaoConvida />
        {/* I8: selector de cozinha por zona (só com multi_cozinha e mais de uma cozinha a aceitar pedidos).
            A marca é a mesma; cada opção é um balcão/zona. O título dá a afordância de lugar e o ✓
            reforça qual está escolhido. */}
        {ligada('multi_cozinha') && !carrinho.grupo && cozinhas.length > 1 && (
          <View style={{ gap: espaco.s }}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: cores.texto }}>📍 De onde queres pedir?</Text>
            {cozinhas.some((c) => c.distancia_km != null) && (
              <Text style={{ fontSize: 12, color: cores.textoSuave, marginTop: -espaco.xs }}>Mais perto primeiro</Text>
            )}
            <Escolha
              opcoes={cozinhas.map((c) => ({ valor: c.cozinha_id, rotulo: (c.cozinha_id === cozinhaId ? '✓ ' : '') + c.nome }))}
              valor={cozinhaId ?? ''}
              aoMudar={trocarCozinha}
              horizontal
            />
          </View>
        )}
        {contador !== null && (
          <Cartao>
            <Text style={{ fontSize: 16, fontWeight: '600' }}>{contador} pedidos no teu bairro hoje</Text>
          </Cartao>
        )}
        {enderecos.length === 0 && cardapio !== null && (
          <Aviso>
            Antes do primeiro pedido, adiciona o endereço de entrega.{' '}
            <Text style={{ fontWeight: '700' }} onPress={() => router.push('/enderecos/novo')}>
              Adicionar endereço
            </Text>
          </Aviso>
        )}
        {ligada('pedidos_grupo') && carrinho.grupo && (
          <Aviso>
            A juntar ao pedido de grupo das {carrinho.grupo.hora}. Escolhe os teus pratos.{' '}
            <Text style={{ fontWeight: '700' }} onPress={() => carrinho.definirGrupo(null)}>
              Sair do grupo
            </Text>
          </Aviso>
        )}
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {cardapio !== null && cardapio.length === 0 && <Paragrafo suave>O cardápio de hoje ainda não está disponível.</Paragrafo>}
        {categorias.map(([categoria, itens]) => (
          <View key={categoria} style={{ gap: espaco.s }}>
            {categoria === 'Prato do dia' ? (
              <View style={{ alignSelf: 'flex-start', backgroundColor: cores.destaqueFundo, borderRadius: 14, paddingHorizontal: espaco.m, paddingVertical: 4, marginTop: espaco.s }}>
                <Text style={{ color: cores.texto, fontWeight: '700', fontSize: 15 }}>★ Prato do dia</Text>
              </View>
            ) : (
              <Subtitulo>{categoria}</Subtitulo>
            )}
            {itens.map((item) => {
              const noCarrinho = carrinho.quantidadeDe(item.id);
              return (
                <View key={item.id} style={{ backgroundColor: cores.fundoSuave, borderRadius: raio, padding: espaco.m, gap: 4 }}>
                  {item.foto_url ? (
                    <Image
                      source={{ uri: item.foto_url }}
                      style={{ width: '100%', aspectRatio: 4 / 3, borderRadius: raio, marginBottom: 4 }}
                      accessibilityLabel={item.nome}
                    />
                  ) : null}
                  <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: espaco.m }}>
                    <Text style={{ fontSize: 16, fontWeight: '600', flex: 1 }}>{item.nome}</Text>
                    <Text style={{ fontSize: 16, fontWeight: '700' }}>
                      {desde.has(item.id) ? `desde ${formatarKz(desde.get(item.id))}` : formatarKz(item.preco)}
                    </Text>
                  </View>
                  {item.descricao ? <Text style={{ color: cores.textoSuave }} numberOfLines={2}>{item.descricao}</Text> : null}
                  {(() => {
                    const m = item.prato_base_id ? medias?.pratos.find((p) => p.prato_base_id === item.prato_base_id) : undefined;
                    return m ? (
                      <Pressable
                        accessibilityRole="link"
                        onPress={() =>
                          router.push({
                            pathname: '/avaliacoes',
                            params: { cozinha: item.cozinha_id, prato: item.prato_base_id ?? '', nome: item.nome },
                          })
                        }>
                        <Text style={{ color: cores.marca, fontWeight: '600' }}>{formatarMedia(m.media, m.total)}</Text>
                      </Pressable>
                    ) : null;
                  })()}
                  <View style={{ flexDirection: 'row', justifyContent: 'flex-end', alignItems: 'center', gap: espaco.m }}>
                    {noCarrinho > 0 && <Text style={{ color: cores.marca, fontWeight: '600' }}>{noCarrinho} no carrinho</Text>}
                    {!esgotados.has(item.id) && doses.has(item.id) && doses.get(item.id)! > 0 && doses.get(item.id)! <= 5 && (
                      <Text style={{ color: cores.aviso, fontWeight: '600' }}>{`Restam ${doses.get(item.id)}`}</Text>
                    )}
                    {esgotados.has(item.id) || doses.get(item.id) === 0 ? (
                      <Text style={{ color: cores.textoSuave, fontWeight: '700' }}>Esgotado</Text>
                    ) : (
                      <Pressable
                        accessibilityRole="button"
                        onPress={() =>
                          montaveis.has(item.id)
                            ? router.push({ pathname: '/montar/[id]', params: { id: item.id } })
                            : carrinho.adicionar(item)
                        }
                        style={{ backgroundColor: cores.marcaClara, borderRadius: 20, paddingHorizontal: espaco.l, paddingVertical: 6 }}>
                        <Text style={{ color: cores.marca, fontWeight: '700' }}>{montaveis.has(item.id) ? 'Montar' : 'Adicionar'}</Text>
                      </Pressable>
                    )}
                  </View>
                </View>
              );
            })}
          </View>
        ))}
        {/* Promos e extras ficam DEPOIS do cardápio (comida primeiro): pacote, grupo, como chegar. */}
        {ligada('pacotes') && !carrinho.grupo && (
          <Botao titulo="Pacote do mês: paga uma vez, almoça o mês todo" variante="secundario" aoCarregar={() => router.push('/pacotes')} />
        )}
        {ligada('pedidos_grupo') && !carrinho.grupo && (
          <Botao titulo="Pedido de grupo com os colegas" variante="secundario" aoCarregar={() => router.push('/grupos')} />
        )}
        {ligada('como_chegar') && (cozinhaId ?? cardapio?.[0]?.cozinha_id) && (
          <ComoChegar cozinhaId={(cozinhaId ?? cardapio?.[0]?.cozinha_id) as string} />
        )}
        {/* No fim do cardápio: convite às receitas — "comida primeiro, conteúdo depois".
            Cartão (não botão de rodapé solto) para ser discreto mas descoberto. */}
        {ligada('receitas') && !carrinho.grupo && cardapio !== null && cardapio.length > 0 && (
          <Cartao>
            <Text style={{ fontSize: 16, fontWeight: '700', color: cores.texto }}>🍲 Cozinha de casa</Text>
            <Text style={{ color: cores.textoSuave }}>Não decidiste? Inspira-te nas receitas da terra.</Text>
            <Botao titulo="Ver receitas da terra" variante="destaque" aoCarregar={() => router.push('/receitas')} />
          </Cartao>
        )}
      </ScrollView>
      {carrinho.quantidade > 0 && (
        <View style={{ position: 'absolute', left: espaco.l, right: espaco.l, bottom: espaco.l }}>
          <Botao
            titulo={`Ver pedido (${carrinho.quantidade}) · ${formatarKz(carrinho.totalEstimado)}`}
            aoCarregar={() => router.push('/carrinho')}
          />
        </View>
      )}
      <Confirmar
        visivel={trocaPendente !== null}
        titulo="Mudar de cozinha?"
        mensagem="Os pratos no carrinho são desta cozinha e serão removidos."
        textoConfirmar="Mudar e esvaziar"
        aoConfirmar={() => {
          if (trocaPendente) carrinho.definirCozinha({ id: trocaPendente.cozinha_id, nome: trocaPendente.nome });
          setTrocaPendente(null);
        }}
        aoCancelar={() => setTrocaPendente(null)}
      />
    </View>
  );
}
