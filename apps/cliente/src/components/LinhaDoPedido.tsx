import { Pressable, Text, View } from 'react-native';

import { Tabuleiro } from '@/components/Recipientes';
import { zonasDasPecas } from '@/lib/balcaoPanelas';
import type { LinhaCarrinho } from '@/lib/carrinho';
import { formatarKz } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';

/**
 * Uma linha do pedido com o prato servido (opção B do projecto): o tabuleiro pequeno à esquerda, o nome e
 * a composição ao centro e − 1 + à direita. Tocar no prato mostra a lista com os preços.
 * Bandura: o cliente revê o que montou antes de pagar; Cialdini: o que vê é o que paga.
 */
export function LinhaDoPedido({ linha: l, aberta, aoTocarPrato, aoMudar }: { linha: LinhaCarrinho; aberta: boolean; aoTocarPrato: () => void; aoMudar: (qtd: number) => void }) {
  const montado = l.opcoes.length > 0;
  const zonas = zonasDasPecas(l.opcoes);
  return (
    <View style={{ gap: espaco.xs }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.m }}>
        <Tabuleiro
          zonas={zonas}
          prato={64}
          inteiro={montado ? null : { id: l.item.id, nome: l.item.nome, foto_url: l.item.foto_url }}
          aoTocar={montado ? aoTocarPrato : undefined}
          rotuloAcessivel={montado ? `Prato de ${l.item.nome}: ${l.opcoes.map((o) => o.nome).join(', ')}. Toca para ver os preços` : l.item.nome}
        />
        <View style={{ flex: 1 }}>
          <Text style={{ fontSize: 15 }}>{l.item.nome}</Text>
          {montado && <Text style={{ color: cores.textoSuave }}>{l.opcoes.map((o) => o.nome).join(', ')}</Text>}
          {l.tirados.length > 0 && <Text style={{ color: cores.textoSuave }}>Sem {l.tirados.map((c) => c.nome.toLowerCase()).join(', ')}</Text>}
        </View>
        <Pressable accessibilityLabel="Menos" onPress={() => aoMudar(l.qtd - 1)} hitSlop={8}>
          <Text style={{ fontSize: 22, color: cores.marca, width: 24, textAlign: 'center' }}>−</Text>
        </Pressable>
        <Text style={{ fontSize: 16, fontWeight: '600', minWidth: 20, textAlign: 'center' }}>{l.qtd}</Text>
        <Pressable accessibilityLabel="Mais" onPress={() => aoMudar(l.qtd + 1)} hitSlop={8}>
          <Text style={{ fontSize: 22, color: cores.marca, width: 24, textAlign: 'center' }}>+</Text>
        </Pressable>
      </View>
      {aberta && montado && (
        <View style={{ marginLeft: espaco.s, paddingLeft: espaco.s, borderLeftWidth: 2, borderLeftColor: '#E0D3C3', gap: 2 }}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 13, color: cores.texto }}>{l.item.nome}</Text>
            <Text style={{ fontSize: 13, color: cores.textoSuave }}>{formatarKz(l.item.preco)}</Text>
          </View>
          {l.opcoes.map((o) => (
            <View key={o.id} style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
              <Text style={{ fontSize: 13, color: cores.texto }}>{o.nome}</Text>
              <Text style={{ fontSize: 13, color: cores.textoSuave }}>{o.preco_extra > 0 ? `+${formatarKz(o.preco_extra)}` : 'incluído'}</Text>
            </View>
          ))}
          {l.tirados.map((c) => (
            <View key={c.produto_id} style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
              <Text style={{ fontSize: 13, color: cores.texto }}>Sem {c.nome.toLowerCase()}</Text>
              <Text style={{ fontSize: 13, color: cores.textoSuave }}>{c.valor > 0 ? `−${formatarKz(c.valor)}` : ''}</Text>
            </View>
          ))}
        </View>
      )}
    </View>
  );
}
