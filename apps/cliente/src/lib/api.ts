// Chamadas ao servidor. Todos os valores (preços, descontos, ganhos, saldos) vêm daqui:
// a app só mostra o que o servidor devolve.
import { dispositivoId } from './dispositivo';
import { supabase } from './supabase';
import type {
  ComponentePrato,
  Contactos,
  ConversaAtendimento,
  AtrasoPedido,
  MinhaReclamacao,
  Amigo,
  AvaliacaoPublica,
  CozinhaParaPedir,
  Destaque,
  Endereco,
  GrupoDetalhe,
  GrupoOpcoes,
  Funcionalidades,
  ItemCardapio,
  Levantamento,
  LocalizacaoCozinha,
  MetodoPacote,
  MeuPacote,
  MinhaEmpresa,
  MediasAvaliacoes,
  MeuGrupo,
  MinhaPosicao,
  Orcamento,
  Pacote,
  PacotesAMinhaVolta,
  Parametros,
  Pedido,
  Perfil,
  PerfilDestaques,
  PreferenciasNotificacao,
  MeusSelos,
  PessoaComoTu,
  PosicaoEntrega,
  Receita,
  ReceitaResumo,
  Saldo,
  Zona,
  MetodoAntes,
  ModoGrupo,
  OndePedirReceita,
  PagamentoAntes,
  TipoGrupo,
} from './tipos';

function verificar<T>(resultado: { data: T | null; error: { message: string } | null }): T {
  if (resultado.error) throw resultado.error;
  return resultado.data as T;
}

// ---------------------------------------------------------------- configuração
export type Aviso = {
  id: string;
  codigo: string;
  titulo: string;
  corpo: string;
  dados: Record<string, unknown>;
  criado_em: string;
  vista_em: string | null;
};

/** Os meus avisos (sino): os mesmos que chegam por push, guardados para ler dentro da app */
export async function meusAvisos(limite = 50): Promise<Aviso[]> {
  return (verificar(await supabase.rpc('meus_avisos', { p_limite: limite })) as Aviso[]) ?? [];
}

export async function contarAvisosNovos(): Promise<number> {
  return (verificar(await supabase.rpc('contar_avisos_novos')) as number) ?? 0;
}

/** Marca como vistos (sem ids = todos) */
export async function marcarAvisosVistos(ids?: string[]): Promise<number> {
  return (verificar(await supabase.rpc('marcar_avisos_vistos', { p_ids: ids ?? null })) as number) ?? 0;
}

/** PWA: chave pública VAPID (gerada e guardada pelo servidor; null enquanto não existir) */
export async function chavePublicaPushWeb(): Promise<string | null> {
  return (verificar(await supabase.rpc('chave_publica_push_web')) as string | null) ?? null;
}

/** PWA: assinatura Web Push deste navegador */
export async function registarPushWeb(endpoint: string, p256dh: string, auth: string) {
  verificar(await supabase.rpc('registar_push_web', { p_endpoint: endpoint, p_p256dh: p256dh, p_auth: auth }));
}

export async function removerPushWeb(endpoint: string) {
  verificar(await supabase.rpc('remover_push_web', { p_endpoint: endpoint }));
}

/** Antifraude do Convida: aparelho em que a conta entrou (ver dispositivo.ts) */
export async function registarAparelho(instalacao: string, aparelho: string | null, plataforma: string, modelo: string | null) {
  verificar(
    await supabase.rpc('registar_aparelho', { p_instalacao: instalacao, p_aparelho: aparelho, p_plataforma: plataforma, p_modelo: modelo }),
  );
}

export async function lerConfiguracao(): Promise<{ parametros: Parametros; funcionalidades: Funcionalidades }> {
  const [p, f] = await Promise.all([
    supabase.from('parametros').select('*').eq('unico', true).single(),
    supabase.from('funcionalidades').select('chave, activa'),
  ]);
  const parametros = verificar(p) as Parametros;
  const funcionalidades: Funcionalidades = {};
  for (const linha of verificar(f) as { chave: keyof Funcionalidades; activa: boolean }[]) {
    funcionalidades[linha.chave] = linha.activa;
  }
  return { parametros, funcionalidades };
}

// ---------------------------------------------------------------- conta
/** Apaga a conta (soft-delete recuperável 60 dias); revoga as sessões em todos os dispositivos */
export async function apagarConta(): Promise<void> {
  verificar(await supabase.rpc('apagar_conta'));
}

/** Recupera a conta dentro dos 60 dias */
export async function recuperarConta(): Promise<void> {
  verificar(await supabase.rpc('recuperar_conta'));
}

