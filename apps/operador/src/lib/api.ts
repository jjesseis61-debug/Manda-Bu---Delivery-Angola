// Chamadas ao servidor da app do operador. Cada função do servidor verifica a
// permissão do organograma; a app só esconde o que o funcionário não pode usar.
import { supabase } from './supabase';
import type {
  Aviso,
  PublicoAviso,
  AdesaoOperador,
  AlertaPedido,
  CasoConvida,
  CasoInvestigacao,
  PerguntaAnalista,
  PropostaTurno,
  PlanoCompras,
  DosesPrato,
  ConversaResumo,
  ConversaDetalhe,
  Estimulo,
  Reclamacao,
  RelatorioReclamacoes,
  Conciliacao,
  Extrato,
  FechoDiario,
  FechoMensal,
  HistoricoPedido,
  MovimentoExtrato,
  Caixa,
  CaixaGestao,
  ComentarioModeracao,
  Cozinha,
  Embaixador,
  PacoteCatalogo,
  ZonaEntrega,
  ProdutoStock,
  FotoPendente,
  Funcionario,
  GanhoVerificacao,
  GrupoOpcoesPrato,
  GrupoOperador,
  LevantamentoOperador,
  LinhaComparativo,
  LocalizacaoCozinha,
  MetricaTurno,
  OpcaoPrato,
  Painel,
  PalavraFiltrada,
  PedidoAgendado,
  PedidoOperador,
  Periodo,
  PermissaoCatalogo,
  PessoalItem,
  Empresa,
  EmpresaMembro,
  Feira,
  FeiraResumo,
  PosicaoEstafeta,
  RelatorioEmpresa,
  SugestaoDespacho,
  PratoCardapio,
  Reconhecimento,
  Relatorio,
  TipoReconhecimento,
  FechoCaixa,
  ResumoCaixa,
} from './tipos';

function verificar<T>(r: { data: T | null; error: { message: string } | null }): T {
  if (r.error) throw r.error;
  return r.data as T;
}

// ---------------------------------------------------------------- entrada
/** Liga a conta (telefone confirmado por SMS) ao funcionário e devolve o perfil, ou null sem acesso */
export async function entrarComoFuncionario(): Promise<Funcionario | null> {
  verificar(await supabase.rpc('ligar_funcionario'));
  return (verificar(await supabase.rpc('meu_funcionario')) as Funcionario | null) ?? null;
}

// ---------------------------------------------------------------- O1
export async function painel(inicio: string, fim: string): Promise<Painel> {
  return verificar(await supabase.rpc('painel_programa', { p_inicio: inicio, p_fim: fim })) as Painel;
}

// ---------------------------------------------------------------- O2
export async function ganhosEmVerificacao(): Promise<GanhoVerificacao[]> {
  return verificar(await supabase.rpc('ganhos_em_verificacao')) as GanhoVerificacao[];
}

export async function reverGanho(ganhoId: string, decisao: 'confirmar' | 'anular', motivo?: string) {
  verificar(await supabase.rpc('rever_ganho', { p_ganho: ganhoId, p_decisao: decisao, p_motivo: motivo ?? null }));
}

export async function confirmarTodos(indicadorId: string): Promise<number> {
  return verificar(await supabase.rpc('confirmar_ganhos_indicador', { p_indicador: indicadorId })) as number;
}

// ---------------------------------------------------------------- O3
export async function levantamentos(estado: string | null): Promise<LevantamentoOperador[]> {
  return verificar(await supabase.rpc('levantamentos_operador', { p_estado: estado })) as LevantamentoOperador[];
}

export async function aprovarLevantamento(id: string) {
  verificar(await supabase.rpc('aprovar_levantamento', { p_pagamento: id }));
}

export async function rejeitarLevantamento(id: string, motivo: string) {
  verificar(await supabase.rpc('rejeitar_levantamento', { p_pagamento: id, p_motivo: motivo }));
}

export async function marcarPago(id: string, referencia: string) {
  verificar(await supabase.rpc('marcar_pago', { p_pagamento: id, p_referencia: referencia }));
}

// ---------------------------------------------------------------- O4
export async function embaixadores(): Promise<Embaixador[]> {
  return verificar(await supabase.rpc('embaixadores')) as Embaixador[];
}

export async function definirNivel(clienteId: string, nivel: 'normal' | 'embaixador') {
  verificar(await supabase.rpc('definir_nivel_indicador', { p_cliente: clienteId, p_nivel: nivel }));
}

// ---------------------------------------------------------------- O5
export async function lerParametros(): Promise<Record<string, unknown>> {
  return verificar(await supabase.from('parametros').select('*').eq('unico', true).single()) as Record<string, unknown>;
}

export async function lerFuncionalidades(): Promise<{ chave: string; activa: boolean; descricao?: string | null }[]> {
  return verificar(await supabase.from('funcionalidades').select('*').order('chave')) as {
    chave: string;
    activa: boolean;
    descricao?: string | null;
  }[];
}

