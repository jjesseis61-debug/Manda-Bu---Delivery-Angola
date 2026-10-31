import { useRouter } from 'expo-router';
import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Ecra, Paragrafo } from '@/components/ui';
import { marcarNotificacoesVistas, minhasNotificacoes } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { rotaDaNotificacaoNoApp } from '@/lib/push';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import type { Notificacao } from '@/lib/tipos';

function haQuantoTempo(iso: string): string {
  const min = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000));
  if (min < 1) return 'agora';
  if (min < 60) return `há ${min} min`;
  const h = Math.round(min / 60);
  if (h < 24) return `há ${h} h`;
  return `há ${Math.round(h / 24)} dias`;
}

/** Sino: as notificações do funcionário dentro da app (histórico + estado). Ao abrir, marca como vistas. */
export default function Notificacoes() {
  const router = useRouter();
  const { pode } = useSessao();
  const gerir = pode('pedidos.gerir');
  const [lista, setLista] = useState<Notificacao[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      minhasNotificacoes()
        .then((n) => {
          setLista(n);
          // Abrir o sino = ler tudo
          void marcarNotificacoesVistas().catch(() => undefined);
        })
        .catch((e) => setErro(mensagemErro(e)));
    }, []),
  );

  // O gerente vê o histórico do pedido; o estafeta vai às suas entregas, onde aceita o pedido
  // reservado. As notificações sem pedido (login, reclamação, conferência…) abrem o seu ecrã.
  const destinoDe = (n: Notificacao) => rotaDaNotificacaoNoApp(n.dados, { podeGerir: gerir });

  const abrir = (n: Notificacao) => {
    const destino = destinoDe(n);
    if (destino) router.push(destino);
  };

  return (
    <Guarda permissoes={[]} permitir={() => true}>
      <Ecra>
        {erro && <Paragrafo suave>{erro}</Paragrafo>}
        {!lista && !erro && <ACarregar />}
        {lista && lista.length === 0 && <Paragrafo suave>Ainda não tens notificações.</Paragrafo>}
        {lista?.map((n) => {
          const nova = !n.vista_em;
          const temPedido = typeof n.dados?.pedido_id === 'string';
          const destino = destinoDe(n);
          return (
            <Pressable
              key={n.id}
              onPress={() => abrir(n)}
              disabled={!destino}
              style={{
                backgroundColor: nova ? cores.marcaClara : cores.fundoSuave,
                borderRadius: raio,
                padding: espaco.l,
                flexDirection: 'row',
                alignItems: 'flex-start',
                gap: espaco.s,
              }}>
              <View style={{ width: 8, height: 8, borderRadius: 4, marginTop: 6, backgroundColor: nova ? cores.marca : 'transparent' }} />
              <View style={{ flex: 1 }}>
                {n.titulo ? <Text style={{ fontWeight: '700', color: cores.texto }}>{n.titulo}</Text> : null}
                {n.corpo ? <Text style={{ color: cores.texto }}>{n.corpo}</Text> : null}
                <Text style={{ color: cores.textoSuave, fontSize: 12, marginTop: 2 }}>
                  {haQuantoTempo(n.criado_em)}
                  {destino ? (temPedido ? (gerir ? ' · toca para ver o pedido' : ' · toca para aceitar') : ' · toca para abrir') : ''}
                </Text>
              </View>
            </Pressable>
          );
        })}
        {lista && lista.length > 0 && <Paragrafo suave>Guardamos as notificações dos últimos 90 dias.</Paragrafo>}
      </Ecra>
    </Guarda>
  );
}