/** Segurança: termina a sessão em TODOS os dispositivos, incluindo este */
export async function sairDeTodosOsDispositivos(): Promise<void> {
  const { error } = await supabase.auth.signOut({ scope: 'global' });
  if (error) throw error;
}

export async function meuPerfil(): Promise<Perfil | null> {
  return (verificar(await supabase.rpc('meu_perfil')) as Perfil | null) ?? null;
}

export async function registarCliente(nome: string, tipo: 'Particular' | 'Empresa', nif: string | null) {
  return verificar(await supabase.rpc('registar_cliente', { p_nome: nome, p_tipo: tipo, p_nif: nif })) as string;
}

/** Devolve 'ok' ou o motivo (programa_inactivo, codigo_inexistente, …) */
export async function ligarIndicacao(codigo: string): Promise<string> {
  return verificar(await supabase.rpc('ligar_indicacao', { p_codigo: codigo })) as string;
}

/** Desconto garantido da ligação do próprio cliente como indicado (confirmado pelo servidor) */
export async function descontoGarantido(clienteId: string): Promise<number | null> {
  const r = await supabase
    .from('ligacoes_indicacao')
    .select('desconto_garantido, desconto_usado')
    .eq('indicado_id', clienteId)
    .maybeSingle();
  const linha = verificar(r) as { desconto_garantido: number; desconto_usado: boolean } | null;
  return linha && !linha.desconto_usado ? linha.desconto_garantido : null;
}

// ---------------------------------------------------------------- cardápio e cozinha
/** Sem multi_cozinha, todos os pedidos vão para esta cozinha (a mais antiga activa) */
export async function cozinhaPadrao(): Promise<string | null> {
  return verificar(await supabase.rpc('cozinha_padrao')) as string | null;
}

export async function lerCardapio(cozinhaId?: string | null): Promise<ItemCardapio[]> {
  let q = supabase
    .from('cardapio')
    .select('id, nome, descricao, categoria, preco, foto_url, do_dia, cozinha_id, prato_base_id, minimo_montavel, cardapio_popularidade(pessoas)')
    .eq('disponivel', true)
    .eq('visivel_online', true);
  if (cozinhaId) q = q.eq('cozinha_id', cozinhaId);
  const r = await q
    .order('do_dia', { ascending: false })
    .order('ordem')
    .order('nome');
  // O embed vem tipado como array no supabase-js; em runtime é objeto (relação 1-para-1) ou null.
  const linhas = verificar(r) as unknown as (Omit<ItemCardapio, 'pedidos_mes'> & {
    cardapio_popularidade: { pessoas: number } | { pessoas: number }[] | null;
  })[];
  return linhas.map(({ cardapio_popularidade, ...resto }) => {
    const pop = Array.isArray(cardapio_popularidade) ? cardapio_popularidade[0] : cardapio_popularidade;
    return { ...resto, pedidos_mes: pop?.pessoas ?? 0 };
  });
}

export type Cozinha = { id: string; nome: string; foto_url: string | null; historia: string | null; selo_kota?: boolean };

/** Só devolve cozinhas com consentimento público (RLS); com cozinhaId, essa cozinha */
export async function lerCozinhaPublica(cozinhaId?: string | null): Promise<Cozinha | null> {
  const ler = (campos: string) => {
    let q = supabase.from('cozinhas').select(campos).eq('estado', 'activa');
    if (cozinhaId) q = q.eq('id', cozinhaId);
    return q.limit(1);
  };
  let r = await ler('id, nome, foto_url, historia, selo_kota');
  // Servidor ainda sem o selo «Kota da Cozinha»: lê sem ele (o perfil não pode partir por isso)
  if (r.error) r = await ler('id, nome, foto_url, historia');
  return ((verificar(r) as unknown as Cozinha[])[0] ?? null) as Cozinha | null;
}

/** Um prato do cardápio (ecrã de montar o prato) */
export async function lerItemCardapio(id: string): Promise<ItemCardapio | null> {
  const r = await supabase
    .from('cardapio')
    .select('id, nome, descricao, categoria, preco, foto_url, do_dia, cozinha_id, prato_base_id, minimo_montavel')
    .eq('id', id)
    .eq('disponivel', true)
    .maybeSingle();
  return verificar(r) as ItemCardapio | null;
}

