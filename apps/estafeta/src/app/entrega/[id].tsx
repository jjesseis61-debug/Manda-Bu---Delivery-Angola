import { useLocalSearchParams, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { useFocusEffect } from 'expo-router';
import { Image, Linking, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { caixasAbertas, mudarEstado, pedidosOperador } from '@/lib/api';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { enviarComprovativo, escolherFoto } from '@/lib/fotos';
import { cores, espaco } from '@/lib/tema';
import type { Caixa, PedidoOperador } from '@/lib/tipos';

const METODOS = ['Dinheiro', 'Multicaixa Express', 'TPA', 'Unitel Money', 'Transferência'];
const electronico = (m: string) => m !== 'Dinheiro';

type Parcela = { metodo: string; valor: string; referencia: string; foto: string | null };
const novaParcela = (valor: number): Parcela => ({ metodo: 'Dinheiro', valor: String(valor), referencia: '', foto: null });
const parcelaCompleta = (x: Parcela) =>
  Number(x.valor) > 0 && (!electronico(x.metodo) || (x.referencia.trim().length >= 4 && !!x.foto));

// Só dígitos; para o WhatsApp acrescenta o indicativo de Angola se faltar.
const soDigitos = (t: string) => t.replace(/\D/g, '');
function urlWhatsapp(t: string) {
  let n = soDigitos(t);
  if (n.length === 9 && n.startsWith('9')) n = `244${n}`;
  return `https://wa.me/${n}`;
}
const abrir = (url: string) => Linking.openURL(url).catch(() => undefined);

/** Detalhe de uma entrega: navegar, contactar o cliente e avançar o estado (saiu / entregue). */
export default function Entrega() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const [pedido, setPedido] = useState<PedidoOperador | null | undefined>(undefined); // undefined = a carregar
  const [caixas, setCaixas] = useState<Caixa[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  // Fecho da entrega (pagamento)
  const [aFechar, setAFechar] = useState(false);
  const [caixa, setCaixa] = useState<string | null>(null);
  const [parcelas, setParcelas] = useState<Parcela[]>([]);

  const carregar = useCallback(async () => {
    if (!id) return;
    try {
      const [todos, cx] = await Promise.all([pedidosOperador(), caixasAbertas().catch(() => [] as Caixa[])]);
      setCaixas(cx);
      setPedido(todos.find((p) => p.pedido_id === id) ?? null);
    } catch (e) {
      setErro(mensagemErro(e));
    }
  }, [id]);

  useFocusEffect(
    useCallback(() => {
      void carregar();
    }, [carregar]),
  );

  async function marcar(estado: string, extra?: Parameters<typeof mudarEstado>[2]) {
    if (!pedido) return;
    setOcupado(true);
    setErro(null);
    try {
      await mudarEstado(pedido.pedido_id, estado, extra);
      router.back();
    } catch (e) {
      setErro(mensagemErro(e));
      setOcupado(false);
    }
  }

  function comecarFecho() {
    if (!pedido) return;
    setParcelas([novaParcela(pedido.a_pagar)]);
    const daCozinha = caixas.filter((c) => c.cozinha_id === pedido.cozinha_id);
    setCaixa(daCozinha[0]?.id ?? null);
    setAFechar(true);
  }

  async function fotografar(i: number, origem: 'camera' | 'galeria') {
    try {
      const uri = await escolherFoto(origem, false);
      if (uri) setParcelas((ps) => ps.map((x, j) => (j === i ? { ...x, foto: uri } : x)));
    } catch (e) {
      setErro(mensagemErro(e));
    }
  }

  async function entregar() {
    if (!pedido) return;
    setOcupado(true);
    setErro(null);
    try {
      const enviadas = await Promise.all(
        parcelas.map(async (x, i) =>
          electronico(x.metodo)
            ? { metodo: x.metodo, valor: Number(x.valor), referencia: x.referencia.trim(), comprovativo: await enviarComprovativo(pedido.pedido_id, x.foto!, i) }
            : { metodo: x.metodo, valor: Number(x.valor) },
        ),
      );
      await mudarEstado(pedido.pedido_id, 'entregue_pago', { caixa: caixa ?? undefined, parcelas: enviadas });
      router.back();
    } catch (e) {
      setErro(mensagemErro(e));
      setOcupado(false);
    }
  }

  if (pedido === undefined) return <Ecra><ACarregar /></Ecra>;
  if (pedido === null)
    return (
      <Ecra>
        <Paragrafo>Esta entrega já não está na lista (pode ter sido concluída ou reatribuída).</Paragrafo>
        <Botao titulo="Voltar" variante="texto" aoCarregar={() => router.back()} />
      </Ecra>
    );

  const temGeo = pedido.ponto_lat != null && pedido.ponto_lng != null;
  const local = pedido.ponto_referencia || pedido.zona_nome || 'Ponto de entrega';
  const daCozinha = caixas.filter((c) => c.cozinha_id === pedido.cozinha_id);
  const podeEntregar = parcelas.length > 0 && parcelas.every(parcelaCompleta) && !!caixa;

  return (
    <Guarda permissoes={['entregas.registar']}>
      <Ecra>
        <Subtitulo>{pedido.cliente_nome}</Subtitulo>
        <Text style={{ color: cores.textoSuave }}>{local}{pedido.zona_nome && pedido.ponto_referencia ? ` · ${pedido.zona_nome}` : ''}</Text>

        {/* Contactar o cliente */}
        <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
          {pedido.cliente_telefone && <Botao titulo="Ligar" variante="leve" aoCarregar={() => abrir(`tel:${pedido.cliente_telefone}`)} />}
          {pedido.cliente_telefone && <Botao titulo="WhatsApp" variante="whatsapp" aoCarregar={() => abrir(urlWhatsapp(pedido.cliente_telefone!))} />}
          {temGeo && <Botao titulo="Como chegar" variante="secundario" aoCarregar={() => abrir(`https://www.google.com/maps/dir/?api=1&destination=${pedido.ponto_lat},${pedido.ponto_lng}`)} />}
        </View>

        {/* Itens e valor */}
        <Cartao>
          {pedido.itens.map((it, i) => (
            <View key={i} style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
              <Text style={{ color: cores.texto }}>{it.qtd}× {it.nome}</Text>
              <Text style={{ color: cores.textoSuave }}>{formatarKz(it.qtd * it.preco_unitario)}</Text>
            </View>
          ))}
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginTop: espaco.xs }}>
            <Text style={{ fontWeight: '700' }}>A pagar</Text>
            <Text style={{ fontWeight: '700' }}>{formatarKz(pedido.a_pagar)}</Text>
          </View>
          {pedido.observacoes ? <Paragrafo suave>Nota: {pedido.observacoes}</Paragrafo> : null}
        </Cartao>

        {erro && <Aviso tipo="erro">{erro}</Aviso>}

        {/* Acção conforme o estado */}
        {!aFechar && (pedido.estado === 'confirmado' || pedido.estado === 'em_preparacao') && (
          <Botao titulo="Saiu para entrega" aCarregar={ocupado} aoCarregar={() => marcar('em_entrega')} />
        )}

        {!aFechar && pedido.estado === 'em_entrega' && (
          <Botao titulo="Marcar como entregue" aCarregar={ocupado} aoCarregar={comecarFecho} />
        )}

        {/* Fecho da entrega: caixa + pagamento + foto do comprovativo */}
        {aFechar && (
          <Cartao estilo={{ gap: espaco.s }}>
            <Subtitulo>Pagamento</Subtitulo>
            <Text style={{ fontWeight: '700' }}>Caixa onde o dinheiro entra</Text>
            {daCozinha.length === 0 ? (
              <Aviso tipo="erro">Não há caixa aberta desta cozinha. Avisa a loja para abrir a caixa.</Aviso>
            ) : (
              <Escolha opcoes={daCozinha.map((c) => ({ valor: c.id, rotulo: c.posto }))} valor={caixa ?? ''} aoMudar={setCaixa} />
            )}

            {parcelas.map((x, i) => (
              <Cartao key={i} estilo={{ gap: espaco.xs }}>
                <Escolha opcoes={METODOS.map((m) => ({ valor: m, rotulo: m }))} valor={x.metodo} aoMudar={(m) => setParcelas((ps) => ps.map((y, j) => (j === i ? { ...y, metodo: m } : y)))} />
                <Campo rotulo="Valor (Kz)" keyboardType="number-pad" value={x.valor} onChangeText={(t) => setParcelas((ps) => ps.map((y, j) => (j === i ? { ...y, valor: t.replace(/\D/g, '') } : y)))} />
                {electronico(x.metodo) && (
                  <>
                    <Campo rotulo="Referência" value={x.referencia} onChangeText={(t) => setParcelas((ps) => ps.map((y, j) => (j === i ? { ...y, referencia: t } : y)))} />
                    {x.foto ? (
                      <Image source={{ uri: x.foto }} style={{ width: '100%', height: 160, borderRadius: 8 }} accessibilityLabel="Foto do comprovativo" />
                    ) : (
                      <Aviso>Fotografa o comprovativo (talão do TPA ou ecrã do Multicaixa / Unitel Money).</Aviso>
                    )}
                    <View style={{ flexDirection: 'row', gap: espaco.s }}>
                      <Botao titulo={x.foto ? 'Tirar outra' : 'Fotografar'} variante="leve" aoCarregar={() => fotografar(i, 'camera')} />
                      <Botao titulo="Galeria" variante="texto" aoCarregar={() => fotografar(i, 'galeria')} />
                    </View>
                  </>
                )}
                {parcelas.length > 1 && <Botao titulo="Tirar este pagamento" variante="texto" aoCarregar={() => setParcelas((ps) => ps.filter((_, j) => j !== i))} />}
              </Cartao>
            ))}

            <Botao titulo="+ Outro pagamento" variante="texto" aoCarregar={() => setParcelas((ps) => [...ps, novaParcela(0)])} />
            {!podeEntregar && <Aviso>Confirma a caixa, o valor e (nos electrónicos) a referência e a foto.</Aviso>}
            <Botao titulo="Confirmar entrega" aCarregar={ocupado} desactivado={!podeEntregar} aoCarregar={entregar} />
            <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setAFechar(false)} />
          </Cartao>
        )}
      </Ecra>
    </Guarda>
  );
}
