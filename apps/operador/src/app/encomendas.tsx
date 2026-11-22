import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { lerCozinhas } from '@/lib/api';
import {
  aprovarEncomenda,
  cancelarEncomenda,
  enviarEncomendaCozinha,
  encomendasLista,
  nomeEstadoEncomenda,
  responderEncomendaCozinha,
  separarEncomendas,
  type EncomendaOperador,
} from '@/lib/encomendas';
import { formatarData, formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { Cozinha } from '@/lib/tipos';

type Accao = 'propor' | 'recusar' | 'aprovar' | 'cancelar';

const km = (d: number | null) => (d == null ? '' : ` · ${d.toLocaleString('pt-PT', { maximumFractionDigits: 1 })} km`);

/**
 * Encomendas de receitas que nenhuma cozinha tem no cardápio. O operador escolhe a cozinha (o sistema
 * sugere primeiro as que já fizeram o prato e as mais perto); a cozinha propõe o preço ou recusa com o
 * motivo; o operador aprova (pode acertar o preço) e o cliente confirma e paga o sinal na app.
 */
export default function Encomendas() {
  const [lista, setLista] = useState<EncomendaOperador[] | null>(null);
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [escolhida, setEscolhida] = useState<Record<string, string>>({});
  const [aberto, setAberto] = useState<{ id: string; accao: Accao } | null>(null);
  const [preco, setPreco] = useState('');
  const [texto, setTexto] = useState('');
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    encomendasLista()
      .then((l) => {
        setLista(l);
        setErro(null);
        if (l.some((e) => e.pode_gerir)) lerCozinhas().then((c) => setCozinhas(c.filter((x) => x.estado === 'activa'))).catch(() => undefined);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  async function accao(f: () => Promise<void>) {
    setOcupado(true);
    setErro(null);
    try {
      await f();
      setAberto(null);
      setPreco('');
      setTexto('');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  function abrir(e: EncomendaOperador, a: Accao) {
    setAberto({ id: e.id, accao: a });
    setTexto('');
    setPreco(a === 'aprovar' && e.preco_cozinha ? String(e.preco_cozinha) : '');
  }

  const valorPreco = Number(preco.replace(/\D/g, ''));

  const formulario = (e: EncomendaOperador, a: Accao) => {
    const comPreco = a === 'propor' || a === 'aprovar';
    const comTexto = a !== 'aprovar';
    const valido = (!comPreco || valorPreco > 0) && (a === 'propor' || !comTexto || texto.trim().length > 0);
    const titulo = { propor: 'Enviar preço', recusar: 'Não podemos fazer', aprovar: 'Aprovar e enviar ao cliente', cancelar: 'Cancelar encomenda' }[a];
    return (
      <>
        {comPreco && <Campo rotulo={`Preço do prato para ${e.pessoas} pessoas (Kz, sem a entrega)`} value={preco} onChangeText={setPreco} keyboardType="numeric" />}
        {comTexto && (
          <Campo
            rotulo={a === 'propor' ? 'Nota para o operador (opcional)' : a === 'recusar' ? 'Porquê (ex.: sem peixe esta semana)' : 'Motivo (o cliente vê-o)'}
            value={texto}
            onChangeText={setTexto}
          />
        )}
        <View style={{ flexDirection: 'row', gap: espaco.s }}>
          <Botao
            titulo={titulo}
            aCarregar={ocupado}
            desactivado={!valido}
            aoCarregar={() =>
              accao(() =>
                a === 'propor'
                  ? responderEncomendaCozinha(e.id, valorPreco, texto)
                  : a === 'recusar'
                    ? responderEncomendaCozinha(e.id, null, texto)
                    : a === 'aprovar'
                      ? aprovarEncomenda(e.id, valorPreco)
                      : cancelarEncomenda(e.id, texto),
              )
            }
          />
          <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
        </View>
      </>
    );
  };

  const cartao = (e: EncomendaOperador) => {
    const sugeridas = e.sugestoes ?? [];
    const opcoes = [
      ...sugeridas.map((s) => ({ valor: s.cozinha_id, rotulo: `${s.sabe_fazer ? '★ ' : ''}${s.nome}${km(s.distancia_km)}` })),
      ...cozinhas.filter((c) => !sugeridas.some((s) => s.cozinha_id === c.id)).map((c) => ({ valor: c.id, rotulo: c.nome })),
    ];
    const cozinhaEscolhida = escolhida[e.id] ?? sugeridas[0]?.cozinha_id ?? '';
    return (
      <Cartao key={e.id} estilo={{ gap: espaco.xs }}>
        <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: espaco.s }}>
          <Text style={{ fontWeight: '700', flex: 1 }}>
            {e.receita} · {e.pessoas} pessoas
          </Text>
          <Text style={{ fontWeight: '700', color: cores.textoSuave }}>{nomeEstadoEncomenda[e.estado]}</Text>
        </View>
        <Text>
          Para {formatarData(e.para_quando, true)}
          {e.local ? ` · ${e.local}` : ''}
        </Text>
        <Text style={{ color: cores.textoSuave, fontSize: 13 }}>
          {e.cliente_nome}
          {e.cliente_telefone ? ` · ${e.cliente_telefone}` : ''}
          {e.cozinha_nome ? ` · ${e.cozinha_nome}` : ''}
        </Text>
        {e.nota ? <Text>Nota do cliente: {e.nota}</Text> : null}
        {e.motivo ? <Text style={{ color: e.estado === 'pedida' ? cores.erro : cores.textoSuave }}>{e.motivo}</Text> : null}
        {e.preco_cozinha != null && (
          <Text>
            Preço da cozinha: <Text style={{ fontWeight: '700' }}>{formatarKz(e.preco_cozinha)}</Text>
            {e.nota_cozinha ? ` · ${e.nota_cozinha}` : ''}
          </Text>
        )}
        {e.total != null && (
          <Text style={{ color: cores.textoSuave, fontSize: 13 }}>
            Cliente: {formatarKz(e.preco ?? 0)} + entrega {formatarKz(e.taxa_entrega)} = {formatarKz(e.total)} · sinal {formatarKz(e.sinal)}
          </Text>
        )}

        {aberto?.id === e.id ? (
          formulario(e, aberto.accao)
        ) : (
          <>
            {e.estado === 'pedida' && e.pode_gerir && (
              <>
                <Paragrafo suave>★ já fez o prato. Escolhe a cozinha que o vai fazer:</Paragrafo>
                {opcoes.length === 0 ? (
                  <Paragrafo suave>Sem cozinhas activas.</Paragrafo>
                ) : (
                  <Escolha opcoes={opcoes} valor={cozinhaEscolhida} aoMudar={(v) => setEscolhida((x) => ({ ...x, [e.id]: v }))} />
                )}
                <Botao
                  titulo="Enviar à cozinha"
                  aCarregar={ocupado}
                  desactivado={!cozinhaEscolhida}
                  aoCarregar={() => accao(() => enviarEncomendaCozinha(e.id, cozinhaEscolhida))}
                />
              </>
            )}
            {e.estado === 'na_cozinha' && e.pode_propor && (
              <View style={{ flexDirection: 'row', gap: espaco.s }}>
                <View style={{ flex: 1 }}>
                  <Botao titulo="Propor preço" aoCarregar={() => abrir(e, 'propor')} />
                </View>
                <View style={{ flex: 1 }}>
                  <Botao titulo="Não podemos" variante="secundario" aoCarregar={() => abrir(e, 'recusar')} />
                </View>
              </View>
            )}
            {e.estado === 'proposta' && e.pode_gerir && <Botao titulo="Aprovar o preço" aoCarregar={() => abrir(e, 'aprovar')} />}
            {e.pode_gerir && ['pedida', 'na_cozinha', 'proposta', 'a_confirmar'].includes(e.estado) && (
              <Botao titulo="Cancelar" variante="texto" aoCarregar={() => abrir(e, 'cancelar')} />
            )}
          </>
        )}
      </Cartao>
    );
  };

  const partes = lista ? separarEncomendas(lista) : null;

  return (
    <Guarda permissoes={['pedidos.gerir', 'cozinhas.gerir', 'vendas.registar']}>
      <Ecra>
        <Paragrafo suave>
          Pratos das receitas que ninguém tem no cardápio, encomendados com 24 horas de antecedência. Escolhe a cozinha, ela propõe o preço,
          aprovas e o cliente confirma e paga o sinal.
        </Paragrafo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!partes && !erro && <ACarregar />}
        {partes && (
          <>
            <Subtitulo>Por fazer ({partes.porFazer.length})</Subtitulo>
            {partes.porFazer.length === 0 && <Paragrafo suave>Nada à espera.</Paragrafo>}
            {partes.porFazer.map(cartao)}
            <Subtitulo>Em curso e últimos 14 dias</Subtitulo>
            {partes.outras.length === 0 && <Paragrafo suave>Sem encomendas.</Paragrafo>}
            {partes.outras.map(cartao)}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
