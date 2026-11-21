import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { rhGuardarParametros, rhParametros, type Escalao } from '@/lib/rh';
import { cores, espaco } from '@/lib/tema';

type Texto<T> = { [K in keyof T]: string };
const TAXAS: [string, string][] = [
  ['inss_trabalhador', 'Segurança Social do trabalhador (%)'],
  ['inss_empresa', 'Segurança Social da empresa (%)'],
  ['isencao_alimentacao', 'Subsídio de alimentação isento de IRT até (Kz)'],
  ['isencao_transporte', 'Subsídio de transporte isento de IRT até (Kz)'],
  ['subsidio_ferias_pct', 'Subsídio de férias (% do salário base)'],
  ['subsidio_natal_pct', 'Subsídio de Natal (% do salário base)'],
];
const decimal = (t: string) => Number(t.replace(',', '.').replace(/[^\d.]/g, '') || '0');
const inteiro = (t: string) => Number(t.replace(/\D/g, '') || '0');

/** Taxas da Segurança Social, isenções e a tabela do IRT (editáveis quando a lei mudar) */
export default function ParametrosRH() {
  const [taxas, setTaxas] = useState<Record<string, string> | null>(null);
  const [referencia, setReferencia] = useState('');
  const [escaloes, setEscaloes] = useState<Texto<Escalao>[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    setErro(null);
    rhParametros()
      .then((r) => {
        setTaxas(Object.fromEntries(TAXAS.map(([k]) => [k, String((r.parametros as Record<string, unknown>)[k] ?? '')])));
        setReferencia(r.parametros.referencia_legal);
        setEscaloes(
          r.escaloes.map((e) => ({
            limite_inferior: String(e.limite_inferior),
            limite_superior: e.limite_superior == null ? '' : String(e.limite_superior),
            parcela_fixa: String(e.parcela_fixa),
            taxa: String(e.taxa),
            excesso: String(e.excesso),
          })),
        );
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  const mudar = (i: number, k: keyof Escalao, v: string) => setEscaloes(escaloes.map((e, j) => (j === i ? { ...e, [k]: v } : e)));

  async function guardar() {
    if (!taxas) return;
    setErro(null);
    setAviso(null);
    setOcupado(true);
    try {
      await rhGuardarParametros({
        ...Object.fromEntries(TAXAS.map(([k]) => [k, k.startsWith('isencao') ? inteiro(taxas[k]) : decimal(taxas[k])])),
        referencia_legal: referencia,
        escaloes: escaloes.map((e) => ({
          limite_inferior: inteiro(e.limite_inferior),
          limite_superior: e.limite_superior.trim() === '' ? null : inteiro(e.limite_superior),
          parcela_fixa: inteiro(e.parcela_fixa),
          taxa: decimal(e.taxa),
          excesso: inteiro(e.excesso),
        })),
      });
      setAviso('Taxas e tabela guardadas.');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  return (
    <Guarda permissoes={['rh.salarios']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {aviso && <Aviso tipo="sucesso">{aviso}</Aviso>}
        {!taxas && !erro && <ACarregar />}
        {taxas && (
          <>
            <Aviso>Confirma estes valores com o contabilista antes de fechar a primeira folha.</Aviso>
            <Cartao>
              <Subtitulo>Taxas e isenções</Subtitulo>
              {TAXAS.map(([k, rotulo]) => (
                <Campo key={k} rotulo={rotulo} keyboardType="decimal-pad" value={taxas[k]} onChangeText={(t) => setTaxas({ ...taxas, [k]: t })} />
              ))}
              <Campo rotulo="Referência legal" value={referencia} onChangeText={setReferencia} multiline />
            </Cartao>
            <Cartao>
              <Subtitulo>Tabela do IRT (Grupo A, por mês)</Subtitulo>
              <Paragrafo suave>IRT = parcela fixa + (matéria colectável − excesso) × taxa. Matéria colectável = bruto − isentos − Segurança Social.</Paragrafo>
              {escaloes.map((e, i) => (
                <View key={i} style={{ borderTopWidth: 1, borderTopColor: cores.linha, paddingTop: espaco.s, gap: 2 }}>
                  <Text style={{ fontWeight: '700' }}>
                    {i + 1}.º escalão: {formatarKz(inteiro(e.limite_inferior))}
                    {e.limite_superior ? ` a ${formatarKz(inteiro(e.limite_superior))}` : ' ou mais'}
                  </Text>
                  <View style={{ flexDirection: 'row', gap: espaco.s }}>
                    <View style={{ flex: 1 }}>
                      <Campo rotulo="De (Kz)" keyboardType="number-pad" value={e.limite_inferior} onChangeText={(t) => mudar(i, 'limite_inferior', t)} />
                    </View>
                    <View style={{ flex: 1 }}>
                      <Campo rotulo="Até (Kz, vazio = sem limite)" keyboardType="number-pad" value={e.limite_superior} onChangeText={(t) => mudar(i, 'limite_superior', t)} />
                    </View>
                  </View>
                  <View style={{ flexDirection: 'row', gap: espaco.s }}>
                    <View style={{ flex: 1 }}>
                      <Campo rotulo="Parcela fixa" keyboardType="number-pad" value={e.parcela_fixa} onChangeText={(t) => mudar(i, 'parcela_fixa', t)} />
                    </View>
                    <View style={{ flex: 1 }}>
                      <Campo rotulo="Taxa (%)" keyboardType="decimal-pad" value={e.taxa} onChangeText={(t) => mudar(i, 'taxa', t)} />
                    </View>
                    <View style={{ flex: 1 }}>
                      <Campo rotulo="Excesso de" keyboardType="number-pad" value={e.excesso} onChangeText={(t) => mudar(i, 'excesso', t)} />
                    </View>
                  </View>
                </View>
              ))}
            </Cartao>
            <Botao titulo="Guardar as taxas e a tabela" aCarregar={ocupado} aoCarregar={guardar} />
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
