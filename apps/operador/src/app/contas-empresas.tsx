import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo } from '@/components/ui';
import { contasEmpresas, emitirFaturaEmpresa, pagarFaturaEmpresa } from '@/lib/api';
import { formatarData, formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { ContaEmpresa, ContasEmpresas as Contas } from '@/lib/tipos';

const METODOS = ['Transferência', 'Multicaixa Express', 'Unitel Money', 'Dinheiro'] as const;
type Metodo = (typeof METODOS)[number];
const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

/** "2026-10-01" → "outubro de 2026" */
export function nomeMes(iso: string): string {
  const [a, m] = iso.split('-').map(Number);
  return `${MESES[m - 1]} de ${a}`;
}

/** Mês ao lado ("2026-10-01", +1 → "2026-11-01") */
export function mesAoLado(iso: string, n: number): string {
  const [a, m] = iso.split('-').map(Number);
  const d = new Date(a, m - 1 + n, 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
}

/** Vencimento sugerido: dia 15 do mês seguinte ao faturado */
export function vencimentoSugerido(mes: string): string {
  return mesAoLado(mes, 1).replace(/-01$/, '-15');
}

/**
 * Contas das empresas (B2B): no fim do mês, a parte que cada empresa pagou nos almoços dos seus
 * funcionários é faturada (software certificado), com vencimento; aqui fica o número, o pagamento
 * e o que está em atraso.
 */
export default function ContasEmpresas() {
  const [mes, setMes] = useState<string | null>(null);
  const [dados, setDados] = useState<Contas | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aberto, setAberto] = useState<{ id: string; accao: 'faturar' | 'pagar' } | null>(null);
  const [numero, setNumero] = useState('');
  const [vencimento, setVencimento] = useState('');
  const [metodo, setMetodo] = useState<Metodo>('Transferência');
  const [referencia, setReferencia] = useState('');
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    setDados(null);
    setErro(null);
    // Por defeito: o mês passado (o que se fatura agora)
    contasEmpresas(mes ?? mesAoLado(`${new Date().getFullYear()}-${String(new Date().getMonth() + 1).padStart(2, '0')}-01`, -1))
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
      setNumero('');
      setReferencia('');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  function etiqueta(e: ContaEmpresa): { texto: string; cor: string } {
    if (e.estado === 'paga') return { texto: 'Paga', cor: cores.sucesso };
    if (e.estado === 'emitida') return e.em_atraso ? { texto: 'Em atraso', cor: cores.erro } : { texto: 'Por receber', cor: cores.aviso };
    return { texto: 'Por faturar', cor: cores.textoSuave };
  }

  return (
    <Guarda permissoes={['financas.conferir']}>
      <Ecra>
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
          <Botao titulo="‹ Anterior" variante="texto" desactivado={!dados} aoCarregar={() => dados && setMes(mesAoLado(dados.mes, -1))} />
          <Text style={{ fontWeight: '700', fontSize: 16 }}>{dados ? nomeMes(dados.mes) : '…'}</Text>
          <Botao titulo="Seguinte ›" variante="texto" desactivado={!dados} aoCarregar={() => dados && setMes(mesAoLado(dados.mes, 1))} />
        </View>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!dados && !erro && <ACarregar />}
        {dados && (
          <>
            {dados.em_atraso_total > 0 && <Aviso tipo="erro">Em atraso (todas as empresas): {formatarKz(dados.em_atraso_total)}</Aviso>}
            {!dados.pode_faturar && <Aviso>Mês em curso: fatura-se a partir do dia 1 do mês seguinte.</Aviso>}
            {dados.empresas.length === 0 && <Paragrafo suave>Nenhuma empresa com almoços neste mês.</Paragrafo>}
            {dados.empresas.map((e) => {
              const et = etiqueta(e);
              return (
                <Cartao key={e.empresa_id}>
                  <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                    <Text style={{ fontWeight: '700', fontSize: 16 }}>{e.nome}</Text>
                    <Text style={{ color: et.cor, fontWeight: '700' }}>{et.texto}</Text>
                  </View>
                  <Linha esquerda={`${e.pedidos} almoços`} direita={formatarKz(e.valor)} forte />
                  {e.numero && <Text>Fatura {e.numero} · vence {formatarData(e.vencimento)}</Text>}
                  {e.estado === 'paga' && (
                    <Text style={{ color: cores.sucesso }}>
                      Paga {formatarData(e.pago_em)}
                      {e.referencia ? ` · ${e.referencia}` : ''}
                    </Text>
                  )}
                  {aberto?.id === e.empresa_id && aberto.accao === 'faturar' && (
                    <View style={{ gap: espaco.s }}>
                      <Campo rotulo="Número da fatura" autoCapitalize="characters" value={numero} onChangeText={setNumero} />
                      <Campo rotulo="Vencimento (AAAA-MM-DD)" value={vencimento} onChangeText={setVencimento} />
                      <Botao
                        titulo="Registar a fatura"
                        desactivado={!numero.trim() || !/^\d{4}-\d{2}-\d{2}$/.test(vencimento)}
                        aCarregar={ocupado}
                        aoCarregar={() => accao(() => emitirFaturaEmpresa(e.empresa_id, dados.mes, numero.trim(), vencimento))}
                      />
                      <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
                    </View>
                  )}
                  {aberto?.id === e.empresa_id && aberto.accao === 'pagar' && (
                    <View style={{ gap: espaco.s }}>
                      <Escolha opcoes={METODOS.map((m) => ({ valor: m, rotulo: m }))} valor={metodo} aoMudar={setMetodo} />
                      <Campo
                        rotulo={metodo === 'Dinheiro' ? 'Referência (opcional)' : 'Referência (obrigatória)'}
                        value={referencia}
                        onChangeText={setReferencia}
                      />
                      <Botao
                        titulo="Registar o pagamento"
                        aCarregar={ocupado}
                        aoCarregar={() => accao(() => pagarFaturaEmpresa(e.fatura_id!, metodo, referencia.trim() || null))}
                      />
                      <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
                    </View>
                  )}
                  {!aberto && e.estado === 'por_faturar' && dados.pode_faturar && (
                    <Botao
                      titulo="Registar a fatura do mês"
                      variante="secundario"
                      aoCarregar={() => {
                        setAberto({ id: e.empresa_id, accao: 'faturar' });
                        setVencimento(vencimentoSugerido(dados.mes));
                      }}
                    />
                  )}
                  {!aberto && e.estado === 'emitida' && (
                    <Botao titulo="Registar o pagamento" aoCarregar={() => setAberto({ id: e.empresa_id, accao: 'pagar' })} />
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
