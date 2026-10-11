import { useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { lerPerguntasAnalista, pedirRelatorioAnalista, perguntarAnalista } from '@/lib/api';
import { diaLuanda, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { PerguntaAnalista } from '@/lib/tipos';

const MES = /^\d{4}-\d{2}$/;
const SUGESTOES = [
  'Que cozinha vendeu mais este mês e como compara com o mês passado?',
  'Quantos clientes voltaram a comprar e de que bairros são?',
  'Que pratos têm piores avaliações e o que dizem os clientes?',
  'A que horas temos mais pedidos e onde há mais atrasos?',
  'Quanto custou o Convida e Ganha este mês e quanto vendeu?',
];

function mesAnterior(): string {
  const [a, m] = diaLuanda().slice(0, 7).split('-').map(Number);
  return m === 1 ? `${a - 1}-12` : `${a}-${String(m - 1).padStart(2, '0')}`;
}

/**
 * Analista do administrador: perguntas em linguagem normal sobre o negócio. O Claude escolhe que números
 * consultar (vendas, pratos, clientes, operação, satisfação, equipa, finanças) e responde com os números-chave.
 */
export default function Analista() {
  const [lista, setLista] = useState<PerguntaAnalista[] | null>(null);
  const [pergunta, setPergunta] = useState('');
  const [mes, setMes] = useState(mesAnterior());
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [aberta, setAberta] = useState<string | null>(null);
  const relogio = useRef<ReturnType<typeof setInterval> | null>(null);

  const carregar = useCallback(() => {
    lerPerguntasAnalista().then(setLista, (e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  // Enquanto houver perguntas à espera, actualiza de 5 em 5 segundos
  const aEspera = !!lista?.some((p) => p.estado === 'pendente' || p.estado === 'a_responder');
  useEffect(() => {
    if (!aEspera) return;
    relogio.current = setInterval(carregar, 5000);
    return () => {
      if (relogio.current) clearInterval(relogio.current);
    };
  }, [aEspera, carregar]);

  async function correr(f: () => Promise<string>) {
    setErro(null);
    setOcupado(true);
    try {
      const id = await f();
      setAberta(id);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  const perguntar = () =>
    correr(async () => {
      const id = await perguntarAnalista(pergunta.trim());
      setPergunta('');
      return id;
    });
  const relatorio = () =>
    correr(() => {
      const [a, m] = mes.split('-').map(Number);
      return pedirRelatorioAnalista(a, m);
    });

  function cartao(p: PerguntaAnalista) {
    const expandida = aberta === p.id || (aberta === null && p === lista?.[0]);
    return (
      <Cartao key={p.id}>
        <Pressable accessibilityRole="button" onPress={() => setAberta(expandida ? '' : p.id)}>
          <Text style={{ fontWeight: '700' }}>{p.tipo === 'relatorio_mensal' ? `📊 ${p.pergunta}` : p.pergunta}</Text>
          <Text style={{ color: cores.textoSuave }}>
            {new Date(p.criado_em).toLocaleString('pt-PT')}
            {p.quem ? ` · ${p.quem}` : ''}
          </Text>
        </Pressable>
        {p.estado === 'pendente' || p.estado === 'a_responder' ? (
          <Paragrafo suave>O analista está a ver os números…</Paragrafo>
        ) : p.estado === 'indisponivel' ? (
          <Aviso>Analista indisponível{p.ia_nota ? ` (${p.ia_nota})` : ''}.</Aviso>
        ) : (
          expandida && (
            <View style={{ gap: espaco.s }}>
              <Text>{p.resposta}</Text>
              {p.numeros.length > 0 && (
                <View>
                  {p.numeros.map((n, i) => (
                    <Linha key={i} esquerda={n.rotulo} direita={n.valor} />
                  ))}
                </View>
              )}
              {p.sugestoes.length > 0 && (
                <>
                  <Subtitulo>Sugestões</Subtitulo>
                  {p.sugestoes.map((t, i) => (
                    <Text key={i}>• {t}</Text>
                  ))}
                </>
              )}
              {!!p.limitacoes && <Paragrafo suave>Limitações: {p.limitacoes}</Paragrafo>}
              <Paragrafo suave>Consultou {p.passos} conjunto(s) de números.</Paragrafo>
            </View>
          )
        )}
      </Cartao>
    );
  }

  return (
    <Guarda permissoes={['analista.usar']}>
      <Ecra>
        <Campo rotulo="A tua pergunta" value={pergunta} onChangeText={setPergunta} maxLength={600} multiline />
        <Botao titulo="Perguntar" desactivado={pergunta.trim().length < 5} aCarregar={ocupado} aoCarregar={perguntar} />
        <View style={{ gap: espaco.xs }}>
          {SUGESTOES.map((s) => (
            <Botao key={s} titulo={s} variante="texto" aoCarregar={() => setPergunta(s)} />
          ))}
        </View>
        <Campo rotulo="Relatório do mês (AAAA-MM)" value={mes} onChangeText={setMes} maxLength={7} />
        <Botao titulo="Pedir relatório do mês" variante="secundario" desactivado={!MES.test(mes)} aoCarregar={relatorio} />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {lista === null ? <ACarregar /> : lista.length === 0 ? <Paragrafo suave>Ainda não fizeste perguntas.</Paragrafo> : lista.map(cartao)}
      </Ecra>
    </Guarda>
  );
}
