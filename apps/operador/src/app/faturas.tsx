import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo } from '@/components/ui';
import { registarFaturaPedido, vendasSemFatura } from '@/lib/api';
import { formatarData, formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { VendaSemFatura } from '@/lib/tipos';

type Emissor = 'plataforma' | 'cozinha';

/**
 * Faturas das vendas: cada venda entregue tem de ter o número da fatura do software certificado
 * (emitida pela plataforma ou pela própria cozinha). Aqui ficam as que ainda não têm.
 */
export default function Faturas() {
  const [lista, setLista] = useState<VendaSemFatura[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aberto, setAberto] = useState<string | null>(null);
  const [numero, setNumero] = useState('');
  const [emissor, setEmissor] = useState<Emissor>('plataforma');
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    setLista(null);
    vendasSemFatura(30)
      .then(setLista)
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  async function guardar(pedidoId: string) {
    setErro(null);
    setOcupado(true);
    try {
      await registarFaturaPedido(pedidoId, numero.trim(), emissor);
      setAberto(null);
      setNumero('');
      setLista((l) => l?.filter((v) => v.pedido_id !== pedidoId) ?? null);
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  return (
    <Guarda permissoes={['financas.conferir', 'pedidos.gerir']}>
      <Ecra>
        <Paragrafo suave>Vendas dos últimos 30 dias entregues sem número de fatura.</Paragrafo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista && lista.length === 0 && <Aviso tipo="sucesso">Todas as vendas têm fatura.</Aviso>}
        {lista && lista.length > 0 && (
          <Text style={{ color: cores.aviso, fontWeight: '700' }}>
            {lista.length === 1 ? '1 venda sem fatura' : `${lista.length} vendas sem fatura`}
          </Text>
        )}
        {lista?.map((v) => (
          <Cartao key={v.pedido_id}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
              <Text style={{ fontWeight: '700' }}>{formatarKz(v.valor)}</Text>
              <Text style={{ color: cores.textoSuave }}>{formatarData(v.entregue_em, true)}</Text>
            </View>
            <Text>
              {v.cliente_nome ?? 'Cliente'}
              {v.cliente_nif ? ` · NIF ${v.cliente_nif}` : ''}
            </Text>
            <Text style={{ color: cores.textoSuave }}>{v.cozinha_nome}</Text>
            {aberto === v.pedido_id ? (
              <View style={{ gap: espaco.s }}>
                <Campo rotulo="Número da fatura" autoCapitalize="characters" value={numero} onChangeText={setNumero} />
                <Escolha
                  opcoes={[
                    { valor: 'plataforma', rotulo: 'Emitida pela plataforma' },
                    { valor: 'cozinha', rotulo: 'Emitida pela cozinha' },
                  ]}
                  valor={emissor}
                  aoMudar={setEmissor}
                />
                <Botao titulo="Guardar" desactivado={!numero.trim()} aCarregar={ocupado} aoCarregar={() => guardar(v.pedido_id)} />
                <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
              </View>
            ) : (
              <Botao
                titulo="Registar a fatura"
                variante="secundario"
                aoCarregar={() => {
                  setAberto(v.pedido_id);
                  setNumero('');
                  setEmissor(v.faturacao);
                }}
              />
            )}
          </Cartao>
        ))}
      </Ecra>
    </Guarda>
  );
}