export async function alterarParametros(valores: Record<string, number | string | null>) {
  verificar(await supabase.rpc('alterar_parametros', { p_valores: valores }));
}

export async function alterarFuncionalidade(chave: string, activa: boolean) {
  verificar(await supabase.rpc('alterar_funcionalidade', { p_chave: chave, p_activa: activa }));
}

// ---------------------------------------------------------------- O6
export async function lerCozinhas(): Promise<Cozinha[]> {
  return verificar(
    await supabase
      .from('cozinhas')
      .select('id, nome, responsavel, foto_url, historia, estado, consentimento_publico, telefone_publico, whatsapp_publico, horario_publico')
      .is('deletado_em', null)
      .order('criado_em'),
  ) as Cozinha[];
}

export async function guardarCozinha(c: Omit<Cozinha, 'id'> & { id?: string }) {
  const { id, ...dados } = c;
  if (id) verificar(await supabase.from('cozinhas').update({ ...dados, atualizado_em: new Date().toISOString() }).eq('id', id));
  else verificar(await supabase.from('cozinhas').insert(dados));
}

export async function lerCardapio(cozinhaId: string): Promise<PratoCardapio[]> {
  return verificar(
    await supabase
      .from('cardapio')
      .select('id, cozinha_id, nome, descricao, categoria, preco, disponivel, do_dia, ordem, foto_url, doses_dia, visivel_online')
      .eq('cozinha_id', cozinhaId)
      .order('ordem')
      .order('nome'),
  ) as PratoCardapio[];
}

export async function guardarPrato(p: Omit<PratoCardapio, 'id'> & { id?: string }) {
  const { id, ...dados } = p;
  if (id) verificar(await supabase.from('cardapio').update({ ...dados, atualizado_em: new Date().toISOString() }).eq('id', id));
  else verificar(await supabase.from('cardapio').insert(dados));
}

/** Doses que restam hoje dos pratos com limite (as de dias anteriores já não contam) */
export async function lerDosesCardapio(cozinhaId: string): Promise<DosesPrato[]> {
  return verificar(await supabase.rpc('doses_cardapio', { p_cozinha: cozinhaId })) as DosesPrato[];
}

// ---------------------------------------------------------------- I9: opções dos pratos
export async function lerGruposOpcoes(cardapioId: string): Promise<GrupoOpcoesPrato[]> {
  const r = await supabase
    .from('opcoes_grupos')
    .select('id, cardapio_id, nome, minimo, maximo, ordem, opcoes(id, grupo_id, nome, preco_extra, disponivel, ordem, componentes, deletado_em)')
    .eq('cardapio_id', cardapioId)
    .is('deletado_em', null)
    .order('ordem')
    .order('nome');
  type Linha = Omit<GrupoOpcoesPrato, 'opcoes'> & { opcoes: (OpcaoPrato & { deletado_em: string | null })[] };
  return (verificar(r) as Linha[]).map((g) => ({
    ...g,
    opcoes: g.opcoes
      .filter((o) => !o.deletado_em)
      .sort((a, b) => a.ordem - b.ordem || a.nome.localeCompare(b.nome))
      .map(({ deletado_em: _d, ...o }) => o),
  }));
}

export async function guardarGrupoOpcoes(g: Omit<GrupoOpcoesPrato, 'id' | 'opcoes'> & { id?: string }) {
  const { id, ...dados } = g;
  if (id) verificar(await supabase.from('opcoes_grupos').update({ ...dados, atualizado_em: new Date().toISOString() }).eq('id', id));
  else verificar(await supabase.from('opcoes_grupos').insert(dados));
}

export async function guardarOpcao(o: Omit<OpcaoPrato, 'id'> & { id?: string }) {
  const { id, ...dados } = o;
  if (id) verificar(await supabase.from('opcoes').update({ ...dados, atualizado_em: new Date().toISOString() }).eq('id', id));
  else verificar(await supabase.from('opcoes').insert(dados));
}

/** Produtos do stock, para escolher os ingredientes das opções */
export async function lerProdutos(): Promise<ProdutoStock[]> {
  return verificar(
    await supabase.from('produtos').select('id, nome, categoria_medida, tipo_estoque').is('deletado_em', null).order('nome'),
  ) as ProdutoStock[];
}

/** Apagar = marcar deletado_em (os pedidos antigos continuam a mostrar o nome da opção) */
export async function apagarGrupoOpcoes(id: string) {
  const agora = new Date().toISOString();
  verificar(await supabase.from('opcoes_grupos').update({ deletado_em: agora, atualizado_em: agora }).eq('id', id));
}

export async function apagarOpcao(id: string) {
  const agora = new Date().toISOString();
  verificar(await supabase.from('opcoes').update({ deletado_em: agora, atualizado_em: agora }).eq('id', id));
}

// ---------------------------------------------------------------- I10: localização da cozinha
export async function lerLocalizacao(cozinhaId: string): Promise<LocalizacaoCozinha | null> {
  return verificar(
    await supabase
      .from('cozinhas_localizacao')
      .select('id, cozinha_id, morada, horario, lat, lng, publica')
      .eq('cozinha_id', cozinhaId)
      .maybeSingle(),
  ) as LocalizacaoCozinha | null;
}

