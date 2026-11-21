import { supabase } from './supabase';

function verificar<T>(r: { data: T | null; error: { message: string } | null }): T {
  if (r.error) throw r.error;
  return r.data as T;
}

/** Tipos de contrato (Lei Geral do Trabalho, Lei n.º 12/23) */
export const TIPOS_CONTRATO = [
  { valor: 'indeterminado', rotulo: 'Sem prazo (tempo indeterminado)' },
  { valor: 'termo_certo', rotulo: 'A prazo certo' },
  { valor: 'termo_incerto', rotulo: 'A prazo incerto' },
  { valor: 'tempo_parcial', rotulo: 'Tempo parcial' },
  { valor: 'temporario', rotulo: 'Trabalho temporário' },
  { valor: 'estagio', rotulo: 'Estágio profissional' },
  { valor: 'teletrabalho', rotulo: 'Teletrabalho' },
  { valor: 'prestacao_servicos', rotulo: 'Prestação de serviços (fora da folha)' },
] as const;
export type TipoContrato = (typeof TIPOS_CONTRATO)[number]['valor'];
export const nomeContrato = (t: string | null | undefined) => TIPOS_CONTRATO.find((x) => x.valor === t)?.rotulo ?? '—';
/** Período experimental por defeito: 60 dias sem prazo; 30 a prazo (máximo legal); nada na prestação de serviços */
export const experimentalPadrao = (t: TipoContrato) =>
  t === 'prestacao_servicos' ? 0 : t === 'termo_certo' || t === 'termo_incerto' || t === 'temporario' ? 30 : 60;

export const TIPOS_DOCUMENTO = [
  { valor: 'bi', rotulo: 'Bilhete de identidade' },
  { valor: 'nif', rotulo: 'NIF' },
  { valor: 'cartao_inss', rotulo: 'Cartão da Segurança Social' },
  { valor: 'carta_conducao', rotulo: 'Carta de condução' },
  { valor: 'livrete_mota', rotulo: 'Livrete da mota' },
  { valor: 'seguro_mota', rotulo: 'Seguro da mota' },
  { valor: 'declaracao_saude', rotulo: 'Declaração de saúde (manuseio de alimentos)' },
  { valor: 'registo_criminal', rotulo: 'Registo criminal' },
  { valor: 'contrato_assinado', rotulo: 'Contrato assinado' },
  { valor: 'outro', rotulo: 'Outro' },
] as const;
export const nomeDocumento = (t: string) => TIPOS_DOCUMENTO.find((x) => x.valor === t)?.rotulo ?? t;

export const TIPOS_EQUIPAMENTO = [
  { valor: 'mota', rotulo: 'Mota' },
  { valor: 'capacete', rotulo: 'Capacete' },
  { valor: 'colete', rotulo: 'Colete' },
  { valor: 'caixa_termica', rotulo: 'Caixa térmica' },
  { valor: 'uniforme', rotulo: 'Uniforme' },
  { valor: 'telemovel', rotulo: 'Telemóvel' },
  { valor: 'outro', rotulo: 'Outro' },
] as const;
export const nomeEquipamento = (t: string) => TIPOS_EQUIPAMENTO.find((x) => x.valor === t)?.rotulo ?? t;
export const PROPRIEDADES = [
  { valor: 'empresa', rotulo: 'Da empresa' },
  { valor: 'servico_contratado', rotulo: 'Do serviço contratado' },
  { valor: 'trabalhador', rotulo: 'Do trabalhador' },
] as const;

