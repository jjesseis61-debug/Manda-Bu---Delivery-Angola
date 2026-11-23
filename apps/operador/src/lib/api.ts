// Chamadas ao servidor da app do operador. Cada função do servidor verifica a
// permissão do organograma; a app só esconde o que o funcionário não pode usar.
import type { RelatorioDetalhado, Rentabilidade, TemposEtapas } from './relatorio';
import { supabase } from './supabase';
import type {
  AcertosSemana,
  FolhaEstafetas,
  Obrigacoes,
  ResultadosMes,
  ServicosEntrega,
  Compensacao,
  ContasEmpresas,
  VendaSemFatura,
  Aviso,
  AuditoriaCardapio,
  ImpactoPreco,
  MovimentoPreco,
  PublicoAviso,
  ClienteInativo,
  UtilizadorEncontrado,
  UtilizadorBloqueado,
  HorarioCardapio,
  LinhaAuditoria,
  OtpPendente,
  ResumoInativos,
  CampanhaReconquista,
  Notificacao,
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
  AgendadoOperador,
  PedidoOperador,
  EstafetaAtribuir,
  Periodo,
  PermissaoCatalogo,
  PessoalItem,
  Empresa,
  EmpresaMembro,
  Feira,
  FeiraResumo,
  PosicaoEstafeta,
  PosicaoPedido,
  RelatorioEmpresa,
  SugestaoDespacho,
  PratoCardapio,
  Reconhecimento,
  Receita,
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
// ---------------------------------------------------------------- Acertos com as cozinhas
export async function acertosSemana(semana: string | null): Promise<AcertosSemana> {
  return verificar(await supabase.rpc('acertos_semana', { p_semana: semana })) as AcertosSemana;
}

export async function fecharAcerto(cozinhaId: string, semana: string): Promise<string> {
  return verificar(await supabase.rpc('fechar_acerto', { p_cozinha: cozinhaId, p_semana: semana })) as string;
}

export async function registarPagamentoAcerto(
  acertoId: string,
  valor: number,
  metodo: string,
  referencia: string | null,
  comprovativo: string | null = null,
) {
  return verificar(
    await supabase.rpc('registar_pagamento_acerto', {
      p_acerto: acertoId,
      p_valor: valor,
      p_metodo: metodo,
      p_referencia: referencia,
      p_comprovativo: comprovativo,
    }),
  ) as { pago: number; falta: number; estado: string };
}

// Faturas das vendas (número do software certificado; emitida pela plataforma ou pela cozinha)
export async function vendasSemFatura(dias = 30): Promise<VendaSemFatura[]> {
  return verificar(await supabase.rpc('vendas_sem_fatura', { p_dias: dias })) as VendaSemFatura[];
}

export async function registarFaturaPedido(pedidoId: string, numero: string, emitidaPor: 'plataforma' | 'cozinha') {
  verificar(await supabase.rpc('registar_fatura_pedido', { p_pedido: pedidoId, p_numero: numero, p_emitida_por: emitidaPor }));
}

// Compensações das reclamações (a plataforma paga ao cliente; a cargo da cozinha entra no acerto)
export async function compensacoesLista(estado: string | null): Promise<Compensacao[]> {
  return verificar(await supabase.rpc('compensacoes_lista', { p_estado: estado })) as Compensacao[];
}

export async function definirCargoCompensacao(id: string, aCargo: 'plataforma' | 'cozinha') {
  verificar(await supabase.rpc('definir_cargo_compensacao', { p_id: id, p_a_cargo: aCargo }));
}

export async function pagarCompensacao(id: string, metodo: string, referencia: string | null) {
  verificar(await supabase.rpc('pagar_compensacao', { p_id: id, p_metodo: metodo, p_referencia: referencia }));
}

// Estafetas: remuneração (salário, dia, entrega), dias trabalhados e pagamento do mês
export async function estafetasPagamentos(mes: string | null): Promise<FolhaEstafetas> {
  return verificar(await supabase.rpc('estafetas_pagamentos', { p_mes: mes })) as FolhaEstafetas;
}

export async function definirRemuneracaoEstafeta(id: string, salario: number, dia: number, entrega: number) {
  verificar(
    await supabase.rpc('definir_remuneracao_estafeta', {
      p_funcionario: id,
      p_salario_mensal: salario,
      p_valor_dia: dia,
      p_valor_entrega: entrega,
    }),
  );
}

export async function definirDiasEstafeta(id: string, mes: string, dias: number | null) {
  verificar(await supabase.rpc('definir_dias_estafeta', { p_funcionario: id, p_mes: mes, p_dias: dias }));
}

export async function pagarEstafetaMes(id: string, mes: string, metodo: string, referencia: string | null) {
  return verificar(
    await supabase.rpc('pagar_estafeta_mes', { p_funcionario: id, p_mes: mes, p_metodo: metodo, p_referencia: referencia }),
  ) as number;
}

// Serviço de entregas contratado
export async function fornecedoresEntrega(mes: string | null): Promise<ServicosEntrega> {
  return verificar(await supabase.rpc('fornecedores_entrega_lista', { p_mes: mes })) as ServicosEntrega;
}

export async function guardarFornecedorEntrega(f: {
  id: string | null;
  nome: string;
  valorEntrega: number;
  valorMensal: number;
  zonas: string[];
  activo: boolean;
}) {
  return verificar(
    await supabase.rpc('guardar_fornecedor_entrega', {
      p_id: f.id,
      p_nome: f.nome,
      p_valor_entrega: f.valorEntrega,
      p_valor_mensal: f.valorMensal,
      p_zonas: f.zonas,
      p_activo: f.activo,
    }),
  ) as string;
}

export async function pagarFornecedorEntrega(id: string, mes: string, metodo: string, referencia: string | null, fatura: string | null) {
  return verificar(
    await supabase.rpc('pagar_fornecedor_entrega', {
      p_fornecedor: id,
      p_mes: mes,
      p_metodo: metodo,
      p_referencia: referencia,
      p_numero_fatura: fatura,
    }),
  ) as number;
}

// Resultados do mês e obrigações
export async function resultadosMes(mes: string | null): Promise<ResultadosMes> {
  return verificar(await supabase.rpc('resultados_mes', { p_mes: mes })) as ResultadosMes;
}

export async function obrigacoesResumo(): Promise<Obrigacoes> {
  return verificar(await supabase.rpc('obrigacoes_resumo')) as Obrigacoes;
}

// Contas a receber das empresas (B2B)
export async function contasEmpresas(mes: string | null): Promise<ContasEmpresas> {
  return verificar(await supabase.rpc('contas_empresas', { p_mes: mes })) as ContasEmpresas;
}

export async function emitirFaturaEmpresa(empresaId: string, mes: string, numero: string, vencimento: string) {
  return verificar(
    await supabase.rpc('emitir_fatura_empresa', { p_empresa: empresaId, p_mes: mes, p_numero: numero, p_vencimento: vencimento }),
  ) as string;
}

export async function pagarFaturaEmpresa(faturaId: string, metodo: string, referencia: string | null) {
  verificar(await supabase.rpc('pagar_fatura_empresa', { p_fatura: faturaId, p_metodo: metodo, p_referencia: referencia }));
}

export async function definirFaturaAcerto(acertoId: string, numero: string) {
  verificar(await supabase.rpc('definir_fatura_acerto', { p_acerto: acertoId, p_numero: numero }));
}

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

export async function alterarParametros(valores: Record<string, number | string | boolean | null>) {
  verificar(await supabase.rpc('alterar_parametros', { p_valores: valores }));
}

export async function alterarFuncionalidade(chave: string, activa: boolean) {
  verificar(await supabase.rpc('alterar_funcionalidade', { p_chave: chave, p_activa: activa }));
}

// ---------------------------------------------------------------- O6
export async function lerCozinhas(): Promise<Cozinha[]> {
  const campos = 'id, nome, responsavel, foto_url, historia, estado, consentimento_publico, telefone_publico, whatsapp_publico, horario_publico';
  const ler = (c: string) => supabase.from('cozinhas').select(c).is('deletado_em', null).order('criado_em');
  let r = await ler(campos + ', selo_kota');
  // Servidor ainda sem o selo «Kota da Cozinha»: lê sem ele (e o ecrã esconde o interruptor)
  if (r.error) r = await ler(campos);
  return verificar(r) as unknown as Cozinha[];
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
      .select('id, cozinha_id, nome, descricao, categoria, preco, disponivel, do_dia, ordem, foto_url, doses_dia, minimo_montavel, visivel_online, disponivel_de, disponivel_ate')
      .eq('cozinha_id', cozinhaId)
      .order('ordem')
      .order('nome'),
  ) as PratoCardapio[];
}

