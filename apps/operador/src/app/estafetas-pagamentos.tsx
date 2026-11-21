import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo } from '@/components/ui';
import { definirDiasEstafeta, definirRemuneracaoEstafeta, estafetasPagamentos, pagarEstafetaMes } from '@/lib/api';
import { formatarData, formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { EstafetaFolha, FolhaEstafetas } from '@/lib/tipos';

import { mesAoLado, nomeMes } from './contas-empresas';

const METODOS = ['Transferência', 'Multicaixa Express', 'Unitel Money', 'Dinheiro'] as const;
type Metodo = (typeof METODOS)[number];
const numero = (t: string): number => Number(t.replace(/\D/g, '') || '0');

/** Mês corrente ("2026-11-01") */
export function mesActual(agora: Date = new Date()): string {
  return `${agora.getFullYear()}-${String(agora.getMonth() + 1).padStart(2, '0')}-01`;
}

/**
 * Pagamento dos estafetas próprios: cada um com salário mensal, valor por dia e/ou por entrega
 * (todos opcionais). Os dias trabalhados vêm sugeridos pelos dias com entregas e podem ajustar-se;
 * o valor a pagar é calculado no servidor. As entregas das zonas do serviço contratado não contam.
 */
export default function EstafetasPagamentos() {
  const [mes, setMes] = useState<string>(mesAoLado(mesActual(), -1));
  const [dados, setDados] = useState<FolhaEstafetas | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [aberto, setAberto] = useState<{ id: string; accao: 'valores' | 'dias' | 'pagar' } | null>(null);
  const [salario, setSalario] = useState('');
  const [dia, setDia] = useState('');
  const [entrega, setEntrega] = useState('');
  const [dias, setDias] = useState('');
  const [metodo, setMetodo] = useState<Metodo>('Transferência');
  const [referencia, setReferencia] = useState('');
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    setDados(null);
    setErro(null);
    estafetasPagamentos(mes)
      .then(setDados)
      .catch((e) => setErro(mensagemErro(e)));
  }, [mes]);
  useFocusEffect(carregar);

  async function accao(f: () => Promise<unknown>, ok?: string) {
    setErro(null);
    setAviso(null);
    setOcupado(true);
    try {
      await f();
      setAberto(null);
      setReferencia('');
      if (ok) setAviso(ok);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  function abrir(e: EstafetaFolha, a: 'valores' | 'dias' | 'pagar') {
    setAberto({ id: e.funcionario_id, accao: a });
    setSalario(String(e.salario_mensal || ''));
    setDia(String(e.valor_dia || ''));
    setEntrega(String(e.valor_entrega || ''));
    setDias(String(e.dias_trabalhados));
  }

  const total = dados?.estafetas.reduce((s, e) => s + e.a_pagar, 0) ?? 0;

  return (
    <Guarda permissoes={['financas.conferir']}>
      <Ecra>
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
          <Botao titulo="‹ Anterior" variante="texto" aoCarregar={() => setMes(mesAoLado(mes, -1))} />
          <Text style={{ fontWeight: '700', fontSize: 16 }}>{nomeMes(mes)}</Text>
          <Botao titulo="Seguinte ›" variante="texto" aoCarregar={() => setMes(mesAoLado(mes, 1))} />
        </View>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {aviso && <Aviso tipo="sucesso">{aviso}</Aviso>}
        {!dados && !erro && <ACarregar />}
        {dados && (
          <>
            {!dados.pode_pagar && <Aviso>Mês em curso: os valores ainda vão mudar. Paga-se a partir do fim do mês.</Aviso>}
            <Cartao>
              <Linha esquerda="Total do mês" direita={formatarKz(total)} forte />
            </Cartao>
            {dados.estafetas.length === 0 && <Paragrafo suave>Sem estafetas próprios.</Paragrafo>}
            {dados.estafetas.map((e) => {
              const aqui = aberto?.id === e.funcionario_id ? aberto.accao : null;
              const semValores = !e.salario_mensal && !e.valor_dia && !e.valor_entrega;
              return (
                <Cartao key={e.funcionario_id}>
                  <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                    <Text style={{ fontWeight: '700', fontSize: 16 }}>{e.nome}</Text>
                    <Text style={{ fontWeight: '700', color: e.pago_em ? cores.sucesso : cores.aviso }}>
                      {e.pago_em ? 'Pago' : 'Por pagar'}
                    </Text>
                  </View>
                  {semValores && <Text style={{ color: cores.aviso }}>Valores por definir</Text>}
                  <Linha esquerda="Salário do mês" direita={formatarKz(e.salario_mensal)} />
                  <Linha
                    esquerda={`Dias: ${e.dias_trabalhados}${e.dias_ajustados ? ` (sugeridos ${e.dias_sugeridos})` : ''} × ${formatarKz(e.valor_dia)}`}
                    direita={formatarKz(e.dias_trabalhados * e.valor_dia)}
                  />
                  <Linha esquerda={`Entregas: ${e.entregas} × ${formatarKz(e.valor_entrega)}`} direita={formatarKz(e.entregas * e.valor_entrega)} />
                  <Linha esquerda={e.pago_em ? 'Pago' : 'A pagar'} direita={formatarKz(e.a_pagar)} forte />
                  {e.pago_em && (
                    <Text style={{ color: cores.textoSuave }}>
                      {formatarData(e.pago_em, true)} · {e.metodo}
                      {e.referencia ? ` · ${e.referencia}` : ''}
                    </Text>
                  )}

                  {aqui === 'valores' && (
                    <View style={{ gap: espaco.s }}>
                      <Campo rotulo="Salário mensal (Kz)" keyboardType="number-pad" value={salario} onChangeText={setSalario} />
                      <Campo rotulo="Valor por dia (Kz)" keyboardType="number-pad" value={dia} onChangeText={setDia} />
                      <Campo rotulo="Valor por entrega (Kz)" keyboardType="number-pad" value={entrega} onChangeText={setEntrega} />
                      <Paragrafo suave>Deixa a 0 o que não se aplica.</Paragrafo>
                      <Botao
                        titulo="Guardar os valores"
                        aCarregar={ocupado}
                        aoCarregar={() =>
                          accao(() => definirRemuneracaoEstafeta(e.funcionario_id, numero(salario), numero(dia), numero(entrega)), 'Valores guardados.')
                        }
                      />
                      <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
                    </View>
                  )}
                  {aqui === 'dias' && (
                    <View style={{ gap: espaco.s }}>
                      <Campo rotulo={`Dias trabalhados (sugeridos: ${e.dias_sugeridos})`} keyboardType="number-pad" value={dias} onChangeText={setDias} />
                      <Botao titulo="Guardar os dias" aCarregar={ocupado} aoCarregar={() => accao(() => definirDiasEstafeta(e.funcionario_id, mes, numero(dias)))} />
                      {e.dias_ajustados && (
                        <Botao titulo="Voltar aos sugeridos" variante="secundario" aoCarregar={() => accao(() => definirDiasEstafeta(e.funcionario_id, mes, null))} />
                      )}
                      <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
                    </View>
                  )}
                  {aqui === 'pagar' && (
                    <View style={{ gap: espaco.s }}>
                      <Escolha opcoes={METODOS.map((m) => ({ valor: m, rotulo: m }))} valor={metodo} aoMudar={setMetodo} />
                      <Campo
                        rotulo={metodo === 'Dinheiro' ? 'Referência (opcional)' : 'Referência (obrigatória)'}
                        value={referencia}
                        onChangeText={setReferencia}
                      />
                      <Botao
                        titulo={`Pagar ${formatarKz(e.a_pagar)}`}
                        aCarregar={ocupado}
                        aoCarregar={() => accao(() => pagarEstafetaMes(e.funcionario_id, mes, metodo, referencia.trim() || null), 'Pagamento registado.')}
                      />
                      <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
                    </View>
                  )}
                  {!aqui && (
                    <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
                      <View style={{ flex: 1 }}>
                        <Botao titulo="Valores" variante="secundario" aoCarregar={() => abrir(e, 'valores')} />
                      </View>
                      {!e.pago_em && (
                        <View style={{ flex: 1 }}>
                          <Botao titulo="Dias" variante="secundario" aoCarregar={() => abrir(e, 'dias')} />
                        </View>
                      )}
                      {!e.pago_em && dados.pode_pagar && e.a_pagar > 0 && (
                        <View style={{ flex: 1 }}>
                          <Botao titulo="Pagar" aoCarregar={() => abrir(e, 'pagar')} />
                        </View>
                      )}
                    </View>
                  )}
                </Cartao>
              );
            })}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
