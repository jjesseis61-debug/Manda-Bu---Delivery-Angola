import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Cartao, Ecra } from '@/components/ui';
import { lerCozinhas } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { Cozinha } from '@/lib/tipos';

const NOME_ESTADO: Record<Cozinha['estado'], string> = { activa: 'Activa', pausada: 'Pausada', inactiva: 'Inactiva' };

/** O6. Cozinhas */
export default function Cozinhas() {
  const { pode, funcionario } = useSessao();
  const mestre = pode('cozinhas.gerir'); // chave-mestra vê/cria todas; cardapio.gerir só as suas
  const [lista, setLista] = useState<Cozinha[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      lerCozinhas()
        .then(setLista)
        .catch((e) => setErro(mensagemErro(e)));
    }, []),
  );

  // Sem a chave-mestra, só as cozinhas de que é membro
  const visiveis = mestre ? lista : (lista ?? []).filter((c) => funcionario?.cozinhas_equipa.includes(c.id));

  return (
    <Guarda permissoes={['cozinhas.gerir', 'cardapio.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista && visiveis?.length === 0 && <Aviso>Ainda não tens nenhuma cozinha atribuída.</Aviso>}
        {visiveis?.map((c) => (
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
        {mestre && (
          <Botao titulo="Nova cozinha" variante="secundario" aoCarregar={() => router.push({ pathname: '/cozinhas/[id]', params: { id: 'nova' } })} />
        )}
      </Ecra>
    </Guarda>
  );
}