export async function guardarLocalizacao(l: LocalizacaoCozinha) {
  const { id, ...dados } = l;
  if (id) verificar(await supabase.from('cozinhas_localizacao').update({ ...dados, atualizado_em: new Date().toISOString() }).eq('id', id));
  else verificar(await supabase.from('cozinhas_localizacao').insert(dados));
}

// ---------------------------------------------------------------- I11: posição do estafeta
/** Envia a posição; devolve quantos pedidos o estafeta tem a caminho (0 = parar de enviar) */
export async function registarPosicaoEntrega(lat: number, lng: number, precisao: number | null): Promise<number> {
  return verificar(
    await supabase.rpc('registar_posicao_entrega', { p_lat: lat, p_lng: lng, p_precisao: precisao }),
  ) as number;
}

// ---------------------------------------------------------------- O9
export async function relatorioCozinha(cozinhaId: string, inicio: string, fim: string): Promise<Relatorio> {
  return verificar(
    await supabase.rpc('relatorio_cozinha', { p_cozinha: cozinhaId, p_inicio: inicio, p_fim: fim }),
  ) as Relatorio;
}

export async function relatorioComparativo(inicio: string, fim: string): Promise<LinhaComparativo[]> {
  return verificar(await supabase.rpc('relatorio_comparativo', { p_inicio: inicio, p_fim: fim })) as LinhaComparativo[];
}

// ---------------------------------------------------------------- E1
export async function pedidosOperador(): Promise<PedidoOperador[]> {
  return verificar(await supabase.rpc('pedidos_operador')) as PedidoOperador[];
}

export async function caixasAbertas(): Promise<Caixa[]> {
  return verificar(
    await supabase.from('caixa').select('id, posto, data, cozinha_id').is('fechamento', null).order('data', { ascending: false }),
  ) as Caixa[];
}

// ---------------------------------------------------------------- Caixa
/** Caixas abertas e as últimas fechadas (as mais recentes primeiro) */
export async function caixasRecentes(): Promise<CaixaGestao[]> {
  return verificar(
    await supabase
      .from('caixa')
      .select('id, posto, data, cozinha_id, troco_inicial, funcionario_nome, fechamento')
      .order('criado_em', { ascending: false })
      .limit(20),
  ) as CaixaGestao[];
}

export async function resumoCaixa(caixaId: string): Promise<ResumoCaixa> {
  return verificar(await supabase.rpc('resumo_caixa', { p_caixa: caixaId })) as ResumoCaixa;
}

export async function abrirCaixa(cozinhaId: string, posto: string, troco: number): Promise<string> {
  return verificar(await supabase.rpc('abrir_caixa', { p_cozinha: cozinhaId, p_posto: posto, p_troco: troco })) as string;
}

export async function registarSangria(caixaId: string, valor: number, motivo: string) {
  verificar(await supabase.rpc('registar_sangria', { p_caixa: caixaId, p_valor: valor, p_motivo: motivo }));
}

export async function fecharCaixa(caixaId: string, contado: number, observacao: string | null): Promise<FechoCaixa> {
  return verificar(
    await supabase.rpc('fechar_caixa', { p_caixa: caixaId, p_contado: contado, p_observacao: observacao }),
  ) as FechoCaixa;
}

// ---------------------------------------------------------------- alertas dos pedidos
export async function alertasAbertos(): Promise<AlertaPedido[]> {
  return verificar(await supabase.rpc('alertas_abertos')) as AlertaPedido[];
}

/** Diz ao cliente porque é que o pedido vai atrasar (e, se quiser, quantos minutos mais) */
export async function informarAtraso(pedidoId: string, motivo: string, maisMinutos: number | null) {
  verificar(await supabase.rpc('informar_atraso', { p_pedido: pedidoId, p_motivo: motivo, p_mais_minutos: maisMinutos }));
}

// ---------------------------------------------------------------- conferência financeira
export async function lerExtratos(): Promise<Extrato[]> {
  return verificar(
    await supabase.from('extratos').select('id, conta, periodo_inicio, periodo_fim, caminho, tipo_ficheiro, estado, ia_nota, criado_em')
      .order('criado_em', { ascending: false }).limit(40),
  ) as Extrato[];
}

export async function lerMovimentos(extratoId: string): Promise<MovimentoExtrato[]> {
  return verificar(
    await supabase.from('extrato_movimentos')
      .select('id, extrato_id, data, valor, referencia, descricao, origem, comprovativo_id, ligacao')
      .eq('extrato_id', extratoId).order('data').order('valor'),
  ) as MovimentoExtrato[];
}

export async function criarExtrato(conta: string, inicio: string, fim: string): Promise<string> {
  return verificar(await supabase.rpc('criar_extrato', { p_conta: conta, p_inicio: inicio, p_fim: fim })) as string;
}

