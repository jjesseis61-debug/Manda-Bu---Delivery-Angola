import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Linking, Share, Switch, Text, View } from 'react-native';

import { CapturarPonto } from '@/components/CapturarPonto';
import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { lerCozinhas, lerZonasEntrega } from '@/lib/api';
import {
  abrirFecharCozinha,
  adicionarMembroCondominio,
  apagarCondominio,
  dataLimiteISO,
  dataLimiteTexto,
  decidirMembroCondominio,
  erroCondominio,
  guardarCondominio,
  lerCondominios,
  lerMembrosCondominio,
  linkCondominio,
  mensagemConviteCondominio,
  reabreDaquiA,
  textoEstadoCozinha,
  textoVagas,
  type Condominio,
  type MembroCondominio,
  relatorioCondominio,
  type RelatorioCondominio,
} from '@/lib/condominios';
import { formatarData, formatarKz, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Cozinha, ZonaEntrega } from '@/lib/tipos';

type Edicao = {
  id?: string;
  nome: string;
  cozinha_id: string;
  zona_id: string;
  lat: string;
  lng: string;
  raio: string;
  vagas: string;
  ate: string;
  abertas: boolean;
  aprovacao: boolean;
  espera: boolean;
  modo: 'cozinha' | 'parceiro';
  parceiro: string;
};

const NOVO: Edicao = {
  nome: '', cozinha_id: '', zona_id: '', lat: '', lng: '', raio: '300', vagas: '50', ate: '',
  abertas: true, aprovacao: false, espera: true, modo: 'cozinha', parceiro: '',
};

const msg = (e: unknown) => erroCondominio(e) ?? mensagemErro(e);

function Interruptor({ rotulo, valor, aoMudar }: { rotulo: string; valor: boolean; aoMudar: (v: boolean) => void }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: espaco.s, marginBottom: espaco.s }}>
      <Text style={{ flex: 1 }}>{rotulo}</Text>
      <Switch
        thumbColor="#FFFFFF"
        accessibilityLabel={rotulo}
        value={valor}
        onValueChange={aoMudar}
        trackColor={{ true: cores.marca, false: cores.contorno }}
      />
    </View>
  );
}