/** Grava o prato e devolve o id (o existente, ou o novo no caso de criação). */
export async function guardarPrato(p: Omit<PratoCardapio, 'id'> & { id?: string }): Promise<string> {
  const { id, ...resto } = p;
  // Sem espaços nas pontas do nome: "Bitoque " partia o negrito da partilha no WhatsApp
  const dados = { ...resto, nome: resto.nome.trim() };
  if (id) {
    verificar(await supabase.from('cardapio').update({ ...dados, atualizado_em: new Date().toISOString() }).eq('id', id));
    return id;
  }
  const r = verificar(await supabase.from('cardapio').insert(dados).select('id').single()) as { id: string };
  return r.id;
}

/** Doses que restam hoje dos pratos com limite (as de dias anteriores já não contam) */
export async function lerDosesCardapio(cozinhaId: string): Promise<DosesPrato[]> {
  return verificar(await supabase.rpc('doses_cardapio', { p_cozinha: cozinhaId })) as DosesPrato[];
}

/** Rasto de alterações do cardápio de uma cozinha: pratos, perfil, morada e opções (de→para). */
export async function auditoriaCardapio(cozinhaId: string): Promise<AuditoriaCardapio[]> {
  return (verificar(await supabase.rpc('auditoria_cardapio', { p_cozinha: cozinhaId })) as AuditoriaCardapio[]) ?? [];
}

