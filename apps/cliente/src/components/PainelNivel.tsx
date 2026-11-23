import { Text, View } from 'react-native';

import { formatarKz } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';

import { Cartao } from './ui';

/**
 * Painel do embaixador (Bandura: meta próxima + prova do ganho).
 * Mostra o nível atual, o progresso para o próximo e a comissão por pedido.
 * Dados vêm de meu_perfil (nivel, indicados_activos) e dos parâmetros.
 */
export function PainelNivel() {
  const { perfil, parametros } = useSessao();
  if (!perfil || !parametros) return null;

  const limEmb = parametros.limiar_embaixador;
  const limOuro = parametros.limiar_ouro;
  const taxaEmb = parametros.ganho_por_pedido_embaixador;
  const taxaOuro = parametros.ganho_por_pedido_ouro;
  const base = parametros.ganho_por_pedido;
  // Backend antigo (sem os campos dos níveis): não mostra o painel
  if (limEmb == null || limOuro == null || taxaEmb == null || taxaOuro == null) return null;

  const nivel = perfil.nivel ?? 'normal';
  const ativos = perfil.indicados_activos ?? 0;
  const ouro = nivel === 'ouro';
  const cor = ouro ? cores.destaque : cores.marca;

  // Alvo do próximo degrau
  const alvo = nivel === 'normal' ? limEmb : nivel === 'embaixador' ? limOuro : limOuro;
  const faltam = Math.max(0, alvo - ativos);
  const pct = ouro ? 1 : Math.max(0, Math.min(1, ativos / alvo));
  const amigos = (n: number) => `${n} ${n === 1 ? 'amigo ativo' : 'amigos ativos'}`;

  const titulo = ouro ? 'Embaixador Ouro 🏆' : nivel === 'embaixador' ? 'Embaixador' : 'O teu nível';

  return (
    <Cartao estilo={{ borderLeftWidth: 6, borderLeftColor: cor }}>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
        <Text style={{ fontSize: 17, fontWeight: '700', color: cores.texto }}>{titulo}</Text>
        <Text style={{ fontSize: 13, color: cores.textoSuave }}>{amigos(ativos)}</Text>
      </View>

      {ouro ? (
        <Text style={{ color: cores.texto, marginTop: 4 }}>
          Comissão máxima: ganhas <Text style={{ fontWeight: '700' }}>{formatarKz(taxaOuro)}</Text> por pedido e estás
          isento do limite semanal.
        </Text>
      ) : (
        <>
          {/* Barra de progresso para o próximo nível */}
          <View style={{ height: 8, backgroundColor: cores.marcaClara, borderRadius: 4, overflow: 'hidden', marginTop: 10 }}>
            <View style={{ width: `${pct * 100}%`, height: '100%', backgroundColor: cor }} />
          </View>
          <Text style={{ color: cores.texto, marginTop: 8 }}>
            {faltam === 0
              ? nivel === 'normal'
                ? 'Já tens amigos para Embaixador: o nível sobe sozinho no próximo pedido confirmado.'
                : 'Já tens amigos para Ouro: o nível sobe sozinho no próximo pedido confirmado.'
              : nivel === 'normal'
                ? `Falta${faltam === 1 ? '' : 'm'} ${amigos(faltam)} para seres Embaixador.`
                : `Falta${faltam === 1 ? '' : 'm'} ${amigos(faltam)} para Embaixador Ouro.`}
          </Text>
          <Text style={{ color: cores.textoSuave, fontSize: 13, marginTop: 4 }}>
            {nivel === 'normal'
              ? `Ganhas ${formatarKz(base)} por pedido. Como Embaixador, ganharias ${formatarKz(taxaEmb)}.`
              : `Ganhas ${formatarKz(taxaEmb)} por pedido. Como Ouro, ganharias ${formatarKz(taxaOuro)} e sem limite semanal.`}
          </Text>
        </>
      )}
    </Cartao>
  );
}
