import { Redirect, useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';

import { ACarregar, Aviso, Botao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { criarGrupo, lerEnderecos } from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { horaLuanda, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import type { Endereco } from '@/lib/tipos';

const PRAZOS = [
  { valor: '30', rotulo: '30 min antes' },
  { valor: '60', rotulo: '1 h antes' },
  { valor: '120', rotulo: '2 h antes' },
];

/** Horas de entrega possíveis hoje: de meia em meia hora, a partir de daqui a 1 hora, até às 22h00 de Luanda */
function horasPossiveis(agora = new Date()): string[] {
  const meiaHora = 30 * 60 * 1000;
  const inicio = Math.ceil((agora.getTime() + 60 * 60 * 1000) / meiaHora) * meiaHora;
  const r: string[] = [];
  for (let t = inicio; r.length < 16; t += meiaHora) {
    const iso = new Date(t).toISOString();
    if (Number(horaLuanda(iso).slice(0, 2)) >= 22 || new Date(t).getUTCDate() !== new Date(inicio).getUTCDate()) break;
    r.push(iso);
  }
  return r;
}

/** C12. Criar grupo: local de trabalho, hora de entrega, prazo de adesão, modo de pagamento */
export default function NovoGrupo() {
  const router = useRouter();
  const { carregado, ligada, perfil } = useSessao();
  const carrinho = useCarrinho();
  const [enderecos, setEnderecos] = useState<Endereco[] | null>(null);
  const [pontoId, setPontoId] = useState<string | null>(null);
  const horas = useMemo(() => horasPossiveis(), []);
  const [hora, setHora] = useState<string | null>(horas[0] ?? null);
  const [prazo, setPrazo] = useState('60');
  const [modo, setModo] = useState<'individual' | 'empresa'>('individual');
  const [erro, setErro] = useState<string | null>(null);
  const [aCriar, setACriar] = useState(false);

  useFocusEffect(
    useCallback(() => {
      lerEnderecos()
        .then((e) => {
          const trabalho = e.filter((x) => x.pontos_entrega?.tipo === 'empresa');
          setEnderecos(trabalho);
          setPontoId((actual) => actual ?? trabalho[0]?.ponto_entrega_id ?? null);
        })
        .catch((e) => setErro(mensagemErro(e)));
    }, []),
  );

  // Aberto por link ou notificação: espera pelos interruptores antes de decidir
  if (!carregado) return <ACarregar />;
  if (!ligada('pedidos_grupo')) return <Redirect href="/inicio" />;
  if (!enderecos && !erro) return <ACarregar />;

  const prazoIso = hora ? new Date(new Date(hora).getTime() - Number(prazo) * 60000).toISOString() : null;
  const prazoPassado = !prazoIso || new Date(prazoIso).getTime() < Date.now() + 5 * 60000;

  async function criar() {
    if (!pontoId || !hora || !prazoIso) return;
    setErro(null);
    setACriar(true);
    try {
      const codigo = await criarGrupo({
        pontoEntregaId: pontoId,
        horaEntrega: hora,
        prazoAdesao: prazoIso,
        modo,
        cozinhaId: ligada('multi_cozinha') ? carrinho.cozinha?.id : null,
      });
      router.replace({ pathname: '/grupo/[codigo]', params: { codigo } });
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setACriar(false);
    }
  }

  return (
    <Ecra>
      {ligada('multi_cozinha') && carrinho.cozinha && <Paragrafo>Cozinha: {carrinho.cozinha.nome}</Paragrafo>}
      <Subtitulo>Onde</Subtitulo>
      {enderecos && enderecos.length === 0 ? (
        <>
          <Aviso>Os pedidos de grupo são entregues no local de trabalho. Adiciona um endereço do tipo Trabalho.</Aviso>
          <Botao titulo="Adicionar endereço" variante="secundario" aoCarregar={() => router.push('/enderecos/novo')} />
        </>
      ) : (
        <Escolha
          opcoes={(enderecos ?? []).map((e) => ({
            valor: e.ponto_entrega_id,
            rotulo: e.nome ?? e.pontos_entrega?.referencia ?? 'Trabalho',
          }))}
          valor={pontoId ?? ''}
          aoMudar={setPontoId}
        />
      )}

      <Subtitulo>Hora de entrega</Subtitulo>
      {horas.length === 0 ? (
        <Paragrafo suave>Hoje já não há horas de entrega disponíveis.</Paragrafo>
      ) : (
        <Escolha opcoes={horas.map((h) => ({ valor: h, rotulo: horaLuanda(h) }))} valor={hora ?? ''} aoMudar={setHora} />
      )}

      <Subtitulo>Até quando os colegas podem juntar-se</Subtitulo>
      <Escolha opcoes={PRAZOS} valor={prazo} aoMudar={setPrazo} />
      {prazoIso && !prazoPassado && <Paragrafo suave>Fecha às {horaLuanda(prazoIso)}.</Paragrafo>}
      {prazoIso && prazoPassado && <Aviso>Com este prazo o grupo fechava já. Escolhe uma hora mais tarde ou um prazo mais curto.</Aviso>}

      {perfil?.tipo === 'Empresa' && (
        <>
          <Subtitulo>Quem paga</Subtitulo>
          <Escolha
            opcoes={[
              { valor: 'individual', rotulo: 'Cada um paga o seu' },
              { valor: 'empresa', rotulo: 'A empresa paga tudo' },
            ]}
            valor={modo}
            aoMudar={setModo}
          />
        </>
      )}

      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Botao titulo="Criar grupo" aCarregar={aCriar} desactivado={!pontoId || !hora || prazoPassado} aoCarregar={criar} />
    </Ecra>
  );
}
