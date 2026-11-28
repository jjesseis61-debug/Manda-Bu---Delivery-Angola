// Leitura automática (Claude) das fotos dos comprovativos de pagamento e dos extratos (PDF ou foto).
// Chamada de minuto a minuto por pg_cron (agendar_leitura), com o mesmo segredo do envio de avisos.
//
// - Comprovativo: lê valor, referência e data; o servidor compara com o que o estafeta escreveu
//   (registar_leitura_comprovativo -> confere / diverge / ilegivel).
// - Extrato: tira as entradas (créditos) do período; o servidor cruza-as com os comprovativos
//   (registar_leitura_extrato -> conciliar_extrato).
// É sempre um apoio: o gerente confere cada comprovativo e quem tem financas.conferir pode escrever
// as entradas do extrato à mão. Sem a chave ANTHROPIC_API_KEY os documentos ficam "indisponivel".
import Anthropic from 'npm:@anthropic-ai/sdk';
import { createClient } from 'npm:@supabase/supabase-js@2';

const MODELO = 'claude-opus-5-5';
const TEMPO_MAXIMO_MS = 110_000; // não começar leituras novas depois disto (limite da Edge Function)

type Comprovativo = { id: string; caminho: string; metodo: string; valor: number; referencia: string; dia: string };
type Extrato = { id: string; caminho: string; tipo_ficheiro: 'pdf' | 'imagem'; conta: string; inicio: string; fim: string };
type LeituraComprovativo = { legivel: boolean; valor: number | null; referencia: string | null; data: string | null; nota: string };
type Movimento = { data: string; valor: number; referencia: string | null; descricao: string };
type LeituraExtrato = { legivel: boolean; movimentos: Movimento[]; nota: string };

const textoOuNulo = { anyOf: [{ type: 'string' }, { type: 'null' }] };

const ESQUEMA_COMPROVATIVO = {
  type: 'object',
  additionalProperties: false,
  required: ['legivel', 'valor', 'referencia', 'data', 'nota'],
  properties: {
    legivel: { type: 'boolean', description: 'true só se o valor e a referência se lêem com certeza' },
    valor: { anyOf: [{ type: 'number' }, { type: 'null' }], description: 'Valor pago em kwanzas, só o número' },
    referencia: { ...textoOuNulo, description: 'Referência, n.º da transacção ou n.º do talão, tal como aparece' },
    data: { ...textoOuNulo, description: 'Data da transacção no formato AAAA-MM-DD' },
    nota: { type: 'string', description: 'Uma frase curta: o que se leu ou porque não se conseguiu ler' },
  },
};

const ESQUEMA_EXTRATO = {
  type: 'object',
  additionalProperties: false,
  required: ['legivel', 'movimentos', 'nota'],
  properties: {
    legivel: { type: 'boolean' },
    movimentos: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['data', 'valor', 'referencia', 'descricao'],
        properties: {
          data: { type: 'string', description: 'AAAA-MM-DD' },
          valor: { type: 'number', description: 'Valor recebido em kwanzas, só o número, positivo' },
          referencia: textoOuNulo,
          descricao: { type: 'string' },
        },
      },
    },
    nota: { type: 'string' },
  },
};

const SISTEMA =
  'Lês documentos de pagamentos de uma empresa de entregas de refeições em Angola (moeda: kwanza, Kz). ' +
  'Os valores vêm muitas vezes escritos como "3.000,00 Kz" ou "3 000 AOA": devolve só o número (3000). ' +
  'As datas devolvem-se no formato AAAA-MM-DD. Copia as referências exactamente como estão escritas. ' +
  'Nunca inventes nem completes dados: se não consegues ler um valor com certeza, diz que não é legível.';

function paraBase64(dados: ArrayBuffer): string {
  const bytes = new Uint8Array(dados);
  let binario = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binario += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binario);
}

function tipoImagem(caminho: string): 'image/jpeg' | 'image/png' | 'image/webp' {
  const ext = caminho.split('.').pop()?.toLowerCase();
  return ext === 'png' ? 'image/png' : ext === 'webp' ? 'image/webp' : 'image/jpeg';
}

