import { useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { formatarData, formatarKz, mensagemErro } from '@/lib/formatar';
import {
  PROPRIEDADES,
  TIPOS_CONTRATO,
  TIPOS_DOCUMENTO,
  TIPOS_EQUIPAMENTO,
  dataValida,
  experimentalPadrao,
  nomeContrato,
  nomeDocumento,
  nomeEquipamento,
  rhApagarDocumento,
  rhDevolverEquipamento,
  rhFicha,
  rhGuardarContrato,
  rhGuardarDocumento,
  rhGuardarEquipamento,
  rhGuardarFicha,
  rhSimular,
  rhTerminarContrato,
  type Calculo,
  type Ficha,
  type FichaCompleta,
  type TipoContrato,
} from '@/lib/rh';
import { cores, espaco } from '@/lib/tema';

const numero = (t: string) => Number(t.replace(/\D/g, '') || '0');
const CAMPOS_FICHA: [keyof Ficha, string][] = [
  ['bi', 'Bilhete de identidade'],
  ['nif', 'NIF'],
  ['inss_numero', 'N.º da Segurança Social (INSS)'],
  ['data_nascimento', 'Data de nascimento (AAAA-MM-DD)'],
  ['data_admissao', 'Data de admissão (AAAA-MM-DD)'],
  ['morada', 'Morada'],
  ['banco', 'Banco'],
  ['iban', 'IBAN'],
  ['emergencia_nome', 'Contacto de emergência: nome'],
  ['emergencia_telefone', 'Contacto de emergência: telefone'],
  ['notas', 'Notas'],
];

type FormContrato = {
  tipo: TipoContrato;
  funcao: string;
  inicio: string;
  fim: string;
  experimental: string;
  horas: string;
  base: string;
  alim: string;
  transp: string;
  outros: string;
};

/** Ficha de um trabalhador: dados pessoais, documentos, contrato (com o salário simulado) e equipamento */
export default function FichaRH() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [d, setD] = useState<FichaCompleta | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [ficha, setFicha] = useState<Record<string, string>>({});
  const [doc, setDoc] = useState<{ tipo: string; numero: string; validade: string } | null>(null);
  const [contrato, setContrato] = useState<FormContrato | null>(null);
  const [sim, setSim] = useState<Calculo | null>(null);
  const [terminar, setTerminar] = useState<{ data: string; motivo: string } | null>(null);
  const [equip, setEquip] = useState<{ tipo: string; descricao: string; matricula: string; propriedade: string } | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    setErro(null);
    rhFicha(id)
      .then((r) => {
        setD(r);
        setFicha(Object.fromEntries(CAMPOS_FICHA.map(([k]) => [k, (r.ficha?.[k] as string | null) ?? ''])));
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [id]);
  useFocusEffect(carregar);

  // Salário simulado (INSS, IRT, líquido) enquanto se preenche o contrato
  useEffect(() => {
    if (!contrato || contrato.tipo === 'prestacao_servicos') return setSim(null);
    const t = setTimeout(() => {
      rhSimular(numero(contrato.base), numero(contrato.alim), numero(contrato.transp), numero(contrato.outros))
        .then(setSim)
        .catch(() => setSim(null));
    }, 400);
    return () => clearTimeout(t);
  }, [contrato]);

  async function accao(f: () => Promise<unknown>, ok: string, depois?: () => void) {
    setErro(null);
    setAviso(null);
    setOcupado(true);
    try {
      await f();
      depois?.();
      setAviso(ok);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  const activo = d?.contratos.find((c) => c.activo) ?? null;
  const datasFichaOk = dataValida(ficha.data_nascimento ?? '') && dataValida(ficha.data_admissao ?? '');
  const contratoOk =
    !!contrato &&
    /^\d{4}-\d{2}-\d{2}$/.test(contrato.inicio) &&
    dataValida(contrato.fim) &&
    (contrato.tipo !== 'termo_certo' || contrato.fim.trim() !== '');

  function novoContrato() {
    setContrato({
      tipo: activo?.tipo ?? 'indeterminado',
      funcao: activo?.funcao ?? d?.cargo ?? '',
      inicio: '',
      fim: '',
      experimental: String(experimentalPadrao(activo?.tipo ?? 'indeterminado')),
      horas: activo?.horas_semana ? String(activo.horas_semana) : '44',
      base: activo ? String(activo.salario_base) : '',
      alim: activo ? String(activo.subsidio_alimentacao) : '',
      transp: activo ? String(activo.subsidio_transporte) : '',
      outros: activo ? String(activo.outros_subsidios) : '',
    });
  }

  return (
    <Guarda permissoes={['rh.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {aviso && <Aviso tipo="sucesso">{aviso}</Aviso>}
        {!d && !erro && <ACarregar />}
        {d && (
          <>
            <Subtitulo>{d.nome}</Subtitulo>
            <Paragrafo suave>
              {d.cargo ?? 'Sem cargo'}
              {d.telefone ? ` · ${d.telefone}` : ''}
            </Paragrafo>
            {d.alertas.map((a) => (
              <Aviso key={a}>{a}</Aviso>
            ))}

            {/* ------------------------------------------------ contrato */}
            <Cartao>
              <Subtitulo>Contrato</Subtitulo>
              {activo ? (
                <>
                  <Text style={{ fontWeight: '700' }}>{nomeContrato(activo.tipo)}</Text>
                  <Text style={{ color: cores.textoSuave }}>
                    {activo.funcao ?? '—'} · desde {formatarData(activo.inicio)}
                    {activo.fim ? ` até ${formatarData(activo.fim)}` : ''}
                    {activo.periodo_experimental_dias ? ` · ${activo.periodo_experimental_dias} dias de experiência` : ''}
                  </Text>
                  {activo.tipo !== 'prestacao_servicos' && (
                    <>
                      <Linha esquerda="Salário base" direita={formatarKz(activo.salario_base)} />
                      <Linha esquerda="Subsídio de alimentação" direita={formatarKz(activo.subsidio_alimentacao)} />
                      <Linha esquerda="Subsídio de transporte" direita={formatarKz(activo.subsidio_transporte)} />
                      {activo.outros_subsidios > 0 && <Linha esquerda="Outros subsídios" direita={formatarKz(activo.outros_subsidios)} />}
                    </>
                  )}
                </>
              ) : (
                <Paragrafo suave>Sem contrato registado.</Paragrafo>
              )}
              {contrato ? (
                <View style={{ gap: espaco.s }}>
                  <Text style={{ fontWeight: '700' }}>Tipo de contrato</Text>
                  <Escolha
                    opcoes={TIPOS_CONTRATO.map((t) => ({ valor: t.valor, rotulo: t.rotulo }))}
                    valor={contrato.tipo}
                    aoMudar={(v) => setContrato({ ...contrato, tipo: v, experimental: String(experimentalPadrao(v)) })}
                  />
                  <Campo rotulo="Função" value={contrato.funcao} onChangeText={(t) => setContrato({ ...contrato, funcao: t })} />
                  <Campo rotulo="Início (AAAA-MM-DD)" value={contrato.inicio} onChangeText={(t) => setContrato({ ...contrato, inicio: t })} />
                  <Campo
                    rotulo={contrato.tipo === 'termo_certo' ? 'Fim (AAAA-MM-DD, obrigatório)' : 'Fim (AAAA-MM-DD, opcional)'}
                    value={contrato.fim}
                    onChangeText={(t) => setContrato({ ...contrato, fim: t })}
                  />
                  <Campo
                    rotulo="Período experimental (dias)"
                    keyboardType="number-pad"
                    value={contrato.experimental}
                    onChangeText={(t) => setContrato({ ...contrato, experimental: t })}
                  />
                  <Campo rotulo="Horas por semana" keyboardType="number-pad" value={contrato.horas} onChangeText={(t) => setContrato({ ...contrato, horas: t })} />
                  <Campo
                    rotulo={contrato.tipo === 'prestacao_servicos' ? 'Valor mensal do serviço (Kz)' : 'Salário base (Kz)'}
                    keyboardType="number-pad"
                    value={contrato.base}
                    onChangeText={(t) => setContrato({ ...contrato, base: t })}
                  />
                  {contrato.tipo !== 'prestacao_servicos' && (
                    <>
                      <Campo rotulo="Subsídio de alimentação (Kz)" keyboardType="number-pad" value={contrato.alim} onChangeText={(t) => setContrato({ ...contrato, alim: t })} />
                      <Campo rotulo="Subsídio de transporte (Kz)" keyboardType="number-pad" value={contrato.transp} onChangeText={(t) => setContrato({ ...contrato, transp: t })} />
                      <Campo rotulo="Outros subsídios (Kz)" keyboardType="number-pad" value={contrato.outros} onChangeText={(t) => setContrato({ ...contrato, outros: t })} />
                    </>
                  )}
                  {sim && (
                    <View style={{ backgroundColor: cores.fundoSuave, borderRadius: 8, padding: espaco.s }}>
                      <Text style={{ fontWeight: '700' }}>Simulação do mês completo</Text>
                      <Linha esquerda="Bruto" direita={formatarKz(sim.bruto)} />
                      <Linha esquerda="Segurança Social do trabalhador" direita={`−${formatarKz(sim.inss_trabalhador)}`} />
                      <Linha esquerda="IRT" direita={`−${formatarKz(sim.irt)}`} />
                      <Linha esquerda="Líquido a receber" direita={formatarKz(sim.liquido)} forte />
                      <Linha esquerda="Custo para a empresa (com INSS da empresa)" direita={formatarKz(sim.custo_empresa)} />
                    </View>
                  )}
                  <Botao
                    titulo={activo ? 'Guardar o novo contrato (substitui o actual)' : 'Guardar o contrato'}
                    desactivado={!contratoOk}
                    aCarregar={ocupado}
                    aoCarregar={() =>
                      accao(
                        () =>
                          rhGuardarContrato({
                            funcionario_id: d.funcionario_id,
                            tipo: contrato.tipo,
                            funcao: contrato.funcao.trim() || null,
                            inicio: contrato.inicio.trim(),
                            fim: contrato.fim.trim() || null,
                            periodo_experimental_dias: numero(contrato.experimental),
                            horas_semana: contrato.horas.trim() ? numero(contrato.horas) : null,
                            salario_base: numero(contrato.base),
                            subsidio_alimentacao: numero(contrato.alim),
                            subsidio_transporte: numero(contrato.transp),
                            outros_subsidios: numero(contrato.outros),
                          }),
                        'Contrato guardado.',
                        () => setContrato(null),
                      )
                    }
                  />
                  <Botao titulo="Voltar" variante="texto" aoCarregar={() => setContrato(null)} />
                </View>
              ) : terminar && activo ? (
                <View style={{ gap: espaco.s }}>
                  <Campo rotulo="Data do fim (AAAA-MM-DD)" value={terminar.data} onChangeText={(t) => setTerminar({ ...terminar, data: t })} />
                  <Campo rotulo="Motivo" value={terminar.motivo} onChangeText={(t) => setTerminar({ ...terminar, motivo: t })} />
                  <Botao
                    titulo="Terminar o contrato"
                    desactivado={!/^\d{4}-\d{2}-\d{2}$/.test(terminar.data)}
                    aCarregar={ocupado}
                    aoCarregar={() => accao(() => rhTerminarContrato(activo.id, terminar.data, terminar.motivo.trim() || null), 'Contrato terminado.', () => setTerminar(null))}
                  />
                  <Botao titulo="Voltar" variante="texto" aoCarregar={() => setTerminar(null)} />
                </View>
              ) : (
                <View style={{ flexDirection: 'row', gap: espaco.s }}>
                  <View style={{ flex: 1 }}>
                    <Botao titulo={activo ? 'Novo contrato' : 'Registar contrato'} variante="secundario" aoCarregar={novoContrato} />
                  </View>
                  {activo && (
                    <View style={{ flex: 1 }}>
                      <Botao titulo="Terminar" variante="texto" aoCarregar={() => setTerminar({ data: '', motivo: '' })} />
                    </View>
                  )}
                </View>
              )}
              {d.contratos.filter((c) => !c.activo).map((c) => (
                <Text key={c.id} style={{ color: cores.textoSuave, fontSize: 13 }}>
                  Anterior: {nomeContrato(c.tipo)} · {formatarData(c.inicio)} a {c.terminado_em ? formatarData(c.terminado_em) : '—'}
                  {c.motivo_fim ? ` · ${c.motivo_fim}` : ''}
                </Text>
              ))}
            </Cartao>

            {/* ------------------------------------------------ dados pessoais */}
            <Cartao>
              <Subtitulo>Dados pessoais</Subtitulo>
              <Paragrafo suave>Só quem tem a permissão de recursos humanos vê estes dados.</Paragrafo>
              {CAMPOS_FICHA.map(([k, rotulo]) => (
                <Campo key={k} rotulo={rotulo} value={ficha[k] ?? ''} onChangeText={(t) => setFicha({ ...ficha, [k]: t })} />
              ))}
              <Botao
                titulo="Guardar os dados"
                desactivado={!datasFichaOk}
                aCarregar={ocupado}
                aoCarregar={() => accao(() => rhGuardarFicha(d.funcionario_id, ficha), 'Dados guardados.')}
              />
            </Cartao>

            {/* ------------------------------------------------ documentos */}
            <Cartao>
              <Subtitulo>Documentos</Subtitulo>
              {d.documentos.length === 0 && <Paragrafo suave>Sem documentos registados.</Paragrafo>}
              {d.documentos.map((x) => (
                <View key={x.id} style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                  <View style={{ flex: 1 }}>
                    <Text style={{ fontWeight: '600' }}>{nomeDocumento(x.tipo)}</Text>
                    <Text style={{ color: cores.textoSuave }}>
                      {x.numero ?? 's/ n.º'}
                      {x.validade ? ` · válido até ${formatarData(x.validade)}` : ''}
                    </Text>
                  </View>
                  <Botao titulo="Apagar" variante="texto" aoCarregar={() => accao(() => rhApagarDocumento(x.id), 'Documento apagado.')} />
                </View>
              ))}
              {doc ? (
                <View style={{ gap: espaco.s }}>
                  <Escolha opcoes={TIPOS_DOCUMENTO.map((t) => ({ valor: t.valor, rotulo: t.rotulo }))} valor={doc.tipo} aoMudar={(v) => setDoc({ ...doc, tipo: v })} />
                  <Campo rotulo="Número" value={doc.numero} onChangeText={(t) => setDoc({ ...doc, numero: t })} />
                  <Campo rotulo="Válido até (AAAA-MM-DD)" value={doc.validade} onChangeText={(t) => setDoc({ ...doc, validade: t })} />
                  <Botao
                    titulo="Guardar o documento"
                    desactivado={!dataValida(doc.validade)}
                    aCarregar={ocupado}
                    aoCarregar={() =>
                      accao(
                        () => rhGuardarDocumento({ funcionario_id: d.funcionario_id, tipo: doc.tipo, numero: doc.numero.trim() || null, validade: doc.validade.trim() || null }),
                        'Documento guardado.',
                        () => setDoc(null),
                      )
                    }
                  />
                  <Botao titulo="Voltar" variante="texto" aoCarregar={() => setDoc(null)} />
                </View>
              ) : (
                <Botao titulo="Acrescentar documento" variante="secundario" aoCarregar={() => setDoc({ tipo: 'bi', numero: '', validade: '' })} />
              )}
            </Cartao>

            {/* ------------------------------------------------ equipamento */}
            <Cartao>
              <Subtitulo>Equipamento entregue</Subtitulo>
              {d.equipamentos.length === 0 && <Paragrafo suave>Sem equipamento registado.</Paragrafo>}
              {d.equipamentos.map((x) => (
                <View key={x.id} style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                  <View style={{ flex: 1 }}>
                    <Text style={{ fontWeight: '600' }}>
                      {nomeEquipamento(x.tipo)}
                      {x.matricula ? ` ${x.matricula}` : ''}
                      {x.descricao ? ` · ${x.descricao}` : ''}
                    </Text>
                    <Text style={{ color: cores.textoSuave }}>
                      {PROPRIEDADES.find((p) => p.valor === x.propriedade)?.rotulo} · entregue {formatarData(x.entregue_em)}
                      {x.devolvido_em ? ` · devolvido ${formatarData(x.devolvido_em)}` : ''}
                    </Text>
                  </View>
                  {!x.devolvido_em && (
                    <Botao titulo="Devolvido" variante="texto" aoCarregar={() => accao(() => rhDevolverEquipamento(x.id, null), 'Devolução registada.')} />
                  )}
                </View>
              ))}
              {equip ? (
                <View style={{ gap: espaco.s }}>
                  <Escolha opcoes={TIPOS_EQUIPAMENTO.map((t) => ({ valor: t.valor, rotulo: t.rotulo }))} valor={equip.tipo} aoMudar={(v) => setEquip({ ...equip, tipo: v })} />
                  <Escolha opcoes={PROPRIEDADES.map((t) => ({ valor: t.valor, rotulo: t.rotulo }))} valor={equip.propriedade} aoMudar={(v) => setEquip({ ...equip, propriedade: v })} />
                  <Campo rotulo="Descrição" value={equip.descricao} onChangeText={(t) => setEquip({ ...equip, descricao: t })} />
                  {equip.tipo === 'mota' && <Campo rotulo="Matrícula" autoCapitalize="characters" value={equip.matricula} onChangeText={(t) => setEquip({ ...equip, matricula: t })} />}
                  <Botao
                    titulo="Registar a entrega"
                    aCarregar={ocupado}
                    aoCarregar={() =>
                      accao(
                        () =>
                          rhGuardarEquipamento({
                            funcionario_id: d.funcionario_id, tipo: equip.tipo, propriedade: equip.propriedade,
                            descricao: equip.descricao.trim() || null, matricula: equip.matricula.trim() || null,
                          }),
                        'Equipamento registado.',
                        () => setEquip(null),
                      )
                    }
                  />
                  <Botao titulo="Voltar" variante="texto" aoCarregar={() => setEquip(null)} />
                </View>
              ) : (
                <Botao titulo="Entregar equipamento" variante="secundario" aoCarregar={() => setEquip({ tipo: 'mota', descricao: '', matricula: '', propriedade: 'empresa' })} />
              )}
            </Cartao>
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
