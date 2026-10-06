import { useFocusEffect } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { MapaEstafetas } from '@/components/MapaEstafetas';
import { ACarregar, Aviso, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { lerCozinhas, posicoesEstafetas, sugestaoDespacho } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Cozinha, PosicaoEstafeta, SugestaoDespacho } from '@/lib/tipos';

const INTERVALO_MS = 10_000;

/** Mapa de acompanhamento dos estafetas de serviço (despacho). Actualiza a cada 10 s. */
export default function Estafetas() {
  const { funcionario, pode } = useSessao();
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [cozinhaId, setCozinhaId] = useState<string | null>(null);
  const [estafetas, setEstafetas] = useState<PosicaoEstafeta[] | null>(null);
  const [despacho, setDespacho] = useState<SugestaoDespacho[]>([]);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      lerCozinhas()
        .then((cs) => {
          const minhas = pode('cozinhas.gerir') ? cs : cs.filter((c) => funcionario?.cozinhas_equipa.includes(c.id));
          setCozinhas(minhas.length > 0 ? minhas : cs);
          setCozinhaId((actual) => actual ?? (minhas[0]?.id ?? cs[0]?.id ?? null));
        })
        .catch((e) => setErro(mensagemErro(e)));
    }, [pode, funcionario]),
  );

  useFocusEffect(
    useCallback(() => {
      if (!cozinhaId) return;
      let activo = true;
      const ler = () => {
        posicoesEstafetas(cozinhaId)
          .then((e) => {
            if (activo) setEstafetas(e);
          })
          .catch((e) => {
            if (activo) setErro(mensagemErro(e));
          });
        sugestaoDespacho(cozinhaId)
          .then((d) => {
            if (activo) setDespacho(d);
          })
          .catch(() => undefined);
      };
      void ler();
      const t = setInterval(ler, INTERVALO_MS);
      return () => {
        activo = false;
        clearInterval(t);
      };
    }, [cozinhaId]),
  );

  const porZona = useMemo(() => {
    const m = new Map<string, SugestaoDespacho[]>();
    for (const d of despacho) {
      const lista = m.get(d.zona) ?? [];
      lista.push(d);
      m.set(d.zona, lista);
    }
    return [...m.entries()];
  }, [despacho]);

  return (
    <Guarda permissoes={['pedidos.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {cozinhas.length > 1 && cozinhaId && (
          <Escolha opcoes={cozinhas.map((c) => ({ valor: c.id, rotulo: c.nome }))} valor={cozinhaId} aoMudar={setCozinhaId} />
        )}

        {!estafetas && !erro && <ACarregar />}
        {estafetas && estafetas.length === 0 && (
          <Paragrafo suave>Nenhum estafeta a caminho neste momento. O mapa aparece quando houver entregas em curso.</Paragrafo>
        )}
        {estafetas && estafetas.length > 0 && (
          <>
            <MapaEstafetas estafetas={estafetas} />
            <Subtitulo>A caminho ({estafetas.length})</Subtitulo>
            {estafetas.map((e) => (
              <Cartao key={e.funcionario_id}>
                <Text style={{ fontWeight: '700', color: cores.texto }}>{e.nome}</Text>
                <Linha
                  esquerda={`${e.pedidos_a_levar} ${e.pedidos_a_levar === 1 ? 'pedido' : 'pedidos'} a levar`}
                  direita={haQuantoTempo(e.atualizado_em)}
                />
              </Cartao>
            ))}
          </>
        )}
        {porZona.length > 0 && (
          <>
            <Subtitulo>Despacho sugerido</Subtitulo>
            {porZona.map(([zona, lista]) => (
              <Cartao key={zona} estilo={{ gap: espaco.s }}>
                <Text style={{ fontWeight: '700', color: cores.texto }}>
                  {zona} · {lista.length} {lista.length === 1 ? 'pedido' : 'pedidos'}
                </Text>
                {lista.map((d) => (
                  <View key={d.pedido_id} style={{ borderTopWidth: 1, borderTopColor: cores.linha, paddingTop: espaco.xs }}>
                    <Text style={{ color: cores.texto }}>
                      {d.itens.map((i) => `${i.qtd}× ${i.nome}`).join(', ')}
                      {d.referencia ? ` · ${d.referencia}` : ''}
                    </Text>
                    <Text style={{ color: d.sugestao ? cores.sucesso : cores.textoSuave, fontSize: 13 }}>
                      {d.sugestao
                        ? `Sugerido: ${d.sugestao.nome} (${String(d.sugestao.distancia_km).replace('.', ',')} km · ${d.sugestao.pedidos_a_levar} a levar)`
                        : 'Sem estafeta online perto — atribui manualmente'}
                    </Text>
                  </View>
                ))}
              </Cartao>
            ))}
            <Paragrafo suave>
              Pedidos da mesma zona com o mesmo estafeta sugerido podem ir na mesma viagem. É só sugestão — o estafeta
              marca "em entrega" como sempre.
            </Paragrafo>
          </>
        )}
        <Paragrafo suave>
          O mapa só aparece enquanto o estafeta tem pedidos a caminho. Guardamos só a última posição, sem histórico de
          percursos. Precisa do interruptor "acompanhamento_entrega" ligado.
        </Paragrafo>
      </Ecra>
    </Guarda>
  );
}

function haQuantoTempo(iso: string): string {
  const s = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
  return s < 60 ? `há ${s} s` : `há ${Math.round(s / 60)} min`;
}