/** Ficheiro já enviado (caminho) ou null para escrever as entradas à mão */
export async function confirmarExtrato(extratoId: string, caminho: string | null) {
  verificar(await supabase.rpc('confirmar_extrato', { p_extrato: extratoId, p_caminho: caminho }));
}

export async function pedirNovaLeitura(tipo: 'extrato' | 'comprovativo', id: string) {
  verificar(await supabase.rpc('pedir_nova_leitura', { p_tipo: tipo, p_id: id }));
}

export async function registarMovimento(extratoId: string, data: string, valor: number, referencia: string | null, descricao: string | null) {
  return verificar(
    await supabase.rpc('registar_movimento_extrato', {
      p_extrato: extratoId, p_data: data, p_valor: valor, p_referencia: referencia, p_descricao: descricao,
    }),
  ) as string;
}

export async function apagarMovimento(movimentoId: string, motivo: string) {
  verificar(await supabase.rpc('apagar_movimento_extrato', { p_movimento: movimentoId, p_motivo: motivo }));
}

/** Liga (ou desliga, com null) uma entrada do extrato a um comprovativo */
export async function ligarMovimento(movimentoId: string, comprovativoId: string | null) {
  verificar(await supabase.rpc('ligar_movimento', { p_movimento: movimentoId, p_comprovativo: comprovativoId }));
}

export async function relatorioConciliacao(inicio: string, fim: string): Promise<Conciliacao> {
  return verificar(await supabase.rpc('relatorio_conciliacao', { p_inicio: inicio, p_fim: fim })) as Conciliacao;
}

export async function fechoDiario(dia: string, cozinhaId: string | null = null): Promise<FechoDiario> {
  return verificar(await supabase.rpc('fecho_diario', { p_dia: dia, p_cozinha: cozinhaId })) as FechoDiario;
}

export async function fechoMensal(ano: number, mes: number): Promise<FechoMensal> {
  return verificar(await supabase.rpc('fecho_mensal', { p_ano: ano, p_mes: mes })) as FechoMensal;
}

export async function historicoPedido(pedidoId: string): Promise<HistoricoPedido> {
  return verificar(await supabase.rpc('historico_pedido', { p_pedido: pedidoId })) as HistoricoPedido;
}

/** Confere (ou rejeita, com nota) um pagamento electrónico da caixa */
export async function conferirComprovativo(id: string, conferido: boolean, nota: string | null = null) {
  verificar(await supabase.rpc('conferir_comprovativo', { p_comprovativo: id, p_conferido: conferido, p_nota: nota }));
}

export async function mudarEstado(
  pedidoId: string,
  estado: string,
  extra: {
    motivo?: string;
    caixa?: string;
    /** Pagamentos electrónicos levam a referência e o caminho da foto do comprovativo */
    parcelas?: { metodo: string; valor: number; referencia?: string; comprovativo?: string }[];
  } = {},
) {
  verificar(
    await supabase.rpc('mudar_estado_pedido', {
      p_pedido: pedidoId,
      p_estado: estado,
      p_motivo: extra.motivo ?? null,
      p_caixa: extra.caixa ?? null,
      p_parcelas: extra.parcelas ?? null,
    }),
  );
}

export async function marcarPagadorDistinto(pedidoId: string, valor: boolean) {
  verificar(await supabase.rpc('marcar_pagador_distinto', { p_pedido: pedidoId, p_valor: valor }));
}

// ---------------------------------------------------------------- push da equipa (N12)
export async function registarTokenPush(token: string, plataforma: string) {
  verificar(await supabase.rpc('registar_token_push_funcionario', { p_token: token, p_plataforma: plataforma }));
}

export async function removerTokenPush(token: string) {
  verificar(await supabase.rpc('remover_token_push', { p_token: token }));
}

// ---------------------------------------------------------------- O7
export async function comentariosModeracao(dias = 14): Promise<ComentarioModeracao[]> {
  return verificar(await supabase.rpc('avaliacoes_moderacao', { p_dias: dias })) as ComentarioModeracao[];
}

export async function ocultarAvaliacao(id: string, oculta: boolean) {
  verificar(await supabase.rpc('ocultar_avaliacao', { p_avaliacao: id, p_oculta: oculta }));
}

export async function fotosPendentes(): Promise<FotoPendente[]> {
  return verificar(await supabase.rpc('fotos_pendentes')) as FotoPendente[];
}

export async function moderarFoto(fotoId: string, decisao: 'aprovada' | 'rejeitada') {
  verificar(await supabase.rpc('moderar_foto', { p_foto: fotoId, p_decisao: decisao }));
}

/** Endereços temporários (15 min) das fotos do bucket privado; o storage só os dá a moderadores */
export async function enderecosFotos(caminhos: string[]): Promise<Record<string, string>> {
  if (caminhos.length === 0) return {};
  const { data, error } = await supabase.storage.from('fotos-avaliacoes').createSignedUrls(caminhos, 900);
  if (error) throw error;
  const r: Record<string, string> = {};
  for (const d of data ?? []) if (d.path && d.signedUrl) r[d.path] = d.signedUrl;
  return r;
}

