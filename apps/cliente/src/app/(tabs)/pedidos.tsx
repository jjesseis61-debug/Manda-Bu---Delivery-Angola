import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { ACarregar, Aviso, Botao, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { lerPedidos } from '@/lib/api';
import { rotuloAgendamento } from '@/lib/agendar';
import { useCarrinho } from '@/lib/carrinho';
import { corEstadoPedido, formatarKz, mensagemErro, nomeEstadoPedido } from '@/lib/formatar';
import { montarRepeticao } from '@/lib/repetir';
import { cores } from '@/lib/tema';
import type { Pedido } from '@/lib/tipos';

const TERMINADO = ['entregue_pago', 'cancelado', 'estornado'];

export default function Pedidos() {
  const router = useRouter();
  const carrinho = useCarrinho();
  const [pedidos, setPedidos] = useState<Pedido[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aRepetir, setARepetir] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      lerPedidos()
        .then(setPedidos)
        .catch((e) => setErro(mensagemErro(e)));
    }, []),
  );

  async function pedirDeNovo(p: Pedido) {
    setErro(null);
    setARepetir(p.id);
    try {
      const { linhas, cozinha, faltam } = await montarRepeticao(p.itens);
      if (linhas.length === 0) {
        setErro('Os pratos deste pedido já não estão disponíveis.');
        return;
      }
      carrinho.repor(linhas, cozinha);
      router.push({ pathname: '/carrinho', params: faltam.length > 0 ? { faltam: faltam.join(', ') } : {} });
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setARepetir(null);
    }
  }

  if (erro && !pedidos) return <Ecra><Aviso tipo="erro">{erro}</Aviso></Ecra>;
  if (!pedidos) return <ACarregar />;
  return (
    <Ecra>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {pedidos.length === 0 && (
        <Paragrafo suave>Faz o teu primeiro pedido: escolhe um prato no Início e recebe-o em casa ou no trabalho.</Paragrafo>
      )}
      {pedidos.map((p) => (
        <Pressable key={p.id} onPress={() => router.push({ pathname: '/pedido/[id]', params: { id: p.id } })}>
          <Cartao>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, flexShrink: 1 }}>
                <View style={{ width: 9, height: 9, borderRadius: 5, backgroundColor: corEstadoPedido[p.estado] }} />
                <Text style={{ fontWeight: '700', fontSize: 15, color: corEstadoPedido[p.estado] }}>
                  {nomeEstadoPedido[p.estado]}
                </Text>
              </View>
              <Text style={{ fontWeight: '700', fontSize: 15 }}>
                {formatarKz(p.subtotal + p.taxa_entrega - p.desconto_indicacao)}
              </Text>
            </View>
            <Text style={{ color: cores.textoSuave }}>
              {new Date(p.criado_em).toLocaleString('pt-PT', { dateStyle: 'short', timeStyle: 'short' })} ·{' '}
              {p.itens.map((i) => `${i.qtd}× ${i.nome}`).join(', ')}
            </Text>
            {p.agendado_para && !TERMINADO.includes(p.estado) && new Date(p.agendado_para) > new Date() && (
              <Text style={{ color: corEstadoPedido.confirmado, fontWeight: '600' }}>
                Agendado: {rotuloAgendamento(p.agendado_para)}
              </Text>
            )}
            {TERMINADO.includes(p.estado) && (
              <Botao titulo="Pedir de novo" variante="texto" aCarregar={aRepetir === p.id} aoCarregar={() => pedirDeNovo(p)} />
            )}
          </Cartao>
        </Pressable>
      ))}
    </Ecra>
  );
}
