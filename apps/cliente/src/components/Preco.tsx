import { Text, View } from 'react-native';

import { formatarKz, percentagemDesconto } from '@/lib/formatar';
import { cores } from '@/lib/tema';

/**
 * Preço no cartão do prato: com campanha, o preço novo em destaque, o antigo riscado e a
 * percentagem em verde; sem campanha, só o preço (ou "desde ..." nos pratos para montar).
 */
export function Preco({ preco, promo, desde }: { preco: number; promo?: number | null; desde?: number | null }) {
  if (desde != null) {
    return <Text style={{ fontSize: 16, fontWeight: '700', color: cores.texto }}>{`desde ${formatarKz(desde)}`}</Text>;
  }
  const pct = promo != null ? percentagemDesconto(preco, promo) : 0;
  if (promo == null || pct <= 0) {
    return <Text style={{ fontSize: 16, fontWeight: '700', color: cores.texto }}>{formatarKz(preco)}</Text>;
  }
  return (
    <View
      accessible
      accessibilityLabel={`${formatarKz(promo)}, antes ${formatarKz(preco)}, ${pct}% menos`}
      style={{ alignItems: 'flex-end' }}>
      <Text style={{ fontSize: 18, fontWeight: '800', color: cores.texto }}>{formatarKz(promo)}</Text>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
        <Text style={{ fontSize: 13, color: cores.textoSuave, textDecorationLine: 'line-through' }}>{formatarKz(preco)}</Text>
        <Text style={{ fontSize: 13, fontWeight: '800', color: cores.sucesso }}>{`${pct}% menos`}</Text>
      </View>
    </View>
  );
}

/**
 * Preço em destaque, numa linha à esquerda e por baixo do nome (pratos em campanha, «modo Meesho»):
 * o preço novo grande, o antigo riscado e a percentagem em verde, juntos para se lerem de uma vez.
 */
export function PrecoDestaque({ preco, promo }: { preco: number; promo: number }) {
  const pct = percentagemDesconto(preco, promo);
  return (
    <View
      accessible
      accessibilityLabel={`${formatarKz(promo)}, antes ${formatarKz(preco)}, ${pct}% menos`}
      style={{ flexDirection: 'row', alignItems: 'baseline', flexWrap: 'wrap', columnGap: 8 }}>
      <Text style={{ fontSize: 22, fontWeight: '800', color: cores.texto }}>{formatarKz(promo)}</Text>
      <Text style={{ fontSize: 14, color: cores.textoSuave, textDecorationLine: 'line-through' }}>{formatarKz(preco)}</Text>
      {pct > 0 && <Text style={{ fontSize: 14, fontWeight: '800', color: cores.sucesso }}>{`${pct}% menos`}</Text>}
    </View>
  );
}
