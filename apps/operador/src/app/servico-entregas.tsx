import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo } from '@/components/ui';
import { fornecedoresEntrega, guardarFornecedorEntrega, pagarFornecedorEntrega } from '@/lib/api';
import { formatarData, formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco, raio } from '@/lib/tema';
import type { ServicoEntrega, ServicosEntrega } from '@/lib/tipos';

import { mesAoLado, nomeMes } from './contas-empresas';
import { mesActual } from './estafetas-pagamentos';

const METODOS = ['Transferência', 'Multicaixa Express', 'Unitel Money', 'Dinheiro'] as const;
type Metodo = (typeof METODOS)[number];
const numero = (t: string): number => Number(t.replace(/\D/g, '') || '0');

/**
 * Serviço de entregas contratado: valor por entrega e/ou valor mensal (os dois opcionais) e as
 * zonas que serve. As entregas nessas zonas contam para o serviço; paga-se o mês com referência
 * e o número da fatura do fornecedor.
 */
export default function ServicoEntregas() {
  const [mes, setMes] = useState<string>(mesAoLado(mesActual(), -1));
  const [dados, setDados] = useState<ServicosEntrega | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aberto, setAberto] = useState<{ id: string | null; accao: 'editar' | 'pagar' } | null>(null);
  const [nome, setNome] = useState('');
  const [valorEntrega, setValorEntrega] = useState('');
  const [valorMensal, setValorMensal] = useState('');
  const [zonas, setZonas] = useState<string[]>([]);
  const [metodo, setMetodo] = useState<Metodo>('Transferência');
  const [referencia, setReferencia] = useState('');
  const [fatura, setFatura] = useState('');
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    setDados(null);
    setErro(null);
    fornecedoresEntrega(mes)
      .then(setDados)
      .catch((e) => setErro(mensagemErro(e)));
  }, [mes]);
  useFocusEffect(carregar);

  async function accao(f: () => Promise<unknown>) {
    setErro(null);
    setOcupado(true);
    try {
      await f();
      setAberto(null);
      setReferencia('');
      setFatura('');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  function editar(f: ServicoEntrega | null) {
    setAberto({ id: f?.fornecedor_id ?? null, accao: 'editar' });
    setNome(f?.nome ?? '');
    setValorEntrega(f?.valor_entrega ? String(f.valor_entrega) : '');
    setValorMensal(f?.valor_mensal ? String(f.valor_mensal) : '');
    setZonas(f?.zonas.map((z) => z.id) ?? []);
  }

  function formulario(f: ServicoEntrega | null) {
    return (
      <View style={{ gap: espaco.s }}>
        <Campo rotulo="Nome do serviço" value={nome} onChangeText={setNome} />
        <Campo rotulo="Valor por entrega (Kz)" keyboardType="number-pad" value={valorEntrega} onChangeText={setValorEntrega} />
        <Campo rotulo="Valor mensal (Kz)" keyboardType="number-pad" value={valorMensal} onChangeText={setValorMensal} />
        <Paragrafo suave>Deixa a 0 o que não se aplica. Zonas que este serviço entrega:</Paragrafo>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: espaco.s }}>
          {dados?.zonas.map((z) => {
            const minha = zonas.includes(z.id);
            const doutro = !!z.fornecedor_id && z.fornecedor_id !== f?.fornecedor_id;
            return (
              <Pressable
                key={z.id}
                accessibilityRole="checkbox"
                accessibilityState={{ checked: minha }}
                onPress={() => setZonas((l) => (minha ? l.filter((x) => x !== z.id) : [...l, z.id]))}
                style={{
                  borderWidth: 1,
                  borderColor: minha ? cores.marca : cores.linha,
                  backgroundColor: minha ? cores.marca : 'transparent',
                  borderRadius: raio,
                  paddingVertical: 6,
                  paddingHorizontal: 12,
                }}>
                <Text style={{ color: minha ? '#fff' : cores.texto }}>
                  {z.nome}
                  {doutro && !minha ? ' (outro serviço)' : ''}
                </Text>
              </Pressable>
            );
          })}
        </View>
        <Botao
          titulo="Guardar"
          desactivado={!nome.trim()}
          aCarregar={ocupado}
          aoCarregar={() =>
            accao(() =>
              guardarFornecedorEntrega({
                id: f?.fornecedor_id ?? null,
                nome: nome.trim(),
                valorEntrega: numero(valorEntrega),
                valorMensal: numero(valorMensal),
                zonas,
                activo: true,
              }),
            )
          }
        />
        <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
      </View>
    );
  }

  return (
    <Guarda permissoes={['financas.servico_entregas']}>
      <Ecra>
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
          <Botao titulo="‹ Anterior" variante="texto" aoCarregar={() => setMes(mesAoLado(mes, -1))} />
          <Text style={{ fontWeight: '700', fontSize: 16 }}>{nomeMes(mes)}</Text>
          <Botao titulo="Seguinte ›" variante="texto" aoCarregar={() => setMes(mesAoLado(mes, 1))} />
        </View>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!dados && !erro && <ACarregar />}
        {dados && (
          <>
            {!dados.pode_pagar && <Aviso>Mês em curso: paga-se a partir do fim do mês.</Aviso>}
            {dados.fornecedores.length === 0 && !aberto && <Paragrafo suave>Ainda não há serviço de entregas contratado.</Paragrafo>}
            {dados.fornecedores.map((f) => {
              const aqui = aberto?.id === f.fornecedor_id ? aberto.accao : null;
              return (
                <Cartao key={f.fornecedor_id}>
                  <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                    <Text style={{ fontWeight: '700', fontSize: 16 }}>{f.nome}</Text>
                    <Text style={{ fontWeight: '700', color: f.pago ? cores.sucesso : cores.aviso }}>{f.pago ? 'Pago' : 'Por pagar'}</Text>
                  </View>
                  <Text style={{ color: cores.textoSuave }}>
                    Zonas: {f.zonas.length ? f.zonas.map((z) => z.nome).join(', ') : 'nenhuma'}
                  </Text>
                  <Linha esquerda="Valor mensal" direita={formatarKz(f.valor_mensal)} />
                  <Linha esquerda={`Entregas: ${f.entregas} × ${formatarKz(f.valor_entrega)}`} direita={formatarKz(f.entregas * f.valor_entrega)} />
                  <Linha esquerda={f.pago ? 'Pago' : 'A pagar'} direita={formatarKz(f.a_pagar)} forte />
                  {f.pago && (
                    <Text style={{ color: cores.textoSuave }}>
                      {formatarData(f.pago_em, true)} · {f.metodo}
                      {f.referencia ? ` · ${f.referencia}` : ''}
                      {f.numero_fatura ? ` · fatura ${f.numero_fatura}` : ''}
                    </Text>
                  )}
                  {aqui === 'editar' && formulario(f)}
                  {aqui === 'pagar' && (
                    <View style={{ gap: espaco.s }}>
                      <Escolha opcoes={METODOS.map((m) => ({ valor: m, rotulo: m }))} valor={metodo} aoMudar={setMetodo} />
                      <Campo
                        rotulo={metodo === 'Dinheiro' ? 'Referência (opcional)' : 'Referência (obrigatória)'}
                        value={referencia}
                        onChangeText={setReferencia}
                      />
                      <Campo rotulo="Número da fatura do serviço (opcional)" autoCapitalize="characters" value={fatura} onChangeText={setFatura} />
                      <Botao
                        titulo={`Pagar ${formatarKz(f.a_pagar)}`}
                        aCarregar={ocupado}
                        aoCarregar={() =>
                          accao(() => pagarFornecedorEntrega(f.fornecedor_id, mes, metodo, referencia.trim() || null, fatura.trim() || null))
                        }
                      />
                      <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
                    </View>
                  )}
                  {!aqui && (
                    <View style={{ flexDirection: 'row', gap: espaco.s }}>
                      <View style={{ flex: 1 }}>
                        <Botao titulo="Valores e zonas" variante="secundario" aoCarregar={() => editar(f)} />
                      </View>
                      {!f.pago && dados.pode_pagar && f.a_pagar > 0 && (
                        <View style={{ flex: 1 }}>
                          <Botao titulo="Pagar" aoCarregar={() => setAberto({ id: f.fornecedor_id, accao: 'pagar' })} />
                        </View>
                      )}
                    </View>
                  )}
                </Cartao>
              );
            })}
            {aberto?.id === null ? (
              <Cartao>{formulario(null)}</Cartao>
            ) : (
              !aberto && <Botao titulo="Novo serviço de entregas" variante="secundario" aoCarregar={() => editar(null)} />
            )}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
