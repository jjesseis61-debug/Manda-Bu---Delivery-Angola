import * as Location from 'expo-location';
import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Linking, Pressable, RefreshControl, ScrollView, Switch, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { MapaEntregas, type PontoEntrega } from '@/components/MapaEntregas';
import { ACarregar, Aviso, Botao, Cartao, Paragrafo, Subtitulo } from '@/components/ui';
import { entregasFeitasHoje, pedidosOperador, type EntregaFeita } from '@/lib/api';
import { guardarEntregasCache, lerEntregasCache, lerEntregasCacheEm } from '@/lib/entregasCache';
import { lerFila, pedidosNaFila } from '@/lib/filaOffline';
import { distanciaKm, formatarDistancia, formatarKz, haQuantoTempo, horaLuanda, horaPrometida, mensagemErro } from '@/lib/formatar';
import { usePartilharLocalizacao } from '@/lib/partilharLocalizacao';
import { guardarModoEstafeta, lerModoEstafeta } from '@/lib/preferencias';
import { sincronizar } from '@/lib/sincronizar';
import { cores, espaco, raio } from '@/lib/tema';
import type { PedidoOperador } from '@/lib/tipos';

// Estados que interessam a um estafeta (ainda por entregar). 'em_entrega' primeiro (a caminho).
const ESTADOS: Record<string, { rotulo: string; ordem: number } | undefined> = {
  em_entrega: { rotulo: 'A caminho', ordem: 0 },
  em_preparacao: { rotulo: 'Em preparação', ordem: 1 },
  confirmado: { rotulo: 'Confirmado', ordem: 2 },
};

// Número de ajuda/despacho (público, vem do build). Sem ele, o botão de ajuda não aparece.
const TELEFONE_AJUDA = process.env.EXPO_PUBLIC_CONTACTO_TELEFONE || '';

const abrir = (url: string) => Linking.openURL(url).catch(() => undefined);
const urlComoChegar = (lat: number, lng: number) =>
  `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`;

/** Uma métrica do resumo do dia (número grande + rótulo). */
function Metrica({ valor, rotulo }: { valor: string; rotulo: string }) {
  return (
    <View style={{ flex: 1 }}>
      <Text style={{ fontWeight: '700', color: cores.texto, fontSize: 20 }}>{valor}</Text>
      <Text style={{ color: cores.textoSuave, fontSize: 13 }}>{rotulo}</Text>
    </View>
  );
}

