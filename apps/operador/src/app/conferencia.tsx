import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import {
  apagarMovimento,
  confirmarExtrato,
  criarExtrato,
  fechoDiario,
  fechoMensal,
  lerExtratos,
  lerMovimentos,
  ligarMovimento,
  pedirNovaLeitura,
  registarMovimento,
} from '@/lib/api';
import { diaLuanda, formatarDia, formatarKz, mensagemErro, nomeEstadoExtrato, textoLeitura } from '@/lib/formatar';
import { enviarExtrato, escolherFicheiroExtrato, escolherFoto, type FicheiroEscolhido } from '@/lib/fotos';
import { cores, espaco } from '@/lib/tema';
import type { AlertaFecho, Extrato, FechoDiario, FechoMensal, MovimentoExtrato } from '@/lib/tipos';

type Separador = 'dia' | 'mes' | 'extratos';
const DIA = /^\d{4}-\d{2}-\d{2}$/;
const MES = /^\d{4}-\d{2}$/;

const nomeAlerta: Record<string, string> = {
  caixa_diferenca: 'Caixa com diferença',
  caixa_aberta: 'Caixa ainda aberta',
  comprovativo_rejeitado: 'Pagamento rejeitado',
  ia_diverge: 'Comprovativo não confere com a foto',
  ia_ilegivel: 'Foto do comprovativo ilegível',
};

