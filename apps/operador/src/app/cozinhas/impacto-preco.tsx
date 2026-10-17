import { useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Cartao, Ecra, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { impactoPrecoPrato, movimentoPrecoPrato } from '@/lib/api';
import { formatarData, formatarKz, mensagemErro, nomeEstadoPedido } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { ImpactoPreco, MovimentoPreco } from '@/lib/tipos';

/** Impacto dos preços de um prato: quantos pedidos foram atendidos a cada preço e o movimento com os clientes. */
export default function ImpactoPrecoEcra() {
  const { cardapio, nome } = useLocalSearchParams<{ cardapio: string; nome?: string }>();
  const [resumo, setResumo] = useState<ImpactoPreco[] | null>(null);
  const [movimento, setMovimento] = useState<MovimentoPreco[]>([]);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    if (!cardapio) return;
    Promise.all([impactoPrecoPrato(cardapio), movimentoPrecoPrato(cardapio)])
      .then(([r, m]) => {
        setResumo(r);
        setMovimento(m);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [cardapio]);

  return (
    <Guarda permissoes={['auditoria.ver']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!resumo && !erro && <ACarregar />}
        {resumo && (
          <>
            {nome ? <Subtitulo>{nome}</Subtitulo> : null}
            <Paragrafo suave>Pedidos atendidos (entregues e pagos) a cada preço que o prato já teve, e o movimento com os clientes.</Paragrafo>

            {resumo.length === 0 && <Paragrafo suave>Ainda não há pedidos deste prato.</Paragrafo>}
            {resumo.map((r) => (
              <Cartao key={r.preco}>
                <Linha esquerda={formatarKz(r.preco)} direita={`${r.pedidos_entregues} atendidos`} forte />
                <Linha esquerda="Clientes distintos" direita={String(r.clientes)} />
                <Linha esquerda="Total recebido" direita={formatarKz(r.total_kz)} />
                {r.pedidos_cancelados > 0 && (
                  <Text style={{ color: cores.textoSuave }}>{r.pedidos_cancelados} cancelado(s)/estornado(s) — não contam no total</Text>
                )}
              </Cartao>
            ))}

            <Subtitulo>Movimento</Subtitulo>
            {movimento.length === 0 && <Paragrafo suave>Sem movimento.</Paragrafo>}
            {movimento.map((m, i) => {
              const cancelado = m.estado === 'cancelado' || m.estado === 'estornado';
              return (
                <View key={i} style={{ gap: espaco.xs, borderLeftWidth: 3, borderLeftColor: cancelado ? cores.contorno : cores.marca, paddingLeft: espaco.s }}>
                  <Text style={{ color: cores.textoSuave }}>{formatarData(m.quando, true)}</Text>
                  <Text style={{ fontWeight: '600', color: cancelado ? cores.textoSuave : cores.texto }}>
                    {m.cliente} · {m.qtd}× {formatarKz(m.preco)}
                  </Text>
                  <Text style={{ color: cores.textoSuave }}>{nomeEstadoPedido[m.estado] ?? m.estado}</Text>
                </View>
              );
            })}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
