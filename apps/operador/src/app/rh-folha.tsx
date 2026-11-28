import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Switch, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { formatarData, formatarKz, mensagemErro } from '@/lib/formatar';
import { rhFolha, rhFolhaAjustar, rhFolhaFechar, rhFolhaPagar, type Folha, type LinhaFolha } from '@/lib/rh';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';

import { mesAoLado, nomeMes } from './contas-empresas';
import { mesActual } from './estafetas-pagamentos';

const METODOS = ['Transferência', 'Multicaixa Express', 'Unitel Money', 'Dinheiro'] as const;
type Metodo = (typeof METODOS)[number];
const numero = (t: string) => Number(t.replace(/\D/g, '') || '0');

/**
 * Folha de salários do mês: salário (proporcional aos dias do contrato), subsídios, horas extra,
 * faltas, subsídios de férias e de Natal, Segurança Social e IRT. Quem calcula fecha a folha; a
 * tesouraria paga (separação de funções).
 */
export default function FolhaSalarios() {
  const { pode } = useSessao();
  const calcula = pode('rh.salarios');
  const paga = pode('financas.salarios');
  const [mes, setMes] = useState<string>(mesAoLado(mesActual(), -1));
  const [f, setF] = useState<Folha | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [aberto, setAberto] = useState<{ id: string; accao: 'ajustar' | 'pagar' } | null>(null);
  const [aj, setAj] = useState({ extras: '', descontos: '', subFerias: false, subNatal: false, nota: '' });
  const [metodo, setMetodo] = useState<Metodo>('Transferência');
  const [referencia, setReferencia] = useState('');
  const [confirmarFecho, setConfirmarFecho] = useState(false);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    setF(null);
    setErro(null);
    rhFolha(mes)
      .then(setF)
      .catch((e) => setErro(mensagemErro(e)));
  }, [mes]);
  useFocusEffect(carregar);

  async function accao(fn: () => Promise<unknown>, ok: string) {
    setErro(null);
    setAviso(null);
    setOcupado(true);
    try {
      await fn();
      setAberto(null);
      setReferencia('');
      setConfirmarFecho(false);
      setAviso(ok);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  function abrirAjuste(l: LinhaFolha) {
    setAberto({ id: l.funcionario_id, accao: 'ajustar' });
    setAj({ extras: l.extras ? String(l.extras) : '', descontos: l.descontos ? String(l.descontos) : '', subFerias: l.sub_ferias > 0, subNatal: l.sub_natal > 0, nota: l.nota ?? '' });
  }

  return (
    <Guarda permissoes={['rh.salarios', 'financas.salarios']}>
      <Ecra>
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
          <Botao titulo="‹ Anterior" variante="texto" aoCarregar={() => setMes(mesAoLado(mes, -1))} />
          <Text style={{ fontWeight: '700', fontSize: 16 }}>{nomeMes(mes)}</Text>
          <Botao titulo="Seguinte ›" variante="texto" aoCarregar={() => setMes(mesAoLado(mes, 1))} />
        </View>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {aviso && <Aviso tipo="sucesso">{aviso}</Aviso>}
        {!f && !erro && <ACarregar />}
        {f && (
          <>
            <Cartao>
              <Text style={{ fontWeight: '700', color: f.fechada ? cores.sucesso : cores.aviso }}>
                {f.fechada ? 'Folha fechada' : 'Folha em preparação (os valores ainda podem mudar)'}
              </Text>
              <Linha esquerda="Total bruto" direita={formatarKz(f.totais.bruto)} />
              <Linha esquerda="Segurança Social dos trabalhadores" direita={formatarKz(f.totais.inss_trabalhador)} />
              <Linha esquerda="Segurança Social da empresa" direita={formatarKz(f.totais.inss_empresa)} />
              <Linha esquerda="IRT retido" direita={formatarKz(f.totais.irt)} />
              <Linha esquerda="Líquido a pagar" direita={formatarKz(f.totais.liquido)} forte />
              <Linha esquerda="Custo total para a empresa" direita={formatarKz(f.totais.custo_empresa)} />
              {f.fechada && <Linha esquerda="Ainda por pagar" direita={formatarKz(f.totais.por_pagar)} />}
              <Paragrafo suave>
                A entregar ao Estado: Segurança Social {formatarKz(f.totais.inss_trabalhador + f.totais.inss_empresa)} e IRT{' '}
                {formatarKz(f.totais.irt)}.
              </Paragrafo>
            </Cartao>
            {f.linhas.length === 0 && <Paragrafo suave>Ninguém com contrato de trabalho neste mês.</Paragrafo>}
            {f.linhas.map((l) => {
              const aqui = aberto?.id === l.funcionario_id ? aberto.accao : null;
              return (
                <Cartao key={l.funcionario_id}>
                  <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                    <Text style={{ fontWeight: '700', fontSize: 16, flex: 1 }}>{l.nome}</Text>
                    {f.fechada && (
                      <Text style={{ fontWeight: '700', color: l.pago_em ? cores.sucesso : cores.aviso }}>{l.pago_em ? 'Pago' : 'Por pagar'}</Text>
                    )}
                  </View>
                  {l.dias < 28 && <Text style={{ color: cores.textoSuave }}>{l.dias} dias de contrato neste mês (proporcional)</Text>}
                  <Linha esquerda="Salário base" direita={formatarKz(l.salario_base)} />
                  {l.sub_alimentacao + l.sub_transporte + l.outros_subsidios > 0 && (
                    <Linha esquerda="Subsídios" direita={formatarKz(l.sub_alimentacao + l.sub_transporte + l.outros_subsidios)} />
                  )}
                  {l.extras > 0 && <Linha esquerda="Horas extra e prémios" direita={formatarKz(l.extras)} />}
                  {l.sub_ferias > 0 && <Linha esquerda="Subsídio de férias" direita={formatarKz(l.sub_ferias)} />}
                  {l.sub_natal > 0 && <Linha esquerda="Subsídio de Natal" direita={formatarKz(l.sub_natal)} />}
                  {l.descontos > 0 && <Linha esquerda="Faltas e descontos" direita={`−${formatarKz(l.descontos)}`} />}
                  <Linha esquerda="Bruto" direita={formatarKz(l.bruto)} />
                  <Linha esquerda="Segurança Social" direita={`−${formatarKz(l.inss_trabalhador)}`} />
                  <Linha esquerda={`IRT (sobre ${formatarKz(l.materia_colectavel)})`} direita={`−${formatarKz(l.irt)}`} />
                  <Linha esquerda="Líquido" direita={formatarKz(l.liquido)} forte />
                  {l.nota && <Text style={{ color: cores.textoSuave }}>{l.nota}</Text>}
                  {l.pago_em && (
                    <Text style={{ color: cores.textoSuave }}>
                      Pago a {formatarData(l.pago_em, true)} · {l.metodo}
                      {l.referencia ? ` · ${l.referencia}` : ''}
                    </Text>
                  )}

                  {aqui === 'ajustar' && (
                    <View style={{ gap: espaco.s }}>
                      <Campo rotulo="Horas extra e prémios (Kz)" keyboardType="number-pad" value={aj.extras} onChangeText={(t) => setAj({ ...aj, extras: t })} />
                      <Campo rotulo="Faltas e outros descontos (Kz)" keyboardType="number-pad" value={aj.descontos} onChangeText={(t) => setAj({ ...aj, descontos: t })} />
                      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                        <Text>Pagar o subsídio de férias este mês</Text>
                        <Switch accessibilityLabel="Subsídio de férias" value={aj.subFerias} onValueChange={(v) => setAj({ ...aj, subFerias: v })} />
                      </View>
                      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                        <Text>Pagar o subsídio de Natal este mês</Text>
                        <Switch accessibilityLabel="Subsídio de Natal" value={aj.subNatal} onValueChange={(v) => setAj({ ...aj, subNatal: v })} />
                      </View>
                      <Campo rotulo="Nota (opcional)" value={aj.nota} onChangeText={(t) => setAj({ ...aj, nota: t })} />
                      <Botao
                        titulo="Guardar o ajuste"
                        aCarregar={ocupado}
                        aoCarregar={() =>
                          accao(
                            () =>
                              rhFolhaAjustar(mes, l.funcionario_id, {
                                extras: numero(aj.extras), descontos: numero(aj.descontos), subFerias: aj.subFerias, subNatal: aj.subNatal, nota: aj.nota.trim() || null,
                              }),
                            'Ajuste guardado.',
                          )
                        }
                      />
                      <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
                    </View>
                  )}
                  {aqui === 'pagar' && (
                    <View style={{ gap: espaco.s }}>
                      <Escolha opcoes={METODOS.map((m) => ({ valor: m, rotulo: m }))} valor={metodo} aoMudar={setMetodo} />
                      <Campo rotulo={metodo === 'Dinheiro' ? 'Referência (opcional)' : 'Referência (obrigatória)'} value={referencia} onChangeText={setReferencia} />
                      <Botao
                        titulo={`Pagar ${formatarKz(l.liquido)}`}
                        aCarregar={ocupado}
                        aoCarregar={() => accao(() => rhFolhaPagar(mes, l.funcionario_id, metodo, referencia.trim() || null), 'Salário pago.')}
                      />
                      <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
                    </View>
                  )}
                  {!aqui && !f.fechada && calcula && <Botao titulo="Ajustar" variante="secundario" aoCarregar={() => abrirAjuste(l)} />}
                  {!aqui && f.fechada && paga && !l.pago_em && <Botao titulo="Pagar" aoCarregar={() => setAberto({ id: l.funcionario_id, accao: 'pagar' })} />}
                </Cartao>
              );
            })}
            {f.prestadores.length > 0 && (
              <Cartao>
                <Subtitulo>Prestadores de serviços (fora da folha)</Subtitulo>
                {f.prestadores.map((p) => (
                  <Text key={p.nome}>
                    {p.nome}
                    {p.funcao ? ` · ${p.funcao}` : ''}
                  </Text>
                ))}
                <Paragrafo suave>Pagam-se contra fatura ou recibo, fora desta folha.</Paragrafo>
              </Cartao>
            )}
            {!f.fechada && calcula && f.linhas.length > 0 && (
              confirmarFecho ? (
                <>
                  <Aviso>Depois de fechada, a folha deixa de mudar com os contratos e as taxas. Continuar?</Aviso>
                  <Botao titulo="Sim, fechar a folha" aCarregar={ocupado} aoCarregar={() => accao(() => rhFolhaFechar(mes), 'Folha fechada.')} />
                  <Botao titulo="Voltar" variante="texto" aoCarregar={() => setConfirmarFecho(false)} />
                </>
              ) : (
                <Botao
                  titulo={f.pode_fechar ? 'Fechar a folha do mês' : 'Fecha-se a partir do fim do mês'}
                  desactivado={!f.pode_fechar}
                  aoCarregar={() => setConfirmarFecho(true)}
                />
              )
            )}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
