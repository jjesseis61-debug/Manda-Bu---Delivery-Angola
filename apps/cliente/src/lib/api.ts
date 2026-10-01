// Chamadas ao servidor. Todos os valores (preços, descontos, ganhos, saldos) vêm daqui:
// a app só mostra o que o servidor devolve.
import { dispositivoId } from './dispositivo';
import { supabase } from './supabase';
import type {
  Amigo,
  AvaliacaoPublica,
  Destaque,
  Endereco,
  GrupoDetalhe,
  Funcionalidades,
  ItemCardapio,
  Levantamento,
  MediasAvaliacoes,
  MeuGrupo,
  MinhaPosicao,
  Orcamento,
  Parametros,
  Pedido,
  Perfil,
  PerfilDestaques,
  PreferenciasNotificacao,
  PessoaComoTu,
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
export async function lerCardapio(): Promise<ItemCardapio[]> {
  const r = await supabase
    .from('cardapio')
    .select('id, nome, descricao, categoria, preco, foto_url, do_dia, cozinha_id, prato_base_id')
    .eq('disponivel', true)
    .order('do_dia', { ascending: false })
    .order('ordem')
    .order('nome');
  return verificar(r) as ItemCardapio[];
}

export type Cozinha = { id: string; nome: string; foto_url: string | null; historia: string | null };

/** Só devolve cozinhas com consentimento público (RLS) */
export async function lerCozinhaPublica(): Promise<Cozinha | null> {
  const r = await supabase.from('cozinhas').select('id, nome, foto_url, historia').eq('estado', 'activa').limit(1);
  return ((verificar(r) as Cozinha[])[0] ?? null) as Cozinha | null;
}

// ---------------------------------------------------------------- avaliações (C9, C10)
/** Médias da cozinha e dos pratos; o servidor só devolve com o mínimo de avaliações */
export async function mediasAvaliacoes(cozinhaId: string): Promise<MediasAvaliacoes | null> {
  return verificar(await supabase.rpc('medias_avaliacoes', { p_cozinha: cozinhaId })) as MediasAvaliacoes | null;
}

export async function avaliacoesPublicas(cozinhaId: string, pratoId?: string | null): Promise<AvaliacaoPublica[]> {
  return verificar(
    await supabase.rpc('avaliacoes_publicas', { p_cozinha: cozinhaId, p_prato: pratoId ?? null, p_limite: 50 }),
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
}): Promise<void> {
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
export type ItemCarrinho = { cardapio_id: string; qtd: number };

export async function orcamento(itens: ItemCarrinho[], pontoEntregaId: string | null, grupoId?: string | null): Promise<Orcamento> {
  return verificar(
    await supabase.rpc('orcamento_pedido', { p_itens: itens, p_ponto_entrega: pontoEntregaId, p_grupo: grupoId ?? null }),
  ) as Orcamento;
}

/** O servidor recalcula itens, preços, taxa e desconto; devolve o id do pedido */
export async function criarPedido(dados: {
  clienteId: string;
  pontoEntregaId: string | null;
  grupoId?: string | null;
  itens: ItemCarrinho[];
  observacoes: string;
}): Promise<string> {
  const r = await supabase
    .from('pedidos')
    .insert({
      cliente_id: dados.clienteId,
      ponto_entrega_id: dados.pontoEntregaId,
      grupo_id: dados.grupoId ?? null,
      itens: dados.itens,
      observacoes: dados.observacoes.trim() || null,
      dispositivo_id: await dispositivoId(),
    })
    .select('id')
    .single();
  return (verificar(r) as { id: string }).id;
}

export async function usarCredito(pedidoId: string, valor: number): Promise<number> {
  return verificar(await supabase.rpc('usar_credito', { p_pedido: pedidoId, p_valor: valor })) as number;
}

export async function cancelarPedido(pedidoId: string): Promise<void> {
  verificar(await supabase.rpc('cancelar_pedido', { p_pedido: pedidoId, p_motivo: 'Cancelado pelo cliente na app' }));
}

const camposPedido =
  'id, criado_em, estado, itens, subtotal, taxa_entrega, desconto_indicacao, credito_indicacao_usado, observacoes, motivo_cancelamento, hora_prometida, entregue_em';

export async function lerPedidos(): Promise<Pedido[]> {
  const r = await supabase.from('pedidos').select(camposPedido).order('criado_em', { ascending: false }).limit(50);
  return verificar(r) as Pedido[];
}

export async function lerPedido(id: string): Promise<Pedido | null> {
  return verificar(await supabase.from('pedidos').select(camposPedido).eq('id', id).maybeSingle()) as Pedido | null;
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
}): Promise<string> {
  const r = await supabase
    .from('pedidos_grupo')
    .insert({
      ponto_entrega_id: dados.pontoEntregaId,
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
