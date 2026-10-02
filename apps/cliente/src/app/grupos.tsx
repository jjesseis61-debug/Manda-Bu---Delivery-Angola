import { Redirect, useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text } from 'react-native';

import { ACarregar, Aviso, Botao, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { meusGrupos } from '@/lib/api';
import { horaLuanda, mensagemErro, nomeEstadoGrupo } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { MeuGrupo } from '@/lib/tipos';

/** Pedidos de grupo do cliente e atalho para criar um (C12) */
export default function Grupos() {
  const router = useRouter();
  const { carregado, ligada } = useSessao();
  const [lista, setLista] = useState<MeuGrupo[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!ligada('pedidos_grupo')) return;
      meusGrupos()
        .then(setLista)
        .catch((e) => setErro(mensagemErro(e)));
    }, [ligada]),
  );

  // Aberto por link ou notificação: espera pelos interruptores antes de decidir
  if (!carregado) return <ACarregar />;
  if (!ligada('pedidos_grupo')) return <Redirect href="/inicio" />;
  if (!lista && !erro) return <ACarregar />;

  return (
    <Ecra>
      <Paragrafo>
        Organiza o almoço com os colegas: cada um escolhe e paga o seu pedido e chega tudo junto, numa só entrega. A taxa de entrega
        é dividida por todos.
      </Paragrafo>
      <Botao titulo="Criar pedido de grupo" aoCarregar={() => router.push('/grupo/novo')} />
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {lista?.map((g) => (
        <Pressable key={g.codigo_convite} onPress={() => router.push({ pathname: '/grupo/[codigo]', params: { codigo: g.codigo_convite } })}>
          <Cartao>
            <Text style={{ fontSize: 16, fontWeight: '700' }}>
              Grupo das {horaLuanda(g.hora_entrega)}
              {g.sou_organizador ? ' · organizas tu' : ''}
            </Text>
            {g.local && <Text style={{ color: cores.textoSuave }}>{g.local}</Text>}
            <Text>
              {nomeEstadoGrupo[g.estado]} · {g.participantes} {g.participantes === 1 ? 'pessoa' : 'pessoas'}
            </Text>
          </Cartao>
        </Pressable>
      ))}
    </Ecra>
  );
}
