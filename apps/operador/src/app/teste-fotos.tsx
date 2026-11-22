import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { CampoData } from '@/components/CamposData';
import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { resultadoExperiencia, veredictoExperiencia, type GrupoExperiencia, type ResultadoExperiencia } from '@/lib/experiencias';
import { diaLuanda, formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';

const pct = (v: number | null) => (v == null ? '—' : `${v.toLocaleString('pt-PT')}%`);
const seg = (v: number | null) => (v == null ? '—' : v < 60 ? `${v} s` : `${Math.floor(v / 60)} min ${v % 60} s`);

function CartaoGrupo({ letra, nome, g, vence }: { letra: 'A' | 'B'; nome: string; g: GrupoExperiencia; vence: boolean }) {
  return (
    <Cartao estilo={vence ? { borderWidth: 2, borderColor: cores.sucesso } : undefined}>
      <Text style={{ fontWeight: '800', fontSize: 16 }}>
        {letra} · {nome}
        {vence ? ' ✓' : ''}
      </Text>
      <Linha esquerda="Clientes" direita={String(g.clientes)} />
      <Linha esquerda="Dias com visita ao Início" direita={String(g.dias_visita)} />
      <Linha esquerda="Visitas que acabam em pedido" direita={pct(g.conversao_pct)} forte />
      <Linha esquerda="Pedidos" direita={String(g.pedidos)} />
      <Linha esquerda="Valor médio do pedido" direita={g.valor_medio == null ? '—' : formatarKz(g.valor_medio)} />
      <Linha esquerda="Tempo até ao 1.º «Adicionar» (mediana)" direita={seg(g.mediana_segundos)} />
    </Cartao>
  );
}

/**
 * Teste das fotografias do Início (grupo de controlo, Skinner): metade dos clientes vê a fotografia
 * grande (A, como era) e metade a média (B). Compara os pedidos reais dos dias em que visitaram o Início.
 */
export default function TesteFotos() {
  const [de, setDe] = useState(diaLuanda(-20));
  const [ate, setAte] = useState(diaLuanda());
  const [r, setR] = useState<ResultadoExperiencia | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  const carregar = useCallback(() => {
    if (!de || !ate) return;
    setErro(null);
    resultadoExperiencia('fotos_inicio', de, ate)
      .then(setR)
      .catch((e) => setErro(mensagemErro(e)));
  }, [de, ate]);
  useFocusEffect(carregar);

  const intervaloErrado = !!de && !!ate && ate < de;
  const v = r ? veredictoExperiencia(r.grupos.A, r.grupos.B) : null;

  return (
    <Guarda permissoes={['analista.usar']}>
      <Ecra>
        <Paragrafo suave>
          Metade dos clientes vê a fotografia grande (A, como era) e a outra metade a fotografia média ao lado do nome (B). Cada
          cliente fica sempre no mesmo grupo. Conta só pedidos não cancelados feitos no dia da visita.
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
        {r && (
          <>
            {!r.activo && (
              <Aviso>O teste está desligado: todos os clientes vêem a fotografia média. Liga «teste_fotos_inicio» em Parâmetros para começar.</Aviso>
            )}
            {v && (
              <Cartao estilo={{ backgroundColor: v.claro ? cores.sucessoFundo : cores.avisoFundo }}>
                <Subtitulo>Leitura</Subtitulo>
                <Text style={{ color: cores.texto }}>{v.texto}</Text>
              </Cartao>
            )}
            <CartaoGrupo letra="A" nome="Fotografia grande" g={r.grupos.A} vence={!!v?.claro && v.vencedor === 'A'} />
            <CartaoGrupo letra="B" nome="Fotografia média" g={r.grupos.B} vence={!!v?.claro && v.vencedor === 'B'} />
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
