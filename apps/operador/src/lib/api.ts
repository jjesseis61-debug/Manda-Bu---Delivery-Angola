// Chamadas ao servidor da app do operador. Cada função do servidor verifica a
// permissão do organograma; a app só esconde o que o funcionário não pode usar.
import { supabase } from './supabase';
import type {
  Caixa,
  ComentarioModeracao,
  Cozinha,
  Embaixador,
  Funcionario,
  GanhoVerificacao,
  LevantamentoOperador,
  MetricaTurno,
  Painel,
  PalavraFiltrada,
  Periodo,
  PedidoOperador,
  PratoCardapio,
  Reconhecimento,
  Relatorio,
  TipoReconhecimento,
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

export async function alterarParametros(valores: Record<string, number | string>) {
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
      .select('id, nome, responsavel, foto_url, historia, estado, consentimento_publico')
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
      .select('id, cozinha_id, nome, descricao, categoria, preco, disponivel, do_dia, ordem')
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

// ---------------------------------------------------------------- O9
export async function relatorioCozinha(cozinhaId: string, inicio: string, fim: string): Promise<Relatorio> {
  return verificar(
    await supabase.rpc('relatorio_cozinha', { p_cozinha: cozinhaId, p_inicio: inicio, p_fim: fim }),
  ) as Relatorio;
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

export async function mudarEstado(
  pedidoId: string,
  estado: string,
  extra: { motivo?: string; caixa?: string; parcelas?: { metodo: string; valor: number }[] } = {},
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
