import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { formatarData, formatarKz, mensagemErro } from '@/lib/formatar';
import { nomeContrato, rhLista, type PessoaRH } from '@/lib/rh';
import { cores } from '@/lib/tema';

/** Equipa (recursos humanos): contrato, salário e avisos (documentos a caducar, contratos a terminar…) */
export default function EquipaRH() {
  const router = useRouter();
  const [lista, setLista] = useState<PessoaRH[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  const carregar = useCallback(() => {
    setErro(null);
    rhLista()
      .then(setLista)
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  const comAvisos = lista?.filter((p) => p.alertas.length > 0).length ?? 0;

  return (
    <Guarda permissoes={['rh.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista && comAvisos > 0 && <Aviso>{comAvisos === 1 ? '1 pessoa com avisos' : `${comAvisos} pessoas com avisos`}</Aviso>}
        {lista?.length === 0 && <Paragrafo suave>Ainda não há ninguém na equipa.</Paragrafo>}
        {lista?.map((p) => (
          <Pressable key={p.funcionario_id} accessibilityRole="button" onPress={() => router.push({ pathname: '/rh/[id]', params: { id: p.funcionario_id } })}>
            <Cartao>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: 8 }}>
                <Text style={{ fontWeight: '700', fontSize: 16, flex: 1 }}>{p.nome}</Text>
                {p.contrato && p.contrato.salario_base > 0 && <Text style={{ fontWeight: '700' }}>{formatarKz(p.contrato.salario_base)}</Text>}
              </View>
              <Text style={{ color: cores.textoSuave }}>
                {p.cargo ?? 'Sem cargo'} · {p.contrato ? nomeContrato(p.contrato.tipo) : 'sem contrato'}
                {p.contrato?.fim ? ` até ${formatarData(p.contrato.fim)}` : ''}
              </Text>
              {p.equipamentos > 0 && <Text style={{ color: cores.textoSuave }}>{p.equipamentos} equipamento(s) entregue(s)</Text>}
              {p.alertas.map((a) => (
                <Text key={a} style={{ color: cores.aviso, fontWeight: '600' }}>⚠ {a}</Text>
              ))}
            </Cartao>
          </Pressable>
        ))}
      </Ecra>
    </Guarda>
  );
}
