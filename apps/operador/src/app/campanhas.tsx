import { useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Pressable, Switch, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { lerCardapio, lerCozinhas, lerZonasEntrega } from '@/lib/api';
import {
  apagarCampanha,
  avisarCampanha,
  dataLimiteISO,
  dataLimiteTexto,
  erroCondominio,
  guardarCampanha,
  lerCampanhas,
  lerCondominios,
  textoOferta,
  textoQuando,
  type Campanha,
  type Condominio,
} from '@/lib/condominios';
import { formatarData, formatarKz, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Cozinha, PratoCardapio, ZonaEntrega } from '@/lib/tipos';

type Onde = 'condominio' | 'zona' | 'todos';
type Edicao = {
  id?: string;
  nome: string;
  descricao: string;
  onde: Onde;
  condominio_id: string;
  zona_id: string;
  cozinha_id: string;
  tipo: 'percentagem' | 'preco';
  valor: string;
  pratos: string[];
  minimo: string;
  inicio: string;
  fim: string;
  dias: number[];
  horaIni: string;
  horaFim: string;
  soMembros: boolean;
  limCliente: string;
  limTotal: string;
  activa: boolean;
};

const NOVA: Edicao = {
  nome: '', descricao: '', onde: 'condominio', condominio_id: '', zona_id: '', cozinha_id: '', tipo: 'percentagem',
  valor: '', pratos: [], minimo: '', inicio: '', fim: '', dias: [], horaIni: '', horaFim: '', soMembros: true,
  limCliente: '', limTotal: '', activa: true,
};
const DIAS: [number, string][] = [[1, 'Seg'], [2, 'Ter'], [3, 'Qua'], [4, 'Qui'], [5, 'Sex'], [6, 'Sáb'], [7, 'Dom']];
const HORA = /^([01]\d|2[0-3]):[0-5]\d$/;
const msg = (e: unknown) => erroCondominio(e) ?? mensagemErro(e);
const inteiro = (t: string) => (t.trim() === '' ? null : Number(t));

function Interruptor({ rotulo, valor, aoMudar }: { rotulo: string; valor: boolean; aoMudar: (v: boolean) => void }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: espaco.s, marginBottom: espaco.s }}>
      <Text style={{ flex: 1 }}>{rotulo}</Text>
      <Switch thumbColor="#FFFFFF" accessibilityLabel={rotulo} value={valor} onValueChange={aoMudar}
        trackColor={{ true: cores.marca, false: cores.contorno }} />
    </View>
  );
}

function Chip({ rotulo, marcado, aoCarregar }: { rotulo: string; marcado: boolean; aoCarregar: () => void }) {
  return (
    <Pressable
      accessibilityRole="checkbox"
      accessibilityState={{ checked: marcado }}
      onPress={aoCarregar}
      style={{
        paddingHorizontal: espaco.s, paddingVertical: 6, borderRadius: 16, borderWidth: 1,
        borderColor: marcado ? cores.marca : cores.contorno, backgroundColor: marcado ? cores.marca : '#fff',
      }}>
      <Text style={{ color: marcado ? '#fff' : cores.texto }}>{rotulo}</Text>
    </Pressable>
  );
}

