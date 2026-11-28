import { useEffect, useState } from 'react';
import { Text } from 'react-native';

import { Aviso, Botao, Cartao, Paragrafo } from '@/components/ui';
import { horaLuanda } from '@/lib/formatar';
import { supabase } from '@/lib/supabase';
import { cores } from '@/lib/tema';

type Estado = { grupo: 'A' | 'B' | null; confirmada: boolean; local: string | null };

/** Grupo do cliente no teste, a confirmação e o nome da morada (null se o servidor não tiver o teste) */
export async function lerCompromisso(pedidoId: string): Promise<Estado | null> {
  const g = await supabase.rpc('meu_grupo_compromisso');
  if (g.error) return null;
  const grupo = (g.data as 'A' | 'B' | null) ?? null;
  if (grupo !== 'A') return { grupo, confirmada: false, local: null };
  const r = await supabase
    .from('pedidos')
    .select('presenca_confirmada_em, pontos_entrega(referencia, zonas(nome))')
    .eq('id', pedidoId)
    .maybeSingle();
  if (r.error || !r.data) return null;
  const d = r.data as unknown as { presenca_confirmada_em: string | null; pontos_entrega: { referencia: string | null; zonas: { nome: string } | null } | null };
  return { grupo, confirmada: !!d.presenca_confirmada_em, local: d.pontos_entrega?.referencia || d.pontos_entrega?.zonas?.nome || null };
}

/**
 * Pedido agendado (grupo A do teste): o cliente confirma com um toque «Vou estar em <morada> às <hora>».
 * Cialdini: o compromisso que a pessoa faz ela própria cumpre-se mais do que um aviso que lhe dão.
 * O lembrete de 1 h antes repete estas palavras. O grupo B não vê nada (controlo).
 */
export function CompromissoPresenca({ pedidoId, agendadoPara }: { pedidoId: string; agendadoPara: string }) {
  const [estado, setEstado] = useState<Estado | null>(null);
  const [naoPosso, setNaoPosso] = useState(false);
  const [aEnviar, setAEnviar] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    lerCompromisso(pedidoId)
      .then(setEstado)
      .catch(() => setEstado(null));
  }, [pedidoId]);

  if (!estado || estado.grupo !== 'A') return null;
  const hora = horaLuanda(agendadoPara);
  const onde = estado.local ? `em ${estado.local}` : 'em casa';

  if (estado.confirmada) {
    return <Aviso tipo="sucesso">{`✓ Combinado: vais estar ${onde} às ${hora}. Lembramos-te 1 hora antes.`}</Aviso>;
  }

  async function confirmar() {
    setAEnviar(true);
    setErro(null);
    const r = await supabase.rpc('confirmar_presenca', { p_pedido: pedidoId });
    setAEnviar(false);
    if (r.error) setErro('Não foi possível guardar. Tenta outra vez.');
    else setEstado((e) => (e ? { ...e, confirmada: true } : e));
  }

  return (
    <Cartao>
      <Text style={{ fontSize: 16, fontWeight: '700', color: cores.texto }}>{`Vais estar ${onde} às ${hora}?`}</Text>
      {naoPosso ? (
        <Paragrafo>Fala connosco já (em Ajuda ou Contactos) para mudarmos a hora ou cancelarmos sem custos para ninguém.</Paragrafo>
      ) : (
        <>
          <Botao titulo="Sim, vou estar" aCarregar={aEnviar} aoCarregar={confirmar} />
          <Botao titulo="Não vou poder" variante="texto" aoCarregar={() => setNaoPosso(true)} />
        </>
      )}
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
    </Cartao>
  );
}
