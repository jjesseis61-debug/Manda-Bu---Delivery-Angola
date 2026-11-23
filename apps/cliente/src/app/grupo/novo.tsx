import { Redirect, useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';

import { Text } from 'react-native';

import { ACarregar, Aviso, Botao, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { criarGrupo, lerEnderecos } from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { horaLuanda, mensagemErro, TIPOS_GRUPO } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { Endereco, ModoGrupo, TipoGrupo } from '@/lib/tipos';

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

/**
 * C12. Criar grupo: onde (qualquer endereço: trabalho, família, vizinhos, igreja), hora de entrega,
 * prazo de adesão e quem paga (cada um a sua parte antes, quem recebe tudo, ou a empresa no trabalho).
 */
export default function NovoGrupo() {
  const router = useRouter();
  const { carregado, ligada, perfil } = useSessao();
  const carrinho = useCarrinho();
  const [enderecos, setEnderecos] = useState<Endereco[] | null>(null);
  const [pontoId, setPontoId] = useState<string | null>(null);
  const horas = useMemo(() => horasPossiveis(), []);
  // Por defeito, a primeira hora em que o grupo ainda fica aberto pelo menos uns minutos (com o prazo de 1 h)
  const [hora, setHora] = useState<string | null>(
    () => horas.find((h) => new Date(h).getTime() - 60 * 60000 > Date.now() + 5 * 60000) ?? horas[0] ?? null,
  );
  const [prazo, setPrazo] = useState('60');
  const [modo, setModo] = useState<ModoGrupo>('individual');
  const [tipo, setTipo] = useState<TipoGrupo | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aCriar, setACriar] = useState(false);

  useFocusEffect(
    useCallback(() => {
      lerEnderecos(perfil?.cliente_id)
        .then((e) => {
          // Qualquer endereço serve; o primeiro de trabalho vem à frente (era o único caso antes)
          const ordenados = [...e].sort((a, b) => Number(b.pontos_entrega?.tipo === 'empresa') - Number(a.pontos_entrega?.tipo === 'empresa'));
          setEnderecos(ordenados);
          setPontoId((actual) => actual ?? ordenados[0]?.ponto_entrega_id ?? null);
        })
        .catch((e) => setErro(mensagemErro(e)));
    }, []),
  );

  // Aberto por link ou notificação: espera pelos interruptores antes de decidir
  if (!carregado) return <ACarregar />;
  if (!ligada('pedidos_grupo')) return <Redirect href="/inicio" />;
  if (!enderecos && !erro) return <ACarregar />;

  const escolhido = (enderecos ?? []).find((e) => e.ponto_entrega_id === pontoId) ?? null;
  const noTrabalho = escolhido?.pontos_entrega?.tipo === 'empresa';
  // Tipo do grupo: o que a pessoa escolheu, ou o natural para o endereço (trabalho / família)
  const tipoEfectivo: TipoGrupo = tipo ?? (noTrabalho ? 'trabalho' : 'familia');
  // A empresa só paga num endereço de trabalho
  const modoEfectivo: ModoGrupo = modo === 'empresa' && !noTrabalho ? 'individual' : modo;

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
        modo: modoEfectivo,
        tipo: tipoEfectivo,
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
      <Cartao>
        <Text style={{ fontSize: 20, fontWeight: '900', color: cores.marca }}>🤝 Junta Bué</Text>
        <Text style={{ color: cores.texto }}>Junta a família, os vizinhos ou a igreja: tudo chega junto e a entrega fica mais barata.</Text>
      </Cartao>
      {ligada('multi_cozinha') && carrinho.cozinha && <Paragrafo>Cozinha: {carrinho.cozinha.nome}</Paragrafo>}
      <Subtitulo>Onde</Subtitulo>
      {enderecos && enderecos.length === 0 ? (
        <>
          <Aviso>Tudo chega junto num só endereço (casa, trabalho, igreja…). Adiciona primeiro esse endereço.</Aviso>
          <Botao titulo="Adicionar endereço" variante="secundario" aoCarregar={() => router.push('/enderecos/novo')} />
        </>
      ) : (
        <Escolha
          opcoes={(enderecos ?? []).map((e) => ({
            valor: e.ponto_entrega_id,
            rotulo: [e.nome ?? (e.pontos_entrega?.tipo === 'empresa' ? 'Trabalho' : 'Casa'), e.pontos_entrega?.referencia ?? e.pontos_entrega?.zonas?.nome]
              .filter(Boolean)
              .join(' · '),
          }))}
          valor={pontoId ?? ''}
          aoMudar={setPontoId}
        />
      )}

      <Subtitulo>Quem se junta</Subtitulo>
      <Escolha opcoes={TIPOS_GRUPO.map((t) => ({ valor: t.valor, rotulo: t.rotulo }))} valor={tipoEfectivo} aoMudar={(v) => setTipo(v as TipoGrupo)} />

      <Subtitulo>Hora de entrega</Subtitulo>
      {horas.length === 0 ? (
        <Paragrafo suave>Hoje já não há horas de entrega disponíveis.</Paragrafo>
      ) : (
        <Escolha opcoes={horas.map((h) => ({ valor: h, rotulo: horaLuanda(h) }))} valor={hora ?? ''} aoMudar={setHora} />
      )}

      <Subtitulo>Até quando os outros podem juntar-se</Subtitulo>
      <Escolha opcoes={PRAZOS} valor={prazo} aoMudar={setPrazo} />
      {prazoIso && !prazoPassado && <Paragrafo suave>Fecha às {horaLuanda(prazoIso)}.</Paragrafo>}
      {prazoIso && prazoPassado && <Aviso>Com este prazo o grupo fechava já. Escolhe uma hora mais tarde ou um prazo mais curto.</Aviso>}

      <Subtitulo>Quem paga</Subtitulo>
      <Escolha
        opcoes={[
          { valor: 'individual', rotulo: 'Cada um paga a sua parte' },
          { valor: 'quem_recebe', rotulo: 'Quem recebe paga tudo' },
          ...(perfil?.tipo === 'Empresa' && noTrabalho ? [{ valor: 'empresa', rotulo: 'A empresa paga tudo' }] : []),
        ]}
        valor={modoEfectivo}
        aoMudar={(v) => setModo(v as ModoGrupo)}
      />
      <Paragrafo suave>
        {modoEfectivo === 'individual'
          ? 'Cada um paga a sua parte antes, por Multicaixa Express ou Unitel Money, e escreve a referência na app. Quem não puder, paga ao estafeta.'
          : modoEfectivo === 'quem_recebe'
            ? 'Quem recebe a entrega paga tudo ao estafeta (dinheiro ou Multicaixa) e acerta depois com os outros.'
            : 'A empresa paga tudo: os pedidos entram na conta da empresa.'}
      </Paragrafo>

      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Botao titulo="Criar Junta Bué" aCarregar={aCriar} desactivado={!pontoId || !hora || prazoPassado} aoCarregar={criar} />
    </Ecra>
  );
}