/** Campanhas (promoções) por condomínio, por zona ou para todos. Não acumulam com o convite: vale o maior. */
export default function Campanhas() {
  const { pode } = useSessao();
  const gestor = pode('cozinhas.gerir');
  const [lista, setLista] = useState<Campanha[] | null>(null);
  const [condominios, setCondominios] = useState<Condominio[]>([]);
  const [zonas, setZonas] = useState<ZonaEntrega[]>([]);
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [pratos, setPratos] = useState<PratoCardapio[]>([]);
  const [edicao, setEdicao] = useState<Edicao | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    lerCampanhas().then(setLista).catch((e) => setErro(msg(e)));
    lerCondominios().then(setCondominios).catch(() => setCondominios([]));
    if (gestor) {
      lerZonasEntrega().then(setZonas).catch(() => setZonas([]));
      lerCozinhas().then(setCozinhas).catch(() => setCozinhas([]));
    }
  }, [gestor]);
  useFocusEffect(carregar);

  // Cozinha da campanha: a escolhida, ou a do condomínio
  const cozinhaCampanha =
    edicao?.onde === 'condominio' ? condominios.find((c) => c.id === edicao.condominio_id)?.cozinha_id ?? '' : edicao?.cozinha_id ?? '';
  useEffect(() => {
    if (!cozinhaCampanha) return setPratos([]);
    lerCardapio(cozinhaCampanha).then(setPratos).catch(() => setPratos([]));
  }, [cozinhaCampanha]);

  async function correr(f: () => Promise<unknown>, mensagem: string | ((r: unknown) => string), depois?: () => void) {
    setErro(null);
    setSucesso(null);
    setOcupado(true);
    try {
      const r = await f();
      setSucesso(typeof mensagem === 'function' ? mensagem(r) : mensagem);
      depois?.();
      carregar();
    } catch (e) {
      setErro(msg(e));
    } finally {
      setOcupado(false);
    }
  }

  const e = edicao;
  const valorN = Number(e?.valor);
  const inicioISO = e ? dataLimiteISO(e.inicio) : null;
  const fimISO = e ? dataLimiteISO(e.fim) : null;
  const horasOk = e ? (e.horaIni === '' && e.horaFim === '') || (HORA.test(e.horaIni) && HORA.test(e.horaFim)) : false;
  const valido =
    e !== null &&
    e.nome.trim().length >= 2 &&
    Number.isInteger(valorN) && valorN > 0 && (e.tipo !== 'percentagem' || valorN <= 90) &&
    (e.tipo !== 'preco' || e.pratos.length > 0) &&
    (e.onde !== 'condominio' || e.condominio_id !== '') &&
    (e.onde !== 'zona' || e.zona_id !== '') &&
    inicioISO !== undefined && fimISO !== undefined && horasOk;

  function editar(c: Campanha) {
    setEdicao({
      id: c.id, nome: c.nome, descricao: c.descricao ?? '',
      onde: c.condominio_id ? 'condominio' : c.zona_id ? 'zona' : 'todos',
      condominio_id: c.condominio_id ?? '', zona_id: c.zona_id ?? '', cozinha_id: c.cozinha_id ?? '',
      tipo: c.tipo, valor: String(c.valor), pratos: c.cardapio_ids ?? [], minimo: c.minimo_pedido ? String(c.minimo_pedido) : '',
      inicio: '', fim: dataLimiteTexto(c.fim), dias: c.dias_semana ?? [], horaIni: c.hora_inicio ?? '', horaFim: c.hora_fim ?? '',
      soMembros: c.so_membros, limCliente: c.limite_por_cliente ? String(c.limite_por_cliente) : '',
      limTotal: c.limite_total ? String(c.limite_total) : '', activa: c.activa,
    });
  }

  function guardar() {
    if (!e || !valido) return;
    // Datas: início no começo do dia (vazio = agora / mantém); fim no fim do dia
    const inicio = inicioISO ? inicioISO.replace('T23:59:59', 'T00:00:00') : null;
    return correr(
      () =>
        guardarCampanha({
          id: e.id,
          nome: e.nome.trim(),
          descricao: e.descricao.trim() || null,
          condominio_id: e.onde === 'condominio' ? e.condominio_id : null,
          zona_id: e.onde === 'zona' ? e.zona_id : null,
          cozinha_id: e.onde === 'condominio' ? null : e.cozinha_id || null,
          tipo: e.tipo,
          valor: valorN,
          cardapio_ids: e.pratos.length > 0 ? e.pratos : null,
          minimo_pedido: inteiro(e.minimo) ?? 0,
          inicio: inicio ?? '',
          fim: fimISO ?? null,
          dias_semana: e.dias.length > 0 && e.dias.length < 7 ? e.dias : null,
          hora_inicio: e.horaIni || null,
          hora_fim: e.horaFim || null,
          so_membros: e.onde === 'condominio' && e.soMembros,
          limite_por_cliente: inteiro(e.limCliente),
          limite_total: inteiro(e.limTotal),
          activa: e.activa,
        }),
      'Campanha guardada.',
      () => setEdicao(null),
    );
  }

  const formulario = e && (
    <Cartao>
      <Subtitulo>{e.id ? 'Editar campanha' : 'Nova campanha'}</Subtitulo>
      <Campo rotulo="Nome (ex.: Sexta no Jardim)" value={e.nome} maxLength={60} onChangeText={(t) => setEdicao({ ...e, nome: t })} />
      <Campo rotulo="Texto para o cliente (opcional)" value={e.descricao} maxLength={200} onChangeText={(t) => setEdicao({ ...e, descricao: t })} />
      <Text style={{ fontWeight: '700' }}>Para quem</Text>
      <Escolha
        opcoes={[
          { valor: 'condominio' as Onde, rotulo: 'Um condomínio' },
          ...(gestor ? [{ valor: 'zona' as Onde, rotulo: 'Uma zona' }, { valor: 'todos' as Onde, rotulo: 'Todos' }] : []),
        ]}
        valor={e.onde}
        aoMudar={(v) => setEdicao({ ...e, onde: v, pratos: [] })}
      />
      {e.onde === 'condominio' && (
        <>
          <Escolha
            opcoes={condominios.map((c) => ({ valor: c.id, rotulo: c.nome }))}
            valor={e.condominio_id}
            aoMudar={(v) => setEdicao({ ...e, condominio_id: v, pratos: [] })}
          />
          <Interruptor rotulo="Só para os membros da lista" valor={e.soMembros} aoMudar={(v) => setEdicao({ ...e, soMembros: v })} />
        </>
      )}
      {e.onde === 'zona' && (
        <Escolha opcoes={zonas.map((z) => ({ valor: z.id, rotulo: z.nome }))} valor={e.zona_id} aoMudar={(v) => setEdicao({ ...e, zona_id: v })} />
      )}
      {e.onde !== 'condominio' && (
        <>
          <Text style={{ fontWeight: '700' }}>Cozinha</Text>
          <Escolha
            opcoes={[{ valor: '', rotulo: 'Todas' }, ...cozinhas.map((k) => ({ valor: k.id, rotulo: k.nome }))]}
            valor={e.cozinha_id}
            aoMudar={(v) => setEdicao({ ...e, cozinha_id: v, pratos: [] })}
          />
        </>
      )}
      <Text style={{ fontWeight: '700' }}>Oferta</Text>
      <Escolha
        opcoes={[
          { valor: 'percentagem' as const, rotulo: '% de desconto' },
          { valor: 'preco' as const, rotulo: 'Preço especial' },
        ]}
        valor={e.tipo}
        aoMudar={(v) => setEdicao({ ...e, tipo: v })}
      />
      <Campo
        rotulo={e.tipo === 'percentagem' ? 'Desconto (%, 1–90)' : 'Preço especial de cada prato escolhido (Kz)'}
        value={e.valor}
        keyboardType="number-pad"
        onChangeText={(t) => setEdicao({ ...e, valor: t.replace(/\D/g, '') })}
      />
      {cozinhaCampanha !== '' && (
        <>
          <Text style={{ fontWeight: '700' }}>
            Pratos {e.tipo === 'preco' ? '(escolhe pelo menos um)' : '(nenhum escolhido = todos)'}
          </Text>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: espaco.xs }}>
            {pratos.map((p) => (
              <Chip
                key={p.id}
                rotulo={`${p.nome.trim()} · ${formatarKz(p.preco)}`}
                marcado={e.pratos.includes(p.id)}
                aoCarregar={() =>
                  setEdicao({ ...e, pratos: e.pratos.includes(p.id) ? e.pratos.filter((x) => x !== p.id) : [...e.pratos, p.id] })
                }
              />
            ))}
          </View>
        </>
      )}
      <Campo rotulo="Pedido mínimo (Kz, opcional)" value={e.minimo} keyboardType="number-pad"
        onChangeText={(t) => setEdicao({ ...e, minimo: t.replace(/\D/g, '') })} />
      <Subtitulo>Quando</Subtitulo>
      <Campo rotulo={e.id ? 'Começa em (DD/MM/AAAA; vazio = mantém)' : 'Começa em (DD/MM/AAAA; vazio = já)'} value={e.inicio}
        onChangeText={(t) => setEdicao({ ...e, inicio: t })} />
      <Campo rotulo="Acaba em (DD/MM/AAAA, opcional)" value={e.fim} onChangeText={(t) => setEdicao({ ...e, fim: t })} />
      {(inicioISO === undefined || fimISO === undefined) && <Aviso>Data inválida. Usa DD/MM/AAAA.</Aviso>}
      <Text style={{ fontWeight: '700' }}>Dias da semana (nenhum = todos)</Text>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: espaco.xs }}>
        {DIAS.map(([d, r]) => (
          <Chip key={d} rotulo={r} marcado={e.dias.includes(d)}
            aoCarregar={() => setEdicao({ ...e, dias: e.dias.includes(d) ? e.dias.filter((x) => x !== d) : [...e.dias, d] })} />
        ))}
      </View>
      <View style={{ flexDirection: 'row', gap: espaco.s }}>
        <View style={{ flex: 1 }}>
          <Campo rotulo="Das (HH:MM)" value={e.horaIni} maxLength={5} onChangeText={(t) => setEdicao({ ...e, horaIni: t })} />
        </View>
        <View style={{ flex: 1 }}>
          <Campo rotulo="Às (HH:MM)" value={e.horaFim} maxLength={5} onChangeText={(t) => setEdicao({ ...e, horaFim: t })} />
        </View>
      </View>
      {!horasOk && <Aviso>Horas: preenche as duas (ex.: 12:00 e 15:00) ou deixa as duas em branco.</Aviso>}
      <Subtitulo>Limites (opcional)</Subtitulo>
      <Campo rotulo="Pedidos por cliente" value={e.limCliente} keyboardType="number-pad"
        onChangeText={(t) => setEdicao({ ...e, limCliente: t.replace(/\D/g, '') })} />
      <Campo rotulo="Pedidos no total" value={e.limTotal} keyboardType="number-pad"
        onChangeText={(t) => setEdicao({ ...e, limTotal: t.replace(/\D/g, '') })} />
      <Interruptor rotulo="Campanha activa" valor={e.activa} aoMudar={(v) => setEdicao({ ...e, activa: v })} />
      <Paragrafo suave>Não acumula com o desconto de convite: o cliente fica com o maior dos dois.</Paragrafo>
      <Botao titulo="Guardar campanha" desactivado={!valido} aCarregar={ocupado} aoCarregar={guardar} />
      {e.id && (
        <Botao titulo="Apagar campanha" variante="texto" desactivado={ocupado}
          aoCarregar={() => correr(() => apagarCampanha(e.id as string), 'Campanha apagada.', () => setEdicao(null))} />
      )}
      <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setEdicao(null)} />
    </Cartao>
  );

  return (
    <Guarda permissoes={['cozinhas.gerir', 'pedidos.gerir']}>
      <Ecra>
        <Paragrafo suave>
          Promoções por condomínio, por zona ou para todos. O desconto entra no preço dos pratos e não acumula com o convite.
          Precisa do interruptor «condominios» ligado.
        </Paragrafo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
        {lista === null && !erro && <ACarregar />}
        {lista?.length === 0 && !edicao && <Aviso>Ainda não há campanhas.</Aviso>}
        {lista?.map((c) => (
          <Cartao key={c.id}>
            <Text style={{ fontWeight: '700', fontSize: 16 }}>
              {c.em_curso ? '🟢 ' : c.activa ? '🕒 ' : '⏸️ '}
              {c.nome}
            </Text>
            <Text>{textoOferta(c)}{c.minimo_pedido ? ` · a partir de ${formatarKz(c.minimo_pedido)}` : ''}</Text>
            <Text style={{ color: cores.textoSuave }}>
              {c.condominio ? `Condomínio ${c.condominio}${c.so_membros ? ' (só membros)' : ''}` : c.zona ? `Zona ${c.zona}` : 'Todos'}
              {c.cozinha ? ` · ${c.cozinha}` : ''} · {textoQuando(c)}
            </Text>
            <Text style={{ color: cores.textoSuave }}>
              {formatarData(c.inicio)}
              {c.fim ? ` até ${formatarData(c.fim)}` : ' · sem fim'}
              {c.limite_por_cliente ? ` · ${c.limite_por_cliente}/cliente` : ''}
              {c.limite_total ? ` · ${c.limite_total} no total` : ''}
            </Text>
            <Text>
              {c.resultado.pedidos} pedidos · {c.resultado.clientes} clientes · {formatarKz(c.resultado.vendas)} vendidos ·{' '}
              {formatarKz(c.resultado.desconto)} de desconto
            </Text>
            {(c.condominio_id || c.zona_id) && !c.avisado_em && (
              <Botao
                titulo="Avisar os clientes"
                variante="secundario"
                aCarregar={ocupado}
                aoCarregar={() => correr(() => avisarCampanha(c.id), (n) => `Aviso enviado a ${n} cliente(s).`)}
              />
            )}
            {c.avisado_em && <Text style={{ color: cores.textoSuave }}>Clientes avisados em {formatarData(c.avisado_em)}</Text>}
            <Botao titulo="Editar" variante="texto" aoCarregar={() => editar(c)} />
          </Cartao>
        ))}
        {edicao ? formulario : <Botao titulo="Nova campanha" aoCarregar={() => setEdicao({ ...NOVA })} />}
      </Ecra>
    </Guarda>
  );
}
