import { Redirect, useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Pressable, Switch, Text, View } from 'react-native';

import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { avaliacaoPermitida, avaliarPedido, lerPedido, minhaAvaliacao } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { Pedido } from '@/lib/tipos';

const MAX_COMENTARIO = 200;

function Estrelas({ valor, aoMudar, tamanho = 36 }: { valor: number; aoMudar: (v: number) => void; tamanho?: number }) {
  return (
    <View style={{ flexDirection: 'row', gap: 6 }} accessibilityRole="adjustable" accessibilityValue={{ min: 1, max: 5, now: valor }}>
      {[1, 2, 3, 4, 5].map((n) => (
        <Pressable key={n} onPress={() => aoMudar(n)} accessibilityLabel={`${n} ${n === 1 ? 'estrela' : 'estrelas'}`} hitSlop={6}>
          <Text style={{ fontSize: tamanho, color: n <= valor ? cores.destaque : cores.linha }}>★</Text>
        </Pressable>
      ))}
    </View>
  );
}

/** C9. Avaliar pedido: estrelas, comentário curto, estrelas por prato (opcional), pseudónimo */
export default function Avaliar() {
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { ligada, perfil } = useSessao();
  const [pedido, setPedido] = useState<Pedido | null>(null);
  const [estado, setEstado] = useState<'a_carregar' | 'pode' | 'feita' | 'fora_do_prazo'>('a_carregar');
  const [estrelas, setEstrelas] = useState(0);
  const [comentario, setComentario] = useState('');
  const [pseudonimo, setPseudonimo] = useState(false);
  const [pratos, setPratos] = useState<Record<string, number>>({});
  const [erro, setErro] = useState<string | null>(null);
  const [aEnviar, setAEnviar] = useState(false);

  useEffect(() => {
    if (!ligada('avaliacoes')) return;
    Promise.all([lerPedido(String(id)), minhaAvaliacao(String(id)), avaliacaoPermitida(String(id))])
      .then(([p, minha, permitida]) => {
        setPedido(p);
        setEstado(minha ? 'feita' : permitida ? 'pode' : 'fora_do_prazo');
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [id, ligada]);

  // Pratos do pedido que se podem avaliar (os que vêm de um prato base do cardápio)
  const pratosDoPedido = useMemo(() => {
    const vistos = new Map<string, string>();
    for (const i of pedido?.itens ?? []) if (i.prato_base_id && !vistos.has(i.prato_base_id)) vistos.set(i.prato_base_id, i.nome);
    return [...vistos.entries()];
  }, [pedido]);

  if (!ligada('avaliacoes')) return <Redirect href="/pedidos" />;
  if (erro && estado === 'a_carregar') return <Ecra><Aviso tipo="erro">{erro}</Aviso></Ecra>;
  if (estado === 'a_carregar') return <ACarregar />;

  if (estado === 'feita') {
    return (
      <Ecra>
        <Aviso tipo="sucesso">Obrigado! Já avaliaste este pedido.</Aviso>
        <Botao titulo="Voltar" variante="secundario" aoCarregar={() => router.back()} />
      </Ecra>
    );
  }
  if (estado === 'fora_do_prazo') {
    return (
      <Ecra>
        <Paragrafo>Este pedido já não pode ser avaliado.</Paragrafo>
        <Botao titulo="Voltar" variante="secundario" aoCarregar={() => router.back()} />
      </Ecra>
    );
  }

  async function enviar() {
    if (!perfil || estrelas === 0) return;
    setErro(null);
    setAEnviar(true);
    try {
      await avaliarPedido({
        pedidoId: String(id),
        clienteId: perfil.cliente_id,
        estrelas,
        comentario: comentario.trim() || null,
        usarPseudonimo: pseudonimo,
        pratos: Object.entries(pratos).map(([prato_id, e]) => ({ prato_id, estrelas: e })),
      });
      setEstado('feita');
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAEnviar(false);
    }
  }

  return (
    <Ecra>
      <Subtitulo>Como estava?</Subtitulo>
      <Estrelas valor={estrelas} aoMudar={setEstrelas} />
      <Campo
        rotulo={`Comentário (opcional, ${comentario.length}/${MAX_COMENTARIO})`}
        value={comentario}
        onChangeText={(t) => setComentario(t.slice(0, MAX_COMENTARIO))}
        multiline
        maxLength={MAX_COMENTARIO}
      />
      {pratosDoPedido.length > 0 && (
        <Cartao>
          <Paragrafo suave>Avaliar cada prato (opcional)</Paragrafo>
          {pratosDoPedido.map(([pratoId, nome]) => (
            <View key={pratoId} style={{ gap: 2 }}>
              <Text style={{ fontSize: 15 }}>{nome}</Text>
              <Estrelas valor={pratos[pratoId] ?? 0} aoMudar={(v) => setPratos((p) => ({ ...p, [pratoId]: v }))} tamanho={26} />
            </View>
          ))}
        </Cartao>
      )}
      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
        <Text style={{ fontSize: 15, flex: 1 }}>Publicar com o meu pseudónimo em vez do nome</Text>
        <Switch value={pseudonimo} onValueChange={setPseudonimo} trackColor={{ true: cores.marca, false: cores.linha }} />
      </View>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Botao titulo="Enviar avaliação" desactivado={estrelas === 0} aCarregar={aEnviar} aoCarregar={enviar} />
    </Ecra>
  );
}