/** Impacto de cada preço de um prato: quantos pedidos atendidos, clientes e total recebido. */
export async function impactoPrecoPrato(cardapioId: string): Promise<ImpactoPreco[]> {
  return (verificar(await supabase.rpc('impacto_preco_prato', { p_cardapio: cardapioId })) as ImpactoPreco[]) ?? [];
}

/** Movimento cliente a cliente de um prato (opcionalmente só de um preço). */
export async function movimentoPrecoPrato(cardapioId: string, preco?: number): Promise<MovimentoPreco[]> {
  return (
    (verificar(await supabase.rpc('movimento_preco_prato', { p_cardapio: cardapioId, p_preco: preco ?? null })) as MovimentoPreco[]) ?? []
  );
}

// ---------------------------------------------------------------- I9: opções dos pratos
/** Ids dos pratos (desta lista) que são montáveis: têm grupos de opções */
export async function idsMontaveis(cardapioIds: string[]): Promise<Set<string>> {
  if (cardapioIds.length === 0) return new Set();
  const r = await supabase.from('opcoes_grupos').select('cardapio_id').in('cardapio_id', cardapioIds).is('deletado_em', null);
  return new Set((verificar(r) as { cardapio_id: string }[]).map((g) => g.cardapio_id));
}

/** O prato modelo das cozinhas novas (null = o "Serve o teu próprio prato" mais antigo) */
export async function lerModeloMontavel(): Promise<string | null> {
  const p = await lerParametros();
  return (p.cardapio_modelo_montavel as string | null) ?? null;
}

