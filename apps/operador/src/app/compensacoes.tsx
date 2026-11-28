import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo } from '@/components/ui';
import { compensacoesLista, definirCargoCompensacao, pagarCompensacao } from '@/lib/api';
import { formatarData, formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { Compensacao } from '@/lib/tipos';

const METODOS = ['Unitel Money', 'Multicaixa Express', 'Transferência', 'Dinheiro'] as const;
type Metodo = (typeof METODOS)[number];
type Filtro = 'por_pagar' | 'paga' | 'anulada';

const nomeTipo: Record<Compensacao['tipo'], string> = {
  desconto: 'Desconto',
  reembolso_parcial: 'Reembolso parcial',
  reembolso_total: 'Reembolso total',
};

/**
 * Compensações das reclamações: o que se decidiu dar ao cliente. A plataforma paga; se a falha foi
 * da cozinha (qualidade, quantidade, pedido errado), fica a cargo dela e entra no acerto da semana.
 */
export default function Compensacoes() {
  const [filtro, setFiltro] = useState<Filtro>('por_pagar');
  const [lista, setLista] = useState<Compensacao[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aberto, setAberto] = useState<string | null>(null);
  const [metodo, setMetodo] = useState<Metodo>('Unitel Money');
  const [referencia, setReferencia] = useState('');
  const [ocupado, setOcupado] = useState<string | null>(null);

  const carregar = useCallback(() => {
    setLista(null);
    compensacoesLista(filtro)
      .then(setLista)
      .catch((e) => setErro(mensagemErro(e)));
  }, [filtro]);
  useFocusEffect(carregar);

  async function accao(id: string, f: () => Promise<unknown>) {
    setErro(null);
    setOcupado(id);
    try {
      await f();
      setAberto(null);
      setReferencia('');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(null);
    }
  }

  return (
    <Guarda permissoes={['financas.compensacoes']}>
      <Ecra>
        <Escolha
          opcoes={[
            { valor: 'por_pagar', rotulo: 'Por pagar' },
            { valor: 'paga', rotulo: 'Pagas' },
            { valor: 'anulada', rotulo: 'Anuladas' },
          ]}
          valor={filtro}
          aoMudar={setFiltro}
        />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista && lista.length === 0 && <Paragrafo suave>Nada nesta lista.</Paragrafo>}
        {lista?.map((c) => (
          <Cartao key={c.id}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
              <Text style={{ fontWeight: '700', fontSize: 16 }}>{formatarKz(c.valor)}</Text>
              <Text style={{ color: cores.textoSuave }}>{nomeTipo[c.tipo]}</Text>
            </View>
            <Text>
              {c.cliente_nome}
              {c.cliente_telefone ? ` · ${c.cliente_telefone}` : ''}
            </Text>
            <Text style={{ color: cores.textoSuave }}>
              {c.cozinha_nome ?? ''} · {formatarData(c.criado_em, true)}
            </Text>
            <Text style={{ fontStyle: 'italic' }}>«{c.reclamacao}»</Text>
            <Text style={{ fontWeight: '700', color: c.a_cargo === 'cozinha' ? cores.aviso : cores.texto }}>
              A cargo {c.a_cargo === 'cozinha' ? 'da cozinha (entra no acerto)' : 'da plataforma'}
            </Text>
            {c.estado === 'paga' && (
              <Text style={{ color: cores.sucesso }}>
                Paga {formatarData(c.pago_em, true)} · {c.metodo}
                {c.referencia ? ` · ${c.referencia}` : ''}
              </Text>
            )}
            {c.estado === 'por_pagar' &&
              (aberto === c.id ? (
                <View style={{ gap: espaco.s }}>
                  <Escolha opcoes={METODOS.map((m) => ({ valor: m, rotulo: m }))} valor={metodo} aoMudar={setMetodo} />
                  <Campo
                    rotulo={metodo === 'Dinheiro' ? 'Referência (opcional)' : 'Referência (obrigatória)'}
                    value={referencia}
                    onChangeText={setReferencia}
                  />
                  <Botao
                    titulo="Pagar ao cliente"
                    aCarregar={ocupado === c.id}
                    aoCarregar={() => accao(c.id, () => pagarCompensacao(c.id, metodo, referencia.trim() || null))}
                  />
                  <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
                </View>
              ) : (
                <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
                  <View style={{ flex: 1 }}>
                    <Botao titulo="Pagar" aoCarregar={() => setAberto(c.id)} />
                  </View>
                  <View style={{ flex: 1 }}>
                    <Botao
                      titulo={c.a_cargo === 'cozinha' ? 'Passar para a plataforma' : 'Passar para a cozinha'}
                      variante="secundario"
                      aCarregar={ocupado === c.id}
                      aoCarregar={() =>
                        accao(c.id, () => definirCargoCompensacao(c.id, c.a_cargo === 'cozinha' ? 'plataforma' : 'cozinha'))
                      }
                    />
                  </View>
                  <Botao titulo="Anular" variante="texto" aoCarregar={() => accao(c.id, () => pagarCompensacao(c.id, 'anular', null))} />
                </View>
              ))}
          </Cartao>
        ))}
      </Ecra>
    </Guarda>
  );
}
