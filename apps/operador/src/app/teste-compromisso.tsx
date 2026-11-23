import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { CampoData } from '@/components/CamposData';
import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { resultadoCompromisso, taxaAusencia, veredictoCompromisso, type GrupoCompromisso } from '@/lib/compromisso';
import { diaLuanda, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';

function CartaoGrupo({ letra, nome, g, vence }: { letra: 'A' | 'B'; nome: string; g: GrupoCompromisso; vence: boolean }) {
  const t = taxaAusencia(g);
  return (
    <Cartao estilo={vence ? { borderWidth: 2, borderColor: cores.sucesso } : undefined}>
      <Text style={{ fontWeight: '800', fontSize: 16 }}>
        {letra} · {nome}
        {vence ? ' ✓' : ''}
      </Text>
      <Linha esquerda="Pedidos agendados" direita={String(g.agendados)} />
      {letra === 'A' && <Linha esquerda="Disseram «Sim, vou estar»" direita={String(g.confirmados)} />}
      <Linha esquerda="Com cliente ausente" direita={`${g.com_ausencia}${t == null ? '' : ` (${t.toLocaleString('pt-PT')}%)`}`} forte />
      <Linha esquerda="Entregues" direita={String(g.entregues)} />
      <Linha esquerda="Cancelados" direita={String(g.cancelados)} />
    </Cartao>
  );
}

/**
 * Teste do compromisso nos agendados (Cialdini, com grupo de controlo de Skinner): metade dos clientes
 * confirma «Vais estar em … às …?» (A); a outra metade não vê a pergunta (B). Compara as ausências que
 * os estafetas registam («Cliente ausente / não atende»).
 */
export default function TesteCompromisso() {
  const [de, setDe] = useState(diaLuanda(-30));
  const [ate, setAte] = useState(diaLuanda());
  const [r, setR] = useState<{ A: GrupoCompromisso; B: GrupoCompromisso } | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  const carregar = useCallback(() => {
    if (!de || !ate) return;
    setErro(null);
    resultadoCompromisso(de, ate)
      .then(setR)
      .catch((e) => setErro(mensagemErro(e)));
  }, [de, ate]);
  useFocusEffect(carregar);

  const intervaloErrado = !!de && !!ate && ate < de;
  const v = r ? veredictoCompromisso(r.A, r.B) : null;

  return (
    <Guarda permissoes={['analista.usar']}>
      <Ecra>
        <Paragrafo suave>
          Nos pedidos agendados, metade dos clientes confirma «Vais estar em … às …?» (A) e a outra metade não vê a pergunta (B). Os
          dois grupos recebem o lembrete 1 hora antes. As ausências vêm do botão «Cliente ausente» da app do estafeta. Liga
          «compromisso_agendados» em Parâmetros para começar.
        </Paragrafo>
        <View style={{ flexDirection: 'row', gap: espaco.s }}>
          <View style={{ flex: 1 }}>
            <CampoData rotulo="De" valor={de} aoMudar={(iso) => setDe(iso)} />
          </View>
          <View style={{ flex: 1 }}>
            <CampoData rotulo="Até" valor={ate} aoMudar={(iso) => setAte(iso)} erro={intervaloErrado ? 'Tem de ser depois de «De».' : null} />
          </View>
        </View>
        <Botao titulo="Actualizar" variante="secundario" desactivado={intervaloErrado || !de || !ate} aoCarregar={carregar} />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!r && !erro && <ACarregar />}
        {r && v && (
          <>
            <Cartao estilo={{ backgroundColor: v.claro ? cores.sucessoFundo : cores.avisoFundo }}>
              <Subtitulo>Leitura</Subtitulo>
              <Text style={{ color: cores.texto }}>{v.texto}</Text>
            </Cartao>
            <CartaoGrupo letra="A" nome="Com a pergunta" g={r.A} vence={v.claro && v.vencedor === 'A'} />
            <CartaoGrupo letra="B" nome="Sem a pergunta (controlo)" g={r.B} vence={v.claro && v.vencedor === 'B'} />
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