/** I9: grupos de opções dos pratos indicados, só com as opções disponíveis */
export async function lerOpcoes(cardapioIds: string[]): Promise<GrupoOpcoes[]> {
  if (cardapioIds.length === 0) return [];
  const r = await supabase
    .from('opcoes_grupos')
    .select('id, cardapio_id, nome, minimo, maximo, ordem, opcoes(id, nome, preco_extra, ordem, foto_url, disponivel, deletado_em)')
    .in('cardapio_id', cardapioIds)
    .is('deletado_em', null)
    .order('ordem')
    .order('nome');
  type Linha = Omit<GrupoOpcoes, 'opcoes'> & {
    opcoes: (GrupoOpcoes['opcoes'][number] & { disponivel: boolean; deletado_em: string | null })[];
  };
  return (verificar(r) as Linha[]).map((g) => ({
    ...g,
    opcoes: g.opcoes
      .filter((o) => o.disponivel && !o.deletado_em)
      .sort((a, b) => a.ordem - b.ordem || a.nome.localeCompare(b.nome))
      .map(({ id, nome, preco_extra, ordem, foto_url }) => ({ id, nome, preco_extra, ordem, foto_url })),
  }));
}

/** I10: morada e ponto da cozinha, se a responsável autorizou e "Como chegar" está ligado */
export async function localizacaoCozinha(cozinhaId: string): Promise<LocalizacaoCozinha | null> {
  const r = verificar(await supabase.rpc('localizacao_cozinha', { p_cozinha: cozinhaId })) as LocalizacaoCozinha[];
  return r[0] ?? null;
}

/** I11: onde está o estafeta do meu pedido (só enquanto está a caminho) */
export async function posicaoEntrega(pedidoId: string): Promise<PosicaoEntrega> {
  return verificar(await supabase.rpc('posicao_entrega', { p_pedido: pedidoId })) as PosicaoEntrega;
}

/**
 * Gate B: pede ao serviço para actualizar a rota por estrada (Google) deste pedido. Só tem efeito
 * com o interruptor `rota_google` e a chave no servidor; caso contrário não faz nada. O resultado
 * fica em cache e é lido no próximo posicaoEntrega. Nunca estoura (fire-and-forget).
 */
export async function refrescarRota(pedidoId: string): Promise<void> {
  try {
    await supabase.functions.invoke('rota-estafeta', { body: { pedido: pedidoId } });
  } catch {
    // Sem rota do Google, fica a estimativa por distância — não é erro para o cliente
  }
}

/** Cozinhas que aceitam pedidos (I8); com multi_cozinha desligado, só a cozinha por defeito */
export async function cozinhasParaPedir(): Promise<CozinhaParaPedir[]> {
  return verificar(await supabase.rpc('cozinhas_para_pedir')) as CozinhaParaPedir[];
}

/** Balcões ordenados pela distância ao ponto de entrega do cliente (mais perto primeiro). */
export async function cozinhasPertoParaPedir(pontoId: string): Promise<CozinhaParaPedir[]> {
  return (verificar(await supabase.rpc('cozinhas_perto', { p_ponto: pontoId })) as CozinhaParaPedir[]) ?? [];
}

// ---------------------------------------------------------------- avaliações (C9, C10)
/** Médias da cozinha e dos pratos; o servidor só devolve com o mínimo de avaliações */
export async function mediasAvaliacoes(cozinhaId: string): Promise<MediasAvaliacoes | null> {
  return verificar(await supabase.rpc('medias_avaliacoes', { p_cozinha: cozinhaId })) as MediasAvaliacoes | null;
}

export async function avaliacoesPublicas(cozinhaId: string, pratoId?: string | null): Promise<AvaliacaoPublica[]> {
  return verificar(
    await supabase.rpc('lista_avaliacoes', { p_cozinha: cozinhaId, p_prato: pratoId ?? null, p_limite: 50 }),
  ) as AvaliacaoPublica[];
}

export async function avaliacaoPermitida(pedidoId: string): Promise<boolean> {
  return verificar(await supabase.rpc('avaliacao_permitida', { p_pedido: pedidoId })) as boolean;
}

export async function minhaAvaliacao(pedidoId: string): Promise<{ estrelas: number; comentario: string | null } | null> {
  const r = await supabase.from('avaliacoes').select('estrelas, comentario').eq('pedido_id', pedidoId).maybeSingle();
  return verificar(r) as { estrelas: number; comentario: string | null } | null;
}

export async function avaliarPedido(dados: {
  pedidoId: string;
  clienteId: string;
  estrelas: number;
  comentario: string | null;
  usarPseudonimo: boolean;
  pratos: { prato_id: string; estrelas: number }[];
}): Promise<string> {
  const r = await supabase
    .from('avaliacoes')
    .insert({
      pedido_id: dados.pedidoId,
      cliente_id: dados.clienteId,
      estrelas: dados.estrelas,
      comentario: dados.comentario,
      usar_pseudonimo: dados.usarPseudonimo,
      dispositivo_id: await dispositivoId(),
    })
    .select('id')
    .single();
  const { id } = verificar(r) as { id: string };
  if (dados.pratos.length > 0) {
    verificar(await supabase.from('avaliacoes_pratos').insert(dados.pratos.map((p) => ({ ...p, avaliacao_id: id }))));
  }
  return id;
}

