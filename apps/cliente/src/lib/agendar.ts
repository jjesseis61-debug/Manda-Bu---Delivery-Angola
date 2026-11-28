// Faixas de horário para agendar a entrega (sem date-picker nativo): meias-horas nas horas de
// refeição, nos próximos dias, começando pelo menos ~1 hora a partir de agora.
export type FaixaAgendamento = { valor: string; rotulo: string };

const HORAS_REFEICAO = [11, 11.5, 12, 12.5, 13, 13.5, 14, 18, 18.5, 19, 19.5, 20, 20.5];

function rotuloDia(d: Date, agora: Date): string {
  const hoje = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate());
  const dia = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const difDias = Math.round((dia.getTime() - hoje.getTime()) / 86_400_000);
  if (difDias === 0) return 'Hoje';
  if (difDias === 1) return 'Amanhã';
  return d.toLocaleDateString('pt-PT', { weekday: 'short', day: '2-digit', month: '2-digit' });
}

/** Próximas faixas disponíveis (máx. `max`), a partir de agora + 60 min, até 7 dias. */
export function faixasAgendamento(agora = new Date(), max = 12): FaixaAgendamento[] {
  const minimo = new Date(agora.getTime() + 60 * 60 * 1000);
  const faixas: FaixaAgendamento[] = [];
  for (let dia = 0; dia < 7 && faixas.length < max; dia++) {
    const base = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate() + dia);
    for (const h of HORAS_REFEICAO) {
      const d = new Date(base);
      d.setHours(Math.floor(h), (h % 1) * 60, 0, 0);
      if (d > minimo) {
        const hh = String(d.getHours()).padStart(2, '0');
        const mm = String(d.getMinutes()).padStart(2, '0');
        faixas.push({ valor: d.toISOString(), rotulo: `${rotuloDia(d, agora)} ${hh}:${mm}` });
        if (faixas.length >= max) break;
      }
    }
  }
  return faixas;
}

/** "Hoje 12:30" a partir de uma data ISO (para mostrar o agendamento no pedido) */
export function rotuloAgendamento(iso: string, agora = new Date()): string {
  const d = new Date(iso);
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  return `${rotuloDia(d, agora)} ${hh}:${mm}`;
}