/** Pede ao Claude a leitura com saída estruturada; devolve o JSON ou uma recusa */
async function ler<T>(
  anthropic: Anthropic,
  bloco: Record<string, unknown>,
  pedido: string,
  esquema: Record<string, unknown>,
): Promise<{ ok: true; valor: T } | { ok: false; motivo: string }> {
  const resposta = await anthropic.beta.messages.create({
    model: MODELO,
    max_tokens: 16000,
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    output_config: { effort: 'medium', format: { type: 'json_schema', schema: esquema } },
    system: SISTEMA,
    messages: [{ role: 'user', content: [bloco, { type: 'text', text: pedido }] }],
  } as never);
  // deno-lint-ignore no-explicit-any
  const r = resposta as any;
  if (r.stop_reason === 'refusal') return { ok: false, motivo: 'A leitura automática recusou este documento.' };
  if (r.stop_reason === 'max_tokens') return { ok: false, motivo: 'Documento demasiado longo para ler de uma vez.' };
  const texto = (r.content as { type: string; text?: string }[]).filter((b) => b.type === 'text').map((b) => b.text).join('');
  try {
    return { ok: true, valor: JSON.parse(texto) as T };
  } catch {
    return { ok: false, motivo: 'Resposta da leitura automática inválida.' };
  }
}

/** Como tratar uma falha: chave inválida -> indisponível; pedido inválido -> ilegível; o resto -> tentar outra vez */
function classificar(e: unknown): { resultado: 'indisponivel' | 'ilegivel' | 'erro'; nota: string } {
  if (e instanceof Anthropic.AuthenticationError || e instanceof Anthropic.PermissionDeniedError) {
    return { resultado: 'indisponivel', nota: 'Chave da leitura automática inválida: confere à mão.' };
  }
  if (e instanceof Anthropic.BadRequestError) {
    return { resultado: 'ilegivel', nota: 'O documento não pôde ser lido (formato ou tamanho).' };
  }
  return { resultado: 'erro', nota: ((e as Error)?.message ?? 'erro').slice(0, 300) };
}