/** Cria a linha da foto (pendente) e devolve o caminho onde o servidor quer o ficheiro */
export async function criarFoto(avaliacaoId: string): Promise<string> {
  const r = await supabase
    .from('fotos_avaliacao')
    .insert({ avaliacao_id: avaliacaoId, caminho: '-', dispositivo_id: await dispositivoId() })
    .select('caminho')
    .single();
  return (verificar(r) as { caminho: string }).caminho;
}

// ---------------------------------------------------------------- endereços (C11)
// Só os endereços do próprio cliente. O filtro por cliente_id é explícito porque um utilizador que
// também seja funcionário passaria na regra de leitura "sou funcionário" e veria os de outros clientes.
export async function lerEnderecos(clienteId: string | null | undefined): Promise<Endereco[]> {
  if (!clienteId) return [];
  const r = await supabase
    .from('enderecos_cliente')
    .select('id, nome, principal, ponto_entrega_id, pontos_entrega(id, tipo, referencia, zona_id, zonas(nome))')
    .eq('cliente_id', clienteId)
    .is('deletado_em', null)
    .order('principal', { ascending: false })
    .order('criado_em');
  return verificar(r) as unknown as Endereco[];
}

export async function lerZonas(): Promise<Zona[]> {
  const r = await supabase.from('zonas').select('id, nome, taxa, centro_lat, centro_lng').order('nome');
  return (verificar(r) as Zona[]).map((z) => ({
    ...z,
    centro_lat: z.centro_lat != null ? Number(z.centro_lat) : null,
    centro_lng: z.centro_lng != null ? Number(z.centro_lng) : null,
  }));
}

export type PontoProximo = { ponto_entrega_id: string; tipo: string; referencia: string | null; distancia_m: number };

export async function pontosProximos(lat: number, lng: number, tipo: 'residencial' | 'empresa') {
  return verificar(await supabase.rpc('pontos_entrega_proximos', { p_lat: lat, p_lng: lng, p_tipo: tipo })) as PontoProximo[];
}

export async function criarEndereco(dados: {
  clienteId: string;
  nome: string;
  principal: boolean;
  pontoExistente: string | null;
  novoPonto: { tipo: 'residencial' | 'empresa'; lat: number; lng: number; zonaId: string; referencia: string } | null;
}) {
  let pontoId = dados.pontoExistente;
  if (!pontoId && dados.novoPonto) {
    const r = await supabase
      .from('pontos_entrega')
      .insert({
        tipo: dados.novoPonto.tipo,
        lat: dados.novoPonto.lat,
        lng: dados.novoPonto.lng,
        zona_id: dados.novoPonto.zonaId,
        referencia: dados.novoPonto.referencia || null,
        dispositivo_id: await dispositivoId(),
      })
      .select('id')
      .single();
    pontoId = (verificar(r) as { id: string }).id;
  }
  // A mesma morada não fica guardada duas vezes (o servidor também o impede)
  const ja = await supabase
    .from('enderecos_cliente')
    .select('id')
    .eq('cliente_id', dados.clienteId)
    .eq('ponto_entrega_id', pontoId as string)
    .is('deletado_em', null)
    .limit(1);
  if (!ja.error && (ja.data ?? []).length > 0) throw new Error('endereco_repetido');
  const r = await supabase.from('enderecos_cliente').insert({
    cliente_id: dados.clienteId,
    ponto_entrega_id: pontoId,
    nome: dados.nome,
    principal: dados.principal,
    dispositivo_id: await dispositivoId(),
  });
  if (r.error?.code === '23505') throw new Error('endereco_repetido');
  verificar(r);
}

/** Apaga um endereço do cliente (apagar reversível: marca deletado_em; a lista esconde os apagados).
 *  Confirma que apagou mesmo: se a regra de segurança não deixar (não é do próprio), dá erro em vez
 *  de um falso sucesso. */
export async function apagarEndereco(id: string): Promise<void> {
  const linhas = verificar(
    await supabase.from('enderecos_cliente').update({ deletado_em: new Date().toISOString() }).eq('id', id).select('id'),
  ) as { id: string }[] | null;
  if (!linhas || linhas.length === 0) throw new Error('Não foi possível apagar este endereço.');
}

