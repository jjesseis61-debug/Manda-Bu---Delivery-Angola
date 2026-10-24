import { useRouter } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Text, View } from 'react-native';

import { formatarDia, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { CasoAgente } from '@/lib/tipos';

import { ACarregar, Aviso, Botao, Campo, Cartao, Escolha, Linha, Paragrafo, Subtitulo } from './ui';

const DIA = /^\d{4}-\d{2}-\d{2}$/;
const nomeRisco = { baixo: 'Risco baixo', medio: 'Risco médio', alto: 'Risco alto' } as const;
const nomeDecisao = {
  sem_problema: 'Sem problema',
  erro_operacional: 'Erro operacional',
  suspeita_confirmada: 'Suspeita confirmada',
} as const;
const nomeFerramenta: Record<string, string> = {
  comprovativos_do_funcionario: 'Viu os comprovativos',
  caixas_do_funcionario: 'Viu as caixas',
  historico_do_pedido: 'Abriu o histórico de um pedido',
  entradas_do_extrato_parecidas: 'Procurou entradas parecidas no extrato',
  procurar_referencia: 'Procurou a referência noutros pagamentos',
  comparar_com_a_equipa: 'Comparou com a equipa',
  indicados_do_indicador: 'Viu os indicados',
  pedidos_do_indicado: 'Abriu os pedidos de um indicado',
  levantamentos: 'Viu os levantamentos',
  rede: 'Viu a rede de indicações',
  comparar_indicadores: 'Comparou com os outros indicadores',
};

export type OpcoesCasos<C extends CasoAgente> = {
  /** Texto de abertura (o que o agente faz) */
  descricao: string;
  carregar: () => Promise<C[]>;
  abrir: (inicio: string, fim: string) => Promise<number>;
  decidir: (id: string, decisao: string, nota: string) => Promise<void>;
  deNovo: (id: string) => Promise<void>;
  /** Quem é (nome e, se houver, cargo ou código) */
  titulo: (c: C) => string;
  /** Uma linha com os sinais */
  sinais: (c: C) => string;
  /** Primeiro nome de quem se pergunta (ou null para "O que confirmar") */
  perguntarA: (c: C) => string | null;
  textoAbrir: string;
};

/**
 * Casos de um agente (Claude com ferramentas só de leitura): o investigador financeiro e o vigilante do Convida e
 * Ganha. O agente junta os factos e propõe o risco; uma pessoa lê o dossiê, vê o que o agente consultou e decide.
 */
export function CasosAgente<C extends CasoAgente>({
  inicioPadrao,
  fimPadrao,
  opcoes,
}: {
  inicioPadrao: string;
  fimPadrao: string;
  opcoes: OpcoesCasos<C>;
}) {
  const router = useRouter();
  const [casos, setCasos] = useState<C[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [periodo, setPeriodo] = useState({ inicio: inicioPadrao, fim: fimPadrao });
  const [aberto, setAberto] = useState<string | null>(null);
  const [decisao, setDecisao] = useState<{ tipo: keyof typeof nomeDecisao; nota: string }>({ tipo: 'erro_operacional', nota: '' });

  const carregar = useCallback(() => {
    opcoes.carregar().then(setCasos, (e) => setErro(mensagemErro(e)));
  }, [opcoes]);
  useEffect(carregar, [carregar]);

  async function correr(f: () => Promise<unknown>, mensagem?: string) {
    setErro(null);
    setSucesso(null);
    setOcupado(true);
    try {
      await f();
      if (mensagem) setSucesso(mensagem);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  const abrir = () =>
    correr(async () => {
      const n = await opcoes.abrir(periodo.inicio, periodo.fim);
      setSucesso(n === 0 ? 'Ninguém com sinais suficientes neste período.' : `${n} caso(s) aberto(s). O agente investiga nos próximos minutos.`);
    });

  function cartao(c: C) {
    const expandido = aberto === c.id;
    return (
      <Cartao key={c.id}>
        <Text style={{ fontWeight: '700' }}>{opcoes.titulo(c)}</Text>
        <Text style={{ color: cores.textoSuave }}>
          {formatarDia(c.inicio)} a {formatarDia(c.fim)} · {c.pontuacao} pontos de sinais
        </Text>
        <Text>{opcoes.sinais(c)}</Text>
        {c.estado === 'investigado' && c.risco ? (
          <Aviso tipo={c.risco === 'alto' ? 'erro' : c.risco === 'medio' ? 'aviso' : 'sucesso'}>
            {nomeRisco[c.risco]}: {c.resumo}
          </Aviso>
        ) : c.estado === 'indisponivel' ? (
          <Aviso>Agente indisponível{c.ia_nota ? ` (${c.ia_nota})` : ''}: investiga à mão com o fecho do mês.</Aviso>
        ) : (
          <Paragrafo suave>O agente ainda está a investigar…</Paragrafo>
        )}
        {c.decisao ? (
          <Text style={{ fontWeight: '700' }}>
            {nomeDecisao[c.decisao]} · por {c.decidido_por ?? '—'}: {c.decisao_nota}
          </Text>
        ) : (
          <Botao titulo={expandido ? 'Fechar' : 'Ver dossiê e decidir'} variante="texto" aoCarregar={() => setAberto(expandido ? null : c.id)} />
        )}
        {expandido && (
          <View style={{ gap: espaco.s }}>
            {c.conclusao && (
              <>
                <Subtitulo>Factos</Subtitulo>
                {c.conclusao.factos.map((f, i) => (
                  <View key={i}>
                    <Text>• {f.texto}</Text>
                    {f.pedido_id && (
                      <Botao
                        titulo="Histórico do pedido"
                        variante="texto"
                        aoCarregar={() => router.push({ pathname: '/pedido/[id]', params: { id: f.pedido_id as string } })}
                      />
                    )}
                  </View>
                ))}
                <Subtitulo>Explicações possíveis</Subtitulo>
                {c.conclusao.explicacoes_possiveis.map((t, i) => <Text key={i}>• {t}</Text>)}
                <Subtitulo>{opcoes.perguntarA(c) ? `Perguntar a ${opcoes.perguntarA(c)}` : 'O que confirmar'}</Subtitulo>
                {c.conclusao.perguntas_ao_funcionario.map((t, i) => <Text key={i}>• {t}</Text>)}
                <Linha esquerda="Recomendação" direita="" />
                <Text>{c.conclusao.recomendacao}</Text>
              </>
            )}
            {c.passos.length > 0 && (
              <>
                <Subtitulo>O que o agente consultou</Subtitulo>
                {c.passos.map((p, i) => (
                  <Text key={i} style={{ color: cores.textoSuave }}>
                    {i + 1}. {nomeFerramenta[p.ferramenta] ?? p.ferramenta}
                  </Text>
                ))}
              </>
            )}
            <Subtitulo>Decisão</Subtitulo>
            <Escolha
              opcoes={(Object.keys(nomeDecisao) as (keyof typeof nomeDecisao)[]).map((k) => ({ valor: k, rotulo: nomeDecisao[k] }))}
              valor={decisao.tipo}
              aoMudar={(v) => setDecisao({ ...decisao, tipo: v })}
            />
            <Campo
              rotulo="Nota (o que se confirmou)"
              value={decisao.nota}
              onChangeText={(t) => setDecisao({ ...decisao, nota: t })}
              maxLength={500}
              multiline
            />
            <Botao
              titulo="Guardar decisão"
              desactivado={decisao.nota.trim().length < 5}
              aCarregar={ocupado}
              aoCarregar={() =>
                correr(async () => {
                  await opcoes.decidir(c.id, decisao.tipo, decisao.nota.trim());
                  setAberto(null);
                  setDecisao({ tipo: 'erro_operacional', nota: '' });
                }, 'Decisão guardada.')
              }
            />
            <Botao
              titulo="Investigar de novo"
              variante="secundario"
              aoCarregar={() => correr(() => opcoes.deNovo(c.id), 'O agente volta a investigar com os dados de hoje.')}
            />
          </View>
        )}
      </Cartao>
    );
  }

  return (
    <>
      <Paragrafo suave>{opcoes.descricao}</Paragrafo>
      <Campo rotulo="De (AAAA-MM-DD)" value={periodo.inicio} onChangeText={(t) => setPeriodo({ ...periodo, inicio: t })} maxLength={10} />
      <Campo rotulo="Até (AAAA-MM-DD)" value={periodo.fim} onChangeText={(t) => setPeriodo({ ...periodo, fim: t })} maxLength={10} />
      <Botao
        titulo={opcoes.textoAbrir}
        desactivado={!DIA.test(periodo.inicio) || !DIA.test(periodo.fim)}
        aCarregar={ocupado}
        aoCarregar={abrir}
      />
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
      {casos === null ? (
        <ACarregar />
      ) : casos.length === 0 ? (
        <Paragrafo suave>Sem casos abertos.</Paragrafo>
      ) : (
        casos.map(cartao)
      )}
    </>
  );
}
