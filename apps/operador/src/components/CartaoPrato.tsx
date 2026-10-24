import { useState } from 'react';
import { Image, Switch, Text, View } from 'react-native';

import { formatarKz } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { DosesPrato, PratoCardapio } from '@/lib/tipos';

import { Botao, Campo, Cartao } from './ui';

/**
 * Cartão de um prato no cardápio, com os controlos rápidos do dia a dia: disponível e doses.
 * O operador normal só pode ACRESCENTAR doses; só o admin principal pode ajustar (reduzir).
 */
export function CartaoPrato({
  p,
  doses,
  ehAdmin,
  podeAuditoria,
  aoGravarDoses,
  aoMudarDisponivel,
  aoEditar,
  aoOpcoes,
  aoImpacto,
}: {
  p: PratoCardapio;
  doses?: DosesPrato;
  ehAdmin: boolean;
  podeAuditoria: boolean;
  aoGravarDoses: (dosesDia: number | null) => Promise<void>;
  aoMudarDisponivel: (v: boolean) => Promise<void>;
  aoEditar: () => void;
  aoOpcoes: () => void;
  aoImpacto: () => void;
}) {
  const [modo, setModo] = useState<null | 'acrescentar' | 'ajustar'>(null);
  const [valor, setValor] = useState('');
  const [ocupado, setOcupado] = useState(false);

  const lancadasHoje = doses ? doses.lancadas : null; // null = sem limite hoje

  async function correr(f: () => Promise<void>) {
    setOcupado(true);
    try {
      await f();
      setModo(null);
      setValor('');
    } finally {
      setOcupado(false);
    }
  }

  function confirmar() {
    const n = Number(valor);
    if (modo === 'acrescentar') {
      if (!(n > 0)) return;
      void correr(() => aoGravarDoses((p.doses_dia ?? 0) + n));
    } else if (modo === 'ajustar') {
      void correr(() => aoGravarDoses(valor.trim() === '' ? null : n));
    }
  }

  return (
    <Cartao>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: espaco.s }}>
        {p.foto_url ? <Image source={{ uri: p.foto_url }} style={{ width: 44, height: 44, borderRadius: 6 }} accessibilityLabel={p.nome} /> : null}
        <Text style={{ fontWeight: '700', flex: 1, color: p.disponivel ? cores.texto : cores.textoSuave }}>
          {p.nome}
          {p.do_dia ? ' · do dia' : ''}
          {p.disponivel ? '' : ' · indisponível'}
          {doses ? (doses.restantes === 0 ? ' · esgotado hoje' : ` · restam ${doses.restantes} de ${doses.lancadas}`) : ''}
        </Text>
        <Text>{formatarKz(p.preco)}</Text>
      </View>

      {/* Controlo rápido: disponível */}
      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
        <Text style={{ flex: 1 }}>Disponível</Text>
        <Switch
          thumbColor="#FFFFFF"
          value={p.disponivel}
          disabled={ocupado}
          onValueChange={(v) => void correr(() => aoMudarDisponivel(v))}
          trackColor={{ true: cores.marca, false: cores.contorno }}
        />
      </View>

      {/* Controlo rápido: doses */}
      {modo === null ? (
        <View style={{ flexDirection: 'row', gap: espaco.s, alignItems: 'center', flexWrap: 'wrap' }}>
          <Text style={{ color: cores.textoSuave, flex: 1 }}>
            {lancadasHoje == null ? 'Doses hoje: sem limite' : `Doses lançadas hoje: ${lancadasHoje}`}
          </Text>
          <Botao titulo="+ Acrescentar doses" variante="leve" aoCarregar={() => setModo('acrescentar')} />
          {ehAdmin && <Botao titulo="Ajustar" variante="texto" aoCarregar={() => { setModo('ajustar'); setValor(p.doses_dia == null ? '' : String(p.doses_dia)); }} />}
        </View>
      ) : (
        <View style={{ gap: espaco.xs }}>
          <Campo
            rotulo={modo === 'acrescentar' ? 'Quantas doses acrescentar?' : 'Novo total de hoje (em branco = sem limite)'}
            value={valor}
            keyboardType="number-pad"
            onChangeText={(t) => setValor(t.replace(/\D/g, ''))}
          />
          <View style={{ flexDirection: 'row', gap: espaco.s }}>
            <Botao titulo="Guardar" aCarregar={ocupado} aoCarregar={confirmar} />
            <Botao titulo="Cancelar" variante="texto" aoCarregar={() => { setModo(null); setValor(''); }} />
          </View>
        </View>
      )}

      {/* Acções do prato */}
      <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
        <Botao titulo="Editar" variante="texto" aoCarregar={aoEditar} />
        <Botao titulo="Opções" variante="texto" aoCarregar={aoOpcoes} />
        {podeAuditoria && <Botao titulo="Impacto" variante="texto" aoCarregar={aoImpacto} />}
      </View>
    </Cartao>
  );
}
