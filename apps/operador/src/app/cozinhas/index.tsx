import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Cartao, Ecra } from '@/components/ui';
import { lerCozinhas } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { cores } from '@/lib/tema';
import type { Cozinha } from '@/lib/tipos';

const NOME_ESTADO: Record<Cozinha['estado'], string> = { activa: 'Activa', pausada: 'Pausada', inactiva: 'Inactiva' };

/** O6. Cozinhas */
export default function Cozinhas() {
  const [lista, setLista] = useState<Cozinha[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      lerCozinhas()
        .then(setLista)
        .catch((e) => setErro(mensagemErro(e)));
    }, []),
  );

  return (
    <Guarda permissoes={['cozinhas.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista?.map((c) => (
          <Pressable key={c.id} onPress={() => router.push({ pathname: '/cozinhas/[id]', params: { id: c.id } })}>
            <Cartao>
              <Text style={{ fontWeight: '700', fontSize: 16 }}>{c.nome}</Text>
              <Text>Responsável: {c.responsavel}</Text>
              <Text style={{ color: cores.textoSuave }}>
                {NOME_ESTADO[c.estado]} · {c.consentimento_publico ? 'perfil público autorizado' : 'perfil não público'}
              </Text>
            </Cartao>
          </Pressable>
        ))}
        <Botao titulo="Nova cozinha" variante="secundario" aoCarregar={() => router.push({ pathname: '/cozinhas/[id]', params: { id: 'nova' } })} />
      </Ecra>
    </Guarda>
  );
}
