import { useFocusEffect } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { Linking, Switch, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { caixasAbertas, marcarPagadorDistinto, mudarEstado, pedidosOperador } from '@/lib/api';
import { formatarData, formatarDia, formatarKz, mensagemErro, nomeEstadoPedido } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Caixa, PedidoOperador } from '@/lib/tipos';

const METODOS = ['Dinheiro', 'Multicaixa Express', 'TPA', 'Unitel Money', 'Transferência'];

type Parcela = { metodo: string; valor: string };
type Accao = { pedido: string; tipo: 'cancelar' | 'entregar' };

/** Próximo passo de cada estado e quem o pode dar */
const SEGUINTE: Record<string, { estado: string; rotulo: string; gerir: boolean } | undefined> = {
  pendente: { estado: 'confirmado', rotulo: 'Confirmar pedido', gerir: true },
  confirmado: { estado: 'em_preparacao', rotulo: 'Em preparação', gerir: true },
  em_preparacao: { estado: 'em_entrega', rotulo: 'Saiu para entrega', gerir: false },
};

/** E1. Entregas: pedidos por ponto de entrega, estados, caixa e formas de pagamento */
export default function Entregas() {
  const { pode } = useSessao();
  const gerir = pode('pedidos.gerir');
  const entregar = pode('entregas.registar');
  const [pedidos, setPedidos] = useState<PedidoOperador[] | null>(null);
  const [caixas, setCaixas] = useState<Caixa[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [accao, setAccao] = useState<Accao | null>(null);
  const [motivo, setMotivo] = useState('');
  const [caixa, setCaixa] = useState<string | null>(null);
  const [parcelas, setParcelas] = useState<Parcela[]>([]);
  const [ocupado, setOcupado] = useState<string | null>(null);

  const carregar = useCallback(() => {
    Promise.all([pedidosOperador(), caixasAbertas()])
      .then(([p, c]) => {
        setPedidos(p);
        setCaixas(c);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  const grupos = useMemo(() => {
    const m = new Map<string, PedidoOperador[]>();
    for (const p of pedidos ?? []) {
      const chave = p.ponto_entrega_id ?? `sem-ponto-${p.pedido_id}`;
      m.set(chave, [...(m.get(chave) ?? []), p]);
    }
    return [...m.values()];
  }, [pedidos]);

  function abrirEntrega(p: PedidoOperador) {
    const daCozinha = caixas.filter((c) => c.cozinha_id === p.cozinha_id);
    setCaixa(daCozinha.length === 1 ? daCozinha[0].id : null);
    setParcelas(p.a_pagar > 0 ? [{ metodo: 'Dinheiro', valor: String(p.a_pagar) }] : []);
    setAccao({ pedido: p.pedido_id, tipo: 'entregar' });
  }

  async function correr(id: string, f: () => Promise<unknown>) {
    setErro(null);
    setOcupado(id);
    try {
      await f();
      setAccao(null);
      setMotivo('');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(null);
    }
  }

  function painelEntrega(p: PedidoOperador) {
    const daCozinha = caixas.filter((c) => c.cozinha_id === p.cozinha_id);
    const soma = parcelas.reduce((s, x) => s + (Number(x.valor) || 0), 0);
    const certo = soma === p.a_pagar && parcelas.every((x) => Number(x.valor) > 0);
    return (
      <View style={{ gap: espaco.s }}>
        <Text style={{ fontWeight: '700' }}>Caixa onde o dinheiro entra</Text>
        {daCozinha.length === 0 && <Aviso tipo="erro">Não há caixa aberta desta cozinha. Abre a caixa antes de fechar a entrega.</Aviso>}
        {daCozinha.length > 0 && (
          <Escolha opcoes={daCozinha.map((c) => ({ valor: c.id, rotulo: `${c.posto} · ${formatarDia(c.data)}` }))} valor={caixa ?? ''} aoMudar={setCaixa} />
        )}
        {p.a_pagar === 0 ? (
          <Paragrafo suave>Nada a receber (pago com desconto ou crédito).</Paragrafo>
        ) : (
          <>
            <Text style={{ fontWeight: '700' }}>Como pagou ({formatarKz(p.a_pagar)})</Text>
            {parcelas.map((x, i) => (
              <View key={i} style={{ gap: espaco.xs }}>
                <Escolha
                  opcoes={METODOS.map((m) => ({ valor: m, rotulo: m }))}
                  valor={x.metodo}
                  aoMudar={(m) => setParcelas(parcelas.map((y, j) => (j === i ? { ...y, metodo: m } : y)))}
                />
                <Campo
                  rotulo="Valor (Kz)"
                  keyboardType="number-pad"
                  value={x.valor}
                  onChangeText={(t) => setParcelas(parcelas.map((y, j) => (j === i ? { ...y, valor: t.replace(/\D/g, '') } : y)))}
                />
                {parcelas.length > 1 && (
                  <Botao titulo="Tirar este pagamento" variante="texto" aoCarregar={() => setParcelas(parcelas.filter((_, j) => j !== i))} />
                )}
              </View>
            ))}
            <Botao
              titulo="Juntar outra forma de pagamento"
              variante="texto"
              aoCarregar={() => setParcelas([...parcelas, { metodo: 'Multicaixa Express', valor: String(Math.max(p.a_pagar - soma, 0)) }])}
            />
            {!certo && <Aviso>Os pagamentos somam {formatarKz(soma)}; têm de somar {formatarKz(p.a_pagar)}.</Aviso>}
          </>
        )}
        <Botao
          titulo="Entregue e pago"
          aCarregar={ocupado === p.pedido_id}
          desactivado={!caixa || !certo}
          aoCarregar={() =>
            correr(p.pedido_id, () =>
              mudarEstado(p.pedido_id, 'entregue_pago', {
                caixa: caixa ?? undefined,
                parcelas: parcelas.map((x) => ({ metodo: x.metodo, valor: Number(x.valor) })),
              }),
            )
          }
        />
        <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAccao(null)} />
      </View>
    );
  }

  function cartao(p: PedidoOperador) {
    const seguinte = SEGUINTE[p.estado];
    const aberto = accao?.pedido === p.pedido_id;
    return (
      <Cartao key={p.pedido_id}>
        <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
          <Text style={{ fontWeight: '700', fontSize: 16 }}>{p.cliente_nome}</Text>
          <Text style={{ fontWeight: '700', color: cores.marca }}>{nomeEstadoPedido[p.estado] ?? p.estado}</Text>
        </View>
        {p.cliente_telefone && (
          <Text style={{ color: cores.marca }} onPress={() => Linking.openURL(`tel:+244${p.cliente_telefone}`)}>
            Ligar {p.cliente_telefone}
          </Text>
        )}
        {p.itens.map((i, n) => (
          <Text key={n}>
            {i.qtd} × {i.nome}
          </Text>
        ))}
        {p.observacoes && <Text style={{ fontStyle: 'italic' }}>“{p.observacoes}”</Text>}
        <Text style={{ color: cores.textoSuave }}>
          Pedido {formatarData(p.criado_em, true)}
          {p.hora_prometida ? ` · prometido ${formatarData(p.hora_prometida, true)}` : ''}
        </Text>
        <Text style={{ fontWeight: '700' }}>
          A receber: {formatarKz(p.a_pagar)}
          {p.desconto_indicacao > 0 ? ` (desconto ${formatarKz(p.desconto_indicacao)})` : ''}
          {p.credito_indicacao_usado > 0 ? ` (crédito ${formatarKz(p.credito_indicacao_usado)})` : ''}
        </Text>
        {entregar && (p.estado === 'em_entrega' || p.estado === 'em_preparacao') && (
          <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
            <Text style={{ flex: 1 }}>Quem pagou não é o cliente do pedido</Text>
            <Switch
              value={!!p.pagador_distinto}
              trackColor={{ true: cores.marca, false: cores.linha }}
              onValueChange={(v) => correr(p.pedido_id, () => marcarPagadorDistinto(p.pedido_id, v))}
            />
          </View>
        )}

        {aberto && accao?.tipo === 'entregar' && painelEntrega(p)}
        {aberto && accao?.tipo === 'cancelar' && (
          <>
            <Campo rotulo="Motivo do cancelamento" value={motivo} onChangeText={setMotivo} />
            <Botao
              titulo="Cancelar pedido"
              desactivado={!motivo.trim()}
              aCarregar={ocupado === p.pedido_id}
              aoCarregar={() => correr(p.pedido_id, () => mudarEstado(p.pedido_id, 'cancelado', { motivo: motivo.trim() }))}
            />
            <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAccao(null)} />
          </>
        )}
        {!aberto && (
          <View style={{ gap: espaco.s }}>
            {seguinte && (gerir || (!seguinte.gerir && entregar)) && (
              <Botao
                titulo={seguinte.rotulo}
                aCarregar={ocupado === p.pedido_id}
                aoCarregar={() => correr(p.pedido_id, () => mudarEstado(p.pedido_id, seguinte.estado))}
              />
            )}
            {p.estado === 'em_entrega' && (gerir || entregar) && <Botao titulo="Entregue e pago…" aoCarregar={() => abrirEntrega(p)} />}
            {gerir && <Botao titulo="Cancelar…" variante="texto" aoCarregar={() => setAccao({ pedido: p.pedido_id, tipo: 'cancelar' })} />}
          </View>
        )}
      </Cartao>
    );
  }

  return (
    <Guarda permissoes={['entregas.registar', 'pedidos.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!pedidos && !erro && <ACarregar />}
        {pedidos && pedidos.length === 0 && <Paragrafo suave>Sem pedidos em curso.</Paragrafo>}
        <Botao titulo="Actualizar" variante="texto" aoCarregar={carregar} />
        {grupos.map((lista) => {
          const p = lista[0];
          return (
            <View key={p.ponto_entrega_id ?? p.pedido_id} style={{ gap: espaco.s }}>
              <Subtitulo>
                {p.ponto_tipo === 'empresa' ? 'Empresa' : 'Casa'}
                {p.ponto_referencia ? ` · ${p.ponto_referencia}` : ''}
                {p.zona_nome ? ` · ${p.zona_nome}` : ''}
                {lista.length > 1 ? ` · ${lista.length} pedidos` : ''}
              </Subtitulo>
              {p.ponto_lat !== null && p.ponto_lng !== null && (
                <Text
                  style={{ color: cores.marca, fontWeight: '600' }}
                  onPress={() => Linking.openURL(`https://maps.google.com/?q=${p.ponto_lat},${p.ponto_lng}`)}>
                  Abrir no mapa
                </Text>
              )}
              {lista.map(cartao)}
            </View>
          );
        })}
      </Ecra>
    </Guarda>
  );
}