// ---------------------------------------------------------------- pedidos
export type ItemCarrinho = { cardapio_id: string; qtd: number; opcoes?: string[]; componentes_excluidos?: string[] };

export async function orcamento(
  itens: ItemCarrinho[],
  pontoEntregaId: string | null,
  grupoId?: string | null,
  cozinhaId?: string | null,
): Promise<Orcamento> {
  return verificar(
    await supabase.rpc('orcamento_pedido', {
      p_itens: itens,
      p_ponto_entrega: pontoEntregaId,
      p_grupo: grupoId ?? null,
      p_cozinha: cozinhaId ?? null,
    }),
  ) as Orcamento;
}

/**
 * O servidor recalcula itens, preços, taxa e desconto. O pedido é criado com um id gerado no telemóvel. Se a rede falhar depois de o servidor gravar e o
 * cliente tocar outra vez em "Confirmar", o mesmo id é recusado como repetido e não nasce um
 * segundo pedido: confirma-se que o pedido já existe e segue-se como se a primeira tentativa
 * tivesse respondido.
 */
export async function criarPedido(dados: {
  id: string;
  clienteId: string;
  pontoEntregaId: string | null;
  grupoId?: string | null;
  cozinhaId?: string | null;
  itens: ItemCarrinho[];
  observacoes: string;
  agendadoPara?: string | null;
  empresaId?: string | null;
}): Promise<string> {
  const r = await supabase.from('pedidos').insert({
    id: dados.id,
    cliente_id: dados.clienteId,
    ponto_entrega_id: dados.pontoEntregaId,
    grupo_id: dados.grupoId ?? null,
    cozinha_id: dados.cozinhaId ?? null,
    itens: dados.itens,
    observacoes: dados.observacoes.trim() || null,
    agendado_para: dados.agendadoPara ?? null,
    empresa_id: dados.empresaId ?? null,
    dispositivo_id: await dispositivoId(),
  });
  if (r.error && (r.error as { code?: string }).code === '23505') {
    const existente = await supabase.from('pedidos').select('id').eq('id', dados.id).maybeSingle();
    if (verificar(existente)) return dados.id;
  }
  verificar(r);
  return dados.id;
}

export async function minhaEmpresa(): Promise<MinhaEmpresa | null> {
  return (verificar(await supabase.rpc('minha_empresa')) as MinhaEmpresa | null) ?? null;
}

export async function usarCredito(pedidoId: string, valor: number): Promise<number> {
  return verificar(await supabase.rpc('usar_credito', { p_pedido: pedidoId, p_valor: valor })) as number;
}

export async function cancelarPedido(pedidoId: string): Promise<void> {
  verificar(await supabase.rpc('cancelar_pedido', { p_pedido: pedidoId, p_motivo: 'Cancelado pelo cliente na app' }));
}

const camposPedido =
  'id, criado_em, estado, itens, subtotal, taxa_entrega, desconto_indicacao, credito_indicacao_usado, pago_pacote, refeicoes_pacote, observacoes, motivo_cancelamento, hora_prometida, entregue_em, agendado_para, empresa_id, valor_empresa';

// Só os pedidos do próprio cliente. O filtro é explícito porque um utilizador que também seja
// funcionário passaria na regra "sou funcionário" e veria os pedidos de outros clientes.
export async function lerPedidos(clienteId: string | null | undefined): Promise<Pedido[]> {
  if (!clienteId) return [];
  const r = await supabase
    .from('pedidos')
    .select(camposPedido)
    .eq('cliente_id', clienteId)
    .order('criado_em', { ascending: false })
    .limit(50);
  return verificar(r) as Pedido[];
}

/** Atraso avisado num pedido (motivo e nova estimativa), ou null. Escopado ao próprio cliente. */
export async function atrasoDoPedido(pedidoId: string, clienteId: string | null | undefined): Promise<AtrasoPedido | null> {
  if (!clienteId) return null;
  return verificar(
    await supabase.from('alertas_pedido').select('minutos, motivo, mais_minutos, motivo_em, criado_em')
      .eq('pedido_id', pedidoId).eq('cliente_id', clienteId).eq('tipo', 'atraso').maybeSingle(),
  ) as AtrasoPedido | null;
}

/** Justificação do cancelamento de um pedido meu (null se não estiver cancelado) */
export async function justificacaoCancelamento(pedidoId: string): Promise<string | null> {
  return verificar(await supabase.rpc('justificacao_cancelamento', { p_pedido: pedidoId })) as string | null;
}