Deno.serve(async (req) => {
  const inicio = Date.now();
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });

  const recebido = req.headers.get('x-envio-segredo') ?? '';
  const segredo = Deno.env.get('ENVIO_SEGREDO');
  const autorizado =
    recebido !== '' &&
    ((!!segredo && recebido === segredo) ||
      (await supabase.rpc('segredo_envio_valido', { p_segredo: recebido })).data === true);
  if (!autorizado) return Response.json({ erro: 'nao_autorizado' }, { status: 401 });

  const { data, error } = await supabase.rpc('reservar_documentos', { p_limite: 5 });
  if (error) return Response.json({ erro: error.message }, { status: 500 });
  const { comprovativos, extratos } = data as { comprovativos: Comprovativo[]; extratos: Extrato[] };
  if (comprovativos.length === 0 && extratos.length === 0) return Response.json({ comprovativos: 0, extratos: 0 });

  const registarComprovativo = (id: string, resultado: string, l: Partial<LeituraComprovativo> = {}, nota?: string) =>
    supabase.rpc('registar_leitura_comprovativo', {
      p_id: id,
      p_resultado: resultado,
      p_valor: l.valor ?? null,
      p_referencia: l.referencia ?? null,
      p_data: l.data && /^\d{4}-\d{2}-\d{2}$/.test(l.data) ? l.data : null,
      p_nota: nota ?? l.nota ?? null,
    });
  const registarExtrato = (id: string, resultado: string, movimentos: Movimento[] = [], nota?: string) =>
    supabase.rpc('registar_leitura_extrato', { p_id: id, p_resultado: resultado, p_movimentos: movimentos, p_nota: nota ?? null });

  const chave = Deno.env.get('ANTHROPIC_API_KEY');
  if (!chave) {
    // Sem leitura automática: fica tudo para a conferência humana
    const nota = 'Leitura automática não configurada: confere à mão.';
    await Promise.all([
      ...comprovativos.map((c) => registarComprovativo(c.id, 'indisponivel', {}, nota)),
      ...extratos.map((e) => registarExtrato(e.id, 'indisponivel', [], nota)),
    ]);
    return Response.json({ comprovativos: comprovativos.length, extratos: extratos.length, indisponivel: true });
  }
  const anthropic = new Anthropic({ apiKey: chave, maxRetries: 1 });

  async function descarregar(bucket: string, caminho: string): Promise<string> {
    const { data: ficheiro, error: e } = await supabase.storage.from(bucket).download(caminho);
    if (e || !ficheiro) throw new Error(`ficheiro: ${e?.message ?? 'não encontrado'}`);
    return paraBase64(await ficheiro.arrayBuffer());
  }

  const resultados: Record<string, string> = {};

  // Comprovativos em paralelo (são pequenos)
  await Promise.all(
    comprovativos.map(async (c) => {
      try {
        const imagem = await descarregar('comprovativos', c.caminho);
        const r = await ler<LeituraComprovativo>(
          anthropic,
          { type: 'image', source: { type: 'base64', media_type: tipoImagem(c.caminho), data: imagem } },
          `Esta é a foto do comprovativo de um pagamento por ${c.metodo} (talão de TPA, ecrã do Multicaixa Express, ` +
            'Unitel Money ou de uma transferência). Lê o valor pago, a referência da transacção e a data.',
          ESQUEMA_COMPROVATIVO,
        );
        if (!r.ok) {
          await registarComprovativo(c.id, 'ilegivel', {}, r.motivo);
          resultados[c.id] = 'ilegivel';
        } else if (!r.valor.legivel || r.valor.valor === null) {
          await registarComprovativo(c.id, 'ilegivel', r.valor);
          resultados[c.id] = 'ilegivel';
        } else {
          const { data: estado } = await registarComprovativo(c.id, 'lido', r.valor);
          resultados[c.id] = String(estado);
        }
      } catch (e) {
        // falha passageira (rede, limite de pedidos): o servidor tenta mais tarde (até 3 vezes)
        const f = classificar(e);
        await registarComprovativo(c.id, f.resultado, {}, f.nota);
        resultados[c.id] = f.resultado;
      }
    }),
  );

  for (const e of extratos) {
    if (Date.now() - inicio > TEMPO_MAXIMO_MS) {
      await registarExtrato(e.id, 'erro', [], 'Sem tempo nesta execução; volta a tentar.');
      continue;
    }
    try {
      const dados = await descarregar('extratos', e.caminho);
      const bloco =
        e.tipo_ficheiro === 'pdf'
          ? { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: dados } }
          : { type: 'image', source: { type: 'base64', media_type: tipoImagem(e.caminho), data: dados } };
      const r = await ler<LeituraExtrato>(
        anthropic,
        bloco,
        `Extrato da conta "${e.conta}", de ${e.inicio} a ${e.fim}. Lista só as ENTRADAS (créditos: dinheiro recebido), ` +
          'uma por linha do extrato, com a data, o valor, a referência (se houver) e a descrição. ' +
          'Ignora saídas, débitos, comissões e saldos.',
        ESQUEMA_EXTRATO,
      );
      if (!r.ok) {
        await registarExtrato(e.id, 'ilegivel', [], r.motivo);
        resultados[e.id] = 'ilegivel';
      } else if (!r.valor.legivel) {
        await registarExtrato(e.id, 'ilegivel', [], r.valor.nota);
        resultados[e.id] = 'ilegivel';
      } else {
        const movimentos = r.valor.movimentos.filter((m) => m.valor > 0 && /^\d{4}-\d{2}-\d{2}$/.test(m.data));
        await registarExtrato(e.id, 'lido', movimentos, r.valor.nota);
        resultados[e.id] = `lido:${movimentos.length}`;
      }
    } catch (err) {
      const f = classificar(err);
      await registarExtrato(e.id, f.resultado, [], f.nota);
      resultados[e.id] = f.resultado;
    }
  }

  return Response.json({ comprovativos: comprovativos.length, extratos: extratos.length, resultados });
});
