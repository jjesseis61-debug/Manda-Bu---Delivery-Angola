import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Pressable, RefreshControl, ScrollView, Switch, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { MapaEntregas, type PontoEntrega } from '@/components/MapaEntregas';
import { ACarregar, Aviso, Cartao, Paragrafo, Subtitulo } from '@/components/ui';
import { pedidosOperador } from '@/lib/api';
import { guardarEntregasCache, lerEntregasCache } from '@/lib/entregasCache';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { usePartilharLocalizacao } from '@/lib/partilharLocalizacao';
import { guardarModoEstafeta, lerModoEstafeta } from '@/lib/preferencias';
import { cores, espaco, raio } from '@/lib/tema';
import type { PedidoOperador } from '@/lib/tipos';

// Estados que interessam a um estafeta (ainda por entregar). 'em_entrega' primeiro (a caminho).
const ESTADOS: Record<string, { rotulo: string; ordem: number } | undefined> = {
  em_entrega: { rotulo: 'A caminho', ordem: 0 },
  em_preparacao: { rotulo: 'Em preparação', ordem: 1 },
  confirmado: { rotulo: 'Confirmado', ordem: 2 },
};

/** Hoje: entregas por fazer, "Em serviço" (partilha a localização ao cliente), mapa e cache offline. */
export default function Inicio() {
  const router = useRouter();
  const [lista, setLista] = useState<PedidoOperador[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [semRede, setSemRede] = useState(false);
  const [aActualizar, setAActualizar] = useState(false);
  const [emServico, setEmServico] = useState(false);
  const [versao, setVersao] = useState(0);

  // Lê a preferência "em serviço" ao abrir
  useEffect(() => {
    void lerModoEstafeta().then((v) => setEmServico(v ?? false));
  }, []);

  // Partilha a posição ao cliente enquanto está em serviço (pára sozinho quando não há nada a caminho)
  const { aCaminho, erro: erroLoc } = usePartilharLocalizacao(emServico, versao);

  async function alternarServico(v: boolean) {
    setEmServico(v);
    await guardarModoEstafeta(v);
  }

  const carregar = useCallback(async () => {
    setAActualizar(true);
    try {
      const todos = await pedidosOperador();
      const entregas = todos.filter((p) => ESTADOS[p.estado]);
      setLista(entregas);
      setSemRede(false);
      setErro(null);
      setVersao((v) => v + 1);
      void guardarEntregasCache(entregas);
    } catch (e) {
      const cache = await lerEntregasCache();
      if (cache) {
        setLista(cache);
        setSemRede(true);
        setErro(null);
      } else {
        setErro(mensagemErro(e));
      }
    } finally {
      setAActualizar(false);
    }
  }, []);

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
                {emServico ? `A partilhar a tua posição · ${aCaminho} a caminho` : 'Liga para o cliente ver onde está a entrega'}
              </Text>
            </View>
            <Switch thumbColor="#FFFFFF" value={emServico} onValueChange={alternarServico} trackColor={{ true: cores.marca, false: cores.contorno }} />
          </View>
          {emServico && erroLoc && <Aviso tipo="erro">{erroLoc}</Aviso>}
        </Cartao>

        {pontos.length > 0 && <MapaEntregas pontos={pontos} />}

        <Subtitulo>Entregas de hoje</Subtitulo>
        {semRede && <Aviso>Sem ligação — a mostrar a última lista. Puxa para baixo quando tiveres rede.</Aviso>}
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista && ordenada.length === 0 && <Paragrafo suave>Sem entregas por fazer neste momento.</Paragrafo>}

        {ordenada.map((p) => {
          const est = ESTADOS[p.estado];
          const local = p.ponto_referencia || p.zona_nome || 'Ponto de entrega';
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
                <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                  <Text style={{ color: cores.textoSuave }}>{p.itens.reduce((n, i) => n + i.qtd, 0)} itens</Text>
                  <Text style={{ fontWeight: '700' }}>{formatarKz(p.a_pagar)}</Text>
                </View>
                {p.atribuido_a_nome && !p.atribuido_a_mim && (
                  <Text style={{ color: cores.textoSuave, fontSize: 12 }}>Atribuído a {p.atribuido_a_nome}</Text>
                )}
              </Cartao>
            </Pressable>
          );
        })}
      </ScrollView>
    </Guarda>
  );
}