export async function lerPedido(id: string, clienteId: string | null | undefined): Promise<Pedido | null> {
  if (!clienteId) return null;
  return verificar(
    await supabase.from('pedidos').select(camposPedido).eq('id', id).eq('cliente_id', clienteId).maybeSingle(),
  ) as Pedido | null;
}

// ---------------------------------------------------------------- I12: pacotes pré-pagos
export async function lerPacotes(): Promise<Pacote[]> {
  const r = await supabase
    .from('pacotes')
    .select('id, nome, descricao, refeicoes, refeicoes_oferta, valor_refeicao, preco, validade_dias, pausa_max_dias, entrega_gratis')
    .eq('activo', true)
    .is('deletado_em', null)
    .order('ordem')
    .order('preco');
  return verificar(r) as Pacote[];
}

export async function meuPacote(): Promise<MeuPacote | null> {
  return (verificar(await supabase.rpc('meu_pacote')) as MeuPacote | null) ?? null;
}

export async function pacotesAMinhaVolta(): Promise<PacotesAMinhaVolta | null> {
  return (verificar(await supabase.rpc('pacotes_a_minha_volta')) as PacotesAMinhaVolta | null) ?? null;
}

export async function aderirPacote(pacoteId: string, metodo: MetodoPacote): Promise<string> {
  return verificar(await supabase.rpc('aderir_pacote', { p_pacote: pacoteId, p_metodo: metodo })) as string;
}

export async function cancelarAdesaoPacote(adesaoId: string): Promise<void> {
  verificar(await supabase.rpc('cancelar_adesao_pacote', { p_adesao: adesaoId }));
}

/** Gasta refeições do pacote no pedido; devolve o valor pago pelo pacote (repetir não gasta duas vezes) */
export async function usarPacote(pedidoId: string): Promise<number> {
  return verificar(await supabase.rpc('usar_pacote', { p_pedido: pedidoId })) as number;
}

/** Pausa: prolonga a validade; devolve o novo fim */
export async function pausarPacote(dias: number): Promise<string> {
  return verificar(await supabase.rpc('pausar_pacote', { p_dias: dias })) as string;
}

// ---------------------------------------------------------------- Convida e Ganha (C1, C4)
export async function lerSaldo(clienteId: string): Promise<Saldo | null> {
  const r = await supabase.from('saldo_indicacao').select('*').eq('indicador_id', clienteId).maybeSingle();
  return verificar(r) as Saldo | null;
}

export async function meusAmigos(): Promise<Amigo[]> {
  return verificar(await supabase.rpc('meus_amigos')) as Amigo[];
}

export async function pessoasComoTu(): Promise<PessoaComoTu[]> {
  return verificar(await supabase.rpc('pessoas_como_tu')) as PessoaComoTu[];
}

// ---------------------------------------------------------------- destaques (C3, C5)
export async function destaquesMes(): Promise<Destaque[]> {
  return verificar(await supabase.rpc('destaques_mes')) as Destaque[];
}

export async function minhaPosicao(): Promise<MinhaPosicao | null> {
  const linhas = verificar(await supabase.rpc('minha_posicao')) as MinhaPosicao[];
  return linhas[0] ?? null;
}

export async function totalPagoMes(): Promise<number> {
  return verificar(await supabase.rpc('total_pago_mes')) as number;
}

export async function lerPerfilDestaques(clienteId: string): Promise<PerfilDestaques | null> {
  const r = await supabase
    .from('perfil_destaques')
    .select('pseudonimo, mostrar_nome_real, ocultar_ganhos, sair_da_lista')
    .eq('cliente_id', clienteId)
    .maybeSingle();
  return verificar(r) as PerfilDestaques | null;
}

export async function alterarPerfilDestaques(
  clienteId: string,
  valores: Partial<Pick<PerfilDestaques, 'mostrar_nome_real' | 'ocultar_ganhos'>>,
): Promise<void> {
  verificar(
    await supabase
      .from('perfil_destaques')
      .update({ ...valores, atualizado_em: new Date().toISOString() })
      .eq('cliente_id', clienteId),
  );
}

// ---------------------------------------------------------------- notificações (C14)
export async function lerPreferenciasNotificacao(clienteId: string): Promise<PreferenciasNotificacao | null> {
  const r = await supabase
    .from('preferencias_notificacao')
    .select('lembrete_almoco, destaques')
    .eq('cliente_id', clienteId)
    .maybeSingle();
  return verificar(r) as PreferenciasNotificacao | null;
}

export async function alterarPreferenciasNotificacao(
  clienteId: string,
  valores: Partial<PreferenciasNotificacao>,
): Promise<void> {
  verificar(
    await supabase
      .from('preferencias_notificacao')
      .update({ ...valores, atualizado_em: new Date().toISOString() })
      .eq('cliente_id', clienteId),
  );
}

