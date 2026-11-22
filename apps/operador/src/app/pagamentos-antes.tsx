import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { formatarData, formatarKz, horaLuanda, mensagemErro } from '@/lib/formatar';
import {
  decidirPagamentoAntes,
  devolverPagamentoAntes,
  nomeMetodoAntes,
  pagamentosAntes,
  separarPagamentosAntes,
  type PagamentoAntes,
} from '@/lib/pagamentosAntes';
import { cores, espaco } from '@/lib/tema';

const ESTADO: Record<PagamentoAntes['estado'], string> = {
  pendente: 'A confirmar',
  confirmado: '✓ Confirmado',
  rejeitado: 'Rejeitado',
  devolvido: 'Devolvido',
};

/**
 * Pagamentos feitos antes da entrega nos pedidos de grupo (cada um paga a sua parte por Multicaixa
 * Express ou Unitel Money). Confirma-se com o extracto; rejeita-se com o motivo (o cliente vê-o);
 * se o pedido foi cancelado (ou também pago na entrega), regista-se a devolução.
 */
export default function PagamentosAntes() {
  const [lista, setLista] = useState<PagamentoAntes[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aberto, setAberto] = useState<{ id: string; accao: 'rejeitar' | 'devolver' } | null>(null);
  const [texto, setTexto] = useState('');
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    pagamentosAntes()
      .then((l) => {
        setLista(l);
        setErro(null);
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
      setTexto('');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  const partes = lista ? separarPagamentosAntes(lista) : null;

  const cartao = (p: PagamentoAntes) => (
    <Cartao key={p.id} estilo={{ gap: espaco.xs }}>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: espaco.s }}>
        <Text style={{ fontWeight: '700', flex: 1 }}>{p.cliente_nome}</Text>
        <Text style={{ fontWeight: '800' }}>{formatarKz(p.valor)}</Text>
      </View>
      <Text>
        {nomeMetodoAntes[p.metodo]} · referência <Text style={{ fontWeight: '700' }}>{p.referencia}</Text>
      </Text>
      <Text style={{ color: cores.textoSuave, fontSize: 13 }}>
        {formatarData(p.criado_em, true)}
        {p.grupo_hora ? ` · grupo das ${horaLuanda(p.grupo_hora)}` : ''}
        {p.cozinha_nome ? ` · ${p.cozinha_nome}` : ''}
        {p.cliente_telefone ? ` · ${p.cliente_telefone}` : ''}
      </Text>
      <Text style={{ color: p.a_devolver ? cores.erro : cores.textoSuave, fontSize: 13 }}>
        {ESTADO[p.estado]}
        {p.motivo ? ` · ${p.motivo}` : ''}
        {p.a_devolver ? ` · pedido ${p.pedido_estado === 'cancelado' ? 'cancelado' : 'já pago na entrega'}: devolver` : ''}
      </Text>

      {aberto?.id === p.id ? (
        <>
          <Campo
            rotulo={aberto.accao === 'rejeitar' ? 'Motivo (o cliente vê-o na app)' : 'Referência da devolução'}
            value={texto}
            onChangeText={setTexto}
          />
          <View style={{ flexDirection: 'row', gap: espaco.s }}>
            <Botao
              titulo={aberto.accao === 'rejeitar' ? 'Rejeitar' : 'Marcar devolvido'}
              aCarregar={ocupado}
              desactivado={!texto.trim()}
              aoCarregar={() =>
                accao(() => (aberto.accao === 'rejeitar' ? decidirPagamentoAntes(p.id, false, texto.trim()) : devolverPagamentoAntes(p.id, texto.trim())))
              }
            />
            <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
          </View>
        </>
      ) : p.a_devolver ? (
        <Botao titulo="Registar devolução" variante="secundario" aoCarregar={() => setAberto({ id: p.id, accao: 'devolver' })} />
      ) : p.estado === 'pendente' ? (
        <View style={{ flexDirection: 'row', gap: espaco.s }}>
          <View style={{ flex: 1 }}>
            <Botao titulo="Confirmar" aCarregar={ocupado} aoCarregar={() => accao(() => decidirPagamentoAntes(p.id, true))} />
          </View>
          <View style={{ flex: 1 }}>
            <Botao titulo="Rejeitar" variante="secundario" aoCarregar={() => setAberto({ id: p.id, accao: 'rejeitar' })} />
          </View>
        </View>
      ) : null}
    </Cartao>
  );

  return (
    <Guarda permissoes={['financas.acertos']}>
      <Ecra>
        <Paragrafo suave>
          Pedidos de grupo em que cada um paga a sua parte antes. Confirma só depois de ver o dinheiro no extracto: o estafeta deixa de
          cobrar esse valor.
        </Paragrafo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!partes && !erro && <ACarregar />}
        {partes && (
          <>
            <Subtitulo>A confirmar ({partes.aConfirmar.length})</Subtitulo>
            {partes.aConfirmar.length === 0 && <Paragrafo suave>Nada por confirmar.</Paragrafo>}
            {partes.aConfirmar.map(cartao)}
            {partes.aDevolver.length > 0 && (
              <>
                <Subtitulo>A devolver ({partes.aDevolver.length})</Subtitulo>
                {partes.aDevolver.map(cartao)}
              </>
            )}
            <Subtitulo>Últimos 30 dias</Subtitulo>
            {partes.decididos.length === 0 && <Paragrafo suave>Ainda sem pagamentos decididos.</Paragrafo>}
            {partes.decididos.map(cartao)}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
