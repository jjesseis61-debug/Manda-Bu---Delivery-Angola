import { router, useFocusEffect, useLocalSearchParams, useNavigation } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { lerCozinhas } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Cozinha } from '@/lib/tipos';

const NOME_ESTADO: Record<Cozinha['estado'], string> = { activa: 'Activa', pausada: 'Pausada', inactiva: 'Inactiva' };

/** O6. Cozinhas. Com foco=cardapio é o selector de cardápio (toca para abrir; uma só cozinha vai direto). */
export default function Cozinhas() {
  const { foco } = useLocalSearchParams<{ foco?: string }>();
  const modoCardapio = foco === 'cardapio';
  const navigation = useNavigation();
  const { pode, funcionario } = useSessao();
  const mestre = pode('cozinhas.gerir'); // chave-mestra vê/cria todas; cardapio.gerir só as suas
  const [lista, setLista] = useState<Cozinha[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const saltou = useRef(false);

  useEffect(() => {
    navigation.setOptions({ title: modoCardapio ? 'Cardápio' : 'Cozinhas' });
  }, [navigation, modoCardapio]);

  useFocusEffect(
    useCallback(() => {
      lerCozinhas()
        .then(setLista)
        .catch((e) => setErro(mensagemErro(e)));
    }, []),
  );

  // Sem a chave-mestra, só as cozinhas de que é membro
  const visiveis = lista === null ? null : mestre ? lista : lista.filter((c) => funcionario?.cozinhas_equipa.includes(c.id));

  // Cardápio com uma só cozinha: vai direto (replace, para o voltar regressar ao início)
  useEffect(() => {
    if (modoCardapio && visiveis && visiveis.length === 1 && !saltou.current) {
      saltou.current = true;
      router.replace({ pathname: '/cozinhas/[id]/cardapio', params: { id: visiveis[0].id } });
    }
  }, [modoCardapio, visiveis]);

  function abrir(c: Cozinha) {
    if (modoCardapio) router.push({ pathname: '/cozinhas/[id]/cardapio', params: { id: c.id } });
    else router.push({ pathname: '/cozinhas/[id]', params: { id: c.id } });
  }

  return (
    <Guarda permissoes={['cozinhas.gerir', 'cardapio.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {modoCardapio && visiveis && visiveis.length > 1 && <Paragrafo suave>Escolhe a cozinha para gerir o cardápio.</Paragrafo>}
        {lista && visiveis?.length === 0 && <Aviso>Ainda não tens nenhuma cozinha atribuída.</Aviso>}
        {visiveis?.map((c) => (
          <Pressable
            key={c.id}
            accessibilityRole="button"
            accessibilityLabel={`${modoCardapio ? 'Abrir cardápio de' : 'Abrir'} ${c.nome}`}
            onPress={() => abrir(c)}>
            <Cartao>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.s }}>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontWeight: '700', fontSize: 16 }}>{c.nome}</Text>
                  <Text style={{ color: cores.textoSuave }}>
                    {modoCardapio
                      ? `Responsável: ${c.responsavel}`
                      : `${NOME_ESTADO[c.estado]} · ${c.consentimento_publico ? 'perfil público autorizado' : 'perfil não público'}`}
                  </Text>
                </View>
                <Text style={{ color: cores.marca, fontSize: 24, fontWeight: '700' }}>›</Text>
              </View>
            </Cartao>
          </Pressable>
        ))}
        {!modoCardapio && mestre && (
          <Botao titulo="Nova cozinha" variante="secundario" aoCarregar={() => router.push({ pathname: '/cozinhas/[id]', params: { id: 'nova' } })} />
        )}
      </Ecra>
    </Guarda>
  );
}