export type ResumoContrato = { tipo: TipoContrato; inicio: string; fim: string | null; salario_base: number };
export type PessoaRH = {
  funcionario_id: string;
  nome: string;
  cargo: string | null;
  telefone: string | null;
  admissao: string;
  contrato: ResumoContrato | null;
  equipamentos: number;
  alertas: string[];
};
export type Ficha = {
  bi: string | null;
  nif: string | null;
  inss_numero: string | null;
  data_nascimento: string | null;
  morada: string | null;
  banco: string | null;
  iban: string | null;
  emergencia_nome: string | null;
  emergencia_telefone: string | null;
  data_admissao: string | null;
  notas: string | null;
};
export type Documento = { id: string; tipo: string; numero: string | null; validade: string | null; notas: string | null };
export type Contrato = {
  id: string;
  tipo: TipoContrato;
  funcao: string | null;
  inicio: string;
  fim: string | null;
  periodo_experimental_dias: number;
  horas_semana: number | null;
  salario_base: number;
  subsidio_alimentacao: number;
  subsidio_transporte: number;
  outros_subsidios: number;
  activo: boolean;
  terminado_em: string | null;
  motivo_fim: string | null;
};
export type Equipamento = {
  id: string;
  tipo: string;
  descricao: string | null;
  matricula: string | null;
  propriedade: 'empresa' | 'trabalhador' | 'servico_contratado';
  entregue_em: string;
  devolvido_em: string | null;
  estado_devolucao: string | null;
};
export type FichaCompleta = {
  funcionario_id: string;
  nome: string;
  cargo: string | null;
  telefone: string | null;
  ficha: Ficha | null;
  documentos: Documento[];
  contratos: Contrato[];
  equipamentos: Equipamento[];
  alertas: string[];
};
export type Calculo = {
  bruto: number;
  inss_trabalhador: number;
  inss_empresa: number;
  isento: number;
  materia_colectavel: number;
  irt: number;
  liquido: number;
  custo_empresa: number;
};
export type LinhaFolha = {
  funcionario_id: string;
  nome: string;
  tipo: TipoContrato | null;
  dias: number;
  salario_base: number;
  sub_alimentacao: number;
  sub_transporte: number;
  outros_subsidios: number;
  extras: number;
  sub_ferias: number;
  sub_natal: number;
  descontos: number;
  bruto: number;
  inss_trabalhador: number;
  inss_empresa: number;
  materia_colectavel: number;
  irt: number;
  liquido: number;
  nota: string | null;
  pago_em: string | null;
  metodo: string | null;
  referencia: string | null;
};
export type Folha = {
  mes: string;
  fechada: boolean;
  pode_fechar: boolean;
  linhas: LinhaFolha[];
  totais: { bruto: number; inss_trabalhador: number; inss_empresa: number; irt: number; liquido: number; custo_empresa: number; por_pagar: number };
  prestadores: { nome: string; funcao: string | null }[];
};
export type Escalao = { ordem?: number; limite_inferior: number; limite_superior: number | null; parcela_fixa: number; taxa: number; excesso: number };
export type ParametrosRH = {
  parametros: {
    inss_trabalhador: number;
    inss_empresa: number;
    isencao_alimentacao: number;
    isencao_transporte: number;
    subsidio_ferias_pct: number;
    subsidio_natal_pct: number;
    referencia_legal: string;
    atualizado_em: string;
  };
  escaloes: Escalao[];
};

export const rhLista = async () => verificar<PessoaRH[]>(await supabase.rpc('rh_lista'));
export const rhFicha = async (id: string) => verificar<FichaCompleta>(await supabase.rpc('rh_ficha', { p_func: id }));
export const rhGuardarFicha = async (id: string, f: Partial<Ficha>) =>
  verificar(await supabase.rpc('rh_guardar_ficha', { p_func: id, p: f }));
export const rhGuardarDocumento = async (d: { funcionario_id: string; tipo: string; numero: string | null; validade: string | null }) =>
  verificar(await supabase.rpc('rh_guardar_documento', { p: d }));
export const rhApagarDocumento = async (id: string) => verificar(await supabase.rpc('rh_apagar_documento', { p_id: id }));
export const rhGuardarContrato = async (c: Record<string, unknown>) => verificar(await supabase.rpc('rh_guardar_contrato', { p: c }));
export const rhTerminarContrato = async (id: string, data: string, motivo: string | null) =>
  verificar(await supabase.rpc('rh_terminar_contrato', { p_id: id, p_data: data, p_motivo: motivo }));
export const rhGuardarEquipamento = async (e: Record<string, unknown>) => verificar(await supabase.rpc('rh_guardar_equipamento', { p: e }));
export const rhDevolverEquipamento = async (id: string, estado: string | null) =>
  verificar(await supabase.rpc('rh_devolver_equipamento', { p_id: id, p_estado: estado }));
export const rhSimular = async (base: number, alim: number, transp: number, outros: number) =>
  verificar<Calculo>(await supabase.rpc('rh_simular_salario', { p_base: base, p_alim: alim, p_transp: transp, p_outros: outros }));
export const rhFolha = async (mes: string) => verificar<Folha>(await supabase.rpc('rh_folha', { p_mes: mes }));
export const rhFolhaAjustar = async (mes: string, func: string, a: { extras: number; descontos: number; subFerias: boolean; subNatal: boolean; nota: string | null }) =>
  verificar(
    await supabase.rpc('rh_folha_ajustar', {
      p_mes: mes, p_func: func, p_extras: a.extras, p_descontos: a.descontos, p_sub_ferias: a.subFerias, p_sub_natal: a.subNatal, p_nota: a.nota,
    }),
  );
export const rhFolhaFechar = async (mes: string) => verificar<number>(await supabase.rpc('rh_folha_fechar', { p_mes: mes }));
export const rhFolhaPagar = async (mes: string, func: string, metodo: string, referencia: string | null) =>
  verificar<number>(await supabase.rpc('rh_folha_pagar', { p_mes: mes, p_func: func, p_metodo: metodo, p_referencia: referencia }));
export const rhParametros = async () => verificar<ParametrosRH>(await supabase.rpc('rh_parametros_ler'));
export const rhGuardarParametros = async (p: Record<string, unknown>) => verificar(await supabase.rpc('rh_parametros_guardar', { p }));

/** "AAAA-MM-DD" válido (ou vazio) */
export const dataValida = (t: string) => t.trim() === '' || /^\d{4}-\d{2}-\d{2}$/.test(t.trim());
