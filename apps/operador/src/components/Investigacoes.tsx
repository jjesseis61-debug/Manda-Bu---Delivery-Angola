import { CasosAgente, type OpcoesCasos } from './CasosAgente';
import { abrirInvestigacoes, decidirCaso, investigarDeNovo, lerCasosInvestigacao } from '@/lib/api';
import { formatarKz } from '@/lib/formatar';
import type { CasoInvestigacao } from '@/lib/tipos';

const opcoes: OpcoesCasos<CasoInvestigacao> = {
  descricao:
    'O agente investiga quem tem sinais no período (rejeitados, fotos que não conferem, pagamentos sem extrato, caixas com ' +
    'diferença). Só lê dados: não acusa nem bloqueia ninguém. Quem decide és tu.',
  carregar: lerCasosInvestigacao,
  abrir: abrirInvestigacoes,
  decidir: decidirCaso,
  deNovo: investigarDeNovo,
  titulo: (c) => `${c.funcionario}${c.cargo ? ` · ${c.cargo}` : ''}`,
  sinais: (c) =>
    `${c.sinais.rejeitados} rejeitados · ${c.sinais.nao_conferem} não conferem com a foto · ${c.sinais.sem_extrato} sem extrato ` +
    `(${formatarKz(c.sinais.valor_sem_extrato)}) · ${c.sinais.caixas_com_diferenca} caixas com diferença`,
  perguntarA: (c) => c.funcionario.split(' ')[0],
  textoAbrir: 'Abrir investigações do período',
};

/** Investigações do agente investigador financeiro (Conferência → Investigações). Ninguém vê o próprio caso. */
export function Investigacoes({ inicioPadrao, fimPadrao }: { inicioPadrao: string; fimPadrao: string }) {
  return <CasosAgente inicioPadrao={inicioPadrao} fimPadrao={fimPadrao} opcoes={opcoes} />;
}
