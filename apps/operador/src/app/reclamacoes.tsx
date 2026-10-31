import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { decidirReclamacao, lerReclamacoes, pedirNovaAnalise, relatorioReclamacoes } from '@/lib/api';
import { diaLuanda, formatarKz, mensagemErro, nomeCategoria, nomeCompensacao, textoAnalise } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { Reclamacao, RelatorioReclamacoes } from '@/lib/tipos';

type Separador = 'abertas' | 'resolvidas' | 'mes';
type Decisao = { procedente: 'sim' | 'nao'; resposta: string; compensacao: string; valor: string };
const MES = /^\d{4}-\d{2}$/;
const COM_VALOR = ['desconto', 'reembolso_parcial', 'reembolso_total'];

/** Reclamações: os factos do pedido, a análise automática (só um apoio) e a resposta do gerente */
export default function Reclamacoes() {
  const router = useRouter();
  const [sep, setSep] = useState<Separador>('abertas');
  const [lista, setLista] = useState<Reclamacao[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [aberta, setAberta] = useState<string | null>(null);
  const [decisao, setDecisao] = useState<Decisao>({ procedente: 'sim', resposta: '', compensacao: 'nenhuma', valor: '' });
  const [mes, setMes] = useState(diaLuanda().slice(0, 7));
  const [relatorio, setRelatorio] = useState<RelatorioReclamacoes | null>(null);

  const carregar = useCallback(
    (s: Separador = sep) => {
      if (s === 'mes') return;
      setLista(null);
      lerReclamacoes(s === 'abertas' ? 'aberta' : 'resolvida').then(setLista, (e) => setErro(mensagemErro(e)));
    },
    [sep],
  );
  useFocusEffect(useCallback(() => carregar(), [carregar]));

  async function correr(f: () => Promise<unknown>, mensagem?: string) {
    setErro(null);
    setSucesso(null);
    setOcupado(true);
    try {
      await f();
      if (mensagem) setSucesso(mensagem);
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  function mudarSeparador(s: Separador) {
    setSep(s);
    setAberta(null);
    carregar(s);
  }

  function abrir(r: Reclamacao) {
    if (aberta === r.id) return setAberta(null);
    setAberta(r.id);
    setDecisao({
      procedente: r.ia_procedente === 'nao' ? 'nao' : 'sim',
      resposta: r.ia_resposta ?? '',
      compensacao: r.ia_compensacao ?? 'nenhuma',
      valor: '',
    });
  }

  const responder = (r: Reclamacao) =>
    correr(async () => {
      const valor = COM_VALOR.includes(decisao.compensacao) && decisao.valor ? Number(decisao.valor) : null;
      await decidirReclamacao(r.id, decisao.procedente === 'sim', decisao.resposta.trim(), null, decisao.compensacao, valor);
      setAberta(null);
      carregar();
    }, 'Resposta enviada ao cliente.');

  function factos(r: Reclamacao) {
    const p = r.factos.pedido;
    if (!p) return null;
    return (
      <View style={{ gap: espaco.xs }}>
        <Text style={{ color: cores.textoSuave }}>
          {p.itens.map((i) => `${i.qtd}× ${i.nome}`).join(', ')} · {formatarKz(p.total_kz)}
        </Text>
        <Text>
          Feito {p.feito_as.slice(11)}
          {p.confirmado_as ? ` · confirmado ${p.confirmado_as}` : ''}
          {p.saiu_as ? ` · saiu ${p.saiu_as}` : ''}
          {p.entregue_as ? ` · entregue ${p.entregue_as}` : ''}
          {p.hora_prometida ? ` (prometido ${p.hora_prometida})` : ''}
        </Text>
        {p.minutos_de_atraso_na_entrega != null && p.minutos_de_atraso_na_entrega > 0 && (
          <Text style={{ color: cores.erro }}>Entregue {p.minutos_de_atraso_na_entrega} min depois da hora prometida</Text>
        )}
        {r.factos.alertas.map((a, i) => (
          <Text key={i} style={{ color: cores.textoSuave }}>
            Alerta: {a.tipo === 'atraso' ? `atraso de ${a.minutos} min` : `${a.minutos} min sem confirmação`}
            {a.motivo_dado ? ` · motivo dado: ${a.motivo_dado}` : ''}
          </Text>
        ))}
        {r.factos.cliente && (
          <Text style={{ color: cores.textoSuave }}>
            Cliente: {r.factos.cliente.pedidos_90_dias} pedidos e {r.factos.cliente.reclamacoes_90_dias} outras reclamações em 90 dias
          </Text>
        )}
      </View>
    );
  }

  function cartao(r: Reclamacao) {
    const expandida = aberta === r.id;
    return (
      <Cartao key={r.id}>
        <Text style={{ fontWeight: '700' }}>
          {r.cliente_nome}
          {r.estrelas != null ? ` · ${'★'.repeat(r.estrelas)}` : ' · reclamação no pedido'}
        </Text>
        <Text>{r.texto || '(sem comentário)'}</Text>
        <Text style={{ color: cores.textoSuave }}>
          {new Date(r.criado_em).toLocaleString('pt-PT')}
          {r.cozinha ? ` · ${r.cozinha}` : ''}
          {r.estafeta ? ` · entregue por ${r.estafeta}` : ''}
        </Text>
        <Aviso tipo={r.ia_procedente === 'sim' ? 'erro' : 'aviso'}>{textoAnalise(r)}</Aviso>
        {r.ia_estado === 'analisada' && (
          <>
            {r.ia_categoria && <Text>Categoria: {nomeCategoria[r.ia_categoria] ?? r.ia_categoria}</Text>}
            {r.ia_fundamento && <Text style={{ color: cores.textoSuave }}>{r.ia_fundamento}</Text>}
            {r.ia_accao && <Text>A rever: {r.ia_accao}</Text>}
          </>
        )}
        {r.estado === 'resolvida' ? (
          <View style={{ gap: espaco.xs }}>
            <Text style={{ fontWeight: '700' }}>
              {r.procedente ? 'Com razão' : 'Sem razão'} · {nomeCompensacao[r.compensacao ?? 'nenhuma']}
              {r.compensacao_valor ? ` ${formatarKz(r.compensacao_valor)}` : ''}
            </Text>
            <Text>Resposta: {r.resposta}</Text>
            <Text style={{ color: cores.textoSuave }}>Por {r.decidido_por ?? '—'}</Text>
          </View>
        ) : (
          <>
            <Botao titulo={expandida ? 'Fechar' : 'Ver factos e responder'} variante="texto" aoCarregar={() => abrir(r)} />
            {expandida && (
              <View style={{ gap: espaco.s }}>
                {factos(r)}
                <Subtitulo>O cliente tem razão?</Subtitulo>
                <Escolha
                  opcoes={[{ valor: 'sim', rotulo: 'Sim' }, { valor: 'nao', rotulo: 'Não' }]}
                  valor={decisao.procedente}
                  aoMudar={(v) => setDecisao({ ...decisao, procedente: v })}
                />
                <Campo
                  rotulo="Resposta ao cliente"
                  value={decisao.resposta}
                  onChangeText={(t) => setDecisao({ ...decisao, resposta: t })}
                  maxLength={500}
                  multiline
                />
                <Escolha
                  opcoes={Object.entries(nomeCompensacao).map(([valor, rotulo]) => ({ valor, rotulo }))}
                  valor={decisao.compensacao}
                  aoMudar={(v) => setDecisao({ ...decisao, compensacao: v })}
                />
                {COM_VALOR.includes(decisao.compensacao) && (
                  <Campo
                    rotulo="Valor (Kz)"
                    value={decisao.valor}
                    onChangeText={(t) => setDecisao({ ...decisao, valor: t.replace(/\D/g, '') })}
                    keyboardType="number-pad"
                  />
                )}
                <Botao
                  titulo="Responder ao cliente"
                  desactivado={decisao.resposta.trim().length < 5}
                  aCarregar={ocupado}
                  aoCarregar={() => responder(r)}
                />
                {r.ia_estado === 'indisponivel' && (
                  <Botao
                    titulo="Analisar de novo"
                    variante="secundario"
                    aoCarregar={() => correr(async () => { await pedirNovaAnalise('reclamacao', r.id); carregar(); }, 'Volta a ser analisada dentro de minutos.')}
                  />
                )}
                <Botao
                  titulo="Histórico do pedido"
                  variante="texto"
                  aoCarregar={() => router.push({ pathname: '/pedido/[id]', params: { id: r.pedido_id } })}
                />
              </View>
            )}
          </>
        )}
      </Cartao>
    );
  }

  function separadorMes() {
    return (
      <>
        <Campo rotulo="Mês (AAAA-MM)" value={mes} onChangeText={setMes} maxLength={7} />
        <Botao
          titulo="Ver resumo"
          desactivado={!MES.test(mes)}
          aCarregar={ocupado}
          aoCarregar={() =>
            correr(async () => {
              const [a, m] = mes.split('-').map(Number);
              setRelatorio(await relatorioReclamacoes(a, m));
            })
          }
        />
        {relatorio && (
          <>
            <Cartao>
              <Linha esquerda="Reclamações" direita={String(relatorio.total)} forte />
              <Linha esquerda="Com razão" direita={String(relatorio.procedentes)} />
              <Linha esquerda="Por responder" direita={String(relatorio.abertas)} />
              <Linha esquerda="Horas até responder (média)" direita={relatorio.horas_ate_responder != null ? String(relatorio.horas_ate_responder) : '—'} />
              <Linha esquerda="Compensações" direita={formatarKz(relatorio.compensacoes_kz)} />
              <Linha
                esquerda="Análise automática de acordo com o gerente"
                direita={relatorio.ia_com_opiniao > 0 ? `${relatorio.ia_concordou}/${relatorio.ia_com_opiniao}` : '—'}
              />
            </Cartao>
            <Cartao>
              <Subtitulo>Por motivo</Subtitulo>
              {relatorio.por_categoria.map((c) => (
                <Linha key={c.categoria} esquerda={nomeCategoria[c.categoria] ?? 'Por classificar'} direita={`${c.total} (${c.procedentes} com razão)`} />
              ))}
            </Cartao>
            {relatorio.por_estafeta.length > 0 && (
              <Cartao>
                <Subtitulo>Por estafeta</Subtitulo>
                {relatorio.por_estafeta.map((c) => (
                  <Linha key={c.estafeta} esquerda={c.estafeta} direita={`${c.total} (${c.procedentes} com razão)`} />
                ))}
              </Cartao>
            )}
          </>
        )}
      </>
    );
  }

  return (
    <Guarda permissoes={['pedidos.gerir', 'clientes.gerir']}>
      <Ecra>
        <Escolha
          opcoes={[
            { valor: 'abertas', rotulo: 'Por responder' },
            { valor: 'resolvidas', rotulo: 'Respondidas' },
            { valor: 'mes', rotulo: 'Resumo do mês' },
          ]}
          valor={sep}
          aoMudar={mudarSeparador}
        />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
        {sep === 'mes' ? (
          separadorMes()
        ) : lista === null ? (
          <ACarregar />
        ) : lista.length === 0 ? (
          <Paragrafo suave>{sep === 'abertas' ? 'Sem reclamações por responder.' : 'Sem reclamações respondidas nos últimos 90 dias.'}</Paragrafo>
        ) : (
          lista.map(cartao)
        )}
      </Ecra>
    </Guarda>
  );
}
