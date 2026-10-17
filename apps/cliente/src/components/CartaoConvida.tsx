import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { descontoGarantido, lerPerfilDestaques, lerSaldo } from '@/lib/api';
import { formatarKz } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import type { Saldo } from '@/lib/tipos';

/**
 * Cartão "Convida e Ganha" no Início — teaser que leva à tab Convida.
 * Adapta-se (teoria de Bandura): mostra o desconto do 1.º pedido; senão os ganhos com
 * submeta até ao levantamento; senão o convite. Só usa dados que já existem, nunca
 * mostra "0 Kz" (evita o estado afectivo negativo) e respeita o `ocultar_ganhos`.
 */
export function CartaoConvida() {
  const router = useRouter();
  const { perfil, parametros, ligada } = useSessao();
  const [desconto, setDesconto] = useState<number | null>(null);
  const [saldo, setSaldo] = useState<Saldo | null>(null);
  const [ocultar, setOcultar] = useState(false);

  const activo = ligada('indicacao') && !!perfil;
  const clienteId = perfil?.cliente_id;

  useFocusEffect(
    useCallback(() => {
      if (!activo || !clienteId) return;
      let vivo = true;
      void Promise.all([
        descontoGarantido(clienteId).catch(() => null),
        lerSaldo(clienteId).catch(() => null),
        lerPerfilDestaques(clienteId).catch(() => null),
      ]).then(([d, s, p]) => {
        if (!vivo) return;
        setDesconto(d);
        setSaldo(s);
        setOcultar(p?.ocultar_ganhos ?? false);
      });
      return () => {
        vivo = false;
      };
    }, [activo, clienteId]),
  );

  if (!activo) return null;

  const minimo = parametros?.desconto_subtotal_minimo ?? 0;
  const minimoLevantar = parametros?.levantamento_minimo ?? 0;
  const porPedido = parametros?.ganho_por_pedido ?? 0;
  const saldoDisp = saldo?.saldo_disponivel ?? 0;

  let titulo: string;
  let linha: string;
  let progresso: number | null = null;

  if (desconto && desconto > 0) {
    // 1) Desconto do 1.º pedido ainda por usar — a prioridade (expectativa + posse)
    titulo = `🎁 Tens ${formatarKz(desconto)} no teu 1.º pedido`;
    linha = minimo > 0 ? `Em pedidos acima de ${formatarKz(minimo)}. Toca para saber como.` : 'Toca para saber como.';
  } else if (!ocultar && saldoDisp > 0) {
    // 2) Ganhos com submeta até ao mínimo de levantamento (domínio + gradiente do objectivo)
    titulo = `💸 Já ganhaste ${formatarKz(saldoDisp)}`;
    linha =
      minimoLevantar > 0 && saldoDisp < minimoLevantar
        ? `Faltam ${formatarKz(minimoLevantar - saldoDisp)} para levantar.`
        : 'Já podes levantar o teu saldo.';
    if (minimoLevantar > 0) progresso = Math.min(1, saldoDisp / minimoLevantar);
  } else {
    // 3) Convite (CTA) — nunca mostra "0 Kz"
    titulo = porPedido > 0 ? `🎁 Convida e ganha ${formatarKz(porPedido)} por cada pedido` : '🎁 Convida e ganha';
    linha = 'Partilha o teu código com os amigos. Toca para convidar.';
  }

  return (
    <Pressable accessibilityRole="button" accessibilityLabel={titulo} onPress={() => router.push('/convida')}>
      <View
        style={{
          backgroundColor: cores.fundoSuave,
          borderRadius: raio,
          borderLeftWidth: 4,
          borderLeftColor: cores.marca,
          padding: espaco.m,
          gap: 4,
        }}>
        <Text style={{ fontSize: 16, fontWeight: '700', color: cores.marca }}>{titulo}</Text>
        <Text style={{ color: cores.textoSuave }}>{linha}</Text>
        {progresso !== null && (
          <View style={{ height: 8, borderRadius: 4, backgroundColor: cores.marcaClara, overflow: 'hidden', marginTop: 4 }}>
            <View style={{ width: `${Math.round(progresso * 100)}%`, height: '100%', backgroundColor: cores.marca }} />
          </View>
        )}
      </View>
    </Pressable>
  );
}