export async function lerPalavras(): Promise<PalavraFiltrada[]> {
  return verificar(
    await supabase.from('palavras_filtradas').select('id, palavra').is('deletado_em', null).order('palavra'),
  ) as PalavraFiltrada[];
}

export async function adicionarPalavra(palavra: string) {
  verificar(await supabase.from('palavras_filtradas').insert({ palavra: palavra.trim().toLowerCase() }));
}

export async function removerPalavra(id: string) {
  verificar(
    await supabase
      .from('palavras_filtradas')
      .update({ deletado_em: new Date().toISOString(), atualizado_em: new Date().toISOString() })
      .eq('id', id),
  );
}

// ---------------------------------------------------------------- O8
export async function metricasTurno(cozinhaId: string, semana: string): Promise<MetricaTurno[]> {
  return verificar(await supabase.rpc('metricas_turno', { p_cozinha: cozinhaId, p_semana: semana })) as MetricaTurno[];
}

export async function lerReconhecimentos(cozinhaId: string): Promise<Reconhecimento[]> {
  return verificar(
    await supabase
      .from('reconhecimentos_turno')
      .select('id, criado_em, cozinha_id, semana, periodo, tipo, nota')
      .eq('cozinha_id', cozinhaId)
      .is('deletado_em', null)
      .order('semana', { ascending: false })
      .order('criado_em', { ascending: false })
      .limit(30),
  ) as Reconhecimento[];
}

export async function registarReconhecimento(dados: {
  cozinhaId: string;
  semana: string;
  periodo: Periodo;
  tipo: TipoReconhecimento;
  nota: string | null;
}) {
  verificar(
    await supabase.from('reconhecimentos_turno').insert({
      cozinha_id: dados.cozinhaId,
      semana: dados.semana,
      periodo: dados.periodo,
      tipo: dados.tipo,
      nota: dados.nota,
    }),
  );
}

// ---------------------------------------------------------------- O10
export async function gruposDoDia(dia: string): Promise<GrupoOperador[]> {
  return verificar(await supabase.rpc('grupos_operador', { p_dia: dia })) as GrupoOperador[];
}

export async function mudarEstadoGrupo(grupoId: string, estado: 'confirmado' | 'em_preparacao' | 'em_entrega'): Promise<number> {
  return verificar(await supabase.rpc('mudar_estado_grupo', { p_grupo: grupoId, p_estado: estado })) as number;
}

export async function fecharGrupo(grupoId: string) {
  verificar(await supabase.rpc('fechar_grupo', { p_grupo: grupoId }));
}

export async function cancelarGrupo(grupoId: string, motivo: string) {
  verificar(await supabase.rpc('cancelar_grupo', { p_grupo: grupoId, p_motivo: motivo }));
}

// ---------------------------------------------------------------- I12: pacotes pré-pagos
export async function adesoesPacote(estado: string | null): Promise<AdesaoOperador[]> {
  return verificar(await supabase.rpc('adesoes_operador', { p_estado: estado })) as AdesaoOperador[];
}

export async function confirmarPagamentoPacote(adesaoId: string, referencia: string | null, caixaId: string | null) {
  verificar(
    await supabase.rpc('confirmar_pagamento_pacote', { p_adesao: adesaoId, p_referencia: referencia, p_caixa: caixaId }),
  );
}

export async function reembolsarPacote(adesaoId: string, referencia: string): Promise<number> {
  return verificar(await supabase.rpc('reembolsar_pacote', { p_adesao: adesaoId, p_referencia: referencia })) as number;
}

export async function lerCatalogoPacotes(): Promise<PacoteCatalogo[]> {
  return verificar(
    await supabase
      .from('pacotes')
      .select('id, nome, descricao, refeicoes, refeicoes_oferta, valor_refeicao, preco, validade_dias, pausa_max_dias, entrega_gratis, activo, ordem')
      .is('deletado_em', null)
      .order('ordem'),
  ) as PacoteCatalogo[];
}

export async function guardarPacote(p: Omit<PacoteCatalogo, 'id'> & { id?: string }) {
  const { id, ...dados } = p;
  if (id) verificar(await supabase.from('pacotes').update({ ...dados, atualizado_em: new Date().toISOString() }).eq('id', id));
  else verificar(await supabase.from('pacotes').insert(dados));
}

// ---------------------------------------------------------------- Fotos dos pratos e das cozinhas
/** Grava logo a foto (ou a remoção) do prato, sem mexer nos outros campos */
export async function definirFotoPrato(id: string, fotoUrl: string | null) {
  verificar(await supabase.from('cardapio').update({ foto_url: fotoUrl, atualizado_em: new Date().toISOString() }).eq('id', id));
}

export async function definirFotoCozinha(id: string, fotoUrl: string | null) {
  verificar(await supabase.from('cozinhas').update({ foto_url: fotoUrl, atualizado_em: new Date().toISOString() }).eq('id', id));
}