export async function contadorZona(zonaId: string): Promise<number | null> {
  return verificar(await supabase.rpc('contador_zona', { p_zona: zonaId })) as number | null;
}

/** "O mais pedido na tua zona" (últimos 30 dias; só contagens, a partir do limiar da prova social) */
export type MaisPedidoZona = { cardapio_id: string; nome: string; cozinha_id: string; cozinha: string; pedidos: number };
export async function maisPedidosNaZona(ponto: string): Promise<MaisPedidoZona[]> {
  return (verificar(await supabase.rpc('mais_pedidos_na_zona', { p_ponto: ponto })) as MaisPedidoZona[]) ?? [];
}

/**
 * Teste das fotografias do Início (grupo de controlo): sem segundos regista uma visita e devolve o grupo
 * ('A' = fotografia grande, 'B' = média); com segundos guarda o tempo até ao primeiro «Adicionar».
 * null = sem teste (interruptor desligado ou sem conta).
 */
export async function visitaExperiencia(experiencia: 'fotos_inicio', segundosAteAdicionar?: number): Promise<'A' | 'B' | null> {
  const args = segundosAteAdicionar == null ? { p_experiencia: experiencia } : { p_experiencia: experiencia, p_segundos_ate_adicionar: Math.round(segundosAteAdicionar) };
  return (verificar(await supabase.rpc('visita_experiencia', args)) as 'A' | 'B' | null) ?? null;
}

/** Pagar a parte antes: o que se pode fazer neste pedido e o estado do último envio */
export async function meuPagamentoAntes(pedidoId: string): Promise<PagamentoAntes> {
  return verificar(await supabase.rpc('meu_pagamento_antes', { p_pedido: pedidoId })) as PagamentoAntes;
}

/** «Já paguei»: fica a confirmar pelas Finanças */
export async function pagarAntes(pedidoId: string, metodo: MetodoAntes, referencia: string): Promise<void> {
  verificar(await supabase.rpc('pagar_antes', { p_pedido: pedidoId, p_metodo: metodo, p_referencia: referencia }));
}

export async function registarPartilha(): Promise<void> {
  verificar(await supabase.rpc('registar_partilha'));
}

export async function pedirLevantamento(valor: number, metodo: string, numero: string): Promise<void> {
  verificar(await supabase.rpc('pedir_levantamento', { p_valor: valor, p_metodo: metodo, p_numero: numero }));
}

export async function lerLevantamentos(clienteId: string): Promise<Levantamento[]> {
  const r = await supabase
    .from('pagamentos_indicacao')
    .select('id, criado_em, valor, metodo, numero_destino, lote_id, parcela, total_parcelas, estado, referencia, motivo_rejeicao')
    .eq('indicador_id', clienteId)
    .eq('tipo', 'levantamento')
    .order('criado_em', { ascending: false })
    .limit(30);
  return verificar(r) as Levantamento[];
}

// ---------------------------------------------------------------- push
export async function registarTokenPush(token: string, plataforma: string): Promise<void> {
  verificar(await supabase.rpc('registar_token_push', { p_token: token, p_plataforma: plataforma }));
}

export async function removerTokenPush(token: string): Promise<void> {
  verificar(await supabase.rpc('remover_token_push', { p_token: token }));
}

// ---------------------------------------------------------------- pedidos de grupo (C12, C13)
export async function criarGrupo(dados: {
  pontoEntregaId: string;
  horaEntrega: string;
  prazoAdesao: string;
  modo: ModoGrupo;
  tipo: TipoGrupo;
  cozinhaId?: string | null;
}): Promise<string> {
  const r = await supabase
    .from('pedidos_grupo')
    .insert({
      ponto_entrega_id: dados.pontoEntregaId,
      ...(dados.cozinhaId ? { cozinha_id: dados.cozinhaId } : {}),
      hora_entrega: dados.horaEntrega,
      prazo_adesao: dados.prazoAdesao,
      modo_pagamento: dados.modo,
      tipo: dados.tipo,
      dispositivo_id: await dispositivoId(),
    })
    .select('codigo_convite')
    .single();
  return (verificar(r) as { codigo_convite: string }).codigo_convite;
}

export async function grupoDetalhe(codigo: string): Promise<GrupoDetalhe | null> {
  return verificar(await supabase.rpc('grupo_detalhe', { p_codigo: codigo })) as GrupoDetalhe | null;
}

export async function meusGrupos(): Promise<MeuGrupo[]> {
  return verificar(await supabase.rpc('meus_grupos')) as MeuGrupo[];
}

