import { Redirect, useFocusEffect, useLocalSearchParams, useRouter } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';

import { ACarregar, Aviso, Botao, Campo, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { lerEnderecos } from '@/lib/api';
import { diasParaEncomenda, encomendar, HORAS_ENCOMENDA, instanteLuanda, rotuloDia } from '@/lib/encomendas';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import type { Endereco } from '@/lib/tipos';

const PESSOAS = ['4', '6', '8', '10', '15', '20', '30'];

/**
 * Encomendar uma receita que nenhuma cozinha tem no cardápio: para quantas pessoas, quando (com 24 h de
 * antecedência) e onde. O operador escolhe a cozinha, a cozinha propõe o preço e o cliente confirma antes
 * de pagar nada. Bandura: o caminho todo explicado antes de começar (sem surpresas no preço).
 */
export default function NovaEncomenda() {
  const { receita, titulo } = useLocalSearchParams<{ receita: string; titulo?: string }>();
  const router = useRouter();
  const { carregado, ligada, perfil } = useSessao();
  const [enderecos, setEnderecos] = useState<Endereco[] | null>(null);
  const [pontoId, setPontoId] = useState<string | null>(null);
  const dias = useMemo(() => diasParaEncomenda(), []);
  const [dia, setDia] = useState<string | null>(dias[0] ?? null);
  const [hora, setHora] = useState('13:00');
  const [pessoas, setPessoas] = useState('6');
  const [nota, setNota] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [aEnviar, setAEnviar] = useState(false);

  useFocusEffect(
    useCallback(() => {
      lerEnderecos(perfil?.cliente_id)
        .then((e) => {
          setEnderecos(e);
          setPontoId((actual) => actual ?? e[0]?.ponto_entrega_id ?? null);
        })
        .catch((e) => setErro(mensagemErro(e)));
    }, [perfil?.cliente_id]),
  );

  if (!carregado) return <ACarregar />;
  if (!ligada('encomendas') || !receita) return <Redirect href="/inicio" />;
  if (!enderecos && !erro) return <ACarregar />;

  const quando = dia ? instanteLuanda(dia, hora) : null;
  const cedoDemais = !quando || quando.getTime() < Date.now() + 24 * 3600_000;

  async function enviar() {
    if (!receita || !pontoId || !quando) return;
    setErro(null);
    setAEnviar(true);
    try {
      await encomendar({ receitaId: receita, pessoas: Number(pessoas), paraQuando: quando.toISOString(), pontoId, nota });
      router.replace('/encomendas');
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAEnviar(false);
    }
  }

  return (
    <Ecra>
      <Subtitulo>{titulo ? `🎉 Boda Bué · ${titulo}` : '🎉 Boda Bué'}</Subtitulo>
      <Paragrafo suave>
        Escolhemos uma cozinha que o faça e mandamos-te o preço. Só depois de confirmares pagas um sinal de 50%; o resto paga-se na entrega.
      </Paragrafo>

      <Subtitulo>Para quantas pessoas</Subtitulo>
      <Escolha opcoes={PESSOAS.map((p) => ({ valor: p, rotulo: p }))} valor={pessoas} aoMudar={setPessoas} />

      <Subtitulo>Que dia</Subtitulo>
      <Escolha opcoes={dias.map((d) => ({ valor: d, rotulo: rotuloDia(d) }))} valor={dia ?? ''} aoMudar={setDia} />

      <Subtitulo>A que horas</Subtitulo>
      <Escolha opcoes={HORAS_ENCOMENDA.map((h) => ({ valor: h, rotulo: h.replace(':', 'h') }))} valor={hora} aoMudar={setHora} />
      {cedoDemais && <Aviso>Precisamos de pelo menos 24 horas: escolhe uma hora mais tarde ou outro dia.</Aviso>}

      <Subtitulo>Onde entregar</Subtitulo>
      {enderecos && enderecos.length === 0 ? (
        <Botao titulo="Adicionar endereço" variante="secundario" aoCarregar={() => router.push('/enderecos/novo')} />
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

      <Campo rotulo="Nota para a cozinha (opcional)" value={nota} onChangeText={setNota} placeholder="Ex.: pouco picante, é para um aniversário" />

      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Botao titulo="Pedir preço" aCarregar={aEnviar} desactivado={!pontoId || cedoDemais} aoCarregar={enviar} />
      <Paragrafo suave>Pedir preço não te compromete a nada.</Paragrafo>
    </Ecra>
  );
}
