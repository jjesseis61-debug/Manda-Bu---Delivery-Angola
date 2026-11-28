import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { lerCozinhas, lerPlanosCompras, marcarCompra, pedirPlanoCompras } from '@/lib/api';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Cozinha, ItemCompra, PlanoCompras } from '@/lib/tipos';

const nomeUrgencia: Record<ItemCompra['urgencia'], string> = {
  hoje: 'Comprar hoje',
  esta_semana: 'Esta semana',
  proxima_semana: 'Próxima semana',
};
const nomeAlerta: Record<PlanoCompras['alertas'][number]['tipo'], string> = {
  validade: 'Validade',
  desvio: 'Saída sem explicação',
  preco: 'Preço',
  ruptura: 'Ruptura',
  dados: 'Dados',
  outro: 'Alerta',
};

/**
 * Stock e compras: o plano de compras que o agente prepara todos os dias (ou quando se pede) e os alertas do
 * stock. O agente só lê; quem trata do stock marca cada compra como feita ou ignorada. As entradas continuam a
 * ser registadas como hoje.
 */
export default function Compras() {
  const { funcionario, pode } = useSessao();
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [cozinhaId, setCozinhaId] = useState<string | null>(null);
  const [planos, setPlanos] = useState<PlanoCompras[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState<string | null>(null);

  const carregar = useCallback(() => {
    Promise.all([lerCozinhas(), lerPlanosCompras()])
      .then(([cs, ps]) => {
        const minhas = pode('cozinhas.gerir') || funcionario?.administrador_principal
          ? cs
          : cs.filter((c) => funcionario?.cozinhas_equipa.includes(c.id));
        setCozinhas(minhas);
        setCozinhaId((actual) => actual ?? minhas[0]?.id ?? null);
        setPlanos(ps);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [pode, funcionario]);
  useFocusEffect(carregar);

  async function correr(chave: string, accao: () => Promise<unknown>) {
    setErro(null);
    setOcupado(chave);
    try {
      await accao();
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(null);
    }
  }

  const daCozinha = planos?.filter((p) => p.cozinha_id === cozinhaId) ?? [];
  const actual = daCozinha.find((p) => p.estado === 'pronto');
  const aPreparar = daCozinha.some((p) => p.estado === 'pendente' || p.estado === 'a_preparar');
  const ultimo = daCozinha[0];

  function item(p: PlanoCompras, c: ItemCompra, i: number) {
    const feito = c.estado !== 'pendente';
    return (
      <Cartao key={i}>
        <Text style={{ fontWeight: '700', color: feito ? cores.textoSuave : c.urgencia === 'hoje' ? cores.erro : cores.texto }}>
          {c.produto}: {c.quantidade} {c.unidade ?? ''}
        </Text>
        <Text style={{ color: cores.textoSuave }}>
          {[nomeUrgencia[c.urgencia], c.custo_estimado ? `cerca de ${formatarKz(c.custo_estimado)}` : null, c.fornecedor]
            .filter(Boolean)
            .join(' · ')}
        </Text>
        <Text>{c.motivo}</Text>
        {feito ? (
          <View style={{ gap: espaco.s }}>
            <Text style={{ color: cores.textoSuave }}>
              {c.estado === 'comprado' ? 'Comprado' : 'Ignorado'}
              {c.decidido_por ? ` por ${c.decidido_por}` : ''}
            </Text>
            <Botao titulo="Desfazer" variante="texto" aoCarregar={() => correr(`${p.id}${i}`, () => marcarCompra(p.id, i, 'pendente'))} />
          </View>
        ) : (
          <View style={{ gap: espaco.s }}>
            <Botao titulo="Comprado" aCarregar={ocupado === `${p.id}${i}`} aoCarregar={() => correr(`${p.id}${i}`, () => marcarCompra(p.id, i, 'comprado'))} />
            <Botao titulo="Ignorar" variante="secundario" aoCarregar={() => correr(`${p.id}${i}`, () => marcarCompra(p.id, i, 'ignorado'))} />
          </View>
        )}
      </Cartao>
    );
  }

  return (
    <Guarda permissoes={['stock.gerir']}>
      <Ecra>
        <Paragrafo suave>
          Todos os dias o agente vê os saldos, o consumo, os preços e as distribuições e prepara o plano de compras. Ele só
          lê: as entradas continuam a ser registadas como hoje.
        </Paragrafo>
        {cozinhas.length > 1 && cozinhaId && (
          <Escolha opcoes={cozinhas.map((c) => ({ valor: c.id, rotulo: c.nome }))} valor={cozinhaId} aoMudar={setCozinhaId} />
        )}
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {cozinhaId && (
          <Botao
            titulo={aPreparar ? 'A preparar o plano…' : 'Pedir plano agora'}
            desactivado={aPreparar}
            aCarregar={ocupado === 'pedir'}
            aoCarregar={() => correr('pedir', () => pedirPlanoCompras(cozinhaId))}
          />
        )}
        <Botao titulo="Actualizar" variante="texto" aoCarregar={carregar} />
        {planos === null ? (
          <ACarregar />
        ) : !actual ? (
          ultimo?.estado === 'indisponivel' ? (
            <Aviso tipo="erro">O plano não pôde ser preparado. Confirma a chave da análise automática e tenta de novo.</Aviso>
          ) : (
            !aPreparar && <Aviso tipo="sucesso">Ainda não há plano de compras para esta cozinha.</Aviso>
          )
        ) : (
          <>
            <Subtitulo>
              Plano de {actual.dia}
              {actual.pedido_por ? ` (pedido por ${actual.pedido_por})` : ''}
            </Subtitulo>
            <Paragrafo>{actual.resumo}</Paragrafo>
            {actual.alertas.map((a, i) => (
              <Aviso key={i} tipo={a.gravidade === 'alta' ? 'erro' : 'aviso'}>
                {`${nomeAlerta[a.tipo]}${a.produto ? ` · ${a.produto}` : ''}: ${a.texto}`}
              </Aviso>
            ))}
            {actual.compras.length === 0 && <Aviso tipo="sucesso">Nada a comprar por agora.</Aviso>}
            {actual.compras.map((c, i) => item(actual, c, i))}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
