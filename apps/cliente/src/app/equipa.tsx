// «A minha equipa»: o almoço no trabalho com os colegas (Junta Bué no trabalho).
// Rogers: é a vaquinha do almoço do escritório e a conta no fim do mês, agora com ferramentas.
// Cialdini: o colega autoriza, é avisado e pode recusar; a conta de cada um é privada.
// Bandura: metas próximas para a responsável; Prahalad: paga-se ao mês, como se recebe.
import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Switch, Text, View } from 'react-native';

import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { type ItemCarrinho, lerCardapio, lerEnderecos } from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import {
  type ContaMes,
  convidarColega,
  criarEquipa,
  horaValida,
  inicioDoMes,
  lerContaMes,
  type MinhaEquipa,
  minhasEquipas,
  mudarAutorizacoes,
  pagarContaMes,
  pedirPorColega,
  pedirRefeicoesExtra,
  pratoHabitualColega,
  recusarPedidoColega,
  responderConvite,
  sairDaEquipa,
  textoColegasPorPagar,
  textoDias,
  textoEscalao,
} from '@/lib/equipas';
import { formatarKz, horaLuanda, mensagemErro, nomeMetodoAntes } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Endereco, ItemCardapio } from '@/lib/tipos';

type Metodo = 'multicaixa_express' | 'unitel_money';

function Interruptor({ rotulo, valor, aoMudar }: { rotulo: string; valor: boolean; aoMudar: (v: boolean) => void }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: espaco.s }}>
      <Text style={{ flex: 1, color: cores.texto }}>{rotulo}</Text>
      <Switch accessibilityLabel={rotulo} value={valor} onValueChange={aoMudar} trackColor={{ true: cores.marca, false: cores.linha }} thumbColor="#FFFFFF" />
    </View>
  );
}

/** A conta do mês de um colega (a própria, ou a de um colega que autorizou a responsável) */
function CartaoConta({ conta, aoPagar }: { conta: ContaMes; aoPagar: (metodo: Metodo, referencia: string, valor: number) => Promise<void> }) {
  const [metodo, setMetodo] = useState<Metodo>('multicaixa_express');
  const [ref, setRef] = useState('');
  const [ocupado, setOcupado] = useState(false);
  const podePagar = conta.em_falta - conta.a_confirmar;
  return (
    <Cartao>
      <Subtitulo>Conta de {conta.mes.slice(5, 7)}/{conta.mes.slice(0, 4)} · {conta.nome.split(' ')[0]}</Subtitulo>
      <Linha esquerda="Almoços entregues" direita={formatarKz(conta.total)} />
      <Linha esquerda="Pago" direita={formatarKz(conta.pago)} />
      {conta.a_confirmar > 0 && <Linha esquerda="A confirmar pelas Finanças" direita={formatarKz(conta.a_confirmar)} />}
      <Linha esquerda="Em falta" direita={formatarKz(conta.em_falta)} forte />
      <Paragrafo suave>Limite do mês: {formatarKz(conta.limite)}. O que passar do limite paga-se no dia.</Paragrafo>
      {conta.em_atraso && <Aviso>A conta de um mês anterior ainda não foi paga: até pagares, os almoços pagam-se no dia.</Aviso>}
      {conta.linhas.map((l) => (
        <Text key={l.pedido_id} style={{ fontSize: 13, color: l.entregue ? cores.texto : cores.textoSuave }}>
          {l.dia.slice(8, 10)}/{l.dia.slice(5, 7)} · {l.itens} · {formatarKz(l.valor)}
          {l.pedido_por ? ` · pedido por ${l.pedido_por}` : ''}
          {l.entregue ? '' : ' · a caminho'}
        </Text>
      ))}
      {conta.pagamentos.filter((x) => x.estado === 'rejeitado').map((x) => (
        <Aviso key={x.id}>Pagamento de {formatarKz(x.valor)} não confirmado: {x.motivo}</Aviso>
      ))}
      {podePagar > 0 && (
        <View style={{ gap: espaco.s }}>
          <Text style={{ fontWeight: '700' }}>Pagar {formatarKz(podePagar)}</Text>
          <Escolha
            opcoes={[
              { valor: 'multicaixa_express' as Metodo, rotulo: nomeMetodoAntes.multicaixa_express },
              { valor: 'unitel_money' as Metodo, rotulo: nomeMetodoAntes.unitel_money },
            ]}
            valor={metodo}
            aoMudar={setMetodo}
          />
          <Campo rotulo="Referência da transferência" value={ref} onChangeText={setRef} autoCapitalize="characters" />
          <Paragrafo suave>Também podes pagar em dinheiro na cozinha: ela regista e dá-te o recibo.</Paragrafo>
          <Botao
            titulo={`Enviar pagamento de ${formatarKz(podePagar)}`}
            desactivado={ref.trim().length < 4}
            aCarregar={ocupado}
            aoCarregar={async () => {
              setOcupado(true);
              try {
                await aoPagar(metodo, ref, podePagar);
                setRef('');
              } finally {
                setOcupado(false);
              }
            }}
          />
        </View>
      )}
    </Cartao>
  );
}