// ---------------------------------------------------------------- Zonas de entrega
export async function lerZonasEntrega(): Promise<ZonaEntrega[]> {
  const r = await supabase.from('zonas').select('id, nome, taxa, tipo, centro_lat, centro_lng').is('deletado_em', null).order('nome');
  return (verificar(r) as ZonaEntrega[]).map((z) => ({
    ...z,
    taxa: Number(z.taxa ?? 0),
    centro_lat: z.centro_lat != null ? Number(z.centro_lat) : null,
    centro_lng: z.centro_lng != null ? Number(z.centro_lng) : null,
  }));
}

export async function guardarZonaEntrega(z: Omit<ZonaEntrega, 'id'> & { id?: string }) {
  const { id, ...dados } = z;
  const linha = { ...dados, modo_calculo: 'Fixo' };
  if (id) verificar(await supabase.from('zonas').update({ ...linha, atualizado_em: new Date().toISOString() }).eq('id', id));
  else verificar(await supabase.from('zonas').insert(linha));
}

/** Apagar = marcar deletado_em: os pontos e pedidos antigos continuam a apontar para a zona */
export async function apagarZonaEntrega(id: string) {
  const agora = new Date().toISOString();
  verificar(await supabase.from('zonas').update({ deletado_em: agora, atualizado_em: agora }).eq('id', id));
}

// ---------------------------------------------------------------- reclamações e estímulos
export async function lerReclamacoes(estado: 'aberta' | 'resolvida' | 'todas'): Promise<Reclamacao[]> {
  return verificar(await supabase.rpc('reclamacoes_lista', { p_estado: estado })) as Reclamacao[];
}

export async function decidirReclamacao(
  id: string,
  procedente: boolean,
  resposta: string,
  categoria: string | null,
  compensacao: string,
  valor: number | null,
) {
  verificar(
    await supabase.rpc('decidir_reclamacao', {
      p_id: id,
      p_procedente: procedente,
      p_resposta: resposta,
      p_categoria: categoria,
      p_compensacao: compensacao,
      p_valor: valor,
    }),
  );
}

export async function relatorioReclamacoes(ano: number, mes: number): Promise<RelatorioReclamacoes> {
  return verificar(await supabase.rpc('relatorio_reclamacoes', { p_ano: ano, p_mes: mes })) as RelatorioReclamacoes;
}

export async function pedirNovaAnalise(tipo: 'reclamacao' | 'estimulo', id: string) {
  verificar(await supabase.rpc('pedir_nova_analise', { p_tipo: tipo, p_id: id }));
}

export async function gerarEstimulos(ano: number, mes: number): Promise<number> {
  return verificar(await supabase.rpc('gerar_estimulos', { p_ano: ano, p_mes: mes })) as number;
}

export async function estimulosDoMes(ano: number, mes: number): Promise<Estimulo[]> {
  return verificar(await supabase.rpc('estimulos_do_mes', { p_ano: ano, p_mes: mes })) as Estimulo[];
}

export async function decidirEstimulo(id: string, aprovar: boolean, bonus: number | null, mensagem: string | null) {
  verificar(await supabase.rpc('decidir_estimulo', { p_id: id, p_aprovar: aprovar, p_bonus: bonus, p_mensagem: mensagem }));
}

// ---------------------------------------------------------------- agente investigador
export async function lerCasosInvestigacao(): Promise<CasoInvestigacao[]> {
  return verificar(await supabase.rpc('casos_investigacao_lista')) as CasoInvestigacao[];
}

export async function abrirInvestigacoes(inicio: string, fim: string): Promise<number> {
  return verificar(await supabase.rpc('abrir_investigacoes', { p_inicio: inicio, p_fim: fim })) as number;
}

export async function decidirCaso(id: string, decisao: string, nota: string) {
  verificar(await supabase.rpc('decidir_caso', { p_id: id, p_decisao: decisao, p_nota: nota }));
}

export async function investigarDeNovo(id: string) {
  verificar(await supabase.rpc('investigar_de_novo', { p_id: id }));
}

// ---------------------------------------------------------------- analista do administrador
export async function lerPerguntasAnalista(): Promise<PerguntaAnalista[]> {
  return verificar(await supabase.rpc('perguntas_analista_lista')) as PerguntaAnalista[];
}

/** Faz a pergunta e pede logo a resposta (se a chamada falhar, o servidor responde no minuto seguinte) */
export async function perguntarAnalista(pergunta: string): Promise<string> {
  const id = verificar(await supabase.rpc('perguntar_analista', { p_pergunta: pergunta })) as string;
  supabase.functions.invoke('analista', { body: { pergunta_id: id } }).catch(() => undefined);
  return id;
}

export async function pedirRelatorioAnalista(ano: number, mes: number): Promise<string> {
  const id = verificar(await supabase.rpc('pedir_relatorio_analista', { p_ano: ano, p_mes: mes })) as string;
  supabase.functions.invoke('analista', { body: { pergunta_id: id } }).catch(() => undefined);
  return id;
}

// ---------------------------------------------------------------- vigilante do Convida e Ganha
export async function lerCasosConvida(): Promise<CasoConvida[]> {
  return verificar(await supabase.rpc('casos_convida_lista')) as CasoConvida[];
}

