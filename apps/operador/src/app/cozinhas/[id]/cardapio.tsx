import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Modal, ScrollView, Text, View } from 'react-native';

import { CartaoPrato } from '@/components/CartaoPrato';
import { EditorPrato } from '@/components/EditorPrato';
import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { guardarPrato, lerCardapio, lerCozinhas, lerDosesCardapio } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { DosesPrato, PratoCardapio } from '@/lib/tipos';

/** O6. Cardápio de uma cozinha (separado do perfil da cozinha): pratos, doses e opções. */
export default function Cardapio() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { pode, funcionario } = useSessao();
  const ehAdmin = !!funcionario?.administrador_principal;
  const podeAuditoria = pode('auditoria.ver');

  const [nomeCozinha, setNomeCozinha] = useState<string | null>(null);
  const [pratos, setPratos] = useState<PratoCardapio[] | null>(null);
  const [doses, setDoses] = useState<Map<string, DosesPrato>>(new Map());
  const [erro, setErro] = useState<string | null>(null);
  // null = fechado; 'novo' = criar; PratoCardapio = editar
  const [editar, setEditar] = useState<PratoCardapio | 'novo' | null>(null);

  const carregar = useCallback(() => {
    Promise.all([lerCardapio(id), lerDosesCardapio(id).catch(() => [] as DosesPrato[]), lerCozinhas()])
      .then(([ps, ds, cs]) => {
        setPratos(ps);
        setDoses(new Map(ds.map((d) => [d.cardapio_id, d])));
        setNomeCozinha(cs.find((c) => c.id === id)?.nome ?? null);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [id]);
  useEffect(carregar, [carregar]);

  const categorias = [...new Set((pratos ?? []).map((p) => p.categoria).filter((c): c is string => !!c))];

  // Grava um campo rápido (doses ou disponível) de um prato, reaproveitando guardarPrato.
  async function gravarCampo(p: PratoCardapio, campos: Partial<PratoCardapio>) {
    setErro(null);
    try {
      await guardarPrato({ ...p, ...campos });
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
      throw e;
    }
  }

  return (
    <Guarda permissoes={['cardapio.gerir', 'cozinhas.gerir']}>
      <Ecra>
        <Subtitulo>Cardápio{nomeCozinha ? ` · ${nomeCozinha}` : ''}</Subtitulo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!pratos && !erro && <ACarregar />}
        {pratos?.length === 0 && <Paragrafo suave>Sem pratos. Toca em "Novo prato" para começar.</Paragrafo>}

        {pratos?.map((p) => (
          <CartaoPrato
            key={p.id}
            p={p}
            doses={doses.get(p.id)}
            ehAdmin={ehAdmin}
            podeAuditoria={podeAuditoria}
            aoGravarDoses={(dosesDia) => gravarCampo(p, { doses_dia: dosesDia })}
            aoMudarDisponivel={(v) => gravarCampo(p, { disponivel: v })}
            aoEditar={() => setEditar(p)}
            aoOpcoes={() => router.push({ pathname: '/cozinhas/opcoes/[prato]', params: { prato: p.id, nome: p.nome } })}
            aoImpacto={() => router.push({ pathname: '/cozinhas/impacto-preco', params: { cardapio: p.id, nome: p.nome } })}
          />
        ))}

        {pratos && <Botao titulo="Novo prato" variante="secundario" aoCarregar={() => setEditar('novo')} />}

        <Modal visible={editar !== null} animationType="slide" onRequestClose={() => setEditar(null)}>
          <View style={{ flex: 1, backgroundColor: cores.fundo }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', padding: espaco.m }}>
              <Text style={{ fontSize: 18, fontWeight: '700', flex: 1 }}>{editar === 'novo' ? 'Novo prato' : 'Editar prato'}</Text>
              <Text
                accessibilityRole="button"
                style={{ color: cores.marca, fontWeight: '700', fontSize: 16, paddingHorizontal: espaco.s }}
                onPress={() => setEditar(null)}>
                Fechar
              </Text>
            </View>
            <ScrollView contentContainerStyle={{ padding: espaco.m, paddingTop: 0, gap: espaco.s }} keyboardShouldPersistTaps="handled">
              {editar !== null && (
                <EditorPrato
                  cozinhaId={id}
                  pratoInicial={editar === 'novo' ? null : editar}
                  categorias={categorias}
                  ehAdmin={ehAdmin}
                  aoGuardado={() => {
                    setEditar(null);
                    carregar();
                  }}
                  aoFechar={() => setEditar(null)}
                />
              )}
            </ScrollView>
          </View>
        </Modal>
      </Ecra>
    </Guarda>
  );
}
