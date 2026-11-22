import { Redirect, useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo } from '@/components/ui';
import { EMPRESA } from '@/lib/empresa';
import {
  cancelarEncomenda,
  minhasEncomendas,
  pagarSinalEncomenda,
  quandoEncomenda,
  responderEncomenda,
  textoEstadoEncomenda,
  type Encomenda,
} from '@/lib/encomendas';
import { formatarKz, mensagemErro, nomeMetodoAntes } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { MetodoAntes } from '@/lib/tipos';

const ABERTAS = ['pedida', 'na_cozinha', 'proposta', 'a_confirmar'];

/**
 * As encomendas do cliente: o estado de cada uma, a proposta (cozinha, preço, entrega e sinal) para
 * aceitar ou recusar, e o pagamento do sinal com a referência da transferência.
 * Cialdini: compromisso pequeno primeiro (pedir preço), o sinal só depois de ver o total.
 */
export default function Encomendas() {
  const router = useRouter();
  const { carregado, ligada } = useSessao();
  const [lista, setLista] = useState<Encomenda[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [metodo, setMetodo] = useState<MetodoAntes>('multicaixa_express');
  const [referencia, setReferencia] = useState('');

  const carregar = useCallback(() => {
    minhasEncomendas()
      .then((l) => {
        setLista(l);
        setErro(null);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  if (!carregado) return <ACarregar />;
  if (!ligada('encomendas')) return <Redirect href="/inicio" />;

  async function accao(id: string, f: () => Promise<unknown>) {
    setOcupado(id);
    setErro(null);
    try {
      await f();
      setReferencia('');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(null);
    }
  }

  const cartao = (e: Encomenda) => {
    const pag = e.pagamento;
    const sinalPago = (e.pago_antes ?? 0) >= e.sinal && e.sinal > 0;
    return (
      <Cartao key={e.id} estilo={{ gap: espaco.xs }}>
        <Text style={{ fontWeight: '700', color: cores.texto }}>
          {e.receita} · {e.pessoas} pessoas
        </Text>
        <Text style={{ color: cores.textoSuave, fontSize: 13 }}>
          {quandoEncomenda(e.para_quando)}
          {e.local ? ` · ${e.local}` : ''}
        </Text>
        <Text style={{ color: cores.texto }}>{textoEstadoEncomenda(e)}</Text>

        {(e.estado === 'a_confirmar' || e.estado === 'confirmada') && e.total != null && (
          <View style={{ gap: 2 }}>
            {e.cozinha_nome && <Linha esquerda="Cozinha" direita={e.cozinha_nome} />}
            <Linha esquerda="Prato" direita={formatarKz(e.preco ?? 0)} />
            <Linha esquerda="Entrega" direita={formatarKz(e.taxa_entrega)} />
            <Linha esquerda="Total" direita={formatarKz(e.total)} forte />
            <Linha esquerda="Sinal (antes)" direita={formatarKz(e.sinal)} />
          </View>
        )}

        {e.estado === 'a_confirmar' && (
          <View style={{ flexDirection: 'row', gap: espaco.s }}>
            <View style={{ flex: 1 }}>
              <Botao titulo="Aceitar" aCarregar={ocupado === e.id} aoCarregar={() => accao(e.id, () => responderEncomenda(e.id, true))} />
            </View>
            <View style={{ flex: 1 }}>
              <Botao titulo="Recusar" variante="secundario" desactivado={ocupado === e.id} aoCarregar={() => accao(e.id, () => responderEncomenda(e.id, false))} />
            </View>
          </View>
        )}

        {e.estado === 'confirmada' &&
          (sinalPago ? (
            <Aviso tipo="sucesso">✓ Sinal pago. Na entrega pagas o resto.</Aviso>
          ) : pag?.estado === 'pendente' ? (
            <Aviso>⏳ Sinal de {formatarKz(pag.valor)} a confirmar. Confirmamos assim que o dinheiro chegar.</Aviso>
          ) : (
            <View style={{ gap: espaco.xs }}>
              {pag?.estado === 'rejeitado' && (
                <Aviso tipo="erro">O pagamento não foi aceite{pag.motivo ? `: ${pag.motivo}` : ''}. Confirma a referência e envia de novo.</Aviso>
              )}
              <Paragrafo>
                Paga o sinal de {formatarKz(e.sinal)} para a cozinha começar.{' '}
                {EMPRESA.instrucoesPagamento || 'Transfere por Multicaixa Express ou Unitel Money para o número da Cozinha da Alexandra.'}
              </Paragrafo>
              <Escolha
                opcoes={(Object.keys(nomeMetodoAntes) as MetodoAntes[]).map((m) => ({ valor: m, rotulo: nomeMetodoAntes[m] }))}
                valor={metodo}
                aoMudar={(v) => setMetodo(v as MetodoAntes)}
              />
              <Campo rotulo="Referência da transferência" value={referencia} onChangeText={setReferencia} autoCapitalize="characters" />
              <Botao
                titulo="Já paguei o sinal"
                aCarregar={ocupado === e.id}
                desactivado={referencia.replace(/\s/g, '').length < 4}
                aoCarregar={() => accao(e.id, () => pagarSinalEncomenda(e.id, metodo, referencia.trim()))}
              />
            </View>
          ))}

        {e.estado === 'confirmada' && e.pedido_id && (
          <Botao titulo="Ver o pedido" variante="texto" aoCarregar={() => router.push({ pathname: '/pedido/[id]', params: { id: e.pedido_id! } })} />
        )}
        {ABERTAS.includes(e.estado) && (
          <Botao titulo="Cancelar encomenda" variante="texto" desactivado={ocupado === e.id} aoCarregar={() => accao(e.id, () => cancelarEncomenda(e.id))} />
        )}
      </Cartao>
    );
  };

  return (
    <Ecra>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {!lista && !erro && <ACarregar />}
      {lista && lista.length === 0 && (
        <>
          <Paragrafo suave>Ainda não fizeste encomendas. Nas receitas que nenhuma cozinha tem no cardápio, podes encomendar para 4 ou mais pessoas.</Paragrafo>
          <Botao titulo="Ver receitas" variante="secundario" aoCarregar={() => router.push('/receitas')} />
        </>
      )}
      {lista?.map(cartao)}
    </Ecra>
  );
}