export async function lerGruposOpcoes(cardapioId: string): Promise<GrupoOpcoesPrato[]> {
  const r = await supabase
    .from('opcoes_grupos')
    .select('id, cardapio_id, nome, minimo, maximo, ordem, opcoes(id, grupo_id, nome, preco_extra, disponivel, ordem, componentes, foto_url, deletado_em)')
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

// ---------------------------------------------------------------- Sino de notificações
export async function minhasNotificacoes(limite = 30): Promise<Notificacao[]> {
  return (verificar(await supabase.rpc('minhas_notificacoes', { p_limite: limite })) as Notificacao[]) ?? [];
}

export async function contarNotificacoesNovas(): Promise<number> {
  return (verificar(await supabase.rpc('contar_notificacoes_novas')) as number) ?? 0;
}

export async function marcarNotificacoesVistas(ids?: string[]): Promise<number> {
  return (verificar(await supabase.rpc('marcar_notificacoes_vistas', { p_ids: ids ?? null })) as number) ?? 0;
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

/** Relatório detalhado de uma cozinha (resumo com o período anterior, vendas, pratos, pagamentos...) */
export async function relatorioCozinhaDetalhado(cozinhaId: string, inicio: string, fim: string): Promise<RelatorioDetalhado> {
  return verificar(
    await supabase.rpc('relatorio_cozinha_detalhado', { p_cozinha: cozinhaId, p_inicio: inicio, p_fim: fim }),
  ) as RelatorioDetalhado;
}

export async function lerComissaoCozinha(cozinhaId: string): Promise<{ comissao: number; convida: number }> {
  const r = verificar(
    await supabase.from('cozinhas').select('comissao_percent, convida_cozinha_percent').eq('id', cozinhaId).single(),
  ) as { comissao_percent: number | string | null; convida_cozinha_percent: number | string | null };
  return { comissao: Number(r.comissao_percent ?? 0), convida: Number(r.convida_cozinha_percent ?? 0) };
}

/** Parte (%) do desconto de convite e do saldo Convida paga pela cozinha: 0 = plataforma, 100 = cozinha */
export async function definirConvidaCozinha(cozinhaId: string, percent: number) {
  verificar(await supabase.rpc('definir_convida_cozinha', { p_cozinha: cozinhaId, p_percent: percent }));
}

export type CustoItem = {
  item_id: string;
  tipo: 'prato' | 'opcao';
  prato_id: string;
  nome: string;
  grupo: string | null;
  preco: number;
  custo: number | null;
  disponivel: boolean;
};

/** Pratos e opções da cozinha com o preço e o custo de uma dose (só equipa) */
export async function custosDaCozinha(cozinhaId: string): Promise<CustoItem[]> {
  return (verificar(await supabase.rpc('custos_da_cozinha', { p_cozinha: cozinhaId })) as CustoItem[]) ?? [];
}

/** Custo de uma dose de um prato ou opção (null apaga) */
export async function definirCustoItem(itemId: string, custo: number | null) {
  verificar(await supabase.rpc('definir_custo_item', { p_item: itemId, p_custo: custo }));
}

export type Despesa = { id: string; data: string; categoria: string; descricao: string | null; valor: number };

export async function despesasCozinha(cozinhaId: string, inicio: string, fim: string): Promise<Despesa[]> {
  return (verificar(await supabase.rpc('despesas_cozinha', { p_cozinha: cozinhaId, p_inicio: inicio, p_fim: fim })) as Despesa[]) ?? [];
}

export async function lancarDespesa(cozinhaId: string, data: string, categoria: string, descricao: string, valor: number) {
  return verificar(
    await supabase.rpc('lancar_despesa', { p_cozinha: cozinhaId, p_data: data, p_categoria: categoria, p_descricao: descricao, p_valor: valor }),
  ) as string;
}

export async function apagarDespesa(id: string) {
  verificar(await supabase.rpc('apagar_despesa', { p_id: id }));
}

/** Rentabilidade (custo dos pratos, margem, despesas) e doses (esgotados/sobras) de um período */
export async function rentabilidadeCozinha(cozinhaId: string, inicio: string, fim: string): Promise<Rentabilidade> {
  return verificar(await supabase.rpc('rentabilidade_cozinha', { p_cozinha: cozinhaId, p_inicio: inicio, p_fim: fim })) as Rentabilidade;
}

/** Tempo de cada etapa do pedido (confirmar, começar, preparar, entregar) num período */
export async function temposEtapasCozinha(cozinhaId: string, inicio: string, fim: string): Promise<TemposEtapas> {
  return verificar(await supabase.rpc('tempos_etapas_cozinha', { p_cozinha: cozinhaId, p_inicio: inicio, p_fim: fim })) as TemposEtapas;
}

/** Comissão da plataforma sobre as vendas de comida da cozinha (0–50 %), só o admin */
export async function definirComissaoCozinha(cozinhaId: string, percent: number) {
  verificar(await supabase.rpc('definir_comissao_cozinha', { p_cozinha: cozinhaId, p_percent: percent }));
}

export async function relatorioComparativo(inicio: string, fim: string): Promise<LinhaComparativo[]> {
  return verificar(await supabase.rpc('relatorio_comparativo', { p_inicio: inicio, p_fim: fim })) as LinhaComparativo[];
}

// ---------------------------------------------------------------- E1
export async function pedidosOperador(): Promise<PedidoOperador[]> {
  return verificar(await supabase.rpc('pedidos_operador')) as PedidoOperador[];
}

export async function estafetasParaAtribuir(cozinhaId: string): Promise<EstafetaAtribuir[]> {
  return (
    (verificar(await supabase.rpc('estafetas_para_atribuir', { p_cozinha: cozinhaId })) as EstafetaAtribuir[]) ?? []
  );
}

export async function atribuirEntrega(pedidoId: string, estafetaId: string): Promise<void> {
  verificar(await supabase.rpc('atribuir_entrega', { p_pedido: pedidoId, p_estafeta: estafetaId }));
}

export async function recusarEntrega(pedidoId: string): Promise<void> {
  verificar(await supabase.rpc('recusar_entrega', { p_pedido: pedidoId }));
}

export async function caixasAbertas(): Promise<Caixa[]> {
  return verificar(
    await supabase.from('caixa').select('id, posto, data, cozinha_id').is('fechamento', null).order('data', { ascending: false }),
  ) as Caixa[];
}

// ---------------------------------------------------------------- Caixa
/** Caixas que o funcionário pode gerir (só a sua cozinha): abertas e as últimas fechadas */
export async function caixasRecentes(): Promise<CaixaGestao[]> {
  return (verificar(await supabase.rpc('caixas_geridas', { p_limite: 20 })) as CaixaGestao[]) ?? [];
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

/** A cozinha marca (ou desmarca) o pedido em preparação como pronto; avisa o estafeta reservado */
export async function marcarPronto(pedidoId: string, pronto = true): Promise<void> {
  verificar(await supabase.rpc('marcar_pedido_pronto', { p_pedido: pedidoId, p_pronto: pronto }));
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

/** Grava logo a foto (ou a remoção) de uma opção do prato montável, sem mexer nos outros campos */
export async function definirFotoOpcao(id: string, fotoUrl: string | null) {
  verificar(await supabase.from('opcoes').update({ foto_url: fotoUrl, atualizado_em: new Date().toISOString() }).eq('id', id));
}

// ---------------------------------------------------------------- Zonas de entrega
export async function lerZonasEntrega(): Promise<ZonaEntrega[]> {
  const r = await supabase.from('zonas').select('id, nome, taxa, tipo, centro_lat, centro_lng, entrega_gratis_acima').is('deletado_em', null).order('nome');
  return (verificar(r) as ZonaEntrega[]).map((z) => ({
    ...z,
    taxa: Number(z.taxa ?? 0),
    centro_lat: z.centro_lat != null ? Number(z.centro_lat) : null,
    centro_lng: z.centro_lng != null ? Number(z.centro_lng) : null,
    entrega_gratis_acima: z.entrega_gratis_acima != null ? Number(z.entrega_gratis_acima) : null,
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
export type AparelhoPartilhado = {
  chave: string;
  plataforma: string;
  modelo: string | null;
  contas: number;
  ultimo_em: string;
  clientes: { cliente_id: string; nome: string; telefone: string | null; convidado_por: string | null; pedidos: number }[];
};

/** Painel de vigilância (#9): números do Convida num período, para apanhar abusos cedo */
export type PainelVigilancia = {
  dias: number;
  em_verificacao: { n: number; valor: number; mais_antigo: string | null };
  anulados: { n: number; valor: number; por_motivo: { motivo: string; n: number; valor: number }[] };
  levantamentos: { n: number; valor: number; pedidos: number; aprovados: number; mais_antigo: string | null };
  serie: { dia: string; contas: number; ligacoes: number; ganhos: number; pico: boolean }[];
  medias: { contas: number; ligacoes: number; ganhos: number };
  topo: {
    cliente_id: string; nome: string; codigo: string | null; nivel: string | null;
    ganhos: number; valor: number; indicados: number; anulados: number; so_um_pedido: number;
  }[];
  aparelhos_partilhados: number;
};

export async function painelVigilancia(dias = 14): Promise<PainelVigilancia> {
  return verificar(await supabase.rpc('painel_vigilancia', { p_dias: dias })) as PainelVigilancia;
}

/** O que mais sai em cada zona (zona onde o cliente recebe): por cozinha e na visão de todas */
export type PratoZona = { nome: string; qtd: number; receita: number; qtd_anterior: number; cozinha_top?: string | null };
export type ZonaVendas = {
  zona: string;
  pedidos: number;
  vendas: number;
  cozinhas?: number;
  pratos: PratoZona[];
  opcoes: { nome: string; qtd: number }[];
  a_crescer?: { nome: string; qtd: number; qtd_anterior: number }[];
};
export async function pratosPorZonaCozinha(cozinhaId: string, inicio: string, fim: string): Promise<ZonaVendas[]> {
  return (verificar(
    await supabase.rpc('pratos_por_zona_cozinha', { p_cozinha: cozinhaId, p_inicio: inicio, p_fim: fim }),
  ) as ZonaVendas[]) ?? [];
}
export async function vendasPorZona(inicio: string, fim: string): Promise<{ zonas: ZonaVendas[] }> {
  return verificar(await supabase.rpc('vendas_por_zona', { p_inicio: inicio, p_fim: fim })) as { zonas: ZonaVendas[] };
}

/** Relatório dos saldos do Convida que expiraram (validade de 12 meses) e do que vai expirar */
export type RelatorioExpirados = {
  periodo: { inicio: string; fim: string };
  validade_meses: number;
  resumo: { total: number; expiracoes: number; clientes: number; media: number; maior: number; avisados: number };
  por_mes: { mes: string; valor: number; clientes: number }[];
  lista: {
    id: string; data: string; cliente_id: string; nome: string; telefone: string | null; codigo: string | null;
    nivel: string | null; valor: number; ganhos_ate: string; ganhos_antigos: number; usado: number;
    saldo_antes: number; avisado: boolean;
  }[];
  a_expirar: { d30: number; clientes_30: number; d60: number; clientes_60: number; d90: number; clientes_90: number };
  a_expirar_lista: {
    cliente_id: string; nome: string; telefone: string | null; valor: number; em_30_dias: number;
    expira_em: string | null; saldo: number;
  }[];
  saldo_activo_total: number;
  expirado_sempre: number;
};

export async function relatorioSaldosExpirados(inicio: string, fim: string): Promise<RelatorioExpirados> {
  return verificar(
    await supabase.rpc('relatorio_saldos_expirados', { p_inicio: inicio, p_fim: fim }),
  ) as RelatorioExpirados;
}

/** Telemóveis com muitas contas (só alerta; ninguém é bloqueado) */
export async function aparelhosPartilhados(): Promise<AparelhoPartilhado[]> {
  return (verificar(await supabase.rpc('aparelhos_partilhados')) as AparelhoPartilhado[]) ?? [];
}

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

/** Todos os agendados de um período (dias de Luanda, aaaa-mm-dd), com tudo para preparar e entregar */
export async function agendadosOperador(inicio: string, fim: string, cozinha: string | null): Promise<AgendadoOperador[]> {
  return (
    (verificar(
      await supabase.rpc('agendados_operador', { p_inicio: inicio, p_fim: fim, p_cozinha: cozinha }),
    ) as AgendadoOperador[]) ?? []
  );
}

/** Alertas dos agendados: prato fora do horário, doses insuficientes, hora cheia */
export type AlertaAgendado = { pedido_id: string; tipo: 'fora_de_horario' | 'doses' | 'hora_cheia'; detalhe: string };
export async function alertasAgendados(inicio: string, fim: string, cozinha: string | null): Promise<AlertaAgendado[]> {
  return (
    (verificar(
      await supabase.rpc('alertas_agendados', { p_inicio: inicio, p_fim: fim, p_cozinha: cozinha }),
    ) as AlertaAgendado[]) ?? []
  );
}

/** Reagendar a pedido do cliente (20 min a 14 dias); o cliente é avisado */
export async function reagendarPedido(pedidoId: string, nova: string, motivo: string | null): Promise<void> {
  verificar(await supabase.rpc('reagendar_pedido', { p_pedido: pedidoId, p_nova: nova, p_motivo: motivo }));
}

/** Indicadores dos agendados para o relatório da cozinha */
export type IndicadoresAgendados = {
  pedidos: number;
  entregues: number;
  valor: number;
  cancelados: number;
  a_tempo: number;
  antecedencia_horas: number | null;
  horas: { hora: string; pedidos: number }[];
};
export async function indicadoresAgendados(cozinhaId: string, inicio: string, fim: string): Promise<IndicadoresAgendados> {
  return verificar(
    await supabase.rpc('indicadores_agendados', { p_cozinha: cozinhaId, p_inicio: inicio, p_fim: fim }),
  ) as IndicadoresAgendados;
}

/** Cria o prato montável na cozinha a partir do modelo (nasce desactivado) */
export async function criarMontavelDoModelo(cozinhaId: string): Promise<string> {
  return verificar(await supabase.rpc('criar_montavel_do_modelo', { p_cozinha: cozinhaId })) as string;
}

// ---------------------------------------------------------------- Mapa de estafetas (despacho)
export async function posicoesEstafetas(cozinhaId: string): Promise<PosicaoEstafeta[]> {
  return (verificar(await supabase.rpc('posicoes_estafetas', { p_cozinha: cozinhaId })) as PosicaoEstafeta[]) ?? [];
}

export async function sugestaoDespacho(cozinhaId: string): Promise<SugestaoDespacho[]> {
  return (verificar(await supabase.rpc('sugestao_despacho', { p_cozinha: cozinhaId })) as SugestaoDespacho[]) ?? [];
}

// Posição do estafeta de um pedido, para a cozinha acompanhar ao vivo (ou o próprio estafeta)
export async function posicaoPedido(pedidoId: string): Promise<PosicaoPedido> {
  return verificar(await supabase.rpc('posicao_pedido', { p_pedido: pedidoId })) as PosicaoPedido;
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

// ---------------------------------------------------------------- Utilizadores (procurar e bloquear)
export async function procurarUtilizadores(termo: string): Promise<UtilizadorEncontrado[]> {
  return (verificar(await supabase.rpc('procurar_utilizadores', { p_termo: termo })) as UtilizadorEncontrado[]) ?? [];
}

export async function bloquearUtilizador(telefone: string, motivo: string | null) {
  verificar(await supabase.rpc('bloquear_utilizador', { p_telefone: telefone, p_motivo: motivo }));
}

export async function desbloquearUtilizador(telefone: string) {
  verificar(await supabase.rpc('desbloquear_utilizador', { p_telefone: telefone }));
}

export async function listarUtilizadoresBloqueados(): Promise<UtilizadorBloqueado[]> {
  return (verificar(await supabase.rpc('utilizadores_bloqueados_lista')) as UtilizadorBloqueado[]) ?? [];
}

// ---------------------------------------------------------------- OTP manual (códigos de login)
export async function auditoriaLista(categoria?: string | null, desde?: string | null): Promise<LinhaAuditoria[]> {
  return (
    (verificar(await supabase.rpc('auditoria_lista', { p_categoria: categoria ?? null, p_desde: desde ?? null })) as LinhaAuditoria[]) ?? []
  );
}

export async function lerHorarios(cardapioId: string): Promise<HorarioCardapio[]> {
  return (
    (verificar(
      await supabase
        .from('cardapio_horarios')
        .select('id, cardapio_id, dia_semana, data, hora_inicio, hora_fim')
        .eq('cardapio_id', cardapioId)
        .order('dia_semana', { nullsFirst: false })
        .order('data')
        .order('hora_inicio'),
    ) as HorarioCardapio[]) ?? []
  );
}

export async function guardarHorario(h: {
  id?: string;
  cardapio_id: string;
  dia_semana: number | null;
  data: string | null;
  hora_inicio: string;
  hora_fim: string;
}): Promise<void> {
  if (h.id) {
    const { id, ...resto } = h;
    verificar(await supabase.from('cardapio_horarios').update(resto).eq('id', id));
  } else {
    verificar(await supabase.from('cardapio_horarios').insert(h));
  }
}

export async function apagarHorario(id: string): Promise<void> {
  verificar(await supabase.from('cardapio_horarios').delete().eq('id', id));
}

export async function otpPendentes(): Promise<OtpPendente[]> {
  return (verificar(await supabase.rpc('otp_pendentes_lista')) as OtpPendente[]) ?? [];
}

export async function otpMarcarEntregue(id: string) {
  verificar(await supabase.rpc('otp_marcar_entregue', { p_id: id }));
}

export async function otpLimpar() {
  verificar(await supabase.rpc('otp_limpar'));
}

/** Segurança: termina a sessão em TODOS os dispositivos, incluindo este */
export async function sairDeTodosOsDispositivos() {
  const { error } = await supabase.auth.signOut({ scope: 'global' });
  if (error) throw error;
}

// ---------------------------------------------------------------- Reconquista de clientes inativos
export async function clientesInativosResumo(): Promise<ResumoInativos> {
  return verificar(await supabase.rpc('clientes_inativos_resumo')) as ResumoInativos;
}

export async function clientesInativos(
  diasMin: number,
  diasMax: number | null = null,
  zonaId: string | null = null,
): Promise<ClienteInativo[]> {
  return (
    (verificar(
      await supabase.rpc('clientes_inativos', { p_dias_min: diasMin, p_dias_max: diasMax, p_zona: zonaId }),
    ) as ClienteInativo[]) ?? []
  );
}

export async function enviarCampanhaReconquista(dados: {
  diasMin: number;
  diasMax: number | null;
  zonaId: string | null;
  titulo: string;
  corpo: string;
  link?: string | null;
  controloPct?: number | null;
}): Promise<{ campanha_id: string; elegiveis: number; enviados: number; controlo: number; enviados_push: number }> {
  return verificar(
    await supabase.rpc('enviar_campanha_reconquista', {
      p_dias_min: dados.diasMin,
      p_dias_max: dados.diasMax,
      p_zona: dados.zonaId,
      p_titulo: dados.titulo,
      p_corpo: dados.corpo,
      p_link: dados.link ?? null,
      p_controlo_pct: dados.controloPct ?? null,
    }),
  ) as { campanha_id: string; elegiveis: number; enviados: number; controlo: number; enviados_push: number };
}

export async function listarCampanhasReconquista(limite = 50): Promise<CampanhaReconquista[]> {
  return (
    (verificar(await supabase.rpc('listar_campanhas_reconquista', { p_limite: limite })) as CampanhaReconquista[]) ?? []
  );
}

// ---------------------------------------------------------------- Receitas (Cozinha de casa): R1
export async function lerReceitasGerir(): Promise<Receita[]> {
  return verificar(
    await supabase
      .from('receitas')
      .select('id, titulo, resumo, corpo, foto_url, cozinha_id, estado, origem, criado_em, publicado_em')
      .is('deletado_em', null)
      .order('criado_em', { ascending: false }),
  ) as Receita[];
}

/** Cria ou actualiza uma receita; devolve o id (preciso para enviar a foto depois de criar) */
export async function guardarReceita(
  r: { id?: string; titulo: string; resumo: string | null; corpo: string; cozinha_id: string | null; foto_url?: string | null },
): Promise<string> {
  const { id, ...dados } = r;
  if (id) {
    verificar(await supabase.from('receitas').update({ ...dados, atualizado_em: new Date().toISOString() }).eq('id', id));
    return id;
  }
  const criada = verificar(await supabase.from('receitas').insert(dados).select('id').single()) as { id: string };
  return criada.id;
}

/** Pratos (de qualquer cozinha) que fazem a receita: o «Pedir» do cliente escolhe entre eles */
export type PratoDaReceita = { cardapio_id: string; nome: string; preco: number; cozinha_id: string; cozinha_nome: string; disponivel: boolean };
export async function pratosDaReceita(receitaId: string): Promise<PratoDaReceita[]> {
  return (verificar(await supabase.rpc('receita_pratos_gerir', { p_receita: receitaId })) as PratoDaReceita[]) ?? [];
}
export async function guardarPratosDaReceita(receitaId: string, cardapioIds: string[]): Promise<number> {
  return verificar(await supabase.rpc('receita_guardar_pratos', { p_receita: receitaId, p_cardapio: cardapioIds })) as number;
}

/** Números de cada receita: aberturas, toques em «Pedir», pedidos que vieram dela, «quero que façam» e quem a faz */
export type MetricasReceita = { aberturas: number; toques: number; pedidos: number; interessados: number; cozinhas: string[] };
export async function metricasReceitas(): Promise<Record<string, MetricasReceita>> {
  return (verificar(await supabase.rpc('receitas_metricas')) as Record<string, MetricasReceita>) ?? {};
}

/** Todos os pratos de todas as cozinhas (para ligar a uma receita) */
export async function lerTodosPratos(): Promise<PratoCardapio[]> {
  return verificar(
    await supabase.from('cardapio').select('id, cozinha_id, nome, preco, disponivel, visivel_online').is('deletado_em', null).order('nome'),
  ) as PratoCardapio[];
}

export async function definirFotoReceita(id: string, foto_url: string | null): Promise<void> {
  verificar(await supabase.from('receitas').update({ foto_url, atualizado_em: new Date().toISOString() }).eq('id', id));
}

export async function publicarReceita(id: string, publicar: boolean): Promise<void> {
  verificar(await supabase.from('receitas').update({
    estado: publicar ? 'publicada' : 'rascunho',
    publicado_em: publicar ? new Date().toISOString() : null,
    atualizado_em: new Date().toISOString(),
  }).eq('id', id));
}

export async function arquivarReceita(id: string): Promise<void> {
  verificar(await supabase.from('receitas').update({ estado: 'arquivada', atualizado_em: new Date().toISOString() }).eq('id', id));
}

// Receitas R2/R3: gerar rascunho com Claude e avisar os clientes de uma receita publicada
export async function gerarRascunhoReceita(tema: string): Promise<string> {
  const { data, error } = await supabase.functions.invoke('receita-rascunho', { body: { tema } });
  if (error) throw new Error('nao_gerou');
  const d = data as { id?: string };
  if (!d?.id) throw new Error('nao_gerou');
  return d.id;
}
export async function avisarNovaReceita(id: string): Promise<number> {
  return verificar(await supabase.rpc('avisar_nova_receita', { p_id: id })) as number;
}

// A geração por IA das receitas está ligada? (interruptor 'receitas_ia')
export async function iaDasReceitasLigada(): Promise<boolean> {
  const r = verificar(await supabase.from('funcionalidades').select('activa').eq('chave', 'receitas_ia').maybeSingle()) as
    | { activa: boolean }
    | null;
  return !!r?.activa;
}
