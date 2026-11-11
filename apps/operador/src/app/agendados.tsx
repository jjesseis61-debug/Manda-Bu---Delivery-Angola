import { useFocusEffect } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { Linking, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import {
  agrupar,
  comoPedido,
  diaLuanda,
  estadoAlerta,
  faltam,
  horaMinLuanda,
  instanteLuanda,
  intervaloDo,
  linkMapa,
  linkWhatsapp,
  linhasCsvAgendados,
  listaProducao,
  NOME_ALERTA,
  nomeDia,
  textoLembrete,
  type LinhaProducao,
  type Periodo,
} from '@/lib/agendados';
import { agendadosOperador, alertasAgendados, lerCozinhas, mudarEstado, reagendarPedido, type AlertaAgendado } from '@/lib/api';
import { escaparHtml, exportarCsv, imprimirHtml } from '@/lib/exportar';
import { formatarKz, mensagemErro, nomeEstadoPedido, paraCsv } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { detalharItem, htmlTalaoCozinha, htmlTalaoEntrega, numeroCurto } from '@/lib/talao';
import { cores, espaco } from '@/lib/tema';
import type { AgendadoOperador, Cozinha } from '@/lib/tipos';

const MOTIVOS_CANCELAMENTO = [
  'Acabou um ingrediente',
  'Avaria na cozinha (gás, luz ou equipamento)',
  'A cozinha não conseguiria entregar a horas',
  'Endereço fora da zona de entrega',
  'O cliente pediu para cancelar',
];

const hh = (h: number) => `${String(h).padStart(2, '0')}:00`;

function htmlProducao(titulo: string, linhas: LinhaProducao[]): string {
  const corpo = linhas
    .map(
      (l) =>
        `<div class="prato">${l.qtd}× ${escaparHtml(l.prato)}</div>` +
        l.opcoes.map((o) => `<div class="op">${o.qtd}× ${escaparHtml(o.nome)}</div>`).join('') +
        l.sem.map((s) => `<div class="op"><b>SEM ${escaparHtml(s.nome)}: ${s.qtd}</b></div>`).join(''),
    )
    .join('');
  return `<html><head><meta charset="utf-8"><style>
    body { font-family: -apple-system, Roboto, Arial, sans-serif; font-size: 14px; margin: 4mm; }
    h1 { font-size: 18px; margin: 0 0 6px; } .prato { font-weight: 700; font-size: 16px; margin-top: 8px; }
    .op { padding-left: 16px; }
  </style></head><body><h1>${escaparHtml(titulo)}</h1>${corpo || '<p>Nada a preparar.</p>'}</body></html>`;
}

/** Pedidos agendados: por dia e hora, com tudo para preparar e entregar, e a lista de produção */
export default function Agendados() {
  const { pode } = useSessao();
  const gerir = pode('pedidos.gerir');
  const [periodo, setPeriodo] = useState<Periodo>('hoje');
  const [de, setDe] = useState('');
  const [ate, setAte] = useState('');
  const [cozinha, setCozinha] = useState('todas');
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [lista, setLista] = useState<AgendadoOperador[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [aberto, setAberto] = useState<string | null>(null);
  const [cancelar, setCancelar] = useState<{ pedido: string; motivo: string; outro: string } | null>(null);
  const [reagendar, setReagendar] = useState<{ pedido: string; dia: string; hora: string; motivo: string } | null>(null);
  const [alertas, setAlertas] = useState<AlertaAgendado[]>([]);
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [verProducao, setVerProducao] = useState(false);
  const [agora, setAgora] = useState(() => new Date());

  const intervalo = useMemo(() => intervaloDo(periodo, agora, de, ate), [periodo, agora, de, ate]);

  const carregar = useCallback(() => {
    if (!intervalo) return;
    setErro(null);
    setAgora(new Date());
    Promise.all([
      agendadosOperador(intervalo.inicio, intervalo.fim, cozinha === 'todas' ? null : cozinha),
      lerCozinhas().catch(() => [] as Cozinha[]),
      alertasAgendados(intervalo.inicio, intervalo.fim, cozinha === 'todas' ? null : cozinha).catch(() => [] as AlertaAgendado[]),
    ])
      .then(([a, c, al]) => {
        setLista(a);
        setCozinhas(c);
        setAlertas(al);
      })
      .catch((e) => setErro(mensagemErro(e)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [intervalo?.inicio, intervalo?.fim, cozinha]);

  useFocusEffect(
    useCallback(() => {
      carregar();
      const t = setInterval(carregar, 60_000);
      return () => clearInterval(t);
    }, [carregar]),
  );

  const dias = useMemo(() => agrupar(lista ?? []), [lista]);
  const producao = useMemo(() => listaProducao(lista ?? []), [lista]);
  const porConfirmar = (lista ?? []).filter((a) => estadoAlerta(a, agora) !== null);
  const urgentes = porConfirmar.filter((a) => estadoAlerta(a, agora) === 'urgente');

  function imprimir(html: string) {
    setErro(null);
    imprimirHtml(html).catch((e) => setErro(String((e as Error)?.message ?? e)));
  }

  function correr(pedido: string, f: () => Promise<unknown>, ok: string) {
    setOcupado(pedido);
    setErro(null);
    setAviso(null);
    f()
      .then(() => {
        setAviso(ok);
        setCancelar(null);
        setReagendar(null);
        carregar();
      })
      .catch((e) => setErro(mensagemErro(e)))
      .finally(() => setOcupado(null));
  }

  function abrir(url: string | null) {
    if (url) Linking.openURL(url).catch(() => setErro('Não foi possível abrir.'));
  }

  function cartao(a: AgendadoOperador) {
    const alerta = estadoAlerta(a, agora);
    const expandido = aberto === a.pedido_id;
    const emCancelar = cancelar?.pedido === a.pedido_id ? cancelar : null;
    const motivo = emCancelar ? (emCancelar.motivo === 'outro' ? emCancelar.outro.trim() : emCancelar.motivo) : '';
    const descontos = a.desconto_indicacao + a.credito_indicacao_usado;
    const meusAlertas = alertas.filter((x) => x.pedido_id === a.pedido_id);
    const emReagendar = reagendar?.pedido === a.pedido_id ? reagendar : null;
    const novaHora = emReagendar ? instanteLuanda(emReagendar.dia, emReagendar.hora) : null;
    return (
      <View
        key={a.pedido_id}
        style={{
          borderTopWidth: 1,
          borderTopColor: cores.linha,
          paddingTop: espaco.s,
          gap: espaco.xs,
          borderLeftWidth: alerta ? 4 : 0,
          borderLeftColor: alerta === 'urgente' ? cores.erro : cores.aviso,
          paddingLeft: alerta ? espaco.s : 0,
        }}
      >
        <Text style={{ fontWeight: '700', color: cores.texto }} onPress={() => setAberto(expandido ? null : a.pedido_id)}>
          {horaMinLuanda(a.agendado_para)}
          {' · '}#{numeroCurto(a.pedido_id)} · {a.cliente_nome}
          {'  '}
          <Text style={{ fontWeight: '400', color: cores.textoSuave }}>
            {nomeEstadoPedido[a.estado] ?? a.estado} · {faltam(a.agendado_para, agora)}
          </Text>
        </Text>
        {alerta === 'urgente' && <Aviso tipo="erro">URGENTE: já entrou na fila e ainda não foi confirmado.</Aviso>}
        {alerta === 'por_confirmar' && <Aviso>Por confirmar — liga ao cliente ou confirma.</Aviso>}
        {meusAlertas.map((x) => (
          <Aviso key={x.tipo + x.detalhe}>{`${NOME_ALERTA[x.tipo] ?? x.tipo}: ${x.detalhe}`}</Aviso>
        ))}
        {a.itens.map((i, n) => {
          const d = detalharItem(i);
          return (
            <View key={n}>
              <Text style={{ color: cores.texto, fontWeight: '600' }}>
                {i.qtd}× {d.nome}
              </Text>
              {d.opcoes.map((o) => (
                <Text key={o} style={{ color: cores.texto, paddingLeft: espaco.m }}>
                  • {o}
                </Text>
              ))}
              {d.sem.length > 0 && (
                <Text style={{ color: cores.erro, paddingLeft: espaco.m, fontWeight: '700' }}>SEM {d.sem.join(', ')}</Text>
              )}
            </View>
          );
        })}
        {a.observacoes ? <Aviso>OBS: {a.observacoes}</Aviso> : null}
        <Text style={{ color: cores.textoSuave }}>
          {[a.ponto_referencia, a.zona_nome, cozinha === 'todas' && cozinhas.length > 1 ? a.cozinha_nome : null]
            .filter(Boolean)
            .join(' · ') || 'Sem morada'}
          {a.empresa ? ' · Empresa' : ''}
          {a.grupo ? ' · Pedido de grupo' : ''}
        </Text>
        <Text style={{ color: cores.texto, fontWeight: '700' }}>
          A receber: {formatarKz(a.a_pagar)}
          {descontos > 0 ? `  (descontos ${formatarKz(descontos)})` : ''}
          {a.pago_pacote > 0 ? `  (pacote ${formatarKz(a.pago_pacote)})` : ''}
          {a.valor_empresa > 0 ? `  (empresa ${formatarKz(a.valor_empresa)})` : ''}
        </Text>
        {a.atribuido_a_nome && <Text style={{ color: cores.textoSuave }}>➤ {a.atribuido_a_nome}</Text>}

        {!expandido && <Botao titulo="Acções" variante="texto" aoCarregar={() => setAberto(a.pedido_id)} />}
        {expandido && emReagendar && (
          <View style={{ gap: espaco.s }}>
            <Text style={{ fontWeight: '700' }}>Nova hora (a pedido do cliente)</Text>
            <View style={{ flexDirection: 'row', gap: espaco.s }}>
              <View style={{ flex: 1 }}>
                <Campo rotulo="Dia (aaaa-mm-dd)" value={emReagendar.dia} maxLength={10}
                  onChangeText={(t) => setReagendar({ ...emReagendar, dia: t })} />
              </View>
              <View style={{ flex: 1 }}>
                <Campo rotulo="Hora (HH:MM)" value={emReagendar.hora} maxLength={5}
                  onChangeText={(t) => setReagendar({ ...emReagendar, hora: t })} />
              </View>
            </View>
            <Campo rotulo="Motivo (opcional)" value={emReagendar.motivo} maxLength={200}
              onChangeText={(t) => setReagendar({ ...emReagendar, motivo: t })} />
            {!novaHora && <Paragrafo suave>Escreve o dia e a hora (ex.: 2026-11-12 e 12:30).</Paragrafo>}
            <Paragrafo suave>O cliente recebe um aviso com a nova hora.</Paragrafo>
            <Botao
              titulo="Reagendar"
              desactivado={!novaHora}
              aCarregar={ocupado === a.pedido_id}
              aoCarregar={() =>
                novaHora &&
                correr(a.pedido_id, () => reagendarPedido(a.pedido_id, novaHora, emReagendar.motivo.trim() || null),
                  'Pedido reagendado; o cliente foi avisado.')
              }
            />
            <Botao titulo="Voltar" variante="texto" aoCarregar={() => setReagendar(null)} />
          </View>
        )}
        {expandido && !emCancelar && !emReagendar && (
          <View style={{ gap: espaco.s }}>
            {gerir && a.estado === 'pendente' && (
              <Botao
                titulo="Confirmar agora"
                aCarregar={ocupado === a.pedido_id}
                aoCarregar={() => correr(a.pedido_id, () => mudarEstado(a.pedido_id, 'confirmado'), 'Pedido confirmado.')}
              />
            )}
            {a.cliente_telefone && (
              <Botao titulo={`📞 Ligar ${a.cliente_telefone}`} variante="secundario" aoCarregar={() => abrir(`tel:+244${a.cliente_telefone}`)} />
            )}
            {a.cliente_telefone && (
              <Botao
                titulo="WhatsApp: lembrar o cliente"
                variante="whatsapp"
                aoCarregar={() => abrir(linkWhatsapp(a.cliente_telefone, textoLembrete(a)))}
              />
            )}
            {linkMapa(a.ponto_lat, a.ponto_lng) && (
              <Botao titulo="🗺 Abrir no Google Maps" variante="leve" aoCarregar={() => abrir(linkMapa(a.ponto_lat, a.ponto_lng))} />
            )}
            <Botao titulo="🖨 Talão da cozinha" variante="leve" aoCarregar={() => imprimir(htmlTalaoCozinha(comoPedido(a)))} />
            <Botao titulo="🖨 Talão de entrega" variante="leve" aoCarregar={() => imprimir(htmlTalaoEntrega(comoPedido(a)))} />
            <Paragrafo suave>O estafeta atribui-se quando o pedido entrar na fila (cerca de 90 min antes).</Paragrafo>
            {gerir && !a.grupo && (a.estado === 'pendente' || a.estado === 'confirmado') && (
              <Botao
                titulo="📅 Reagendar…"
                variante="leve"
                aoCarregar={() =>
                  setReagendar({ pedido: a.pedido_id, dia: diaLuanda(a.agendado_para), hora: horaMinLuanda(a.agendado_para), motivo: '' })
                }
              />
            )}
            {gerir && (
              <Botao
                titulo="Cancelar pedido…"
                variante="texto"
                aoCarregar={() => setCancelar({ pedido: a.pedido_id, motivo: '', outro: '' })}
              />
            )}
            <Botao titulo="Fechar" variante="texto" aoCarregar={() => setAberto(null)} />
          </View>
        )}
        {expandido && emCancelar && (
          <View style={{ gap: espaco.s }}>
            <Text style={{ fontWeight: '700' }}>Porque é que se cancela?</Text>
            <Escolha
              opcoes={[...MOTIVOS_CANCELAMENTO.map((m) => ({ valor: m, rotulo: m })), { valor: 'outro', rotulo: 'Outro…' }]}
              valor={emCancelar.motivo}
              aoMudar={(m) => setCancelar({ ...emCancelar, motivo: m })}
            />
            {emCancelar.motivo === 'outro' && (
              <Campo
                rotulo="Motivo (o cliente vai ler)"
                value={emCancelar.outro}
                maxLength={200}
                onChangeText={(t) => setCancelar({ ...emCancelar, outro: t })}
              />
            )}
            <Paragrafo suave>O cliente recebe um pedido de desculpa com o motivo e não paga nada.</Paragrafo>
            <Botao
              titulo="Cancelar pedido"
              desactivado={!motivo}
              aCarregar={ocupado === a.pedido_id}
              aoCarregar={() =>
                correr(a.pedido_id, () => mudarEstado(a.pedido_id, 'cancelado', { motivo }), 'Pedido cancelado; o cliente foi avisado.')
              }
            />
            <Botao titulo="Voltar" variante="texto" aoCarregar={() => setCancelar(null)} />
          </View>
        )}
      </View>
    );
  }

  const tituloPeriodo = intervalo
    ? intervalo.inicio === intervalo.fim
      ? nomeDia(intervalo.inicio, agora)
      : `${nomeDia(intervalo.inicio, agora)} a ${nomeDia(intervalo.fim, agora)}`
    : '';

  return (
    <Guarda permissoes={['pedidos.gerir', 'entregas.registar']}>
      <Ecra>
        <Escolha<Periodo>
          opcoes={[
            { valor: 'hoje', rotulo: 'Hoje' },
            { valor: 'amanha', rotulo: 'Amanhã' },
            { valor: 'semana', rotulo: '7 dias' },
            { valor: 'datas', rotulo: 'Datas…' },
          ]}
          valor={periodo}
          aoMudar={setPeriodo}
        />
        {periodo === 'datas' && (
          <View style={{ flexDirection: 'row', gap: espaco.s }}>
            <View style={{ flex: 1 }}>
              <Campo rotulo="De (aaaa-mm-dd)" value={de} onChangeText={setDe} placeholder="2026-11-12" maxLength={10} />
            </View>
            <View style={{ flex: 1 }}>
              <Campo rotulo="Até (opcional)" value={ate} onChangeText={setAte} placeholder="2026-11-15" maxLength={10} />
            </View>
          </View>
        )}
        {periodo === 'datas' && !intervalo && <Paragrafo suave>Escreve a data inicial (ex.: 2026-11-12).</Paragrafo>}
        {cozinhas.length > 1 && (
          <Escolha
            opcoes={[{ valor: 'todas', rotulo: 'Todas' }, ...cozinhas.map((c) => ({ valor: c.id, rotulo: c.nome }))]}
            valor={cozinha}
            aoMudar={setCozinha}
          />
        )}
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {aviso && <Aviso tipo="sucesso">{aviso}</Aviso>}
        {urgentes.length > 0 && (
          <Aviso tipo="erro">
            {urgentes.length} agendado{urgentes.length === 1 ? '' : 's'} já na fila sem confirmação.
          </Aviso>
        )}
        {porConfirmar.length > urgentes.length && (
          <Aviso>
            {porConfirmar.length - urgentes.length} agendado{porConfirmar.length - urgentes.length === 1 ? '' : 's'} por confirmar.
          </Aviso>
        )}
        {intervalo && !lista && !erro && <ACarregar />}

        {lista && (
          <Cartao estilo={{ gap: espaco.s }}>
            <Subtitulo>
              {tituloPeriodo}: {lista.length} pedido{lista.length === 1 ? '' : 's'} · {formatarKz(lista.reduce((s, a) => s + a.a_pagar, 0))}
            </Subtitulo>
            {alertas.length > 0 && (
              <Aviso>{`${new Set(alertas.map((x) => x.pedido_id)).size} pedido(s) com alertas: horário, doses ou hora cheia.`}</Aviso>
            )}
            <Botao
              titulo={verProducao ? 'Esconder lista de produção' : '🍳 Lista de produção (o que preparar)'}
              variante="secundario"
              aoCarregar={() => setVerProducao(!verProducao)}
            />
            {verProducao && (
              <View style={{ gap: espaco.xs }}>
                {producao.length === 0 && <Paragrafo suave>Nada a preparar neste período.</Paragrafo>}
                {producao.map((l) => (
                  <View key={l.prato}>
                    <Text style={{ fontWeight: '700', color: cores.texto }}>
                      {l.qtd}× {l.prato}
                    </Text>
                    {l.opcoes.map((o) => (
                      <Text key={o.nome} style={{ color: cores.texto, paddingLeft: espaco.m }}>
                        {o.qtd}× {o.nome}
                      </Text>
                    ))}
                    {l.sem.map((s) => (
                      <Text key={s.nome} style={{ color: cores.erro, paddingLeft: espaco.m }}>
                        SEM {s.nome}: {s.qtd}
                      </Text>
                    ))}
                  </View>
                ))}
                {producao.length > 0 && (
                  <Botao
                    titulo="🖨 Imprimir lista de produção"
                    variante="leve"
                    aoCarregar={() => imprimir(htmlProducao(`Produção — ${tituloPeriodo}`, producao))}
                  />
                )}
              </View>
            )}
          </Cartao>
        )}

        {lista && lista.length === 0 && (
          <Paragrafo suave>Sem pedidos agendados neste período.</Paragrafo>
        )}

        {dias.map((d) => (
          <Cartao key={d.dia} estilo={{ gap: espaco.s }}>
            <Subtitulo>
              {nomeDia(d.dia, agora)} · {d.pedidos} pedido{d.pedidos === 1 ? '' : 's'} · {formatarKz(d.total)}
            </Subtitulo>
            {d.horas.map((h) => (
              <View key={h.hora} style={{ gap: espaco.s }}>
                <Text style={{ fontWeight: '700', color: cores.marca }}>
                  {hh(h.hora)}–{hh(h.hora + 1)} · {h.pedidos.length} pedido{h.pedidos.length === 1 ? '' : 's'} · {formatarKz(h.total)}
                </Text>
                {h.pedidos.map(cartao)}
              </View>
            ))}
          </Cartao>
        ))}
        {lista && lista.length > 0 && intervalo && (
          <Botao
            titulo="⬇ Exportar lista (CSV)"
            variante="texto"
            aoCarregar={() =>
              exportarCsv(`agendados-${intervalo.inicio}-${intervalo.fim}.csv`, paraCsv(linhasCsvAgendados(lista))).catch((e) =>
                setErro(mensagemErro(e)),
              )
            }
          />
        )}
        <Botao titulo="Actualizar" variante="texto" aoCarregar={carregar} />
        <Paragrafo suave>
          Entram na fila de Pedidos e entregas cerca de 90 min antes. A cozinha recebe um aviso se o pedido ainda estiver por
          confirmar perto da hora.
        </Paragrafo>
      </Ecra>
    </Guarda>
  );
}

