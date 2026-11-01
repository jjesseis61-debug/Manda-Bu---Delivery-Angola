import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { RefreshControl, ScrollView, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Cartao, Paragrafo, Subtitulo } from '@/components/ui';
import { pedidosOperador } from '@/lib/api';
import { guardarEntregasCache, lerEntregasCache } from '@/lib/entregasCache';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco, raio } from '@/lib/tema';
import type { PedidoOperador } from '@/lib/tipos';

// Estados que interessam a um estafeta (ainda por entregar). 'em_entrega' primeiro (a caminho).
const ESTADOS: Record<string, { rotulo: string; ordem: number } | undefined> = {
  em_entrega: { rotulo: 'A caminho', ordem: 0 },
  em_preparacao: { rotulo: 'Em preparação', ordem: 1 },
  confirmado: { rotulo: 'Confirmado', ordem: 2 },
};

/** Hoje: entregas por fazer, com cache offline (mostra a última lista mesmo sem rede). */
export default function Inicio() {
  const [lista, setLista] = useState<PedidoOperador[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [semRede, setSemRede] = useState(false);
  const [aActualizar, setAActualizar] = useState(false);

  const carregar = useCallback(async () => {
    setAActualizar(true);
    try {
      const todos = await pedidosOperador();
      const entregas = todos.filter((p) => ESTADOS[p.estado]);
      setLista(entregas);
      setSemRede(false);
      setErro(null);
      void guardarEntregasCache(entregas);
    } catch (e) {
      // Sem rede: mostra a última lista conhecida, se existir
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

  return (
    <Guarda permissoes={['entregas.registar']}>
      <ScrollView
        style={{ flex: 1, backgroundColor: cores.fundo }}
        contentContainerStyle={{ padding: espaco.l, gap: espaco.m, paddingBottom: espaco.xl * 2 }}
        refreshControl={<RefreshControl refreshing={aActualizar} onRefresh={carregar} tintColor={cores.marca} />}>
        <Subtitulo>Entregas de hoje</Subtitulo>
        {semRede && <Aviso>Sem ligação — a mostrar a última lista. Puxa para baixo quando tiveres rede.</Aviso>}
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista && ordenada.length === 0 && <Paragrafo suave>Sem entregas por fazer neste momento.</Paragrafo>}

        {ordenada.map((p) => {
          const est = ESTADOS[p.estado];
          const local = p.ponto_referencia || p.zona_nome || 'Ponto de entrega';
          return (
            <Cartao key={p.pedido_id}>
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
          );
        })}
      </ScrollView>
    </Guarda>
  );
}
