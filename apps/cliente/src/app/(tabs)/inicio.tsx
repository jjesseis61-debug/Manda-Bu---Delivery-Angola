import Ionicons from '@expo/vector-icons/Ionicons';
import { useFocusEffect, useNavigation, useRouter } from 'expo-router';
import { useCallback, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, Image, Pressable, RefreshControl, ScrollView, Text, View } from 'react-native';

import { CartaoConvida } from '@/components/CartaoConvida';
import { Confirmar } from '@/components/Confirmar';
import { BotaoBalcao, FolhaBalcoes, textoDistancia } from '@/components/EscolherBalcao';
import { LoginNecessario } from '@/components/LoginNecessario';
import { FaixaConfianca } from '@/components/FaixaConfianca';
import { ComoChegar } from '@/components/ComoChegar';
import { MediaAvaliacao } from '@/components/MediaAvaliacao';
import { PrecoCartao } from '@/components/Preco';
import { Sino, SinoVisitante } from '@/components/Sino';
import { Aviso, Botao, Cartao, Paragrafo, Subtitulo, estilos } from '@/components/ui';
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
  maisPedidosNaZona,
  visitaExperiencia,
  type MaisPedidoZona,
} from '@/lib/api';
import { balcaoLonge, cardapioMaisTarde, cozinhasPertoDe, posicaoActual, textoQuandoVolta, type PratoMaisTarde } from '@/lib/balcao';
import { useCarrinho } from '@/lib/carrinho';
import {
  condominioAqui,
  cozinhasComCondominio,
  posicaoParaCondominio,
  promocoesParaMim,
  textoCondominioFechado,
  type CondominioAqui,
  type Promocao,
  precosParaMim,
} from '@/lib/condominio';
import { corEstadoPedido, formatarData, formatarKz, horaLuanda, mensagemErro, nomeEstadoPedido, textoPediram, textoPromocao } from '@/lib/formatar';
import { gruposEsgotados, precoMinimo } from '@/lib/opcoes';
import { usePartilhar } from '@/components/Partilhar';
import { usePedirDeNovo } from '@/lib/pedirDeNovo';
import { useSessao } from '@/lib/sessao';
import {
  lerCardapioVisitante,
  lerCozinhasVisitante,
  lerZonasVisitante,
  lerZonaVisitante,
  ordenarCozinhasVisitante,
  type Destino,
  type ZonaVisitante,
  lerPrecosVisitante,
} from '@/lib/visitante';
import { cores, espaco, raio } from '@/lib/tema';
import type { CozinhaParaPedir, Endereco, ItemCardapio, MediasAvaliacoes, MeusSelos, Pedido } from '@/lib/tipos';

const EM_ANDAMENTO = ['pendente', 'confirmado', 'em_preparacao', 'em_entrega'];