export async function abrirVigilancia(inicio: string, fim: string): Promise<number> {
  return verificar(await supabase.rpc('abrir_vigilancia', { p_inicio: inicio, p_fim: fim })) as number;
}

export async function decidirCasoConvida(id: string, decisao: string, nota: string) {
  verificar(await supabase.rpc('decidir_caso_convida', { p_id: id, p_decisao: decisao, p_nota: nota }));
}

export async function vigiarDeNovo(id: string) {
  verificar(await supabase.rpc('vigiar_de_novo', { p_id: id }));
}

// ---------------------------------------------------------------- gerente de turno
export async function lerPropostasTurno(): Promise<PropostaTurno[]> {
  return verificar(await supabase.rpc('propostas_turno_lista')) as PropostaTurno[];
}

export async function decidirPropostaTurno(id: string, aceitar: boolean, motivo: string | null, maisMinutos: number | null) {
  verificar(await supabase.rpc('decidir_proposta_turno', { p_id: id, p_aceitar: aceitar, p_motivo: motivo, p_mais_minutos: maisMinutos }));
}

// ---------------------------------------------------------------- stock e compras
export async function lerPlanosCompras(): Promise<PlanoCompras[]> {
  return verificar(await supabase.rpc('planos_compras_lista')) as PlanoCompras[];
}

/** Pede um plano agora e chama logo o agente (o pg_cron apanha-o se esta chamada falhar) */
export async function pedirPlanoCompras(cozinhaId: string): Promise<string> {
  const id = verificar(await supabase.rpc('pedir_plano_compras', { p_cozinha: cozinhaId })) as string;
  supabase.functions.invoke('compras', { body: { plano_id: id } }).catch(() => undefined);
  return id;
}

export async function marcarCompra(planoId: string, indice: number, estado: 'pendente' | 'comprado' | 'ignorado') {
  verificar(await supabase.rpc('marcar_compra', { p_plano: planoId, p_indice: indice, p_estado: estado }));
}

// ---------------------------------------------------------------- atendimento ao cliente
export async function lerConversasAtendimento(): Promise<ConversaResumo[]> {
  return verificar(await supabase.rpc('conversas_atendimento_lista')) as ConversaResumo[];
}

export async function lerConversaAtendimento(id: string): Promise<ConversaDetalhe> {
  return verificar(await supabase.rpc('conversa_atendimento', { p_id: id })) as ConversaDetalhe;
}

export async function responderAtendimento(id: string, texto: string) {
  verificar(await supabase.rpc('responder_atendimento', { p_id: id, p_texto: texto }));
}

export async function mudarConversaAtendimento(id: string, estado: 'agente' | 'fechada') {
  verificar(await supabase.rpc('mudar_conversa_atendimento', { p_id: id, p_estado: estado }));
}

// ---------------------------------------------------------------- Pessoal (só administrador principal)
export async function listarPessoal(): Promise<PessoalItem[]> {
  return (verificar(await supabase.rpc('listar_pessoal')) as PessoalItem[]) ?? [];
}

export async function criarFuncionario(dados: {
  nome: string;
  cargo: string | null;
  telefone: string | null;
  estafeta: boolean;
}): Promise<string> {
  return verificar(
    await supabase.rpc('criar_funcionario', {
      p_nome: dados.nome,
      p_cargo: dados.cargo,
      p_telefone: dados.telefone,
      p_estafeta: dados.estafeta,
    }),
  ) as string;
}

export async function editarFuncionario(dados: {
  id: string;
  nome: string;
  cargo: string | null;
  activo: boolean;
  /** Opcional: as permissões são geridas à parte (definirPermissoes); null não toca em entregas.registar */
  estafeta?: boolean;
}) {
  verificar(
    await supabase.rpc('editar_funcionario', {
      p_id: dados.id,
      p_nome: dados.nome,
      p_cargo: dados.cargo,
      p_estafeta: dados.estafeta ?? null,
      p_activo: dados.activo,
    }),
  );
}

export async function definirTelefoneFuncionario(id: string, telefone: string | null) {
  verificar(await supabase.rpc('definir_telefone_funcionario', { p_funcionario: id, p_telefone: telefone }));
}

/** Catálogo de permissões (para montar os checkboxes por grupo) */
export async function permissoesCatalogo(): Promise<PermissaoCatalogo[]> {
  return (verificar(await supabase.rpc('permissoes_catalogo')) as PermissaoCatalogo[]) ?? [];
}

/** Define todas as permissões de um funcionário (objeto {chave: true}) */
export async function definirPermissoes(funcionarioId: string, permissoes: Record<string, boolean>) {
  verificar(await supabase.rpc('definir_permissoes_funcionario', { p_func: funcionarioId, p_permissoes: permissoes }));
}

/** Define as cozinhas (equipa fixa) de um funcionário */
export async function definirCozinhas(funcionarioId: string, cozinhas: string[]) {
  verificar(await supabase.rpc('definir_cozinhas_funcionario', { p_func: funcionarioId, p_cozinhas: cozinhas }));
}

