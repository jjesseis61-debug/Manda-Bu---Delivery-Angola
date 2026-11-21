import { useEffect, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { Campo } from '@/components/ui';
import { ddmmParaIso, dataPorExtenso, horaValida, isoParaDDMM, mesVizinho, nomeDoMes } from '@/lib/datas';
import { mascaraData, mascaraHora } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';

const Erro = ({ texto }: { texto: string }) => <Text style={{ color: cores.erro, fontSize: 13, marginTop: -espaco.s, marginBottom: espaco.s }}>{texto}</Text>;
const Nota = ({ texto }: { texto: string }) => (
  <Text style={{ color: cores.textoSuave, fontSize: 13, marginTop: -espaco.s, marginBottom: espaco.s }}>{texto}</Text>
);

/**
 * Data no formato de Angola (DD/MM/AAAA): escreve-se só os algarismos e as "/" aparecem sozinhas;
 * mostra a data por extenso para confirmar e o erro por baixo do campo.
 * `valor` e `aoMudar` usam 'AAAA-MM-DD' (o que o servidor recebe): '' quando o campo está vazio ou
 * a data ainda não é válida; o segundo argumento diz se o campo está bem (vazio conta como bem).
 */
export function CampoData({
  rotulo,
  valor,
  aoMudar,
  opcional = false,
  erro,
}: {
  rotulo: string;
  valor: string;
  aoMudar: (iso: string, valida: boolean) => void;
  opcional?: boolean;
  /** Erro de uma regra do ecrã (ex.: "o fim tem de ser depois do início") */
  erro?: string | null;
}) {
  const [texto, setTexto] = useState(() => isoParaDDMM(valor));
  const [saiu, setSaiu] = useState(false);

  // Quando o ecrã muda o valor (abrir um registo, limpar o formulário), o campo acompanha
  useEffect(() => {
    const actual = ddmmParaIso(texto);
    if (valor && valor !== actual) setTexto(isoParaDDMM(valor));
    if (!valor && actual) setTexto('');
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [valor]);

  const iso = ddmmParaIso(texto);
  const completo = texto.length === 10;
  const invalida = texto !== '' && !iso && (completo || saiu);
  const mensagem = invalida
    ? completo
      ? 'Esta data não existe. Confirma o dia e o mês.'
      : 'Data incompleta: escreve DD/MM/AAAA (ex.: 01/09/1988).'
    : !opcional && saiu && texto === ''
      ? 'Obrigatório.'
      : (erro ?? null);

  return (
    <View>
      <Campo
        rotulo={`${rotulo} (DD/MM/AAAA${opcional ? ', opcional' : ''})`}
        placeholder="DD/MM/AAAA"
        keyboardType="number-pad"
        maxLength={10}
        value={texto}
        onBlur={() => setSaiu(true)}
        onChangeText={(t) => {
          const m = mascaraData(t);
          setTexto(m);
          const novo = ddmmParaIso(m);
          aoMudar(novo ?? '', m === '' || !!novo);
        }}
      />
      {mensagem ? <Erro texto={mensagem} /> : iso ? <Nota texto={dataPorExtenso(iso)} /> : null}
    </View>
  );
}

/** Hora HH:MM: escreve-se "1230" e aparece "12:30"; erro por baixo se não for uma hora válida */
export function CampoHora({
  rotulo,
  valor,
  aoMudar,
  erro,
}: {
  rotulo: string;
  valor: string;
  aoMudar: (hora: string) => void;
  erro?: string | null;
}) {
  const invalida = valor.length === 5 && !horaValida(valor);
  return (
    <View>
      <Campo
        rotulo={`${rotulo} (HH:MM)`}
        placeholder="HH:MM"
        keyboardType="number-pad"
        maxLength={5}
        value={valor}
        onChangeText={(t) => aoMudar(mascaraHora(t))}
      />
      {invalida ? <Erro texto="Hora inválida (00:00 a 23:59)." /> : erro ? <Erro texto={erro} /> : null}
    </View>
  );
}

/** Mês com setas ‹ outubro de 2026 › (valor 'AAAA-MM'), em vez de escrever */
export function SeletorMes({ valor, aoMudar, rotulo }: { valor: string; aoMudar: (mes: string) => void; rotulo?: string }) {
  const seta = (s: string, n: number, nome: string) => (
    <Pressable accessibilityRole="button" accessibilityLabel={nome} hitSlop={8} onPress={() => aoMudar(mesVizinho(valor, n))}
      style={{ paddingHorizontal: espaco.m, paddingVertical: espaco.s }}>
      <Text style={{ fontSize: 22, color: cores.marca, fontWeight: '700' }}>{s}</Text>
    </Pressable>
  );
  return (
    <View style={{ marginBottom: espaco.m }}>
      {rotulo && <Text style={{ color: cores.textoSuave, marginBottom: 4 }}>{rotulo}</Text>}
      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', backgroundColor: cores.fundoSuave, borderRadius: 10 }}>
        {seta('‹', -1, 'Mês anterior')}
        <Text style={{ fontWeight: '700', fontSize: 16 }}>{nomeDoMes(valor)}</Text>
        {seta('›', 1, 'Mês seguinte')}
      </View>
    </View>
  );
}