/** Hoje: resumo do dia, entregas por fazer, "Em serviço", mapa, feitas hoje e cache offline. */
export default function Inicio() {
  const router = useRouter();
  const [lista, setLista] = useState<PedidoOperador[] | null>(null);
  const [feitas, setFeitas] = useState<EntregaFeita[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [semRede, setSemRede] = useState(false);
  const [aActualizar, setAActualizar] = useState(false);
  const [emServico, setEmServico] = useState(false);
  const [versao, setVersao] = useState(0);
  const [pendentes, setPendentes] = useState(0);
  const [naFila, setNaFila] = useState<Set<string>>(new Set());
  const [aSincronizar, setASincronizar] = useState(false);
  const [atualizadoEm, setAtualizadoEm] = useState<number | null>(null);
  const [minhaPos, setMinhaPos] = useState<{ lat: number; lng: number } | null>(null);

  // Lê a preferência "em serviço" ao abrir
  useEffect(() => {
    void lerModoEstafeta().then((v) => setEmServico(v ?? false));
  }, []);

  // Posição atual (uma leitura), só se a permissão já estiver dada — para mostrar a distância a cada
  // entrega sem pedir autorização neste ecrã (a autorização é pedida no "Em serviço").
  useEffect(() => {
    void (async () => {
      try {
        const { status } = await Location.getForegroundPermissionsAsync();
        if (status !== 'granted') return;
        const p = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
        setMinhaPos({ lat: p.coords.latitude, lng: p.coords.longitude });
      } catch {
        // sem localização: segue sem distâncias
      }
    })();
  }, []);

  // Partilha a posição ao cliente enquanto está em serviço (pára sozinho quando não há nada a caminho)
  const { aCaminho, erro: erroLoc } = usePartilharLocalizacao(emServico, versao);

  async function alternarServico(v: boolean) {
    setEmServico(v);
    await guardarModoEstafeta(v);
  }

  const carregar = useCallback(async () => {
    setAActualizar(true);
    // Primeiro tenta enviar o que está em fila (se houver rede); depois recarrega a lista.
    await sincronizar().catch(() => undefined);
    try {
      const [todos, feitasHoje] = await Promise.all([pedidosOperador(), entregasFeitasHoje()]);
      const entregas = todos.filter((p) => ESTADOS[p.estado]);
      setLista(entregas);
      setFeitas(feitasHoje);
      setSemRede(false);
      setErro(null);
      setVersao((v) => v + 1);
      setAtualizadoEm(Date.now());
      void guardarEntregasCache(entregas);
    } catch (e) {
      const cache = await lerEntregasCache();
      if (cache) {
        setLista(cache);
        setSemRede(true);
        setErro(null);
        setAtualizadoEm(await lerEntregasCacheEm());
      } else {
        setErro(mensagemErro(e));
      }
    } finally {
      setPendentes((await lerFila()).length);
      setNaFila(await pedidosNaFila());
      setAActualizar(false);
    }
  }, []);

  async function sincronizarAgora() {
    setASincronizar(true);
    await sincronizar().catch(() => undefined);
    await carregar();
    setASincronizar(false);
  }

  useFocusEffect(
    useCallback(() => {
      void carregar();
    }, [carregar]),
  );

  const ordenada = (lista ?? [])
    .slice()
    .sort((a, b) => (ESTADOS[a.estado]?.ordem ?? 9) - (ESTADOS[b.estado]?.ordem ?? 9));

  const pontos: PontoEntrega[] = ordenada
    .filter((p) => p.ponto_lat != null && p.ponto_lng != null)
    .map((p) => ({ id: p.pedido_id, lat: p.ponto_lat as number, lng: p.ponto_lng as number, titulo: p.cliente_nome, aCaminho: p.estado === 'em_entrega' }));

  // Resumo do dia: o que falta (por fazer / a receber) e o que já se fez (feitas / recebido hoje).
  const totalReceber = ordenada.reduce((s, p) => s + (p.a_pagar ?? 0), 0);
  const recebidoHoje = feitas.reduce((s, f) => s + (f.a_pagar ?? 0), 0);

  return (
    <Guarda permissoes={['entregas.registar']}>
      <ScrollView
        style={{ flex: 1, backgroundColor: cores.fundo }}
        contentContainerStyle={{ padding: espaco.l, gap: espaco.m, paddingBottom: espaco.xl * 2 }}
        refreshControl={<RefreshControl refreshing={aActualizar} onRefresh={carregar} tintColor={cores.marca} />}>
        {/* Em serviço */}
        <Cartao>
          <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
            <View style={{ flex: 1 }}>
              <Text style={{ fontWeight: '700', color: cores.texto }}>Em serviço</Text>
              <Text style={{ color: cores.textoSuave, fontSize: 13 }}>
                {emServico
                  ? `A partilhar a tua posição · ${aCaminho} a caminho`
                  : 'Liga ao começar o turno — o cliente passa a ver onde está a entrega.'}
              </Text>
            </View>
            <Switch thumbColor="#FFFFFF" value={emServico} onValueChange={alternarServico} trackColor={{ true: cores.marca, false: cores.contorno }} />
          </View>
          {emServico && erroLoc && <Aviso tipo="erro">{erroLoc}</Aviso>}
        </Cartao>

        {/* Resumo do dia: sempre visível (por fazer / a receber / feitas hoje / recebido hoje) */}
        <Cartao>
          <View style={{ flexDirection: 'row', gap: espaco.m }}>
            <Metrica valor={String(ordenada.length)} rotulo="por fazer" />
            <Metrica valor={formatarKz(totalReceber)} rotulo="a receber" />
          </View>
          <View style={{ flexDirection: 'row', gap: espaco.m, marginTop: espaco.s }}>
            <Metrica valor={String(feitas.length)} rotulo="feitas hoje" />
            <Metrica valor={formatarKz(recebidoHoje)} rotulo="recebido hoje" />
          </View>
          {atualizadoEm != null && (
            <Text style={{ color: cores.textoSuave, fontSize: 12, marginTop: espaco.xs }}>Atualizado {haQuantoTempo(atualizadoEm)}</Text>
          )}
        </Cartao>

        {pendentes > 0 && (
          <Cartao>
            <Text style={{ fontWeight: '700', color: cores.texto }}>{pendentes} por sincronizar</Text>
            <Text style={{ color: cores.textoSuave, fontSize: 13 }}>Entregas guardadas sem rede — envia quando tiveres ligação.</Text>
            <Botao titulo="Sincronizar agora" variante="leve" aCarregar={aSincronizar} aoCarregar={sincronizarAgora} />
          </Cartao>
        )}

        {pontos.length > 0 && <MapaEntregas pontos={pontos} />}

        <Subtitulo>Entregas de hoje</Subtitulo>
        {semRede && <Aviso>Sem ligação — a mostrar a última lista. Puxa para baixo quando tiveres rede.</Aviso>}
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista && ordenada.length === 0 && <Paragrafo suave>Sem entregas por fazer neste momento.</Paragrafo>}

        {ordenada.map((p) => {
          const est = ESTADOS[p.estado];
          const local = p.ponto_referencia || p.zona_nome || 'Ponto de entrega';
          const hp = horaPrometida(p.hora_prometida);
          const temGeo = p.ponto_lat != null && p.ponto_lng != null;
          const dist = minhaPos && temGeo ? distanciaKm(minhaPos.lat, minhaPos.lng, p.ponto_lat as number, p.ponto_lng as number) : null;
          return (
            <Pressable key={p.pedido_id} onPress={() => router.push({ pathname: '/entrega/[id]', params: { id: p.pedido_id } })}>
              <Cartao>
                <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: espaco.s }}>
                  <Text style={{ fontWeight: '700', color: cores.texto, flex: 1 }}>{p.cliente_nome}</Text>
                  {est && (
                    <Text
                      style={{
                        fontSize: 12,
                        fontWeight: '700',
                        color: p.estado === 'em_entrega' ? cores.marca : cores.textoSuave,
                        backgroundColor: p.estado === 'em_entrega' ? cores.marcaClara : cores.fundoSuave,
                        paddingHorizontal: espaco.s,
                        paddingVertical: 2,
                        borderRadius: raio,
                      }}>
                      {est.rotulo}
                    </Text>
                  )}
                </View>
                <Text style={{ color: cores.textoSuave }}>{local}{p.zona_nome && p.ponto_referencia ? ` · ${p.zona_nome}` : ''}</Text>
                {hp && (
                  <Text style={{ fontSize: 13, fontWeight: '700', color: hp.atrasado ? cores.erro : cores.textoSuave }}>
                    {hp.atrasado ? `⚠ atrasado · ${hp.texto}` : hp.texto}
                  </Text>
                )}
                {naFila.has(p.pedido_id) && <Text style={{ color: cores.sucesso, fontSize: 12, fontWeight: '700' }}>✓ guardado — a enviar</Text>}
                <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
                  <Text style={{ color: cores.textoSuave }}>{p.itens.reduce((n, i) => n + i.qtd, 0)} itens</Text>
                  <Text style={{ fontWeight: '700' }}>{formatarKz(p.a_pagar)}</Text>
                </View>
                {p.atribuido_a_nome && !p.atribuido_a_mim && (
                  <Text style={{ color: cores.textoSuave, fontSize: 12 }}>Atribuído a {p.atribuido_a_nome}</Text>
                )}
                {temGeo && (
                  <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginTop: espaco.xs }}>
                    <Text style={{ color: cores.textoSuave, fontSize: 13 }}>{dist != null ? `📍 ~${formatarDistancia(dist)}` : ''}</Text>
                    <Pressable
                      onPress={() => abrir(urlComoChegar(p.ponto_lat as number, p.ponto_lng as number))}
                      hitSlop={8}
                      style={{ paddingVertical: 6, paddingHorizontal: 12, borderRadius: raio, backgroundColor: cores.fundoSuave }}>
                      <Text style={{ color: cores.marca, fontWeight: '700', fontSize: 13 }}>Como chegar</Text>
                    </Pressable>
                  </View>
                )}
              </Cartao>
            </Pressable>
          );
        })}

        {/* Feitas hoje: o estafeta confirma o que já entregou e os valores */}
        {feitas.length > 0 && (
          <>
            <Subtitulo>Feitas hoje</Subtitulo>
            {feitas.map((f) => (
              <Cartao key={f.pedido_id}>
                <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
                  <Text style={{ color: cores.texto, flex: 1 }}>{f.cliente_nome}</Text>
                  <Text style={{ color: cores.textoSuave, fontSize: 13 }}>{horaLuanda(f.entregue_em)}</Text>
                </View>
                <Text style={{ fontWeight: '700', textAlign: 'right' }}>{formatarKz(f.a_pagar)}</Text>
              </Cartao>
            ))}
          </>
        )}

        {/* Ajuda: ligar ao despacho se precisar */}
        {TELEFONE_AJUDA !== '' && (
          <Botao titulo="Precisas de ajuda? Ligar ao despacho" variante="texto" aoCarregar={() => abrir(`tel:${TELEFONE_AJUDA}`)} />
        )}
      </ScrollView>
    </Guarda>
  );
}
