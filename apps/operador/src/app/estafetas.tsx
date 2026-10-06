import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { MapaEstafetas } from '@/components/MapaEstafetas';
import { ACarregar, Aviso, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { lerCozinhas, posicoesEstafetas } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { Cozinha, PosicaoEstafeta } from '@/lib/tipos';

const INTERVALO_MS = 10_000;

/** Mapa de acompanhamento dos estafetas de serviço (despacho). Actualiza a cada 10 s. */
export default function Estafetas() {
  const { funcionario, pode } = useSessao();
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [cozinhaId, setCozinhaId] = useState<string | null>(null);
  const [estafetas, setEstafetas] = useState<PosicaoEstafeta[] | null>(null);
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
      const ler = () =>
        posicoesEstafetas(cozinhaId)
          .then((e) => {
            if (activo) setEstafetas(e);
          })
          .catch((e) => {
            if (activo) setErro(mensagemErro(e));
          });
      void ler();
      const t = setInterval(ler, INTERVALO_MS);
      return () => {
        activo = false;
        clearInterval(t);
      };
    }, [cozinhaId]),
  );

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
        <Paragrafo suave>
          Só aparece enquanto o estafeta tem pedidos a caminho. Guardamos só a última posição, sem histórico de
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
