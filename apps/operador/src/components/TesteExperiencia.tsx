import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { CampoData } from '@/components/CamposData';
import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { type Experiencia, resultadoExperiencia, TEXTOS, veredictoExperiencia, type GrupoExperiencia, type ResultadoExperiencia } from '@/lib/experiencias';
import { diaLuanda, formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';

const pct = (v: number | null) => (v == null ? '-' : `${v.toLocaleString('pt-PT')}%`);
const seg = (v: number | null) => (v == null ? '-' : v < 60 ? `${v} s` : `${Math.floor(v / 60)} min ${v % 60} s`);

function CartaoGrupo({ letra, nome, g, vence, ondeVisita }: { letra: 'A' | 'B'; nome: string; g: GrupoExperiencia; vence: boolean; ondeVisita: string }) {
  return (
    <Cartao estilo={vence ? { borderWidth: 2, borderColor: cores.sucesso } : undefined}>
      <Text style={{ fontWeight: '800', fontSize: 16 }}>
        {letra} · {nome}
        {vence ? ' ✓' : ''}
      </Text>
      <Linha esquerda="Clientes" direita={String(g.clientes)} />
      <Linha esquerda={`Dias com visita ${ondeVisita}`} direita={String(g.dias_visita)} />
      <Linha esquerda="Visitas que acabam em pedido" direita={pct(g.conversao_pct)} forte />
      <Linha esquerda="Pedidos" direita={String(g.pedidos)} />
      <Linha esquerda="Valor médio do pedido" direita={g.valor_medio == null ? '-' : formatarKz(g.valor_medio)} />
      <Linha esquerda="Tempo até ao 1.º «Adicionar» (mediana)" direita={seg(g.mediana_segundos)} />
    </Cartao>
  );
}

type Props = {
  experiencia: Experiencia;
  /** Explicação do teste em cima do ecrã */
  descricao: string;
  /** Aviso quando o interruptor está desligado */
  desligado: string;
  /** Nome de cada cartão, ex.: «Fotografia grande» */
  nomeA: string;
  nomeB: string;
  /** «ao Início», «ao Servir o prato» */
  ondeVisita: string;
};

/**
 * Resultado de um teste com grupo de controlo (Skinner): metade dos clientes vê A (como era) e metade
 * B (o desenho novo). Compara os pedidos reais dos dias em que visitaram o ecrã.
 */
export function TesteExperiencia({ experiencia, descricao, desligado, nomeA, nomeB, ondeVisita }: Props) {
  const [de, setDe] = useState(diaLuanda(-20));
  const [ate, setAte] = useState(diaLuanda());
  const [r, setR] = useState<ResultadoExperiencia | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  const carregar = useCallback(() => {
    if (!de || !ate) return;
    setErro(null);
    resultadoExperiencia(experiencia, de, ate)
      .then(setR)
      .catch((e) => setErro(mensagemErro(e)));
  }, [experiencia, de, ate]);
  useFocusEffect(carregar);

  const intervaloErrado = !!de && !!ate && ate < de;
  const v = r ? veredictoExperiencia(r.grupos.A, r.grupos.B, TEXTOS[experiencia]) : null;

  return (
    <Guarda permissoes={['analista.usar']}>
      <Ecra>
        <Paragrafo suave>{descricao}</Paragrafo>
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
            {!r.activo && <Aviso>{desligado}</Aviso>}
            {v && (
              <Cartao estilo={{ backgroundColor: v.claro ? cores.sucessoFundo : cores.avisoFundo }}>
                <Subtitulo>Leitura</Subtitulo>
                <Text style={{ color: cores.texto }}>{v.texto}</Text>
              </Cartao>
            )}
            <CartaoGrupo letra="A" nome={nomeA} g={r.grupos.A} vence={!!v?.claro && v.vencedor === 'A'} ondeVisita={ondeVisita} />
            <CartaoGrupo letra="B" nome={nomeB} g={r.grupos.B} vence={!!v?.claro && v.vencedor === 'B'} ondeVisita={ondeVisita} />
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
