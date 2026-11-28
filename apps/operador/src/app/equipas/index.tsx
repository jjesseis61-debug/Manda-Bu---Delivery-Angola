import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { type EquipaResumo, lerEquipas } from '@/lib/equipas';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { cores } from '@/lib/tema';

/** Equipas no trabalho: o que precisa de resposta primeiro (refeições extra, pagamentos a confirmar) */
export default function Equipas() {
  const router = useRouter();
  const [lista, setLista] = useState<EquipaResumo[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  useFocusEffect(
    useCallback(() => {
      lerEquipas()
        .then((l) => setLista([...l].sort((a, b) => b.extras_pendentes + b.pagamentos_por_confirmar - (a.extras_pendentes + a.pagamentos_por_confirmar))))
        .catch((e) => setErro(mensagemErro(e)));
    }, []),
  );
  return (
    <Guarda permissoes={['pedidos.gerir', 'financas.acertos', 'clientes.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {lista === null && !erro && <ACarregar />}
        {lista?.length === 0 && <Paragrafo suave>Ainda não há equipas. Os clientes criam-nas na app (Conta → A minha equipa).</Paragrafo>}
        {lista?.map((e) => (
          <Pressable key={e.id} accessibilityRole="button" onPress={() => router.push(`/equipas/${e.id}`)}>
            <Cartao>
              <Text style={{ fontWeight: '700', fontSize: 16 }}>
                {e.nome}
                {e.activa ? '' : ' · parada'}
              </Text>
              <Text style={{ color: cores.textoSuave }}>
                {e.cozinha} · responsável {e.responsavel} · {e.membros} colegas · {e.hora_entrega} · limite {formatarKz(e.limite_mensal)}
              </Text>
              {e.extras_pendentes > 0 && <Text style={{ color: cores.marca, fontWeight: '700' }}>{e.extras_pendentes} pedido(s) de refeições extra por decidir</Text>}
              {e.pagamentos_por_confirmar > 0 && <Text style={{ color: cores.marca, fontWeight: '700' }}>{e.pagamentos_por_confirmar} pagamento(s) por confirmar</Text>}
              {e.em_atraso > 0 && <Text style={{ color: cores.textoSuave }}>{e.em_atraso} colega(s) com a conta em atraso</Text>}
              <Text style={{ color: cores.textoSuave }}>
                {e.acordo ? `Acordo ${e.acordo.estado === 'proposto' ? 'à espera da cozinha' : 'activo'}` : 'Sem acordo (ganha-ganha normal)'}
              </Text>
            </Cartao>
          </Pressable>
        ))}
      </Ecra>
    </Guarda>
  );
}
