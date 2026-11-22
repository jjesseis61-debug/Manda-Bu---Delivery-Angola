import { Redirect, useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Image, Text } from 'react-native';

import { ACarregar, Aviso, Botao, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { lerEnderecos, lerReceita, receitaAbriu, receitaOndePedir, receitaQuero, receitaTocouPedir } from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, raio } from '@/lib/tema';
import type { OndePedirReceita, Receita } from '@/lib/tipos';

const km = (d: number) => `${d.toLocaleString('pt-PT', { maximumFractionDigits: 1 })} km`;

/**
 * Receita da terra. O «Pedir» segue o prato e o balcão do cliente: pede-se no balcão escolhido se ele o
 * fizer; senão no mais perto que o faça (dizendo-o); se ninguém o faz, não se promete — «Quero que façam».
 * O prato abre no ecrã do prato, que pergunta antes de trocar de cozinha com o carrinho cheio.
 */
export default function ReceitaDetalhe() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { carregado, ligada, perfil } = useSessao();
  const carrinho = useCarrinho();
  const [receita, setReceita] = useState<Receita | null>(null);
  const [onde, setOnde] = useState<OndePedirReceita | null>(null);
  const [interessados, setInteressados] = useState<number | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aEnviar, setAEnviar] = useState(false);
  const cozinhaActual = carrinho.cozinhaActual;

  useEffect(() => {
    if (!id) return;
    lerReceita(id)
      .then((r) => {
        setReceita(r);
        if (r) void receitaAbriu(id); // métrica: abriu a receita
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [id]);

  useEffect(() => {
    if (!id) return;
    let vivo = true;
    (async () => {
      const ends = await lerEnderecos(perfil?.cliente_id).catch(() => []);
      const o = await receitaOndePedir(id, cozinhaActual?.id ?? null, ends[0]?.ponto_entrega_id ?? null);
      if (vivo) setOnde(o);
    })().catch(() => vivo && setOnde(null)); // sem a função no servidor: sem botão (melhor do que prometer)
    return () => {
      vivo = false;
    };
  }, [id, cozinhaActual?.id, perfil?.cliente_id]);

  if (!carregado) return <ACarregar />;
  if (!ligada('receitas')) return <Redirect href="/inicio" />;
  if (erro && !receita) return <Ecra><Aviso tipo="erro">{erro}</Aviso></Ecra>;
  if (!receita) return <ACarregar />;

  function pedir() {
    if (!receita || !onde || onde.estado === 'ninguem') return;
    void receitaTocouPedir(receita.id); // métrica: tocou em «Pedir» (o servidor liga ao pedido que vier)
    router.push({ pathname: '/montar/[id]', params: { id: onde.cardapio_id } });
  }

  async function quero() {
    if (!receita) return;
    setAEnviar(true);
    setErro(null);
    try {
      setInteressados(await receitaQuero(receita.id));
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAEnviar(false);
    }
  }

  return (
    <Ecra>
      {receita.foto_url ? (
        <Image source={{ uri: receita.foto_url }} style={{ width: '100%', aspectRatio: 4 / 3, borderRadius: raio }} accessibilityLabel={receita.titulo} />
      ) : null}
      <Subtitulo>{receita.titulo}</Subtitulo>
      {receita.resumo ? <Text style={{ color: cores.textoSuave }}>{receita.resumo}</Text> : null}
      <Paragrafo>{receita.corpo}</Paragrafo>

      {onde?.estado === 'aqui' && (
        <Botao titulo={`Não queres cozinhar? Pede ${onde.prato_nome} em ${onde.cozinha_nome} · ${formatarKz(onde.preco)}`} aoCarregar={pedir} />
      )}

      {onde?.estado === 'perto' && (
        <Cartao>
          <Text style={{ color: cores.texto }}>
            {cozinhaActual ? `${cozinhaActual.nome} não faz ${receita.titulo}. ` : ''}
            {`${onde.cozinha_nome} faz ${onde.prato_nome}${onde.distancia_km != null ? ` (a ${km(onde.distancia_km)})` : ''}.`}
          </Text>
          <Botao titulo={`Pedir em ${onde.cozinha_nome} · ${formatarKz(onde.preco)}`} aoCarregar={pedir} />
        </Cartao>
      )}

      {onde?.estado === 'ninguem' && (
        <Cartao>
          <Text style={{ fontWeight: '700', color: cores.texto }}>Ainda ninguém faz {receita.titulo} perto de ti.</Text>
          {interessados !== null || onde.quero ? (
            <Aviso tipo="sucesso">
              {`✓ Registado${interessados ? `: já são ${interessados} a pedir` : ''}. Mostramos às cozinhas o que os clientes querem.`}
            </Aviso>
          ) : (
            <>
              <Paragrafo suave>Diz-nos que queres: quando houver pedidos suficientes, mostramos às cozinhas da tua zona.</Paragrafo>
              <Botao titulo="Quero que façam" variante="secundario" aCarregar={aEnviar} aoCarregar={quero} />
            </>
          )}
        </Cartao>
      )}
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
    </Ecra>
  );
}
