// Datas no formato de Angola (DD/MM/AAAA) nos campos; o servidor continua a receber AAAA-MM-DD.

const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

/** 'AAAA-MM-DD' (ou ISO completo) -> 'DD/MM/AAAA'; '' se vazio */
export function isoParaDDMM(iso: string | null | undefined): string {
  if (!iso) return '';
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : '';
}

/** 'DD/MM/AAAA' -> 'AAAA-MM-DD' se for uma data real do calendário; senão null */
export function ddmmParaIso(texto: string): string | null {
  const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(texto.trim());
  if (!m) return null;
  const [d, mes, a] = [Number(m[1]), Number(m[2]), Number(m[3])];
  if (a < 1900 || a > 2100) return null;
  const dt = new Date(Date.UTC(a, mes - 1, d));
  if (dt.getUTCFullYear() !== a || dt.getUTCMonth() !== mes - 1 || dt.getUTCDate() !== d) return null;
  return `${m[3]}-${m[2]}-${m[1]}`;
}

/** '2026-03-11' -> '11 de março de 2026' */
export function dataPorExtenso(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  if (!m) return '';
  return `${Number(m[3])} de ${MESES[Number(m[2]) - 1]} de ${m[1]}`;
}

/** Hoje em Luanda, 'AAAA-MM-DD' */
export function hojeIso(agora: Date = new Date()): string {
  return new Date(agora.getTime() + 3600_000).toISOString().slice(0, 10);
}

/** Anos completos entre duas datas ISO */
export function anosEntre(de: string, ate: string): number {
  const [a1, m1, d1] = de.split('-').map(Number);
  const [a2, m2, d2] = ate.split('-').map(Number);
  return a2 - a1 - (m2 < m1 || (m2 === m1 && d2 < d1) ? 1 : 0);
}

/** 'HH:MM' válida (00:00 a 23:59) */
export const horaValida = (t: string) => /^([01]\d|2[0-3]):[0-5]\d$/.test(t);

/** Mês 'AAAA-MM' ao lado (+1 / −1) */
export function mesVizinho(mes: string, n: number): string {
  const [a, m] = mes.split('-').map(Number);
  const d = new Date(Date.UTC(a, m - 1 + n, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}

/** 'AAAA-MM' -> 'outubro de 2026' */
export function nomeDoMes(mes: string): string {
  const [a, m] = mes.split('-').map(Number);
  return m >= 1 && m <= 12 ? `${MESES[m - 1]} de ${a}` : mes;
}

// ------------------------------------------------------------ documentos angolanos

/** BI angolano: 9 algarismos, 2 letras, 3 algarismos (ex.: 001234567LA041) */
export const biValido = (t: string) => /^\d{9}[A-Z]{2}\d{3}$/.test(t.trim().toUpperCase());
/** NIF: o das pessoas singulares é o n.º do BI; empresas têm 10 algarismos */
export const nifValido = (t: string) => biValido(t) || /^\d{10}$/.test(t.trim());
/** IBAN angolano: AO06 + 21 algarismos (25 caracteres) */
export const ibanValido = (t: string) => /^AO06\d{21}$/.test(t.replace(/\s/g, '').toUpperCase());
/** IBAN em grupos de 4 para ler: 'AO06 0040 0000 ...' */
export const ibanAgrupado = (t: string) =>
  t.replace(/\s/g, '').toUpperCase().replace(/(.{4})/g, '$1 ').trim();
/** Telefone angolano: 9 algarismos começados por 9 (aceita +244 / 244 à frente) */
export const telefoneAngolaValido = (t: string) => /^(\+?244)?9\d{8}$/.test(t.replace(/[\s-]/g, ''));