/** Conferência: fecho do dia, fecho do mês (com o extrato) e carregamento dos extratos */
export default function Conferencia() {
  const router = useRouter();
  const [sep, setSep] = useState<Separador>('dia');
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  // fecho do dia
  const [dia, setDia] = useState(diaLuanda());
  const [fechoDia, setFechoDia] = useState<FechoDiario | null>(null);
  // fecho do mês
  const [mes, setMes] = useState(diaLuanda().slice(0, 7));
  const [fechoMes, setFechoMes] = useState<FechoMensal | null>(null);
  const [ligar, setLigar] = useState<string | null>(null);
  // extratos
  const [extratos, setExtratos] = useState<Extrato[] | null>(null);
  const [novo, setNovo] = useState<{ conta: string; inicio: string; fim: string; ficheiro: FicheiroEscolhido | null } | null>(null);
  const [aberto, setAberto] = useState<string | null>(null);
  const [movimentos, setMovimentos] = useState<MovimentoExtrato[]>([]);
  const [entrada, setEntrada] = useState({ data: '', valor: '', referencia: '', descricao: '' });
  const [apagar, setApagar] = useState<{ id: string; motivo: string } | null>(null);

  const historico = (pedidoId?: string) => pedidoId && router.push({ pathname: '/pedido/[id]', params: { id: pedidoId } });

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

  const verDia = () => correr(async () => setFechoDia(await fechoDiario(dia)));
  const verMes = () =>
    correr(async () => {
      const [a, m] = mes.split('-').map(Number);
      setFechoMes(await fechoMensal(a, m));
    });
  const carregarExtratos = useCallback(() => {
    lerExtratos().then(setExtratos, (e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregarExtratos);

  async function abrirExtrato(id: string) {
    if (aberto === id) return setAberto(null);
    setAberto(id);
    setEntrada({ data: '', valor: '', referencia: '', descricao: '' });
    await correr(async () => setMovimentos(await lerMovimentos(id)));
  }

  function alerta(a: AlertaFecho, i: number) {
    return (
      <View key={i} style={{ gap: espaco.xs, borderTopWidth: 1, borderTopColor: cores.contorno, paddingTop: espaco.s }}>
        <Text style={{ fontWeight: '700', color: cores.erro }}>{nomeAlerta[a.tipo] ?? a.tipo}</Text>
        {a.posto && <Text>Caixa {a.posto}{a.valor != null && a.tipo === 'caixa_diferenca' ? `: ${formatarKz(a.valor)}` : ''}</Text>}
        {a.referencia && (
          <Text>
            {a.metodo} {formatarKz(a.valor)} · ref. {a.referencia}
            {a.tipo === 'ia_diverge' ? ` · na foto: ${a.ia_valor != null ? formatarKz(a.ia_valor) : '?'}${a.ia_referencia ? `, ${a.ia_referencia}` : ''}` : ''}
          </Text>
        )}
        {a.quem && <Text style={{ color: cores.textoSuave }}>{a.quem}</Text>}
        {a.pedido_id && <Botao titulo="Histórico do pedido" variante="texto" aoCarregar={() => historico(a.pedido_id)} />}
      </View>
    );
  }

  function separadorDia() {
    return (
      <>
        <Campo rotulo="Dia (AAAA-MM-DD)" value={dia} onChangeText={setDia} maxLength={10} />
        <Botao titulo="Ver fecho do dia" desactivado={!DIA.test(dia)} aCarregar={ocupado} aoCarregar={verDia} />
        {fechoDia && (
          <>
            <Cartao>
              <Text style={{ fontWeight: '700' }}>{formatarDia(fechoDia.dia)}</Text>
              <Linha esquerda={`Entregues (${fechoDia.pedidos_entregues})`} direita={formatarKz(fechoDia.vendido)} forte />
              <Linha esquerda="Pagamentos electrónicos" direita={formatarKz(fechoDia.electronico)} />
              <Linha esquerda="Diferença nas caixas" direita={formatarKz(fechoDia.diferenca_caixas)} />
              <Linha esquerda="Cancelados" direita={String(fechoDia.cancelados)} />
            </Cartao>
            {fechoDia.caixas.map((c) => (
              <Cartao key={c.caixa_id}>
                <Text style={{ fontWeight: '700' }}>{c.posto} · {c.cozinha}</Text>
                <Text style={{ color: cores.textoSuave }}>
                  {c.fechada ? `Fechada por ${c.fechada_por ?? '—'}` : `Aberta por ${c.aberta_por ?? '—'} · ainda não fechou`}
                </Text>
                {c.fechada && (
                  <>
                    <Linha esquerda="Devia estar" direita={formatarKz(c.esperado)} />
                    <Linha esquerda="Contado" direita={formatarKz(c.contado)} />
                    <Linha esquerda="Diferença" direita={formatarKz(c.diferenca)} forte />
                  </>
                )}
                <Linha esquerda="Electrónico" direita={formatarKz(c.electronico)} />
                {(c.por_conferir > 0 || c.rejeitados > 0 || c.ia_alertas > 0) && (
                  <Aviso>
                    {c.por_conferir} por conferir · {c.rejeitados} rejeitados · {c.ia_alertas} com aviso da leitura automática
                  </Aviso>
                )}
              </Cartao>
            ))}
            {fechoDia.alertas.length > 0 ? (
              <Cartao>
                <Subtitulo>Avisos do dia</Subtitulo>
                {fechoDia.alertas.map(alerta)}
              </Cartao>
            ) : (
              <Aviso tipo="sucesso">Sem avisos neste dia.</Aviso>
            )}
          </>
        )}
      </>
    );
  }

  function separadorMes() {
    const c = fechoMes?.conciliacao;
    return (
      <>
        <Campo rotulo="Mês (AAAA-MM)" value={mes} onChangeText={setMes} maxLength={7} />
        <Botao titulo="Ver fecho do mês" desactivado={!MES.test(mes)} aCarregar={ocupado} aoCarregar={verMes} />
        {fechoMes && c && (
          <>
            <Cartao>
              <Linha esquerda={`Entregues (${fechoMes.totais.pedidos})`} direita={formatarKz(fechoMes.totais.vendido)} forte />
              <Linha esquerda="Em dinheiro" direita={formatarKz(fechoMes.totais.dinheiro)} />
              <Linha esquerda="Electrónico" direita={formatarKz(fechoMes.totais.electronico)} />
              <Linha esquerda="Diferença nas caixas" direita={formatarKz(fechoMes.totais.diferenca_caixas)} />
              {fechoMes.totais.caixas_por_fechar > 0 && <Aviso>{fechoMes.totais.caixas_por_fechar} caixa(s) por fechar.</Aviso>}
            </Cartao>

            <Subtitulo>Conferência com o extrato</Subtitulo>
            <Cartao>
              <Linha esquerda={`Encontrados no extrato (${c.encontrados.length})`} direita={formatarKz(c.totais.encontrados)} />
              <Linha esquerda={`Comprovativos sem extrato (${c.comprovativos_sem_extrato.length})`} direita={formatarKz(c.totais.sem_extrato)} forte />
              <Linha
                esquerda={`Entradas sem comprovativo (${c.movimentos_sem_comprovativo.length})`}
                direita={formatarKz(c.totais.movimentos_sem_comprovativo)}
                forte
              />
              {c.aguardam_extrato > 0 && (
                <Paragrafo suave>{c.aguardam_extrato} comprovativo(s) de dias sem extrato carregado (carrega o extrato).</Paragrafo>
              )}
            </Cartao>
            {c.comprovativos_sem_extrato.length > 0 && (
              <Cartao>
                <Text style={{ fontWeight: '700', color: cores.erro }}>Comprovativos que não aparecem no extrato</Text>
                <Paragrafo suave>O pagamento foi registado na entrega mas o dinheiro não aparece no extrato.</Paragrafo>
                {c.comprovativos_sem_extrato.map((k) => (
                  <View key={k.comprovativo_id} style={{ gap: espaco.xs, borderTopWidth: 1, borderTopColor: cores.contorno, paddingTop: espaco.s }}>
                    <Linha esquerda={`${k.metodo} · ${k.cliente_nome}`} direita={formatarKz(k.valor)} />
                    <Text>{formatarDia(k.dia)} · ref. {k.referencia}</Text>
                    <Text style={{ color: cores.textoSuave }}>
                      Registou: {k.registado_por ?? '—'} · {k.estado === 'conferido' ? `conferiu: ${k.conferido_por ?? '—'}` : k.estado === 'rejeitado' ? 'rejeitado' : 'por conferir'}
                    </Text>
                    {textoLeitura(k.ia_estado).alerta && <Text style={{ color: cores.erro }}>{textoLeitura(k.ia_estado).texto}</Text>}
                    <Botao titulo="Histórico do pedido" variante="texto" aoCarregar={() => historico(k.pedido_id)} />
                  </View>
                ))}
              </Cartao>
            )}
            {c.movimentos_sem_comprovativo.length > 0 && (
              <Cartao>
                <Text style={{ fontWeight: '700' }}>Entradas do extrato sem comprovativo</Text>
                <Paragrafo suave>Dinheiro recebido sem pagamento registado numa entrega.</Paragrafo>
                {c.movimentos_sem_comprovativo.map((m) => {
                  const candidatos = c.comprovativos_sem_extrato.filter((k) => k.valor === m.valor);
                  return (
                    <View key={m.movimento_id} style={{ gap: espaco.xs, borderTopWidth: 1, borderTopColor: cores.contorno, paddingTop: espaco.s }}>
                      <Linha esquerda={`${formatarDia(m.data)} · ${m.conta}`} direita={formatarKz(m.valor)} />
                      <Text>{m.referencia ? `ref. ${m.referencia} · ` : ''}{m.descricao ?? ''}</Text>
                      {ligar === m.movimento_id ? (
                        <>
                          {candidatos.length === 0 && <Paragrafo suave>Nenhum comprovativo sem extrato com este valor.</Paragrafo>}
                          {candidatos.map((k) => (
                            <Botao
                              key={k.comprovativo_id}
                              titulo={`Ligar a ${k.metodo} ref. ${k.referencia} (${formatarDia(k.dia)})`}
                              variante="leve"
                              aCarregar={ocupado}
                              aoCarregar={() => correr(async () => { await ligarMovimento(m.movimento_id, k.comprovativo_id); setLigar(null); await verMes(); }, 'Ligado.')}
                            />
                          ))}
                          <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setLigar(null)} />
                        </>
                      ) : (
                        <Botao titulo="Ligar a um comprovativo…" variante="texto" aoCarregar={() => setLigar(m.movimento_id)} />
                      )}
                    </View>
                  );
                })}
              </Cartao>
            )}

            {fechoMes.por_funcionario.length > 0 && (
              <>
                <Subtitulo>Por funcionário</Subtitulo>
                {fechoMes.por_funcionario.map((f) => (
                  <Cartao key={f.funcionario_id}>
                    <Text style={{ fontWeight: '700' }}>{f.nome}</Text>
                    <Linha esquerda="Comprovativos registados" direita={String(f.comprovativos)} />
                    {f.sem_extrato > 0 && <Linha esquerda="Sem extrato" direita={`${f.sem_extrato} · ${formatarKz(f.valor_sem_extrato)}`} forte />}
                    {f.rejeitados > 0 && <Linha esquerda="Rejeitados" direita={String(f.rejeitados)} />}
                    {f.ia_alertas > 0 && <Linha esquerda="Avisos da leitura automática" direita={String(f.ia_alertas)} />}
                    {f.conferiu > 0 && <Linha esquerda="Conferiu" direita={`${f.conferiu}${f.conferiu_sem_extrato ? ` (${f.conferiu_sem_extrato} sem extrato)` : ''}`} />}
                    {f.diferenca_caixas !== 0 && <Linha esquerda="Diferença nas caixas que fechou" direita={formatarKz(f.diferenca_caixas)} />}
                  </Cartao>
                ))}
              </>
            )}
          </>
        )}
      </>
    );
  }

  async function guardarNovo() {
    if (!novo) return;
    await correr(async () => {
      const id = await criarExtrato(novo.conta.trim(), novo.inicio, novo.fim);
      const caminho = novo.ficheiro ? await enviarExtrato(id, novo.ficheiro) : null;
      await confirmarExtrato(id, caminho);
      setNovo(null);
      carregarExtratos();
    }, novo.ficheiro ? 'Extrato carregado. A leitura automática começa dentro de um minuto.' : 'Extrato criado: escreve as entradas à mão.');
  }

  function separadorExtratos() {
    return (
      <>
        <Paragrafo suave>
          Carrega o extrato do mês (PDF ou foto) do banco, do Multicaixa ou do Unitel Money. A leitura automática tira as entradas e o
          sistema cruza-as com os comprovativos. Sem leitura automática, escreve as entradas à mão.
        </Paragrafo>
        {novo ? (
          <Cartao>
            <Subtitulo>Novo extrato</Subtitulo>
            <Campo rotulo="Conta (ex.: Multicaixa Express BAI)" value={novo.conta} maxLength={80} onChangeText={(t) => setNovo({ ...novo, conta: t })} />
            <Campo rotulo="De (AAAA-MM-DD)" value={novo.inicio} maxLength={10} onChangeText={(t) => setNovo({ ...novo, inicio: t })} />
            <Campo rotulo="Até (AAAA-MM-DD)" value={novo.fim} maxLength={10} onChangeText={(t) => setNovo({ ...novo, fim: t })} />
            {novo.ficheiro ? (
              <Aviso tipo="sucesso">{novo.ficheiro.tipo === 'application/pdf' ? 'PDF escolhido.' : 'Imagem escolhida.'}</Aviso>
            ) : (
              <Paragrafo suave>Sem ficheiro, as entradas escrevem-se à mão.</Paragrafo>
            )}
            <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
              <Botao
                titulo="Escolher PDF ou imagem"
                variante="leve"
                aoCarregar={() => correr(async () => { const f = await escolherFicheiroExtrato(); if (f) setNovo({ ...novo, ficheiro: f }); })}
              />
              <Botao
                titulo="Fotografar"
                variante="texto"
                aoCarregar={() => correr(async () => { const uri = await escolherFoto('camera', false); if (uri) setNovo({ ...novo, ficheiro: { uri, tipo: 'image/jpeg' } }); })}
              />
            </View>
            <Botao
              titulo="Guardar extrato"
              desactivado={!novo.conta.trim() || !DIA.test(novo.inicio) || !DIA.test(novo.fim)}
              aCarregar={ocupado}
              aoCarregar={guardarNovo}
            />
            <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setNovo(null)} />
          </Cartao>
        ) : (
          <Botao
            titulo="Carregar extrato"
            aoCarregar={() => setNovo({ conta: '', inicio: `${diaLuanda().slice(0, 7)}-01`, fim: diaLuanda(), ficheiro: null })}
          />
        )}

        {extratos === null && <ACarregar />}
        {extratos?.length === 0 && <Paragrafo suave>Ainda não há extratos.</Paragrafo>}
        {extratos?.map((e) => (
          <Cartao key={e.id}>
            <Text style={{ fontWeight: '700' }}>{e.conta}</Text>
            <Text style={{ color: cores.textoSuave }}>
              {formatarDia(e.periodo_inicio)} a {formatarDia(e.periodo_fim)} · {nomeEstadoExtrato[e.estado] ?? e.estado}
            </Text>
            {e.ia_nota && <Text style={{ color: cores.textoSuave }}>{e.ia_nota}</Text>}
            <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
              <Botao titulo={aberto === e.id ? 'Fechar' : 'Ver entradas'} variante="leve" aoCarregar={() => abrirExtrato(e.id)} />
              {e.caminho && ['lido', 'ilegivel', 'indisponivel', 'manual'].includes(e.estado) && (
                <Botao
                  titulo="Ler de novo"
                  variante="texto"
                  aoCarregar={() => correr(async () => { await pedirNovaLeitura('extrato', e.id); carregarExtratos(); }, 'Nova leitura pedida.')}
                />
              )}
            </View>
            {aberto === e.id && (
              <View style={{ gap: espaco.s }}>
                {movimentos.length === 0 && <Paragrafo suave>Sem entradas.</Paragrafo>}
                {movimentos.map((m) => (
                  <View key={m.id} style={{ gap: espaco.xs, borderTopWidth: 1, borderTopColor: cores.contorno, paddingTop: espaco.s }}>
                    <Linha esquerda={formatarDia(m.data)} direita={formatarKz(m.valor)} />
                    <Text>{m.referencia ? `ref. ${m.referencia} · ` : ''}{m.descricao ?? ''}</Text>
                    <Text style={{ color: m.comprovativo_id ? cores.sucesso : cores.erro }}>
                      {m.comprovativo_id ? `Ligado a um comprovativo (${m.ligacao === 'manual' ? 'à mão' : 'automático'})` : 'Sem comprovativo'}
                      {m.origem === 'manual' ? ' · escrita à mão' : ' · leitura automática'}
                    </Text>
                    {apagar?.id === m.id ? (
                      <>
                        <Campo rotulo="Porque apagas esta entrada?" value={apagar.motivo} maxLength={200} onChangeText={(t) => setApagar({ id: m.id, motivo: t })} />
                        <Botao
                          titulo="Apagar entrada"
                          variante="secundario"
                          desactivado={!apagar.motivo.trim()}
                          aCarregar={ocupado}
                          aoCarregar={() => correr(async () => { await apagarMovimento(m.id, apagar.motivo.trim()); setApagar(null); setMovimentos(await lerMovimentos(e.id)); }, 'Entrada apagada.')}
                        />
                        <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setApagar(null)} />
                      </>
                    ) : (
                      <View style={{ flexDirection: 'row', gap: espaco.s }}>
                        {m.comprovativo_id && (
                          <Botao
                            titulo="Desligar"
                            variante="texto"
                            aoCarregar={() => correr(async () => { await ligarMovimento(m.id, null); setMovimentos(await lerMovimentos(e.id)); }, 'Desligado.')}
                          />
                        )}
                        <Botao titulo="Apagar…" variante="texto" aoCarregar={() => setApagar({ id: m.id, motivo: '' })} />
                      </View>
                    )}
                  </View>
                ))}
                <Subtitulo>Juntar entrada à mão</Subtitulo>
                <Campo rotulo="Data (AAAA-MM-DD)" value={entrada.data} maxLength={10} onChangeText={(t) => setEntrada({ ...entrada, data: t })} />
                <Campo rotulo="Valor (Kz)" value={entrada.valor} keyboardType="number-pad" onChangeText={(t) => setEntrada({ ...entrada, valor: t.replace(/\D/g, '') })} />
                <Campo rotulo="Referência (opcional)" value={entrada.referencia} maxLength={60} autoCapitalize="characters" onChangeText={(t) => setEntrada({ ...entrada, referencia: t })} />
                <Campo rotulo="Descrição (opcional)" value={entrada.descricao} maxLength={200} onChangeText={(t) => setEntrada({ ...entrada, descricao: t })} />
                <Botao
                  titulo="Juntar entrada"
                  desactivado={!DIA.test(entrada.data) || !Number(entrada.valor)}
                  aCarregar={ocupado}
                  aoCarregar={() =>
                    correr(async () => {
                      await registarMovimento(e.id, entrada.data, Number(entrada.valor), entrada.referencia.trim() || null, entrada.descricao.trim() || null);
                      setEntrada({ data: entrada.data, valor: '', referencia: '', descricao: '' });
                      setMovimentos(await lerMovimentos(e.id));
                      carregarExtratos();
                    }, 'Entrada juntada e cruzada com os comprovativos.')
                  }
                />
              </View>
            )}
          </Cartao>
        ))}
      </>
    );
  }

  return (
    <Guarda permissoes={['financas.conferir']}>
      <Ecra>
        <Escolha
          opcoes={[
            { valor: 'dia', rotulo: 'Fecho do dia' },
            { valor: 'mes', rotulo: 'Fecho do mês' },
            { valor: 'extratos', rotulo: 'Extratos' },
          ]}
          valor={sep}
          aoMudar={(v) => setSep(v as Separador)}
        />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
        {sep === 'dia' && separadorDia()}
        {sep === 'mes' && separadorMes()}
        {sep === 'extratos' && separadorExtratos()}
      </Ecra>
    </Guarda>
  );
}
