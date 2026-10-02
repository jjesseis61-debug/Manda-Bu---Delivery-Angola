import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { ACarregar, Aviso, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { lerPedidos } from '@/lib/api';
import { formatarKz, mensagemErro, nomeEstadoPedido } from '@/lib/formatar';
import { cores } from '@/lib/tema';
import type { Pedido } from '@/lib/tipos';

export default function Pedidos() {
  const router = useRouter();
  const [pedidos, setPedidos] = useState<Pedido[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      lerPedidos()
        .then(setPedidos)
        .catch((e) => setErro(mensagemErro(e)));
    }, []),
  );

  if (erro) return <Ecra><Aviso tipo="erro">{erro}</Aviso></Ecra>;
  if (!pedidos) return <ACarregar />;
  return (
    <Ecra>
      {pedidos.length === 0 && <Paragrafo suave>Ainda não fizeste nenhum pedido.</Paragrafo>}
      {pedidos.map((p) => (
        <Pressable key={p.id} onPress={() => router.push({ pathname: '/pedido/[id]', params: { id: p.id } })}>
          <Cartao>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
              <Text style={{ fontWeight: '700', fontSize: 15 }}>{nomeEstadoPedido[p.estado]}</Text>
              <Text style={{ fontWeight: '700', fontSize: 15 }}>
                {formatarKz(p.subtotal + p.taxa_entrega - p.desconto_indicacao)}
              </Text>
            </View>
            <Text style={{ color: cores.textoSuave }}>
              {new Date(p.criado_em).toLocaleString('pt-PT', { dateStyle: 'short', timeStyle: 'short' })} ·{' '}
              {p.itens.map((i) => `${i.qtd}× ${i.nome}`).join(', ')}
            </Text>
          </Cartao>
        </Pressable>
      ))}
    </Ecra>
  );
}