export default function Inicio() {
  const router = useRouter();
  const navigation = useNavigation();
  const { ligada, perfil, parametros, sessao } = useSessao();
  // Sem conta (a app abre no Início para todos): lê o que é público e pede o número só no «Pedir»
  const visitante = !sessao || !perfil;
  // Funções pessoais tocadas pelo visitante (pacote, grupo, receitas): pede para entrar e volta aqui
  const [login, setLogin] = useState<{ motivo: string; destino: Destino } | null>(null);
  const carrinho = useCarrinho();
  // Quem tem código de convite partilha o prato com ele: o amigo ganha o desconto e conta para o embaixador
  // Partilhar: com conta leva o código de convite; sem conta propõe «Partilha e ganha» antes
  const { partilhar, folhas: folhasPartilha } = usePartilhar();
  const pedirDeNovoNoCarrinho = usePedirDeNovo();
  const [cardapio, setCardapio] = useState<ItemCardapio[] | null>(null);
  const [enderecos, setEnderecos] = useState<Endereco[]>([]);
  const [maisZona, setMaisZona] = useState<MaisPedidoZona[]>([]);
  const [contador, setContador] = useState<number | null>(null);
  const [medias, setMedias] = useState<MediasAvaliacoes | null>(null);
  const [cozinhas, setCozinhas] = useState<CozinhaParaPedir[]>([]);
  // Cozinha de condomínio (pelo GPS, só para membros): aberta substitui a lista; fechada mostra um cartão
  const [condominio, setCondominio] = useState<CondominioAqui | null>(null);
  // Promoções (campanhas) que valem agora para a morada principal
  const [promocoes, setPromocoes] = useState<Promocao[]>([]);
  /** Preço com campanha de cada prato (riscado no cartão) e o limiar da entrega grátis da zona */
  const [precosCampanha, setPrecosCampanha] = useState<Map<string, { preco: number; campanha: string }>>(new Map());
  const [entregaGratisAcima, setEntregaGratisAcima] = useState<number | null>(null);
  // Troca de cozinha com carrinho cheio: confirma antes de esvaziar
  const [trocaPendente, setTrocaPendente] = useState<CozinhaParaPedir | null>(null);
  // Lista dos balcões aberta a partir do botão do título
  const [aEscolherBalcao, setAEscolherBalcao] = useState(false);
  // «Perto de mim»: com a posição do telemóvel, os balcões ordenam-se a partir dela (e não da morada)
  const [gps, setGps] = useState<{ lat: number; lng: number } | null>(null);
  const [aLocalizar, setALocalizar] = useState(false);
  const [erroGps, setErroGps] = useState<string | null>(null);
  // Aviso «há um balcão mais perto»: o cliente pode dizer que quer ficar neste
  const [ficarEm, setFicarEm] = useState<string | null>(null);
  // Pratos fora do horário agora, com a hora a que voltam (para não desaparecerem sem explicação)
  const [maisTarde, setMaisTarde] = useState<PratoMaisTarde[]>([]);
  /** Fotografia grande (como antes) ou média no cartão do prato: decidido pelo teste com grupo de controlo */
  const [fotoGrande, setFotoGrande] = useState(false);
  // Hora em que o Início abriu e se o primeiro «Adicionar» desta visita já foi contado (só com teste activo)
  const abertoEm = useRef(0);
  const tempoContado = useRef(true);
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
  // Herói do montável no topo + barra fixa que aparece quando o herói sai do ecrã ao rolar
  const [heroiFora, setHeroiFora] = useState(false);
  const heroiFimY = useRef(0);
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
      if (visitante) {
        // Visitante: bairro escolhido (taxa de entrega), cozinhas desse bairro e o cardápio público
        const [zs, guardada] = await Promise.all([lerZonasVisitante().catch(() => [] as ZonaVisitante[]), lerZonaVisitante()]);
        const z = guardada ? (zs.find((x) => x.id === guardada.id) ?? null) : null;
        const lista: CozinhaParaPedir[] = ordenarCozinhasVisitante(await lerCozinhasVisitante(z?.id ?? null)).map((c) => ({
          cozinha_id: c.id,
          nome: c.nome,
          publica: !!c.foto_url,
          foto_url: c.foto_url,
          historia: null,
          pratos: c.pratos,
          distancia_km: c.distancia_km,
        }));
        let escolhida = cozinhaId;
        if (!emGrupo && (!escolhida || !lista.some((c) => c.cozinha_id === escolhida)) && lista[0]) {
          escolhida = lista[0].cozinha_id;
          carrinhoRef.current.definirCozinha({ id: lista[0].cozinha_id, nome: lista[0].nome });
        }
        setCozinhas(ligada('multi_cozinha') ? lista : []);
        const dados = escolhida ? await lerCardapioVisitante(escolhida) : null;
        const itens = dados?.pratos ?? [];
        setCardapio(itens);
        setMontaveis(new Set(itens.filter((i) => i.montar).map((i) => i.id)));
        setEsgotados(new Set(itens.filter((i) => i.esgotado).map((i) => i.id)));
        setDoses(new Map());
        setDesde(new Map(itens.filter((i) => i.desde != null).map((i) => [i.id, i.desde as number])));
        setEnderecos([]);
        setMaisTarde([]);
        setMaisZona([]);
        setPromocoes([]);
        // Preço riscado também para quem ainda não entrou (campanhas para todos e do bairro); falha em silêncio
        const precosV = escolhida && ligada('campanhas') ? await lerPrecosVisitante(escolhida, z?.id ?? null).catch(() => null) : null;
        setPrecosCampanha(new Map((precosV?.pratos ?? []).map((p) => [p.cardapio_id, { preco: p.preco_campanha, campanha: p.campanha }])));
        setEntregaGratisAcima(z?.entrega_gratis_acima ?? null);
        setCondominio(null);
        setContador(null);
        setMedias(null);
        setPedidoActivo(null);
        setUltimoTerminado(null);
        setSelos(null);
        setMinutosEstafeta(null);
        return;
      }
      // Endereços primeiro: o ponto de entrega serve para ordenar os balcões por proximidade
      const ends = await lerEnderecos(perfil?.cliente_id);
      const ponto = ends[0]?.ponto_entrega_id ?? null;
      // I8: com multi_cozinha, o cliente escolhe a cozinha; por defeito a primeira da lista (a mais perto)
      let escolhida = cozinhaId;
      if (ligada('multi_cozinha')) {
        // Ordem: a posição do telemóvel («perto de mim»), senão a morada principal, senão a lista geral
        const gerais = gps
          ? await cozinhasPertoDe(gps.lat, gps.lng)
          : ponto
            ? await cozinhasPertoParaPedir(ponto)
            : await cozinhasParaPedir();
        let cond: CondominioAqui | null = null;
        if (ligada('condominios')) {
          const pos = await posicaoParaCondominio();
          cond = pos ? await condominioAqui(pos.lat, pos.lng).catch(() => null) : null;
        }
        setCondominio(cond?.visivel ? cond : null);
        const lista = cozinhasComCondominio(cond, gerais);
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
      setMaisTarde(escolhida ? await cardapioMaisTarde(escolhida).catch(() => []) : []);
      setDoses(new Map(itens[0] ? (await lerDoses(itens[0].cozinha_id).catch(() => [])).map((d) => [d.cardapio_id, d.restantes]) : []));
      setEnderecos(ends);
      // Prova social local: o que mais se pede na zona da morada (falha em silêncio)
      setMaisZona(ponto ? await maisPedidosNaZona(ponto).catch(() => []) : []);
      setPromocoes(ponto && ligada('campanhas') ? await promocoesParaMim(ponto).catch(() => []) : []);
      // Preço riscado (só com campanha verdadeira) e entrega grátis da zona; falha em silêncio
      const cozinhaPrecos = itens[0]?.cozinha_id ?? escolhida;
      const precos = ponto && cozinhaPrecos ? await precosParaMim(ponto, cozinhaPrecos).catch(() => null) : null;
      setPrecosCampanha(new Map((precos?.pratos ?? []).map((p) => [p.cardapio_id, { preco: p.preco_campanha, campanha: p.campanha }])));
      setEntregaGratisAcima(precos?.entrega_gratis_acima ?? null);
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
  }, [ligada, cozinhaId, emGrupo, visitante, gps]);


  useFocusEffect(
    useCallback(() => {
      void carregar();
    }, [carregar]),
  );

  // Teste das fotografias (Skinner: medir com grupo de controlo). Cada cliente fica sempre no mesmo
  // grupo; sem teste (desligado, sem conta ou erro) todos vêem a fotografia média.
  const comTeste = !visitante && ligada('teste_fotos_inicio');
  useFocusEffect(
    useCallback(() => {
      if (!comTeste) {
        setFotoGrande(false);
        tempoContado.current = true;
        return;
      }
      abertoEm.current = Date.now();
      tempoContado.current = false;
      visitaExperiencia('fotos_inicio')
        .then((g) => setFotoGrande(g === 'A'))
        .catch(() => setFotoGrande(false));
    }, [comTeste]),
  );
  /** Primeiro «Adicionar»/«Servir» desta visita: guarda quanto tempo levou (uma vez, falha em silêncio) */
  const contarPrimeiroAdicionar = () => {
    if (tempoContado.current) return;
    tempoContado.current = true;
    void visitaExperiencia('fotos_inicio', (Date.now() - abertoEm.current) / 1000).catch(() => undefined);
  };

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
      if (!(await pedirDeNovoNoCarrinho(p.itens))) setErro('Os pratos desse pedido já não estão disponíveis.');
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setARepetir(false);
    }
  }

  function trocarCozinha(id: string, lista: CozinhaParaPedir[] = cozinhas) {
    setAEscolherBalcao(false);
    const c = lista.find((x) => x.cozinha_id === id);
    if (!c || c.cozinha_id === cozinhaId) return;
    if (carrinho.quantidade > 0) setTrocaPendente(c);
    else carrinho.definirCozinha({ id: c.cozinha_id, nome: c.nome });
  }

  // «Perto de mim»: pede a posição, ordena os balcões a partir dela e propõe o mais perto
  async function pertoDeMim() {
    setErroGps(null);
    setALocalizar(true);
    try {
      const pos = await posicaoActual();
      if (!pos) {
        setErroGps('Não conseguimos a tua localização. Autoriza a localização no telemóvel ou escolhe da lista.');
        return;
      }
      const lista = await cozinhasPertoDe(pos.lat, pos.lng);
      setGps(pos);
      setCozinhas(lista);
      setFicarEm(null);
      if (lista[0]) trocarCozinha(lista[0].cozinha_id, lista);
      else setAEscolherBalcao(false);
    } catch (e) {
      setErroGps(mensagemErro(e));
    } finally {
      setALocalizar(false);
    }
  }

  const categorias = useMemo(() => {
    const grupos = new Map<string, ItemCardapio[]>();
    for (const item of cardapio ?? []) {
      if (montaveis.has(item.id)) continue; // os montáveis aparecem como herói no topo
      const chave = item.do_dia ? 'Prato do dia' : item.categoria || 'Cardápio';
      grupos.set(chave, [...(grupos.get(chave) ?? []), item]);
    }
    return [...grupos.entries()];
  }, [cardapio, montaveis]);

  // Montáveis em destaque (herói) e o primeiro servível (para a barra fixa)
  const herois = (cardapio ?? []).filter((i) => montaveis.has(i.id));
  const heroiServivel = herois.find((i) => !(esgotados.has(i.id) || doses.get(i.id) === 0));

  // Balcão no título («📍 Viana ▾»): escolhe-se primeiro de onde se pede, e só depois vêm campanhas e pratos
  const podeEscolherBalcao = ligada('multi_cozinha') && !carrinho.grupo && cozinhas.length > 1;
  const balcaoActual = cozinhaId ?? cardapio?.[0]?.cozinha_id ?? null;
  const nomeBalcao = cozinhas.find((c) => c.cozinha_id === balcaoActual)?.nome ?? null;
  // De onde se medem as distâncias: o telemóvel («de ti») ou a morada principal
  const morada = enderecos[0];
  const referenciaBalcoes = gps
    ? 'de ti'
    : morada
      ? `de ${[morada.nome ?? 'Casa', morada.pontos_entrega?.zonas?.nome].filter(Boolean).join(' · ')}`
      : null;
  // Aviso «há um balcão mais perto» (o carrinho guarda o balcão de antes, mesmo que o cliente já esteja noutro sítio)
  const longe = podeEscolherBalcao && referenciaBalcoes ? balcaoLonge(cozinhas, balcaoActual) : null;
  const mostrarLonge = longe && ficarEm !== longe.actual.cozinha_id;
  const idsMaisTarde = new Map(maisTarde.map((p) => [p.cardapio_id, p]));
  const soMaisTarde = maisTarde.filter((p) => !(cardapio ?? []).some((i) => i.id === p.cardapio_id));
  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          {podeEscolherBalcao && nomeBalcao ? <BotaoBalcao nome={nomeBalcao} aoCarregar={() => setAEscolherBalcao(true)} /> : null}
          {visitante ? <SinoVisitante /> : <Sino />}
        </View>
      ),
    });
  }, [navigation, podeEscolherBalcao, nomeBalcao, visitante]);

  return (
    <View style={{ flex: 1, backgroundColor: cores.fundo }}>
      <ScrollView
        contentContainerStyle={[estilos.conteudo, { paddingBottom: 120 }]}
        scrollEventThrottle={16}
        onScroll={(e) => {
          const y = e.nativeEvent.contentOffset.y;
          const fora = heroiFimY.current > 0 && y > heroiFimY.current - 8;
          setHeroiFora((v) => (v === fora ? v : fora));
        }}
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
        {/* Faixa de confiança: o contador do bairro passa a alternar dentro dela */}
        <FaixaConfianca contador={contador} />
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
        {maisZona.length > 0 && (
          <Cartao estilo={{ gap: espaco.xs }}>
            <Text style={{ fontWeight: '700', color: cores.texto }}>🔥 O mais pedido na tua zona</Text>
            {maisZona.map((m) => {
              const daqui = m.cozinha_id === cozinhaId;
              return (
                <Pressable
                  key={m.cardapio_id}
                  accessibilityRole={daqui ? 'button' : undefined}
                  disabled={!daqui}
                  onPress={() => router.push({ pathname: '/montar/[id]', params: { id: m.cardapio_id } })}>
                  <Text style={{ color: daqui ? cores.marca : cores.texto, fontWeight: daqui ? '700' : '400' }}>
                    {`${m.nome}${daqui ? '' : ` · ${m.cozinha}`} — ${m.pedidos} pedidos nos últimos 30 dias`}
                  </Text>
                </Pressable>
              );
            })}
          </Cartao>
        )}
        {/* Herói: "Serve o teu próprio prato" em destaque no topo (rompe o padrão da lista) */}
        {ligada('pratos_montaveis') && herois.length > 0 && (
          <View
            style={{ gap: espaco.s }}
            onLayout={(e) => {
              heroiFimY.current = e.nativeEvent.layout.y + e.nativeEvent.layout.height;
            }}>
            {herois.map((item) => {
              const servivel = !(esgotados.has(item.id) || doses.get(item.id) === 0);
              // Linha compacta (era um cartão grande com fotografia): a comida fica mais perto do topo
              return (
                <Pressable
                  key={item.id}
                  accessibilityRole="button"
                  accessibilityLabel={`${item.nome}. ${servivel ? 'Servir' : 'Esgotado'}`}
                  disabled={!servivel}
                  onPress={() => router.push({ pathname: '/montar/[id]', params: { id: item.id } })}
                  style={{
                    flexDirection: 'row',
                    alignItems: 'center',
                    gap: espaco.s,
                    backgroundColor: cores.marcaClara,
                    borderRadius: raio,
                    borderWidth: 1.5,
                    borderColor: cores.marca,
                    padding: espaco.m,
                  }}>
                  {item.foto_url ? (
                    <Image source={{ uri: item.foto_url }} style={{ width: 48, height: 48, borderRadius: 24 }} accessibilityLabel={item.nome} />
                  ) : (
                    <Text style={{ fontSize: 26 }}>🍽️</Text>
                  )}
                  <View style={{ flex: 1, gap: 2 }}>
                    <Text style={{ fontSize: 16, fontWeight: '800', color: cores.marcaEscura }} numberOfLines={1}>{item.nome}</Text>
                    {item.descricao ? (
                      <Text style={{ color: cores.textoSuave, fontSize: 13 }} numberOfLines={1}>{item.descricao}</Text>
                    ) : null}
                  </View>
                  <Pressable
                    accessibilityRole="button"
                    accessibilityLabel={`Partilhar ${item.nome} no WhatsApp`}
                    hitSlop={8}
                    onPress={() => void partilhar(item.nome, item.id)}>
                    <Ionicons name="share-social-outline" size={20} color={cores.marca} />
                  </Pressable>
                  {servivel ? (
                    <View style={{ backgroundColor: cores.marca, borderRadius: 20, paddingHorizontal: espaco.m, paddingVertical: 6 }}>
                      <Text style={{ color: '#FFFFFF', fontWeight: '800' }}>Servir</Text>
                    </View>
                  ) : (
                    <Text style={{ color: cores.textoSuave, fontWeight: '700' }}>Esgotado</Text>
                  )}
                </Pressable>
              );
            })}
          </View>
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
          <View
            style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.s, backgroundColor: cores.fundoSuave, borderRadius: raio, padding: espaco.m }}>
            <View style={{ flex: 1, gap: 2 }}>
              <Text style={{ fontSize: 15, fontWeight: '700', color: cores.texto }}>↺ O teu habitual</Text>
              <Text style={{ color: cores.textoSuave, fontSize: 13 }} numberOfLines={2}>
                {ultimoTerminado.itens.map((i) => `${i.qtd}× ${i.nome}`).join(', ')}
              </Text>
            </View>
            <Pressable
              accessibilityRole="button"
              disabled={aRepetir}
              onPress={() => void pedirDeNovo(ultimoTerminado)}
              style={{ backgroundColor: cores.marca, borderRadius: 20, paddingHorizontal: espaco.m, paddingVertical: 8, minWidth: 120, alignItems: 'center' }}>
              {aRepetir ? <ActivityIndicator color="#FFFFFF" /> : <Text style={{ color: '#FFFFFF', fontWeight: '800' }}>Pedir de novo</Text>}
            </Pressable>
          </View>
        )}
        {/* Cozinha de condomínio (o balcão escolhe-se no título, «📍 … ▾») */}
        {condominio && condominio.aberta && !carrinho.grupo && (
          <Cartao>
            <Text style={{ fontSize: 15, fontWeight: '700', color: cores.texto }}>🏘️ {condominio.cozinha}</Text>
            <Text style={{ color: cores.textoSuave }}>A cozinha do {condominio.nome}, só para os moradores.</Text>
          </Cartao>
        )}
        {condominio && !condominio.aberta && <Aviso>{textoCondominioFechado(condominio, horaLuanda)}</Aviso>}
        {promocoes.map((p) => (
          <Cartao key={p.nome}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: cores.marca }}>🏷️ {p.nome}</Text>
            <Text style={{ color: cores.texto }}>{textoPromocao(p)}</Text>
            {p.fim && <Text style={{ color: cores.textoSuave, fontSize: 12 }}>Até {formatarData(p.fim)}</Text>}
          </Cartao>
        ))}
        {!visitante && enderecos.length === 0 && cardapio !== null && (
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
        {mostrarLonge && longe && (
          <Cartao estilo={{ gap: espaco.s }}>
            <Text style={{ fontWeight: '700', color: cores.texto }}>
              {`📍 ${longe.actual.nome} fica a ${textoDistancia(longe.actual.distancia_km ?? 0)} ${referenciaBalcoes}.`}
            </Text>
            <Text style={{ color: cores.texto }}>
              {`${longe.perto.nome} fica a ${textoDistancia(longe.perto.distancia_km ?? 0)}: a comida chega mais depressa.`}
            </Text>
            <Botao titulo={`Pedir em ${longe.perto.nome}`} aoCarregar={() => trocarCozinha(longe.perto.cozinha_id)} />
            <Botao titulo={`Ficar em ${longe.actual.nome}`} variante="texto" aoCarregar={() => setFicarEm(longe.actual.cozinha_id)} />
          </Cartao>
        )}
        {cardapio !== null && cardapio.length === 0 && <Paragrafo suave>O cardápio de hoje ainda não está disponível.</Paragrafo>}
        {entregaGratisAcima != null && cardapio !== null && cardapio.length > 0 && (
          <Text style={{ color: cores.sucesso, fontWeight: '700' }}>
            🚚 Entrega grátis em pedidos a partir de {formatarKz(entregaGratisAcima)}
          </Text>
        )}
        {categorias.map(([categoria, itens], indice) => (
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
              // Preço sempre no mesmo sítio (por baixo do nome, grande); com campanha leva o riscado e os selos
              const promo = desde.has(item.id) ? undefined : precosCampanha.get(item.id);
              const final = promo?.preco ?? item.preco;
              const gratis = entregaGratisAcima != null && !desde.has(item.id) && final >= entregaGratisAcima;
              const selo = (texto: string, fundo: string, cor: string) => (
                <Text
                  key={texto}
                  style={{ backgroundColor: fundo, color: cor, fontSize: 12, fontWeight: '700', borderRadius: 8, paddingHorizontal: 8, paddingVertical: 3, overflow: 'hidden' }}>
                  {texto}
                </Text>
              );
              const media = item.prato_base_id ? medias?.pratos.find((p) => p.prato_base_id === item.prato_base_id) : undefined;
              const foto = item.foto_url ? (
                <Image
                  source={{ uri: item.foto_url }}
                  style={fotoGrande ? { width: '100%', aspectRatio: 4 / 3, borderRadius: raio } : { width: 112, height: 100, borderRadius: raio }}
                  accessibilityLabel={item.nome}
                />
              ) : null;
              return (
                <View key={item.id} style={{ backgroundColor: cores.fundoSuave, borderRadius: raio, padding: espaco.m, gap: espaco.s }}>
                  {fotoGrande && foto}
                  <View style={{ flexDirection: 'row', gap: espaco.m }}>
                    {!fotoGrande && foto}
                    <View style={{ flex: 1, gap: 4 }}>
                      <Text style={{ fontSize: 16, fontWeight: '700', color: cores.texto }} numberOfLines={2}>{item.nome}</Text>
                      <PrecoCartao preco={item.preco} promo={promo?.preco} desde={desde.get(item.id)} />
                      {(promo || gratis) && (
                        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: espaco.xs }}>
                          {promo && selo('✓ Desconto aplicado', cores.sucessoFundo, cores.sucesso)}
                          {promo && selo(`🏷️ ${promo.campanha}`, cores.fundo, cores.textoSuave)}
                          {gratis && selo('🚚 Entrega grátis', cores.sucessoFundo, cores.sucesso)}
                        </View>
                      )}
                      {media ? (
                        <Pressable
                          accessibilityRole="link"
                          onPress={() =>
                            router.push({
                              pathname: '/avaliacoes',
                              params: { cozinha: item.cozinha_id, prato: item.prato_base_id ?? '', nome: item.nome },
                            })
                          }>
                          <MediaAvaliacao media={media.media} total={media.total} />
                        </Pressable>
                      ) : null}
                      {parametros && item.pedidos_mes >= parametros.limiar_pediram && (
                        <Text style={{ color: cores.textoSuave, fontSize: 13 }}>👍 {textoPediram(item.pedidos_mes)}</Text>
                      )}
                    </View>
                  </View>
                  {item.descricao ? <Text style={{ color: cores.textoSuave }} numberOfLines={2}>{item.descricao}</Text> : null}
                  <View style={{ flexDirection: 'row', justifyContent: 'flex-end', alignItems: 'center', gap: espaco.m }}>
                    <Pressable
                      accessibilityRole="button"
                      accessibilityLabel={`Partilhar ${item.nome} no WhatsApp`}
                      onPress={() => void partilhar(item.nome, item.id)}
                      hitSlop={8}
                      style={{ flexDirection: 'row', alignItems: 'center', gap: 4, marginRight: 'auto' }}>
                      <Ionicons name="share-social-outline" size={18} color={cores.marca} />
                      <Text style={{ color: cores.marca, fontWeight: '600' }}>Partilhar</Text>
                    </Pressable>
                    {noCarrinho > 0 && <Text style={{ color: cores.marca, fontWeight: '600' }}>{noCarrinho} no carrinho</Text>}
                    {!esgotados.has(item.id) && doses.has(item.id) && doses.get(item.id)! > 0 && doses.get(item.id)! <= 5 && (
                      <Text style={{ color: cores.aviso, fontWeight: '600' }}>{`Restam ${doses.get(item.id)}`}</Text>
                    )}
                    {idsMaisTarde.has(item.id) ? (
                      <Text style={{ color: cores.aviso, fontWeight: '700' }}>{`À venda ${textoQuandoVolta(idsMaisTarde.get(item.id)!.proxima)}`}</Text>
                    ) : esgotados.has(item.id) || doses.get(item.id) === 0 ? (
                      <Text style={{ color: cores.textoSuave, fontWeight: '700' }}>Esgotado</Text>
                    ) : (
                      <Pressable
                        accessibilityRole="button"
                        onPress={() => {
                          contarPrimeiroAdicionar();
                          if (montaveis.has(item.id)) router.push({ pathname: '/montar/[id]', params: { id: item.id } });
                          else carrinho.adicionar(item);
                        }}
                        style={{ backgroundColor: cores.marcaClara, borderRadius: 20, paddingHorizontal: espaco.l, paddingVertical: 6 }}>
                        <Text style={{ color: cores.marca, fontWeight: '700' }}>{montaveis.has(item.id) ? 'Servir' : 'Adicionar'}</Text>
                      </Pressable>
                    )}
                  </View>
                </View>
              );
            })}
            {/* Convida e Ganha entre os pratos (depois do primeiro grupo): a comida vem primeiro */}
            {indice === 0 && <CartaoConvida />}
          </View>
        ))}
        {categorias.length === 0 && <CartaoConvida />}
        {/* Promos e extras ficam DEPOIS do cardápio (comida primeiro): pacote, grupo, como chegar. */}
        {ligada('pacotes') && !carrinho.grupo && (
          <Botao
            titulo="Pacote do mês: paga uma vez, almoça o mês todo"
            variante="secundario"
            aoCarregar={() =>
              visitante ? setLogin({ motivo: 'Entra para comprares o pacote do mês.', destino: '/pacotes' }) : router.push('/pacotes')
            }
          />
        )}
        {ligada('pedidos_grupo') && !carrinho.grupo && (
          <Botao
            titulo="Pedido de grupo (colegas, família, vizinhos)"
            variante="secundario"
            aoCarregar={() =>
              visitante ? setLogin({ motivo: 'Entra para fazeres um pedido de grupo.', destino: '/grupos' }) : router.push('/grupos')
            }
          />
        )}
        {/* Pratos fora do horário agora: dizem quando voltam, em vez de desaparecerem sem explicação */}
        {soMaisTarde.length > 0 && (
          <View style={{ gap: espaco.s }}>
            <Subtitulo>Mais tarde</Subtitulo>
            {soMaisTarde.map((p) => (
              <Cartao key={p.cardapio_id} estilo={{ flexDirection: 'row', alignItems: 'center', gap: espaco.m }}>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontWeight: '700', color: cores.texto }}>{p.nome}</Text>
                  <Text style={{ color: cores.textoSuave }}>{formatarKz(p.preco)}</Text>
                </View>
                <Text style={{ color: cores.aviso, fontWeight: '700' }}>{`À venda ${textoQuandoVolta(p.proxima)}`}</Text>
              </Cartao>
            ))}
          </View>
        )}
        {!visitante && ligada('como_chegar') && (cozinhaId ?? cardapio?.[0]?.cozinha_id) && (
          <ComoChegar cozinhaId={(cozinhaId ?? cardapio?.[0]?.cozinha_id) as string} />
        )}
        {/* No fim do cardápio: convite às receitas — "comida primeiro, conteúdo depois".
            Cartão (não botão de rodapé solto) para ser discreto mas descoberto. */}
        {ligada('receitas') && !carrinho.grupo && cardapio !== null && cardapio.length > 0 && (
          <Cartao>
            <Text style={{ fontSize: 16, fontWeight: '700', color: cores.texto }}>🍲 Cozinha de casa</Text>
            <Text style={{ color: cores.textoSuave }}>Não decidiste? Inspira-te nas receitas da terra.</Text>
            <Botao
              titulo="Ver receitas da terra"
              variante="destaque"
              aoCarregar={() =>
                visitante ? setLogin({ motivo: 'Entra para veres as receitas da terra.', destino: '/receitas' }) : router.push('/receitas')
              }
            />
          </Cartao>
        )}
      </ScrollView>
      {/* Barra fixa: reaparece quando o herói sai do ecrã ao rolar (recupera a visibilidade) */}
      {heroiFora && heroiServivel && (
        <Pressable
          accessibilityRole="button"
          onPress={() => router.push({ pathname: '/montar/[id]', params: { id: heroiServivel.id } })}
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            right: 0,
            backgroundColor: cores.marca,
            paddingHorizontal: espaco.l,
            paddingVertical: espaco.m,
            flexDirection: 'row',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: espaco.s,
          }}>
          <Text numberOfLines={1} style={{ color: '#FFFFFF', fontWeight: '800', fontSize: 15, flex: 1 }}>🍽️ Serve o teu próprio prato</Text>
          <View style={{ backgroundColor: '#FFFFFF', borderRadius: 16, paddingHorizontal: espaco.m, paddingVertical: 4 }}>
            <Text style={{ color: cores.marca, fontWeight: '800' }}>Servir</Text>
          </View>
        </Pressable>
      )}
      {carrinho.quantidade > 0 && (
        <View style={{ position: 'absolute', left: espaco.l, right: espaco.l, bottom: espaco.l }}>
          <Botao
            titulo={`Ver pedido (${carrinho.quantidade}) · ${formatarKz(carrinho.totalEstimado)}`}
            aoCarregar={() => router.push('/carrinho')}
          />
        </View>
      )}
      {folhasPartilha}
      <LoginNecessario
        visivel={login !== null}
        motivo={login?.motivo ?? ''}
        destino={login?.destino ?? '/inicio'}
        aoFechar={() => setLogin(null)}
      />
      <FolhaBalcoes
        visivel={aEscolherBalcao}
        cozinhas={cozinhas}
        actual={balcaoActual}
        referencia={referenciaBalcoes}
        aoPertoDeMim={visitante ? undefined : () => void pertoDeMim()}
        aLocalizar={aLocalizar}
        erroLocalizacao={erroGps}
        aoEscolher={(id) => trocarCozinha(id)}
        aoFechar={() => setAEscolherBalcao(false)}
      />
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
