import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { Image, Linking, Switch, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { alertasAbertos, caixasAbertas, informarAtraso, lerCozinhas, marcarPagadorDistinto, mudarEstado, pedidosOperador } from '@/lib/api';
import { formatarData, formatarDia, formatarKz, mensagemErro, nomeEstadoPedido } from '@/lib/formatar';
import { enviarComprovativo, escolherFoto } from '@/lib/fotos';
import { usePartilharLocalizacao } from '@/lib/partilharLocalizacao';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { AlertaPedido, Caixa, Cozinha, PedidoOperador } from '@/lib/tipos';

const METODOS = ['Dinheiro', 'Multicaixa Express', 'TPA', 'Unitel Money', 'Transferência'];

/** Pagamento na entrega; os electrónicos levam a referência e a foto do comprovativo */
type Parcela = { metodo: string; valor: string; referencia: string; foto: string | null };

const novaParcela = (metodo: string, valor: number): Parcela => ({ metodo, valor: String(valor), referencia: '', foto: null });
const electronico = (metodo: string) => metodo !== 'Dinheiro';
/** Parcela pronta: valor positivo e, se for electrónica, referência (4+ caracteres) e foto */
function parcelaCompleta(x: Parcela): boolean {
  return Number(x.valor) > 0 && (!electronico(x.metodo) || (x.referencia.trim().length >= 4 && !!x.foto));
}
type Accao = { pedido: string; tipo: 'cancelar' | 'entregar' | 'atraso' };

/** Motivos de atraso mais comuns (o texto vai tal e qual para o cliente) */
const MOTIVOS_ATRASO = [
  'Muitos pedidos neste momento',
  'Trânsito',
  'Chuva',
  'Falta de um ingrediente, já estamos a resolver',
  'O estafeta está a terminar outra entrega',
];

/** Próximo passo de cada estado e quem o pode dar */
const SEGUINTE: Record<string, { estado: string; rotulo: string; gerir: boolean } | undefined> = {
  pendente: { estado: 'confirmado', rotulo: 'Confirmar pedido', gerir: true },
  confirmado: { estado: 'em_preparacao', rotulo: 'Em preparação', gerir: true },
  em_preparacao: { estado: 'em_entrega', rotulo: 'Saiu para entrega', gerir: false },
};

/** E1. Entregas: pedidos por ponto de entrega, estados, caixa e formas de pagamento */
export default function Entregas() {
  const { pode } = useSessao();
  const router = useRouter();
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
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [filtroCozinha, setFiltroCozinha] = useState('todas');
  const [versao, setVersao] = useState(0);
  const [alertas, setAlertas] = useState<Record<string, AlertaPedido[]>>({});
  const [atraso, setAtraso] = useState({ motivo: MOTIVOS_ATRASO[0], outro: '', minutos: '' });

  const carregar = useCallback(() => {
    Promise.all([pedidosOperador(), caixasAbertas(), lerCozinhas().catch(() => [] as Cozinha[]), alertasAbertos().catch(() => [] as AlertaPedido[])])
      .then(([p, c, cz, al]) => {
        const porPedido: Record<string, AlertaPedido[]> = {};
        for (const a of al) porPedido[a.pedido_id] = [...(porPedido[a.pedido_id] ?? []), a];
        setAlertas(porPedido);
        setPedidos(p);
        setCaixas(c);
        setCozinhas(cz);
        setVersao((v) => v + 1);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  // I11: com pedidos a caminho, envia a posição para o cliente acompanhar a entrega
  const partilha = usePartilharLocalizacao(entregar && (pedidos ?? []).some((p) => p.estado === 'em_entrega'), versao);

  const grupos = useMemo(() => {
    const m = new Map<string, PedidoOperador[]>();
    for (const p of (pedidos ?? []).filter((x) => filtroCozinha === 'todas' || x.cozinha_id === filtroCozinha)) {
      const chave = p.ponto_entrega_id ?? `sem-ponto-${p.pedido_id}`;
      m.set(chave, [...(m.get(chave) ?? []), p]);
    }
    return [...m.values()];
  }, [pedidos, filtroCozinha]);

  function abrirEntrega(p: PedidoOperador) {
    const daCozinha = caixas.filter((c) => c.cozinha_id === p.cozinha_id);
    setCaixa(daCozinha.length === 1 ? daCozinha[0].id : null);
    setParcelas(p.a_pagar > 0 ? [novaParcela('Dinheiro', p.a_pagar)] : []);
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
    const completas = parcelas.every(parcelaCompleta);
    const mudar = (i: number, m: Partial<Parcela>) => setParcelas(parcelas.map((y, j) => (j === i ? { ...y, ...m } : y)));
    async function fotografar(i: number, origem: 'camera' | 'galeria') {
      try {
        const uri = await escolherFoto(origem, false);
        if (uri) mudar(i, { foto: uri });
      } catch (e) {
        setErro(mensagemErro(e));
      }
    }
    // Envia as fotos dos comprovativos e só depois marca o pedido como entregue e pago
    async function entregarPago() {
      const enviadas = await Promise.all(
        parcelas.map(async (x, i) =>
          electronico(x.metodo)
            ? {
                metodo: x.metodo,
                valor: Number(x.valor),
                referencia: x.referencia.trim(),
                comprovativo: await enviarComprovativo(p.pedido_id, x.foto!, i),
              }
            : { metodo: x.metodo, valor: Number(x.valor) },
        ),
      );
      await mudarEstado(p.pedido_id, 'entregue_pago', { caixa: caixa ?? undefined, parcelas: enviadas });
    }
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
                  aoMudar={(m) => mudar(i, { metodo: m })}
                />
                <Campo rotulo="Valor (Kz)" keyboardType="number-pad" value={x.valor} onChangeText={(t) => mudar(i, { valor: t.replace(/\D/g, '') })} />
                {electronico(x.metodo) && (
                  <>
                    <Campo
                      rotulo="Referência da transacção"
                      value={x.referencia}
                      autoCapitalize="characters"
                      maxLength={60}
                      onChangeText={(t) => mudar(i, { referencia: t })}
                    />
                    {x.foto ? (
                      <Image
                        source={{ uri: x.foto }}
                        accessibilityLabel="Foto do comprovativo"
                        style={{ width: '100%', height: 180, borderRadius: 8, backgroundColor: cores.contorno }}
                        resizeMode="contain"
                      />
                    ) : (
                      <Aviso>Fotografa o comprovativo (talão do TPA ou ecrã do Multicaixa / Unitel Money).</Aviso>
                    )}
                    <View style={{ flexDirection: 'row', gap: espaco.s }}>
                      <Botao titulo={x.foto ? 'Tirar outra foto' : 'Fotografar comprovativo'} variante="leve" aoCarregar={() => fotografar(i, 'camera')} />
                      <Botao titulo="Galeria" variante="texto" aoCarregar={() => fotografar(i, 'galeria')} />
                    </View>
                  </>
                )}
                {parcelas.length > 1 && (
                  <Botao titulo="Tirar este pagamento" variante="texto" aoCarregar={() => setParcelas(parcelas.filter((_, j) => j !== i))} />
                )}
              </View>
            ))}
            <Botao
              titulo="Juntar outra forma de pagamento"
              variante="texto"
              aoCarregar={() => setParcelas([...parcelas, novaParcela('Multicaixa Express', Math.max(p.a_pagar - soma, 0))])}
            />
            {!certo && <Aviso>Os pagamentos somam {formatarKz(soma)}; têm de somar {formatarKz(p.a_pagar)}.</Aviso>}
            {certo && !completas && <Aviso>Falta a referência ou a foto de um pagamento electrónico.</Aviso>}
          </>
        )}
        <Botao
          titulo="Entregue e pago"
          aCarregar={ocupado === p.pedido_id}
          desactivado={!caixa || !certo || !completas}
          aoCarregar={() => correr(p.pedido_id, entregarPago)}
        />
        <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAccao(null)} />
      </View>
    );
  }

  function painelAtraso(p: PedidoOperador) {
    const motivo = atraso.motivo === 'outro' ? atraso.outro.trim() : atraso.motivo;
    return (
      <View style={{ gap: espaco.s }}>
        <Text style={{ fontWeight: '700' }}>Porque é que vai atrasar?</Text>
        <Escolha
          opcoes={[...MOTIVOS_ATRASO.map((m) => ({ valor: m, rotulo: m })), { valor: 'outro', rotulo: 'Outro…' }]}
          valor={atraso.motivo}
          aoMudar={(m) => setAtraso({ ...atraso, motivo: m })}
        />
        {atraso.motivo === 'outro' && (
          <Campo rotulo="Motivo (o cliente vai ler)" value={atraso.outro} maxLength={200} onChangeText={(t) => setAtraso({ ...atraso, outro: t })} />
        )}
        <Campo
          rotulo="Mais quantos minutos? (opcional)"
          keyboardType="number-pad"
          value={atraso.minutos}
          onChangeText={(t) => setAtraso({ ...atraso, minutos: t.replace(/\D/g, '') })}
        />
        <Botao
          titulo="Avisar o cliente"
          desactivado={!motivo}
          aCarregar={ocupado === p.pedido_id}
          aoCarregar={() => correr(p.pedido_id, () => informarAtraso(p.pedido_id, motivo, atraso.minutos ? Number(atraso.minutos) : null))}
        />
        <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAccao(null)} />
      </View>
    );
  }

  function avisos(p: PedidoOperador) {
    const lista = alertas[p.pedido_id] ?? [];
    const semConfirmacao = lista.find((a) => a.tipo === 'sem_confirmacao');
    const atrasado = lista.find((a) => a.tipo === 'atraso');
    return (
      <>
        {semConfirmacao && p.estado === 'pendente' && (
          <Aviso tipo="erro">Por confirmar há mais de {semConfirmacao.minutos} minutos.</Aviso>
        )}
        {atrasado && (
          <Aviso tipo={atrasado.motivo ? 'aviso' : 'erro'}>
            {atrasado.motivo
              ? `Atrasado. Cliente avisado: ${atrasado.motivo}${atrasado.mais_minutos ? ` (mais ${atrasado.mais_minutos} min)` : ''}.`
              : `Atrasado ${atrasado.minutos} min. Diz ao cliente o motivo.`}
          </Aviso>
        )}
      </>
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
            <Switch thumbColor="#FFFFFF"
              value={!!p.pagador_distinto}
              trackColor={{ true: cores.marca, false: cores.contorno }}
              onValueChange={(v) => correr(p.pedido_id, () => marcarPagadorDistinto(p.pedido_id, v))}
            />
          </View>
        )}

        {avisos(p)}
        {aberto && accao?.tipo === 'entregar' && painelEntrega(p)}
        {aberto && accao?.tipo === 'atraso' && painelAtraso(p)}
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
            {(gerir || (entregar && p.estado === 'em_entrega')) && (
              <Botao
                titulo="Avisar cliente do atraso…"
                variante="texto"
                aoCarregar={() => {
                  setAtraso({ motivo: MOTIVOS_ATRASO[0], outro: '', minutos: '' });
                  setAccao({ pedido: p.pedido_id, tipo: 'atraso' });
                }}
              />
            )}
            {gerir && <Botao titulo="Cancelar…" variante="texto" aoCarregar={() => setAccao({ pedido: p.pedido_id, tipo: 'cancelar' })} />}
            {gerir && (
              <Botao
                titulo="Histórico"
                variante="texto"
                aoCarregar={() => router.push({ pathname: '/pedido/[id]', params: { id: p.pedido_id } })}
              />
            )}
          </View>
        )}
      </Cartao>
    );
  }

  return (
    <Guarda permissoes={['entregas.registar', 'pedidos.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {partilha.erro && <Aviso>{partilha.erro}</Aviso>}
        {partilha.aCaminho > 0 && (
          <Aviso tipo="sucesso">
            A partilhar a tua localização com {partilha.aCaminho === 1 ? '1 cliente' : `${partilha.aCaminho} clientes`}. Mantém
            este ecrã aberto durante a entrega.
          </Aviso>
        )}
        {/* I8: com várias cozinhas, filtrar a fila por cozinha */}
        {cozinhas.length > 1 && (
          <Escolha
            opcoes={[{ valor: 'todas', rotulo: 'Todas' }, ...cozinhas.map((c) => ({ valor: c.id, rotulo: c.nome }))]}
            valor={filtroCozinha}
            aoMudar={setFiltroCozinha}
          />
        )}
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