/** Cozinha de condomínio: área no mapa, lista de moradores com vagas, abrir/fechar e modo de entrega */
export default function Condominios() {
  const { pode } = useSessao();
  const gestor = pode('cozinhas.gerir');
  const [lista, setLista] = useState<Condominio[] | null>(null);
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [zonas, setZonas] = useState<ZonaEntrega[]>([]);
  const [edicao, setEdicao] = useState<Edicao | null>(null);
  const [aberto, setAberto] = useState<string | null>(null);
  const [membros, setMembros] = useState<MembroCondominio[] | null>(null);
  const [novoMembro, setNovoMembro] = useState({ telefone: '', bloco: '', casa: '' });
  const [relatorio, setRelatorio] = useState<{ id: string; r: RelatorioCondominio | null } | null>(null);
  const [fechar, setFechar] = useState<{ id: string; horas: string } | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    lerCondominios()
      .then(setLista)
      .catch((e) => setErro(msg(e)));
    if (gestor) {
      lerCozinhas().then(setCozinhas).catch(() => setCozinhas([]));
      lerZonasEntrega().then(setZonas).catch(() => setZonas([]));
    }
  }, [gestor]);
  useFocusEffect(carregar);

  const carregarMembros = useCallback((id: string) => {
    setMembros(null);
    lerMembrosCondominio(id)
      .then(setMembros)
      .catch((e) => setErro(msg(e)));
  }, []);

  async function correr(f: () => Promise<unknown>, mensagem: string, depois?: () => void) {
    setErro(null);
    setSucesso(null);
    setOcupado(true);
    try {
      await f();
      setSucesso(mensagem);
      depois?.();
      carregar();
    } catch (e) {
      setErro(msg(e));
    } finally {
      setOcupado(false);
    }
  }

  const ate = edicao ? dataLimiteISO(edicao.ate) : null;
  const raioN = Number(edicao?.raio);
  const vagasN = Number(edicao?.vagas);
  const latN = Number((edicao?.lat ?? '').replace(',', '.'));
  const lngN = Number((edicao?.lng ?? '').replace(',', '.'));
  const valido =
    edicao !== null &&
    edicao.nome.trim().length >= 2 &&
    edicao.cozinha_id !== '' &&
    edicao.lat.trim() !== '' && Number.isFinite(latN) && Math.abs(latN) <= 90 &&
    edicao.lng.trim() !== '' && Number.isFinite(lngN) && Math.abs(lngN) <= 180 &&
    Number.isInteger(raioN) && raioN >= 30 && raioN <= 5000 &&
    Number.isInteger(vagasN) && vagasN >= 1 &&
    ate !== undefined;

  function editar(c: Condominio) {
    setEdicao({
      id: c.id, nome: c.nome, cozinha_id: c.cozinha_id, zona_id: c.zona_id ?? '',
      lat: String(c.centro_lat), lng: String(c.centro_lng), raio: String(c.raio_m), vagas: String(c.vagas),
      ate: dataLimiteTexto(c.inscricoes_ate), abertas: c.inscricoes_abertas, aprovacao: c.aprovacao_manual, espera: c.lista_espera,
      modo: c.modo_entrega, parceiro: c.parceiro_nome ?? '',
    });
  }

  function guardar() {
    if (!edicao || !valido) return;
    return correr(
      () =>
        guardarCondominio({
          id: edicao.id,
          nome: edicao.nome.trim(),
          cozinha_id: edicao.cozinha_id,
          zona_id: edicao.zona_id || null,
          centro_lat: latN,
          centro_lng: lngN,
          raio_m: raioN,
          vagas: vagasN,
          inscricoes_ate: ate ?? null,
          inscricoes_abertas: edicao.abertas,
          aprovacao_manual: edicao.aprovacao,
          lista_espera: edicao.espera,
          modo_entrega: edicao.modo,
          parceiro_nome: edicao.modo === 'parceiro' ? edicao.parceiro.trim() || null : null,
        }),
      'Condomínio guardado.',
      () => setEdicao(null),
    );
  }

  const formulario = edicao && (
    <Cartao>
      <Subtitulo>{edicao.id ? 'Editar condomínio' : 'Novo condomínio'}</Subtitulo>
      <Campo rotulo="Nome do condomínio" value={edicao.nome} onChangeText={(t) => setEdicao({ ...edicao, nome: t })} />
      <Text style={{ fontWeight: '700' }}>Cozinha do condomínio</Text>
      <Paragrafo suave>Fica escondida de quem não está na lista. Não pode ser a cozinha principal.</Paragrafo>
      <Escolha
        opcoes={cozinhas.map((k) => ({ valor: k.id, rotulo: k.nome }))}
        valor={edicao.cozinha_id}
        aoMudar={(v) => setEdicao({ ...edicao, cozinha_id: v })}
      />
      <Text style={{ fontWeight: '700' }}>Zona do condomínio (taxa de entrega)</Text>
      <Paragrafo suave>A taxa, a entrega grátis e o relatório "o que mais sai" usam esta zona. Sem zona, conta a do endereço.</Paragrafo>
      <Escolha
        opcoes={[{ valor: '', rotulo: 'Sem zona' }, ...zonas.map((z) => ({ valor: z.id, rotulo: z.nome }))]}
        valor={edicao.zona_id}
        aoMudar={(v) => setEdicao({ ...edicao, zona_id: v })}
      />
      <Subtitulo>Área do condomínio</Subtitulo>
      <Paragrafo suave>Marca o centro e o raio. Dentro dele (com 50 m de margem) os moradores vêem a cozinha pelo GPS.</Paragrafo>
      <CapturarPonto lat={edicao.lat} lng={edicao.lng} aoMudar={(la, lo) => setEdicao({ ...edicao, lat: la, lng: lo })} />
      <Campo
        rotulo="Raio (metros, 30–5000)"
        value={edicao.raio}
        keyboardType="number-pad"
        onChangeText={(t) => setEdicao({ ...edicao, raio: t.replace(/\D/g, '') })}
      />
      <Subtitulo>Lista de moradores</Subtitulo>
      <Campo
        rotulo="Vagas (quantos podem aderir)"
        value={edicao.vagas}
        keyboardType="number-pad"
        onChangeText={(t) => setEdicao({ ...edicao, vagas: t.replace(/\D/g, '') })}
      />
      <Campo
        rotulo="Inscrições até (DD/MM/AAAA, opcional)"
        value={edicao.ate}
        onChangeText={(t) => setEdicao({ ...edicao, ate: t })}
      />
      {ate === undefined && <Aviso>Data inválida. Usa DD/MM/AAAA ou deixa em branco.</Aviso>}
      <Interruptor rotulo="Inscrições abertas" valor={edicao.abertas} aoMudar={(v) => setEdicao({ ...edicao, abertas: v })} />
      <Interruptor
        rotulo="A cozinha aprova cada morador (senão entra logo até encher)"
        valor={edicao.aprovacao}
        aoMudar={(v) => setEdicao({ ...edicao, aprovacao: v })}
      />
      <Interruptor
        rotulo="Lista de espera quando as vagas enchem (entram por ordem quando abrir vaga)"
        valor={edicao.espera}
        aoMudar={(v) => setEdicao({ ...edicao, espera: v })}
      />
      <Subtitulo>Entregas</Subtitulo>
      <Escolha
        opcoes={[
          { valor: 'cozinha' as const, rotulo: 'Estafeta da cozinha' },
          { valor: 'parceiro' as const, rotulo: 'Serviço contratado' },
        ]}
        valor={edicao.modo}
        aoMudar={(v) => setEdicao({ ...edicao, modo: v })}
      />
      {edicao.modo === 'parceiro' && (
        <Campo rotulo="Nome do serviço contratado" value={edicao.parceiro} onChangeText={(t) => setEdicao({ ...edicao, parceiro: t })} />
      )}
      <Botao titulo="Guardar condomínio" desactivado={!valido} aCarregar={ocupado} aoCarregar={guardar} />
      {edicao.id && (
        <Botao
          titulo="Apagar condomínio"
          variante="texto"
          desactivado={ocupado}
          aoCarregar={() => correr(() => apagarCondominio(edicao.id as string), 'Condomínio apagado.', () => setEdicao(null))}
        />
      )}
      <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setEdicao(null)} />
    </Cartao>
  );

  return (
    <Guarda permissoes={['cozinhas.gerir', 'pedidos.gerir']}>
      <Ecra>
        <Paragrafo suave>
          Cozinha só para os moradores da lista: vêem-na quando estão no condomínio (GPS) e o servidor confirma que o endereço
          de entrega é lá dentro. Liga o interruptor «condominios» em Parâmetros (precisa de «multi_cozinha»).
        </Paragrafo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
        {lista === null && !erro && <ACarregar />}
        {lista?.length === 0 && !edicao && <Aviso>Ainda não há condomínios.</Aviso>}

        {lista?.map((c) => (
          <Cartao key={c.id}>
            <Text style={{ fontWeight: '700', fontSize: 16 }}>{c.nome}</Text>
            <Text style={{ color: cores.textoSuave }}>
              {c.cozinha}
              {c.zona ? ` · zona ${c.zona}` : ''} · raio {c.raio_m} m
            </Text>
            <Text>{textoEstadoCozinha(c)}</Text>
            <Text>{textoVagas(c)}</Text>
            <Text style={{ color: cores.textoSuave }}>
              {c.activos_30d} pediram nos últimos 30 dias
              {c.inscricoes_ate ? ` · inscrições até ${dataLimiteTexto(c.inscricoes_ate)}` : ''}
            </Text>
            <Text style={{ color: cores.textoSuave }}>
              Entregas: {c.modo_entrega === 'parceiro' ? `serviço contratado${c.parceiro_nome ? ` (${c.parceiro_nome})` : ''}` : 'estafeta da cozinha'}
            </Text>

            {c.cozinha_aberta ? (
              fechar?.id === c.id ? (
                <View style={{ gap: espaco.s }}>
                  <Campo
                    rotulo="Volta a abrir daqui a quantas horas? (1–24, opcional)"
                    value={fechar.horas}
                    keyboardType="number-pad"
                    onChangeText={(t) => setFechar({ id: c.id, horas: t.replace(/\D/g, '') })}
                  />
                  <Botao
                    titulo="Confirmar: fechar a cozinha"
                    aCarregar={ocupado}
                    aoCarregar={() =>
                      correr(
                        () => abrirFecharCozinha(c.cozinha_id, false, fechar.horas ? reabreDaquiA(Number(fechar.horas)) : null),
                        'Cozinha fechada. Os moradores vêem "fechada" durante 12 horas.',
                        () => setFechar(null),
                      )
                    }
                  />
                  <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setFechar(null)} />
                </View>
              ) : (
                <Botao titulo="Fechar a cozinha" variante="secundario" aoCarregar={() => setFechar({ id: c.id, horas: '' })} />
              )
            ) : (
              <Botao
                titulo="Abrir a cozinha"
                aCarregar={ocupado}
                aoCarregar={() => correr(() => abrirFecharCozinha(c.cozinha_id, true), 'Cozinha aberta.')}
              />
            )}

            <Botao
              titulo="Partilhar o link de inscrição"
              variante="texto"
              aoCarregar={() => Share.share({ message: mensagemConviteCondominio(c.nome, linkCondominio(c.codigo)) }).then(() => undefined)}
            />
            <Botao
              titulo={aberto === c.id ? 'Esconder moradores' : `Moradores (${c.activos}${c.pendentes ? ` + ${c.pendentes} pendentes` : ''})`}
              variante="texto"
              aoCarregar={() => {
                if (aberto === c.id) setAberto(null);
                else {
                  setAberto(c.id);
                  carregarMembros(c.id);
                }
              }}
            />
            <Botao
              titulo={relatorio?.id === c.id ? 'Esconder relatório' : 'Relatório (últimos 30 dias)'}
              variante="texto"
              aoCarregar={() => {
                if (relatorio?.id === c.id) return setRelatorio(null);
                setRelatorio({ id: c.id, r: null });
                const fim = new Date();
                const ini = new Date(fim.getTime() - 29 * 86400_000);
                const dia = (d: Date) => new Date(d.getTime() + 3600_000).toISOString().slice(0, 10);
                relatorioCondominio(c.id, dia(ini), dia(fim))
                  .then((r) => setRelatorio({ id: c.id, r }))
                  .catch((e) => {
                    setRelatorio(null);
                    setErro(msg(e));
                  });
              }}
            />
            {relatorio?.id === c.id && (
              <View style={{ gap: 2 }}>
                {relatorio.r === null ? (
                  <ACarregar />
                ) : (
                  <>
                    <Text>
                      {relatorio.r.entregues} pedidos entregues · {formatarKz(relatorio.r.vendas)}
                      {relatorio.r.ticket_medio ? ` · ticket médio ${formatarKz(relatorio.r.ticket_medio)}` : ''}
                    </Text>
                    <Text style={{ color: cores.textoSuave }}>
                      {relatorio.r.membros_que_pediram} de {relatorio.r.membros.activos} membros pediram · {relatorio.r.membros.novos} novos ·{' '}
                      {relatorio.r.membros.sairam} saíram · {relatorio.r.cancelados} cancelados · {relatorio.r.com_campanha} com promoção
                    </Text>
                    {relatorio.r.pratos.length > 0 && (
                      <Text style={{ color: cores.textoSuave }}>
                        Mais pedidos: {relatorio.r.pratos.map((p) => `${p.nome} (${p.qtd})`).join(', ')}
                      </Text>
                    )}
                    {relatorio.r.horas.length > 0 && (
                      <Text style={{ color: cores.textoSuave }}>
                        Horas com mais pedidos: {relatorio.r.horas.map((h) => `${h.hora}h (${h.pedidos})`).join(', ')}
                      </Text>
                    )}
                  </>
                )}
              </View>
            )}
            {gestor && <Botao titulo="Editar" variante="texto" aoCarregar={() => editar(c)} />}

            {aberto === c.id && (
              <View style={{ gap: espaco.s }}>
                {membros === null && <ACarregar />}
                {membros?.length === 0 && <Paragrafo suave>Ainda não há moradores.</Paragrafo>}
                {membros?.map((m) => (
                  <View key={m.id} style={{ borderTopWidth: 1, borderColor: cores.contorno, paddingTop: espaco.s }}>
                    <Text style={{ fontWeight: '700' }}>
                      {m.cliente_nome}
                      {m.estado === 'pendente' ? ' · à espera de aprovação' : m.estado === 'espera' ? ' · em lista de espera' : ''}
                    </Text>
                    <Text style={{ color: cores.textoSuave }}>
                      {[m.bloco && `Bloco ${m.bloco}`, m.casa && `Casa ${m.casa}`].filter(Boolean).join(' · ') || 'Sem casa indicada'}
                      {' · '}
                      {m.origem === 'link' ? 'pelo link' : 'pela cozinha'}
                      {m.ultimo_pedido ? ` · último pedido ${formatarData(m.ultimo_pedido)}` : ' · ainda não pediu'}
                    </Text>
                    {m.telefone && (
                      <Text style={{ color: cores.marca }} onPress={() => Linking.openURL(`tel:+244${m.telefone}`)}>
                        {m.telefone}
                      </Text>
                    )}
                    {m.estado === 'pendente' && (
                      <View style={{ flexDirection: 'row', gap: espaco.s }}>
                        <Botao
                          titulo="Aprovar"
                          aoCarregar={() => correr(() => decidirMembroCondominio(m.id, 'aprovar'), 'Morador aprovado.', () => carregarMembros(c.id))}
                        />
                        <Botao
                          titulo="Recusar"
                          variante="texto"
                          aoCarregar={() => correr(() => decidirMembroCondominio(m.id, 'recusar'), 'Pedido recusado.', () => carregarMembros(c.id))}
                        />
                      </View>
                    )}
                    {m.estado !== 'pendente' && (
                      <Botao
                        titulo={m.estado === 'espera' ? 'Tirar da lista de espera' : 'Remover da lista'}
                        variante="texto"
                        aoCarregar={() => correr(() => decidirMembroCondominio(m.id, 'remover'), 'Morador removido; a vaga ficou livre.', () => carregarMembros(c.id))}
                      />
                    )}
                  </View>
                ))}
                <Subtitulo>Acrescentar morador</Subtitulo>
                <Campo
                  rotulo="Telefone do morador (conta na app)"
                  value={novoMembro.telefone}
                  keyboardType="phone-pad"
                  onChangeText={(t) => setNovoMembro({ ...novoMembro, telefone: t })}
                />
                <View style={{ flexDirection: 'row', gap: espaco.s }}>
                  <View style={{ flex: 1 }}>
                    <Campo rotulo="Bloco" value={novoMembro.bloco} onChangeText={(t) => setNovoMembro({ ...novoMembro, bloco: t })} />
                  </View>
                  <View style={{ flex: 1 }}>
                    <Campo rotulo="Casa" value={novoMembro.casa} onChangeText={(t) => setNovoMembro({ ...novoMembro, casa: t })} />
                  </View>
                </View>
                <Botao
                  titulo="Acrescentar à lista"
                  desactivado={novoMembro.telefone.replace(/\D/g, '').length < 9}
                  aCarregar={ocupado}
                  aoCarregar={() =>
                    correr(
                      () => adicionarMembroCondominio(c.id, novoMembro.telefone, novoMembro.bloco, novoMembro.casa),
                      'Morador acrescentado.',
                      () => {
                        setNovoMembro({ telefone: '', bloco: '', casa: '' });
                        carregarMembros(c.id);
                      },
                    )
                  }
                />
              </View>
            )}
          </Cartao>
        ))}

        {edicao ? formulario : gestor && <Botao titulo="Novo condomínio" aoCarregar={() => setEdicao({ ...NOVO })} />}
      </Ecra>
    </Guarda>
  );
}