// ---------------------------------------------------------------- Pedidos agendados
export async function pedidosAgendados(): Promise<PedidoAgendado[]> {
  return (verificar(await supabase.rpc('pedidos_agendados')) as PedidoAgendado[]) ?? [];
}

// ---------------------------------------------------------------- Mapa de estafetas (despacho)
export async function posicoesEstafetas(cozinhaId: string): Promise<PosicaoEstafeta[]> {
  return (verificar(await supabase.rpc('posicoes_estafetas', { p_cozinha: cozinhaId })) as PosicaoEstafeta[]) ?? [];
}

export async function sugestaoDespacho(cozinhaId: string): Promise<SugestaoDespacho[]> {
  return (verificar(await supabase.rpc('sugestao_despacho', { p_cozinha: cozinhaId })) as SugestaoDespacho[]) ?? [];
}

// ---------------------------------------------------------------- Conta de empresa (B2B)
export async function listarEmpresas(): Promise<Empresa[]> {
  return (verificar(await supabase.rpc('listar_empresas')) as Empresa[]) ?? [];
}

export async function criarEmpresa(nome: string, limite: number): Promise<string> {
  return verificar(await supabase.rpc('criar_empresa', { p_nome: nome, p_limite: limite })) as string;
}

export async function editarEmpresa(id: string, nome: string, limite: number, activa: boolean) {
  verificar(await supabase.rpc('editar_empresa', { p_id: id, p_nome: nome, p_limite: limite, p_activa: activa }));
}

export async function empresaMembrosLista(empresaId: string): Promise<EmpresaMembro[]> {
  return (verificar(await supabase.rpc('empresa_membros_lista', { p_empresa: empresaId })) as EmpresaMembro[]) ?? [];
}

export async function empresaAdicionarMembro(empresaId: string, codigo: string) {
  verificar(await supabase.rpc('empresa_adicionar_membro', { p_empresa: empresaId, p_codigo: codigo }));
}

export async function empresaRemoverMembro(empresaId: string, clienteId: string) {
  verificar(await supabase.rpc('empresa_remover_membro', { p_empresa: empresaId, p_cliente: clienteId }));
}

export async function relatorioEmpresa(empresaId: string, ano: number, mes: number): Promise<RelatorioEmpresa> {
  return verificar(await supabase.rpc('relatorio_empresa', { p_empresa: empresaId, p_ano: ano, p_mes: mes })) as RelatorioEmpresa;
}

// ---------------------------------------------------------------- Feira (consignação)
export async function listarFeiras(cozinhaId: string): Promise<Feira[]> {
  return (verificar(await supabase.rpc('listar_feiras', { p_cozinha: cozinhaId })) as Feira[]) ?? [];
}

export async function criarFeira(cozinhaId: string, vendedorId: string, nome: string): Promise<string> {
  return verificar(await supabase.rpc('criar_feira', { p_cozinha: cozinhaId, p_vendedor: vendedorId, p_nome: nome })) as string;
}

export async function feiraAdicionarItem(feiraId: string, cardapioId: string, qtd: number): Promise<string> {
  return verificar(await supabase.rpc('feira_adicionar_item', { p_feira: feiraId, p_cardapio: cardapioId, p_qtd: qtd })) as string;
}

export async function feiraVender(
  itemId: string,
  qtd: number,
  metodo: 'dinheiro' | 'transferencia',
  referencia?: string | null,
): Promise<number> {
  return verificar(
    await supabase.rpc('feira_vender', { p_item: itemId, p_qtd: qtd, p_metodo: metodo, p_referencia: referencia ?? null }),
  ) as number;
}

export async function feiraFechar(feiraId: string, acertos: { item_id: string; devolvida: number; perda: number }[]) {
  verificar(await supabase.rpc('feira_fechar', { p_feira: feiraId, p_acertos: acertos }));
}

export async function feiraResumo(feiraId: string): Promise<FeiraResumo> {
  return verificar(await supabase.rpc('feira_resumo', { p_feira: feiraId })) as FeiraResumo;
}

// ---------------------------------------------------------------- Central de Avisos
export async function preVisualizarAviso(
  publico: PublicoAviso,
  alvo: Record<string, unknown> = {},
): Promise<number> {
  return (verificar(await supabase.rpc('pre_visualizar_aviso', { p_publico: publico, p_alvo: alvo })) as number) ?? 0;
}

export async function enviarAviso(
  publico: PublicoAviso,
  titulo: string,
  corpo: string,
  alvo: Record<string, unknown> = {},
  link?: string,
): Promise<{ id: string; total: number }> {
  return verificar(
    await supabase.rpc('enviar_aviso', {
      p_publico: publico,
      p_titulo: titulo,
      p_corpo: corpo,
      p_alvo: alvo,
      p_link: link ?? null,
    }),
  ) as { id: string; total: number };
}

export async function listarAvisos(limite = 50): Promise<Aviso[]> {
  return (verificar(await supabase.rpc('listar_avisos', { p_limite: limite })) as Aviso[]) ?? [];
}
