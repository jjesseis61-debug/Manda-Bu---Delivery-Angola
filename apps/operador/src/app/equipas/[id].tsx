import { useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Switch, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import {
  aceitarAcordo,
  decidirExtra,
  decidirPagamento,
  definirEquipa,
  type EquipaDetalhe,
  lerEquipa,
  nomeQuemPaga,
  pagarBeneficio,
  proporAcordo,
  type QuemPaga,
  registarDinheiro,
  terminarAcordo,
  textoEscaloes,
} from '@/lib/equipas';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';

const numero = (t: string) => t.replace(/\D/g, '');

/**
 * Uma equipa no trabalho: a cozinha decide as refeições extra e regista o dinheiro; as Finanças confirmam
 * as referências, propõem o acordo e pagam o benefício; quem gere clientes define o limite e a origem.
 * Skinner: o benefício só chega quando cada colega paga; os limites travam abusos.
 */
export default function EquipaOperador() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { pode } = useSessao();
  const cozinha = pode('pedidos.gerir');
  const financas = pode('financas.acertos');
  const clientes = pode('clientes.gerir');
  const [e, setE] = useState<EquipaDetalhe | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [feito, setFeito] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [parte, setParte] = useState<Record<string, string>>({});
  const [dinheiro, setDinheiro] = useState<{ cliente: string; nome: string; valor: string } | null>(null);
  const [rejeitar, setRejeitar] = useState<{ id: string; motivo: string } | null>(null);
  const [def, setDef] = useState<{ limite: string; origem: 'plataforma' | 'cozinha'; activa: boolean } | null>(null);
  const [novo, setNovo] = useState<{ quem_paga: QuemPaga; parte: string; pct_1: string; pct_2: string; pct_3: string; limite_2: string; limite_3: string; bebidas: boolean; tecto: string } | null>(null);

  const carregar = useCallback(() => {
    lerEquipa(String(id))
      .then(setE)
      .catch((x) => setErro(mensagemErro(x)));
  }, [id]);
  useFocusEffect(carregar);

  async function correr(f: () => Promise<unknown>, mensagem: string) {
    setErro(null);
    setFeito(null);
    setOcupado(true);
    try {
      await f();
      setFeito(mensagem);
      carregar();
    } catch (x) {
      setErro(mensagemErro(x));
    } finally {
      setOcupado(false);
    }
  }

  return (
    <Guarda permissoes={['pedidos.gerir', 'financas.acertos', 'clientes.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {feito && <Aviso tipo="sucesso">{feito}</Aviso>}
        {!e && !erro && <ACarregar />}
        {e && (
          <>
            <Cartao>
              <Subtitulo>{e.nome}</Subtitulo>
              <Paragrafo suave>
                {e.cozinha} · responsável {e.responsavel} · entrega às {e.hora_entrega} · pedir até {e.prazo_minutos} min antes · trazida pela{' '}
                {e.origem === 'cozinha' ? 'cozinha' : 'plataforma'}
              </Paragrafo>
              <Linha esquerda="Limite mensal por colega" direita={formatarKz(e.limite_mensal)} />
              {e.grupo_hoje ? (
                <Linha esquerda="Grupo de hoje" direita={`${e.grupo_hoje.estado} · ${e.grupo_hoje.pedidos} pedido(s)`} />
              ) : (
                <Paragrafo suave>Hoje não há grupo.</Paragrafo>
              )}
              {clientes && !def && (
                <Botao
                  titulo="Limite, origem e estado"
                  variante="texto"
                  aoCarregar={() => setDef({ limite: String(e.limite_mensal), origem: e.origem, activa: e.activa })}
                />
              )}
              {def && (
                <View style={{ gap: espaco.s }}>
                  <Campo rotulo="Limite mensal por colega (Kz)" value={def.limite} keyboardType="number-pad" onChangeText={(t) => setDef({ ...def, limite: numero(t) })} />
                  <Text style={{ fontWeight: '700' }}>Quem trouxe a equipa</Text>
                  <Escolha
                    opcoes={[
                      { valor: 'plataforma' as const, rotulo: 'Plataforma' },
                      { valor: 'cozinha' as const, rotulo: 'A cozinha' },
                    ]}
                    valor={def.origem}
                    aoMudar={(v) => setDef({ ...def, origem: v })}
                  />
                  <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
                    <Text>Equipa activa</Text>
                    <Switch value={def.activa} onValueChange={(v) => setDef({ ...def, activa: v })} trackColor={{ true: cores.marca, false: cores.contorno }} thumbColor="#FFFFFF" />
                  </View>
                  <Botao
                    titulo="Guardar"
                    aCarregar={ocupado}
                    aoCarregar={() => correr(async () => {
                      await definirEquipa(e.id, Number(def.limite || 0), def.origem, def.activa);
                      setDef(null);
                    }, 'Equipa actualizada.')}
                  />
                  <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setDef(null)} />
                </View>
              )}
            </Cartao>

            {/* Refeições extra: a cozinha aprova tudo, parte ou recusa, vendo as doses que lhe restam */}
            {e.extras.some((x) => x.estado === 'pendente') && (
              <Cartao>
                <Subtitulo>Refeições extra por decidir</Subtitulo>
                {e.extras
                  .filter((x) => x.estado === 'pendente')
                  .map((x) => (
                    <View key={x.id} style={{ gap: espaco.xs }}>
                      <Text style={{ fontWeight: '600' }}>
                        {x.cliente}: mais {x.quantidade} · {x.motivo}
                      </Text>
                      {cozinha ? (
                        <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap', alignItems: 'flex-end' }}>
                          <Botao titulo={`Aprovar ${x.quantidade}`} aCarregar={ocupado} aoCarregar={() => correr(() => decidirExtra(x.id, x.quantidade), 'Aprovado. O cliente foi avisado.')} />
                          {x.quantidade > 1 && (
                            <>
                              <View style={{ width: 90 }}>
                                <Campo rotulo="Só" value={parte[x.id] ?? ''} keyboardType="number-pad" onChangeText={(t) => setParte({ ...parte, [x.id]: numero(t) })} />
                              </View>
                              <Botao
                                titulo="Aprovar parte"
                                variante="secundario"
                                desactivado={!Number(parte[x.id]) || Number(parte[x.id]) >= x.quantidade}
                                aoCarregar={() => correr(() => decidirExtra(x.id, Number(parte[x.id])), 'Aprovado em parte. O cliente foi avisado.')}
                              />
                            </>
                          )}
                          <Botao titulo="Recusar" variante="texto" aoCarregar={() => correr(() => decidirExtra(x.id, 0), 'Recusado. O cliente foi avisado.')} />
                        </View>
                      ) : (
                        <Paragrafo suave>A cozinha decide.</Paragrafo>
                      )}
                    </View>
                  ))}
                <Paragrafo suave>Sem resposta até ao prazo do grupo, fica recusado.</Paragrafo>
              </Cartao>
            )}

            {/* Pagamentos por referência: as Finanças confirmam */}
            {e.pagamentos_pendentes.length > 0 && (
              <Cartao>
                <Subtitulo>Pagamentos por confirmar</Subtitulo>
                {e.pagamentos_pendentes.map((p) => (
                  <View key={p.id} style={{ gap: espaco.xs }}>
                    <Text>
                      {p.cliente} · {formatarKz(p.valor)} · {p.metodo === 'unitel_money' ? 'Unitel Money' : 'Multicaixa Express'} · ref. {p.referencia} · conta de{' '}
                      {p.mes.slice(5, 7)}/{p.mes.slice(0, 4)}
                    </Text>
                    {financas && (
                      <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
                        <Botao titulo="Confirmar" aCarregar={ocupado} aoCarregar={() => correr(() => decidirPagamento(p.id, true), 'Pagamento confirmado.')} />
                        <Botao titulo="Não encontrado" variante="texto" aoCarregar={() => setRejeitar({ id: p.id, motivo: '' })} />
                      </View>
                    )}
                    {rejeitar?.id === p.id && (
                      <>
                        <Campo rotulo="Motivo (o cliente vê)" value={rejeitar.motivo} onChangeText={(t) => setRejeitar({ ...rejeitar, motivo: t })} />
                        <Botao
                          titulo="Rejeitar"
                          variante="secundario"
                          desactivado={!rejeitar.motivo.trim()}
                          aoCarregar={() => correr(async () => {
                            await decidirPagamento(p.id, false, rejeitar.motivo.trim());
                            setRejeitar(null);
                          }, 'Pagamento rejeitado. O cliente foi avisado.')}
                        />
                      </>
                    )}
                  </View>
                ))}
              </Cartao>
            )}

            {/* Contas do mês de cada colega */}
            <Cartao>
              <Subtitulo>
                Contas de {e.mes.slice(5, 7)}/{e.mes.slice(0, 4)}
              </Subtitulo>
              {e.contas.map((c) => (
                <View key={c.cliente_id} style={{ gap: 2, paddingVertical: 4, borderBottomWidth: 1, borderBottomColor: cores.linha }}>
                  <Text style={{ fontWeight: '600' }}>
                    {c.nome}
                    {c.em_atraso ? ' · em atraso (paga no dia)' : ''}
                  </Text>
                  <Text style={{ color: cores.textoSuave }}>
                    Almoços {formatarKz(c.total)} · pago {formatarKz(c.pago)}
                    {c.a_confirmar > 0 ? ` · a confirmar ${formatarKz(c.a_confirmar)}` : ''} · em falta {formatarKz(c.em_falta)}
                  </Text>
                  {cozinha && c.em_falta > 0 && (
                    <Botao titulo="Recebi em dinheiro…" variante="texto" aoCarregar={() => setDinheiro({ cliente: c.cliente_id, nome: c.nome, valor: String(c.em_falta) })} />
                  )}
                </View>
              ))}
              {dinheiro && (
                <View style={{ gap: espaco.s }}>
                  <Campo rotulo={`Valor recebido de ${dinheiro.nome} (Kz)`} value={dinheiro.valor} keyboardType="number-pad" onChangeText={(t) => setDinheiro({ ...dinheiro, valor: numero(t) })} />
                  <Paragrafo suave>Entrega o recibo e põe o dinheiro na caixa da cozinha.</Paragrafo>
                  <Botao
                    titulo="Registar dinheiro recebido"
                    aCarregar={ocupado}
                    desactivado={!Number(dinheiro.valor)}
                    aoCarregar={() => correr(async () => {
                      await registarDinheiro(e.id, dinheiro.cliente, e.mes, Number(dinheiro.valor));
                      setDinheiro(null);
                    }, 'Pagamento registado. O cliente foi avisado.')}
                  />
                  <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setDinheiro(null)} />
                </View>
              )}
            </Cartao>

            {/* Acordo e benefício da responsável */}
            <Cartao>
              <Subtitulo>Acordo e benefício da responsável</Subtitulo>
              {!e.acordo ? (
                <Paragrafo suave>Sem acordo: os pedidos contam para o ganha-ganha (Kambas) como os outros.</Paragrafo>
              ) : (
                <>
                  <Linha esquerda="Estado" direita={e.acordo.estado === 'proposto' ? 'à espera da cozinha' : 'activo'} />
                  <Linha esquerda="Quem paga" direita={nomeQuemPaga[e.acordo.quem_paga]} />
                  {e.acordo.quem_paga === 'plataforma_cozinha' && <Linha esquerda="Parte da cozinha" direita={`${e.acordo.parte_cozinha_pct}%`} />}
                  <Paragrafo suave>{textoEscaloes(e.acordo)}</Paragrafo>
                  <Paragrafo suave>
                    Tecto {formatarKz(e.acordo.tecto_refeicao)} por refeição · bebidas {e.acordo.conta_bebidas ? 'contam' : 'não contam'} · sem a taxa de entrega
                  </Paragrafo>
                  {e.acordo.estado === 'proposto' && cozinha && (
                    <Botao titulo="A cozinha aceita o acordo" aCarregar={ocupado} aoCarregar={() => correr(() => aceitarAcordo(e.acordo?.id as string), 'Acordo activo. A responsável foi avisada.')} />
                  )}
                  {(financas || cozinha) && (
                    <Botao titulo="Terminar acordo" variante="texto" aoCarregar={() => correr(() => terminarAcordo(e.acordo?.id as string), 'Acordo terminado.')} />
                  )}
                </>
              )}
              <Linha esquerda={`Média do mês anterior`} direita={`${String(e.escalao.media).replace('.', ',')} almoços/dia · ${e.escalao.pct}%`} />
              <Linha esquerda="Benefício deste mês" direita={formatarKz(e.beneficios.mes)} />
              {e.beneficios.parte_cozinha_mes > 0 && <Linha esquerda="Benefício da equipa (parte da cozinha)" direita={formatarKz(e.beneficios.parte_cozinha_mes)} />}
              <Linha esquerda="À espera de os colegas pagarem" direita={formatarKz(e.beneficios.pendente)} />
              <Linha esquerda="Desbloqueado, por pagar à responsável" direita={formatarKz(e.beneficios.desbloqueado)} forte />
              <Linha esquerda="Já pago" direita={formatarKz(e.beneficios.pago)} />
              {e.beneficios.desbloqueado > 0 && (financas || (cozinha && e.acordo?.quem_paga === 'cozinha')) && (
                <Botao
                  titulo={`Paguei ${formatarKz(e.beneficios.desbloqueado)} à responsável`}
                  aCarregar={ocupado}
                  aoCarregar={() => correr(() => pagarBeneficio(e.id, 'dinheiro'), 'Benefício pago. A responsável foi avisada.')}
                />
              )}
              {financas && !novo && e.acordo?.estado !== 'proposto' && (
                <Botao
                  titulo={e.acordo ? 'Propor novo acordo' : 'Propor acordo'}
                  variante="secundario"
                  aoCarregar={() =>
                    setNovo({ quem_paga: 'plataforma', parte: '50', pct_1: '3', pct_2: '5', pct_3: '10', limite_2: '10', limite_3: '15', bebidas: false, tecto: '1000' })
                  }
                />
              )}
              {novo && (
                <View style={{ gap: espaco.s }}>
                  <Text style={{ fontWeight: '700' }}>Quem paga o benefício</Text>
                  <Escolha
                    opcoes={(['plataforma', 'plataforma_cozinha', 'cozinha'] as QuemPaga[]).map((v) => ({ valor: v, rotulo: nomeQuemPaga[v] }))}
                    valor={novo.quem_paga}
                    aoMudar={(v) => setNovo({ ...novo, quem_paga: v })}
                  />
                  {novo.quem_paga === 'cozinha' && e.origem !== 'cozinha' && (
                    <Aviso>«Só a cozinha» é só para equipas trazidas pela cozinha. Muda primeiro a origem da equipa.</Aviso>
                  )}
                  {novo.quem_paga === 'plataforma_cozinha' && (
                    <Campo rotulo="Parte da cozinha (%)" value={novo.parte} keyboardType="number-pad" onChangeText={(t) => setNovo({ ...novo, parte: numero(t) })} />
                  )}
                  <View style={{ flexDirection: 'row', gap: espaco.s }}>
                    {(['pct_1', 'pct_2', 'pct_3'] as const).map((k, i) => (
                      <View key={k} style={{ flex: 1 }}>
                        <Campo rotulo={`Escalão ${i + 1} (%)`} value={novo[k]} keyboardType="decimal-pad" onChangeText={(t) => setNovo({ ...novo, [k]: t.replace(/[^\d.]/g, '') })} />
                      </View>
                    ))}
                  </View>
                  <View style={{ flexDirection: 'row', gap: espaco.s }}>
                    <View style={{ flex: 1 }}>
                      <Campo rotulo="Escalão 2 a partir de (almoços/dia)" value={novo.limite_2} keyboardType="number-pad" onChangeText={(t) => setNovo({ ...novo, limite_2: numero(t) })} />
                    </View>
                    <View style={{ flex: 1 }}>
                      <Campo rotulo="Escalão 3 a partir de" value={novo.limite_3} keyboardType="number-pad" onChangeText={(t) => setNovo({ ...novo, limite_3: numero(t) })} />
                    </View>
                  </View>
                  <Campo rotulo="Tecto por refeição (Kz)" value={novo.tecto} keyboardType="number-pad" onChangeText={(t) => setNovo({ ...novo, tecto: numero(t) })} />
                  <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
                    <Text>As bebidas contam</Text>
                    <Switch value={novo.bebidas} onValueChange={(v) => setNovo({ ...novo, bebidas: v })} trackColor={{ true: cores.marca, false: cores.contorno }} thumbColor="#FFFFFF" />
                  </View>
                  <Paragrafo suave>O acordo fica à espera de a cozinha aceitar. Cada pedido conta só num programa: com acordo, benefício da equipa.</Paragrafo>
                  <Botao
                    titulo="Propor à cozinha"
                    aCarregar={ocupado}
                    aoCarregar={() =>
                      correr(async () => {
                        await proporAcordo(e.id, {
                          quem_paga: novo.quem_paga,
                          parte_cozinha_pct: Number(novo.parte || 0),
                          pct_1: Number(novo.pct_1 || 0),
                          pct_2: Number(novo.pct_2 || 0),
                          pct_3: Number(novo.pct_3 || 0),
                          limite_2: Number(novo.limite_2 || 0),
                          limite_3: Number(novo.limite_3 || 0),
                          conta_bebidas: novo.bebidas,
                          tecto_refeicao: Number(novo.tecto || 0),
                        });
                        setNovo(null);
                      }, 'Acordo proposto. Falta a cozinha aceitar.')
                    }
                  />
                  <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setNovo(null)} />
                </View>
              )}
            </Cartao>
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