export default function Equipa() {
  const router = useRouter();
  const { perfil, ligada } = useSessao();
  const carrinho = useCarrinho();
  const [equipas, setEquipas] = useState<MinhaEquipa[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [feito, setFeito] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [conta, setConta] = useState<ContaMes | null>(null);
  const [contaColega, setContaColega] = useState<ContaMes | null>(null);
  // Convite (aceitar com as autorizações escolhidas)
  const [autPedir, setAutPedir] = useState(false);
  const [autConta, setAutConta] = useState(false);
  // Criar equipa
  const [enderecos, setEnderecos] = useState<Endereco[]>([]);
  const [nome, setNome] = useState('');
  const [ponto, setPonto] = useState<string | null>(null);
  const [hora, setHora] = useState('12:30');
  const [prazo, setPrazo] = useState('90');
  // Responsável
  const [codigo, setCodigo] = useState('');
  const [pedirPor, setPedirPor] = useState<{ id: string; nome: string } | null>(null);
  const [habitual, setHabitual] = useState<{ itens: ItemCarrinho[]; texto: string } | null | undefined>(undefined);
  const [cardapio, setCardapio] = useState<ItemCardapio[] | null>(null);
  // Mais refeições
  const [extraQtd, setExtraQtd] = useState('1');
  const [extraMotivo, setExtraMotivo] = useState('');
  const [verExtra, setVerExtra] = useState(false);

  const carregar = useCallback(() => {
    setErro(null);
    minhasEquipas()
      .then((l) => {
        setEquipas(l);
        const activa = l.find((e) => e.estado === 'activo');
        if (activa) lerContaMes(activa.id).then(setConta).catch(() => setConta(null));
        else lerEnderecos(perfil?.cliente_id).then((e) => {
          setEnderecos(e);
          setPonto((p) => p ?? e.find((x) => x.pontos_entrega?.tipo === 'empresa')?.ponto_entrega_id ?? e[0]?.ponto_entrega_id ?? null);
        });
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [perfil?.cliente_id]);
  useFocusEffect(carregar);

  async function correr(f: () => Promise<unknown>, mensagem?: string) {
    setErro(null);
    setFeito(null);
    setOcupado(true);
    try {
      await f();
      if (mensagem) setFeito(mensagem);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  if (!ligada('equipas_trabalho')) {
    return (
      <Ecra>
        <Paragrafo>Esta funcionalidade ainda não está disponível.</Paragrafo>
      </Ecra>
    );
  }
  if (equipas === null) return <Ecra>{erro ? <Aviso tipo="erro">{erro}</Aviso> : <ACarregar />}</Ecra>;

  const convites = equipas.filter((e) => e.estado === 'convidado');
  const eq = equipas.find((e) => e.estado === 'activo') ?? null;
  const prazoPassou = !!eq?.hoje && new Date(eq.hoje.prazo).getTime() <= Date.now();

  return (
    <Ecra>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {feito && <Aviso tipo="sucesso">{feito}</Aviso>}

      {convites.map((c) => (
        <Cartao key={c.id}>
          <Subtitulo>Convite: equipa «{c.nome}»</Subtitulo>
          <Paragrafo>
            {c.responsavel} convidou-te para almoçar com a equipa. O almoço chega às {c.hora_entrega}, {textoDias(c.dias)}, e paga-se ao mês.
          </Paragrafo>
          <Paragrafo suave>Escolhe o que autorizas. Podes mudar quando quiseres.</Paragrafo>
          <Interruptor rotulo={`${c.responsavel} pode pedir o meu almoço`} valor={autPedir} aoMudar={setAutPedir} />
          <Interruptor rotulo={`${c.responsavel} pode ver a minha conta do mês`} valor={autConta} aoMudar={setAutConta} />
          <Botao titulo="Aceitar" aCarregar={ocupado} aoCarregar={() => correr(() => responderConvite(c.id, true, autPedir, autConta), 'Entraste na equipa.')} />
          <Botao titulo="Recusar" variante="texto" aoCarregar={() => correr(() => responderConvite(c.id, false, false, false))} />
        </Cartao>
      ))}

      {!eq && (
        <Cartao>
          <Subtitulo>Criar uma equipa</Subtitulo>
          <Paragrafo suave>
            Juntas os colegas uma vez. Todos os dias úteis o grupo do almoço abre sozinho e sai uma só entrega. Cada um paga a sua conta no
            fim do mês.
          </Paragrafo>
          <Campo rotulo="Nome da equipa (ex.: Contabilidade)" value={nome} onChangeText={setNome} />
          <Text style={{ fontWeight: '700' }}>Onde entregar</Text>
          {enderecos.length === 0 ? (
            <Paragrafo suave>Junta primeiro o endereço do trabalho em Conta → Endereços.</Paragrafo>
          ) : (
            <Escolha opcoes={enderecos.map((e) => ({ valor: e.ponto_entrega_id, rotulo: e.nome ?? 'Endereço' }))} valor={ponto ?? ''} aoMudar={setPonto} />
          )}
          <Campo rotulo="Hora da entrega (HH:MM)" value={hora} onChangeText={setHora} keyboardType="numbers-and-punctuation" />
          <Text style={{ fontWeight: '700' }}>Pedir até</Text>
          <Escolha
            opcoes={[
              { valor: '60', rotulo: '1 hora antes' },
              { valor: '90', rotulo: '1h30 antes' },
              { valor: '120', rotulo: '2 horas antes' },
            ]}
            valor={prazo}
            aoMudar={setPrazo}
          />
          {!carrinho.cozinhaActual && <Aviso>Escolhe primeiro a cozinha no Início.</Aviso>}
          <Botao
            titulo="Criar equipa"
            aCarregar={ocupado}
            desactivado={nome.trim().length < 2 || !ponto || !horaValida(hora) || !carrinho.cozinhaActual}
            aoCarregar={() =>
              correr(
                () =>
                  criarEquipa({
                    nome: nome.trim(),
                    ponto: ponto as string,
                    cozinha: carrinho.cozinhaActual?.id as string,
                    hora: hora.trim(),
                    prazoMinutos: Number(prazo),
                    dias: [1, 2, 3, 4, 5],
                  }),
                'Equipa criada. Agora junta os colegas pelo código deles.',
              )
            }
          />
        </Cartao>
      )}

      {eq && (
        <>
          <Cartao>
            <Subtitulo>{eq.nome}</Subtitulo>
            <Paragrafo suave>
              {eq.cozinha ?? 'Cozinha'} · {eq.local ?? 'trabalho'} · entrega às {eq.hora_entrega}, {textoDias(eq.dias)}
              {eq.sou_responsavel ? ' · és a responsável' : ` · responsável: ${eq.responsavel}`}
            </Paragrafo>
            {!eq.activa && <Aviso>A equipa está parada: o grupo do dia não abre.</Aviso>}
          </Cartao>

          {/* Hoje */}
          <Cartao>
            <Subtitulo>Hoje</Subtitulo>
            {!eq.hoje ? (
              <Paragrafo suave>Hoje não há almoço da equipa.</Paragrafo>
            ) : eq.hoje.meu_pedido ? (
              <>
                <Paragrafo>
                  O teu almoço: {eq.hoje.meu_pedido.itens}
                  {eq.hoje.meu_pedido.pedido_por ? ` (pedido por ${eq.hoje.meu_pedido.pedido_por})` : ''}.
                </Paragrafo>
                {eq.hoje.meu_pedido.pedido_por && eq.hoje.meu_pedido.estado === 'pendente' && !prazoPassou && (
                  <Botao
                    titulo="Não quero este almoço"
                    variante="secundario"
                    aCarregar={ocupado}
                    aoCarregar={() => correr(() => recusarPedidoColega(eq.hoje?.meu_pedido?.id as string), 'Recusaste. Podes pedir outro até ao prazo.')}
                  />
                )}
              </>
            ) : prazoPassou ? (
              <Paragrafo suave>O prazo já passou.</Paragrafo>
            ) : (
              <>
                <Paragrafo>
                  Vais almoçar hoje? Pede até às {horaLuanda(eq.hoje.prazo)}. Entrega às {horaLuanda(eq.hoje.hora)}.
                </Paragrafo>
                <Botao titulo="Pedir o meu almoço" aoCarregar={() => router.push(`/grupo/${eq.hoje?.codigo}`)} />
              </>
            )}
            {eq.hoje && !prazoPassou && (
              <>
                {eq.extras_hoje.map((x) => (
                  <Paragrafo key={x.id} suave>
                    Mais {x.quantidade} refeição(ões) ({x.motivo}):{' '}
                    {x.estado === 'pendente' ? 'à espera da cozinha' : x.estado === 'aprovado' ? `${x.aprovadas} aprovada(s)` : 'recusado'}
                  </Paragrafo>
                ))}
                {!verExtra ? (
                  <Botao titulo="Mais refeições hoje (visitas)" variante="texto" aoCarregar={() => setVerExtra(true)} />
                ) : (
                  <View style={{ gap: espaco.s }}>
                    <Paragrafo suave>Cada colega tem uma refeição por dia. Para mais, a cozinha confirma se ainda tem doses.</Paragrafo>
                    <Campo rotulo="Quantas" value={extraQtd} onChangeText={(t) => setExtraQtd(t.replace(/\D/g, '').slice(0, 2))} keyboardType="number-pad" />
                    <Campo rotulo="Porquê (ex.: visita de um cliente)" value={extraMotivo} onChangeText={setExtraMotivo} />
                    <Botao
                      titulo="Pedir à cozinha"
                      aCarregar={ocupado}
                      desactivado={!Number(extraQtd) || Number(extraQtd) > 10 || extraMotivo.trim().length < 2}
                      aoCarregar={() =>
                        correr(async () => {
                          await pedirRefeicoesExtra(eq.id, Number(extraQtd), extraMotivo.trim());
                          setVerExtra(false);
                          setExtraMotivo('');
                        }, 'Pedido enviado à cozinha. Recebes um aviso com a resposta.')
                      }
                    />
                  </View>
                )}
              </>
            )}
          </Cartao>

          {/* A minha conta do mês */}
          {conta && (
            <CartaoConta
              conta={conta}
              aoPagar={(metodo, referencia, valor) =>
                correr(
                  () => pagarContaMes({ equipa: eq.id, cliente: conta.cliente_id, mes: inicioDoMes(conta.mes), metodo, referencia, valor }),
                  'Pagamento enviado. As Finanças confirmam e recebes um aviso.',
                )
              }
            />
          )}

          {/* Autorizações (o colega decide e pode retirar) */}
          {!eq.sou_responsavel && (
            <Cartao>
              <Subtitulo>O que {eq.responsavel} pode fazer</Subtitulo>
              <Interruptor
                rotulo="Pedir o meu almoço"
                valor={eq.pode_pedir}
                aoMudar={(v) => correr(() => mudarAutorizacoes(eq.id, v, eq.pode_ver_conta))}
              />
              <Interruptor
                rotulo="Ver a minha conta do mês"
                valor={eq.pode_ver_conta}
                aoMudar={(v) => correr(() => mudarAutorizacoes(eq.id, eq.pode_pedir, v))}
              />
              <Paragrafo suave>Quando pede por ti, recebes logo um aviso e podes trocar ou recusar até ao prazo.</Paragrafo>
              <Botao titulo="Sair da equipa" variante="texto" aoCarregar={() => correr(() => sairDaEquipa(eq.id), 'Saíste da equipa.')} />
            </Cartao>
          )}

          {/* Responsável: benefício, colegas e convites */}
          {eq.sou_responsavel && eq.beneficio && (
            <Cartao>
              <Subtitulo>O teu benefício</Subtitulo>
              <Paragrafo>{textoEscalao(eq.beneficio.escalao)}</Paragrafo>
              <Linha esquerda="Este mês, à espera dos pagamentos" direita={formatarKz(eq.beneficio.mes_pendente)} />
              <Linha esquerda="Desbloqueado (a receber)" direita={formatarKz(eq.beneficio.desbloqueado)} forte />
              <Linha esquerda="Já recebido" direita={formatarKz(eq.beneficio.pago)} />
              {textoColegasPorPagar(eq.beneficio.colegas_por_pagar) && <Paragrafo suave>{textoColegasPorPagar(eq.beneficio.colegas_por_pagar)}</Paragrafo>}
              <Paragrafo suave>O preço dos colegas não muda: o benefício sai do que a cozinha recebe.</Paragrafo>
            </Cartao>
          )}

          {eq.sou_responsavel && (
            <Cartao>
              <Subtitulo>Colegas</Subtitulo>
              {eq.colegas.map((c) => (
                <View key={c.cliente_id} style={{ gap: 4, paddingVertical: 4, borderBottomWidth: 1, borderBottomColor: cores.linha }}>
                  <Text style={{ fontWeight: '600' }}>
                    {c.nome}
                    {c.estado === 'convidado' ? ' · convite enviado' : ''}
                    {c.pediu_hoje ? ' · ✓ pediu hoje' : ''}
                    {c.em_atraso ? ' · conta em atraso' : ''}
                  </Text>
                  {c.estado === 'activo' && c.cliente_id !== perfil?.cliente_id && (
                    <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
                      {c.pode_pedir && eq.hoje && !c.pediu_hoje && !prazoPassou && (
                        <Botao
                          titulo="Pedir por ele"
                          variante="secundario"
                          aoCarregar={() => {
                            setPedirPor({ id: c.cliente_id, nome: c.nome });
                            setHabitual(undefined);
                            pratoHabitualColega(eq.id, c.cliente_id).then(setHabitual).catch(() => setHabitual(null));
                            if (cardapio === null) lerCardapio(eq.cozinha_id).then(setCardapio).catch(() => setCardapio([]));
                          }}
                        />
                      )}
                      {c.pode_ver_conta && (
                        <Botao
                          titulo="Ver conta"
                          variante="texto"
                          aoCarregar={() => lerContaMes(eq.id, c.cliente_id).then(setContaColega).catch((e) => setErro(mensagemErro(e)))}
                        />
                      )}
                      <Botao titulo="Tirar" variante="texto" aoCarregar={() => correr(() => sairDaEquipa(eq.id, c.cliente_id))} />
                    </View>
                  )}
                </View>
              ))}
              <Campo rotulo="Código do colega (ex.: MB4812)" value={codigo} onChangeText={setCodigo} autoCapitalize="characters" />
              <Botao
                titulo="Convidar"
                variante="secundario"
                desactivado={codigo.trim().length < 4}
                aCarregar={ocupado}
                aoCarregar={() =>
                  correr(async () => {
                    const n = await convidarColega(eq.id, codigo);
                    setCodigo('');
                    setFeito(`Convite enviado a ${n}. Ele aceita na app.`);
                  })
                }
              />
            </Cartao>
          )}

          {pedirPor && eq.sou_responsavel && (
            <Cartao>
              <Subtitulo>Almoço de {pedirPor.nome.split(' ')[0]}</Subtitulo>
              {habitual === undefined && <ACarregar />}
              {habitual && (
                <Botao
                  titulo={`Repetir o habitual: ${habitual.texto}`}
                  aCarregar={ocupado}
                  aoCarregar={() =>
                    correr(async () => {
                      await pedirPorColega(eq.id, pedirPor.id, habitual.itens);
                      setPedirPor(null);
                    }, `Pedido feito. ${pedirPor.nome.split(' ')[0]} recebeu um aviso e pode trocar ou recusar.`)
                  }
                />
              )}
              {(cardapio ?? [])
                .filter((p) => !p.minimo_montavel)
                .slice(0, 12)
                .map((p) => (
                  <Botao
                    key={p.id}
                    titulo={`${p.nome} · ${formatarKz(p.preco)}`}
                    variante="texto"
                    aoCarregar={() =>
                      correr(async () => {
                        await pedirPorColega(eq.id, pedirPor.id, [{ cardapio_id: p.id, qtd: 1 }]);
                        setPedirPor(null);
                      }, `Pedido feito. ${pedirPor.nome.split(' ')[0]} recebeu um aviso e pode trocar ou recusar.`)
                    }
                  />
                ))}
              <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setPedirPor(null)} />
            </Cartao>
          )}

          {contaColega && eq.sou_responsavel && (
            <CartaoConta
              conta={contaColega}
              aoPagar={(metodo, referencia, valor) =>
                correr(async () => {
                  await pagarContaMes({ equipa: eq.id, cliente: contaColega.cliente_id, mes: inicioDoMes(contaColega.mes), metodo, referencia, valor });
                  setContaColega(await lerContaMes(eq.id, contaColega.cliente_id));
                }, `Pagamento enviado em nome de ${contaColega.nome.split(' ')[0]}.`)
              }
            />
          )}
        </>
      )}
    </Ecra>
  );
}
