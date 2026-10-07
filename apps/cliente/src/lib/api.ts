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
  PessoaComoTu,
  PosicaoEntrega,
  Saldo,
  Zona,
} from './tipos';

function verificar<T>(resultado: { data: T | null; error: { message: string } | null }): T {
  if (resultado.error) throw resultado.error;
  return resultado.data as T;
}

// ---------------------------------------------------------------- configuração
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
/** Apaga a conta do cliente da sessão (dados pessoais e utilizador da Auth); pedidos e vendas ficam anónimos */
export async function apagarConta(): Promise<void> {
  verificar(await supabase.rpc('apagar_conta'));
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
    .select('id, nome, descricao, categoria, preco, foto_url, do_dia, cozinha_id, prato_base_id')
    .eq('disponivel', true)
    .eq('visivel_online', true);
  if (cozinhaId) q = q.eq('cozinha_id', cozinhaId);
  const r = await q
    .order('do_dia', { ascending: false })
    .order('ordem')
    .order('nome');
  return verificar(r) as ItemCardapio[];
}

export type Cozinha = { id: string; nome: string; foto_url: string | null; historia: string | null };

/** Só devolve cozinhas com consentimento público (RLS); com cozinhaId, essa cozinha */
export async function lerCozinhaPublica(cozinhaId?: string | null): Promise<Cozinha | null> {
  let q = supabase.from('cozinhas').select('id, nome, foto_url, historia').eq('estado', 'activa');
  if (cozinhaId) q = q.eq('id', cozinhaId);
  const r = await q.limit(1);
  return ((verificar(r) as Cozinha[])[0] ?? null) as Cozinha | null;
}

/** Um prato do cardápio (ecrã de montar o prato) */
export async function lerItemCardapio(id: string): Promise<ItemCardapio | null> {
  const r = await supabase
    .from('cardapio')
    .select('id, nome, descricao, categoria, preco, foto_url, do_dia, cozinha_id, prato_base_id')
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
    .select('id, cardapio_id, nome, minimo, maximo, ordem, opcoes(id, nome, preco_extra, ordem, disponivel, deletado_em)')
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
      .map(({ id, nome, preco_extra, ordem }) => ({ id, nome, preco_extra, ordem })),
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
export async function lerEnderecos(): Promise<Endereco[]> {
  const r = await supabase
    .from('enderecos_cliente')
    .select('id, nome, principal, ponto_entrega_id, pontos_entrega(id, tipo, referencia, zona_id, zonas(nome))')
    .is('deletado_em', null)
    .order('principal', { ascending: false })
    .order('criado_em');
  return verificar(r) as unknown as Endereco[];
}

export async function lerZonas(): Promise<Zona[]> {
  return verificar(await supabase.from('zonas').select('id, nome, taxa').order('nome')) as Zona[];
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
  const r = await supabase.from('enderecos_cliente').insert({
    cliente_id: dados.clienteId,
    ponto_entrega_id: pontoId,
    nome: dados.nome,
    principal: dados.principal,
    dispositivo_id: await dispositivoId(),
  });
  verificar(r);
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

export async function lerPedidos(): Promise<Pedido[]> {
  const r = await supabase.from('pedidos').select(camposPedido).order('criado_em', { ascending: false }).limit(50);
  return verificar(r) as Pedido[];
}

/** Atraso avisado num pedido (motivo e nova estimativa), ou null */
export async function atrasoDoPedido(pedidoId: string): Promise<AtrasoPedido | null> {
  return verificar(
    await supabase.from('alertas_pedido').select('minutos, motivo, mais_minutos, motivo_em, criado_em')
      .eq('pedido_id', pedidoId).eq('tipo', 'atraso').maybeSingle(),
  ) as AtrasoPedido | null;
}

/** Justificação do cancelamento de um pedido meu (null se não estiver cancelado) */
export async function justificacaoCancelamento(pedidoId: string): Promise<string | null> {
  return verificar(await supabase.rpc('justificacao_cancelamento', { p_pedido: pedidoId })) as string | null;
}

export async function lerPedido(id: string): Promise<Pedido | null> {
  return verificar(await supabase.from('pedidos').select(camposPedido).eq('id', id).maybeSingle()) as Pedido | null;
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
  modo: 'individual' | 'empresa';
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