export async function fecharGrupo(grupoId: string): Promise<void> {
  verificar(await supabase.rpc('fechar_grupo', { p_grupo: grupoId }));
}

export async function cancelarGrupo(grupoId: string, motivo: string | null): Promise<void> {
  verificar(await supabase.rpc('cancelar_grupo', { p_grupo: grupoId, p_motivo: motivo }));
}

/** Reclamações do cliente sobre um pedido (o texto, o estado e a resposta da cozinha) */
export async function minhasReclamacoes(pedidoId: string): Promise<MinhaReclamacao[]> {
  return verificar(await supabase.rpc('minhas_reclamacoes', { p_pedido: pedidoId })) as MinhaReclamacao[];
}

export async function fazerReclamacao(pedidoId: string, texto: string): Promise<string> {
  return verificar(await supabase.rpc('fazer_reclamacao', { p_pedido: pedidoId, p_texto: texto })) as string;
}

// ---------------------------------------------------------------- atendimento ao cliente
export async function minhaConversaAtendimento(): Promise<ConversaAtendimento | null> {
  return (verificar(await supabase.rpc('minha_conversa_atendimento')) as ConversaAtendimento | null) ?? null;
}

/** Envia a mensagem e chama logo o assistente (o pg_cron apanha-a se esta chamada falhar) */
export async function enviarMensagemAtendimento(texto: string): Promise<void> {
  const r = verificar(await supabase.rpc('enviar_mensagem_atendimento', { p_texto: texto })) as { conversa_id: string; estado: string };
  if (r.estado === 'agente') supabase.functions.invoke('atendimento', { body: { conversa_id: r.conversa_id } }).catch(() => undefined);
}

export async function pedirPessoaAtendimento(): Promise<void> {
  verificar(await supabase.rpc('pedir_pessoa_atendimento'));
}

// ---------------------------------------------------------------- contactos
export async function lerContactos(): Promise<Contactos> {
  return verificar(await supabase.rpc('contactos')) as Contactos;
}

// ---------------------------------------------------------------- ingredientes que se podem tirar (pratos montáveis)
export async function lerComponentes(cardapioIds: string[]): Promise<ComponentePrato[]> {
  if (cardapioIds.length === 0) return [];
  return verificar(await supabase.rpc('componentes_dos_pratos', { p_cardapio: cardapioIds })) as ComponentePrato[];
}

/** Doses que restam hoje dos pratos com limite (a cozinha lançou quantas tem) */
export async function lerDoses(cozinhaId: string): Promise<{ cardapio_id: string; restantes: number }[]> {
  return verificar(await supabase.rpc('doses_cardapio', { p_cozinha: cozinhaId })) as { cardapio_id: string; restantes: number }[];
}

// Receitas (Cozinha de casa) — só aparecem com o interruptor 'receitas' ligado (garantido no servidor)
export async function lerReceitas(): Promise<ReceitaResumo[]> {
  return (verificar(await supabase.rpc('receitas_publicas')) as ReceitaResumo[]) ?? [];
}

export async function lerReceita(id: string): Promise<Receita | null> {
  const r = verificar(await supabase.rpc('receita_publica', { p_id: id })) as Receita[];
  return r[0] ?? null;
}

// Cartão de selos: progresso do cliente; devolve null com o interruptor 'selos' desligado
export async function meusSelos(): Promise<MeusSelos | null> {
  return (verificar(await supabase.rpc('meus_selos')) as MeusSelos | null) ?? null;
}

// Métricas das receitas (abrir -> pedir): fire-and-forget, nunca atrapalham o cliente
export async function receitaAbriu(id: string): Promise<void> {
  await supabase.rpc('receita_abriu', { p_id: id }).then(() => undefined, () => undefined);
}
/** Onde pedir o prato da receita, a partir do balcão escolhido e da morada principal */
export async function receitaOndePedir(id: string, cozinhaId: string | null, pontoId: string | null): Promise<OndePedirReceita> {
  return verificar(
    await supabase.rpc('receita_onde_pedir', { p_receita: id, p_cozinha: cozinhaId, p_ponto: pontoId }),
  ) as OndePedirReceita;
}

/** «Quero que façam»: devolve quantos já pediram */
export async function receitaQuero(id: string): Promise<number> {
  return (verificar(await supabase.rpc('receita_quero', { p_receita: id })) as number) ?? 0;
}

export async function receitaTocouPedir(id: string): Promise<void> {
  await supabase.rpc('receita_tocou_pedir', { p_id: id }).then(() => undefined, () => undefined);
}
