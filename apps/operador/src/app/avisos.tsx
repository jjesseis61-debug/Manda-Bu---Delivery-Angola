import { useFocusEffect } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { enviarAviso, lerCozinhas, lerZonasEntrega, listarAvisos, preVisualizarAviso } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { Aviso as AvisoHistorico, Cozinha, PublicoAviso, ZonaEntrega } from '@/lib/tipos';

const PUBLICOS: { valor: PublicoAviso; rotulo: string }[] = [
  { valor: 'clientes_todos', rotulo: 'Todos os clientes' },
  { valor: 'clientes_zona', rotulo: 'Clientes por zona' },
  { valor: 'clientes_cozinha', rotulo: 'Clientes por cozinha' },
  { valor: 'func_todos', rotulo: 'Todos os funcionários' },
  { valor: 'func_permissao', rotulo: 'Funcionários por função' },
  { valor: 'func_cozinha', rotulo: 'Equipa de uma cozinha' },
];

// Funções mais usadas para avisar (mapeadas às permissões do organograma)
const FUNCOES: { valor: string; rotulo: string }[] = [
  { valor: 'entregas.registar', rotulo: 'Estafetas' },
  { valor: 'vendas.registar', rotulo: 'Operadores de caixa' },
  { valor: 'pedidos.gerir', rotulo: 'Cozinha / pedidos' },
  { valor: 'atendimento.responder', rotulo: 'Atendimento' },
];

const rotuloPublico = (p: PublicoAviso) => PUBLICOS.find((o) => o.valor === p)?.rotulo ?? p;

/** Central de Avisos: enviar notificações segmentadas a clientes e à equipa. */
export default function Avisos() {
  const [zonas, setZonas] = useState<ZonaEntrega[]>([]);
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [historico, setHistorico] = useState<AvisoHistorico[] | null>(null);

  const [titulo, setTitulo] = useState('');
  const [corpo, setCorpo] = useState('');
  const [publico, setPublico] = useState<PublicoAviso>('clientes_todos');
  const [zonaId, setZonaId] = useState<string | null>(null);
  const [cozinhaId, setCozinhaId] = useState<string | null>(null);
  const [funcao, setFuncao] = useState<string>(FUNCOES[0].valor);

  const [previsto, setPrevisto] = useState<number | null>(null);
  const [aGuardar, setAGuardar] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);

  const recarregar = useCallback(() => {
    listarAvisos().then(setHistorico).catch((e) => setErro(mensagemErro(e)));
  }, []);

  useFocusEffect(
    useCallback(() => {
      Promise.all([lerZonasEntrega(), lerCozinhas()])
        .then(([zs, cs]) => {
          setZonas(zs);
          setCozinhas(cs);
          setZonaId((z) => z ?? zs[0]?.id ?? null);
          setCozinhaId((c) => c ?? cs[0]?.id ?? null);
        })
        .catch((e) => setErro(mensagemErro(e)));
      recarregar();
    }, [recarregar]),
  );

  // O "alvo" que cada público precisa (e se está escolhido)
  const alvo = useMemo((): Record<string, unknown> | null => {
    switch (publico) {
      case 'clientes_zona':
        return zonaId ? { zona_id: zonaId } : null;
      case 'clientes_cozinha':
      case 'func_cozinha':
        return cozinhaId ? { cozinha_id: cozinhaId } : null;
      case 'func_permissao':
        return funcao ? { permissao: funcao } : null;
      default:
        return {};
    }
  }, [publico, zonaId, cozinhaId, funcao]);

  const limpar = () => {
    setTitulo('');
    setCorpo('');
    setPrevisto(null);
  };

  const mudarPublico = (p: PublicoAviso) => {
    setPublico(p);
    setPrevisto(null);
    setSucesso(null);
  };

  async function prever() {
    if (!alvo) return;
    setErro(null);
    try {
      setPrevisto(await preVisualizarAviso(publico, alvo));
    } catch (e) {
      setErro(mensagemErro(e));
    }
  }

  async function enviar() {
    if (!alvo || corpo.trim().length === 0) return;
    setAGuardar(true);
    setErro(null);
    setSucesso(null);
    try {
      const r = await enviarAviso(publico, titulo.trim(), corpo.trim(), alvo);
      setSucesso(`Aviso enviado a ${r.total} ${r.total === 1 ? 'pessoa' : 'pessoas'}.`);
      limpar();
      recarregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAGuardar(false);
    }
  }

  const faltaAlvo = alvo === null;
  const podeEnviar = !faltaAlvo && corpo.trim().length > 0 && !aGuardar;

  return (
    <Guarda permissoes={['avisos.enviar']}>
      <Ecra>
        <Subtitulo>Central de Avisos</Subtitulo>
        <Paragrafo suave>Envia uma notificação a clientes ou à equipa. Escolhe o público, pré-vê quantos recebem e envia.</Paragrafo>

        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}

        <Cartao>
          <Campo rotulo="Título (opcional)" value={titulo} onChangeText={setTitulo} placeholder="Ex.: Promoção de hoje" />
          <Campo
            rotulo="Mensagem"
            value={corpo}
            onChangeText={(t) => {
              setCorpo(t);
              setPrevisto(null);
            }}
            placeholder="O que queres dizer?"
            multiline
          />

          <Text style={{ color: cores.textoSuave, marginTop: espaco.s, marginBottom: 4 }}>Público</Text>
          <Escolha opcoes={PUBLICOS} valor={publico} aoMudar={mudarPublico} />

          {publico === 'clientes_zona' && (
            <View style={{ marginTop: espaco.s }}>
              <Text style={{ color: cores.textoSuave, marginBottom: 4 }}>Zona</Text>
              {zonas.length === 0 ? (
                <Paragrafo suave>Ainda não há zonas.</Paragrafo>
              ) : (
                <Escolha
                  opcoes={zonas.map((z) => ({ valor: z.id, rotulo: z.nome }))}
                  valor={zonaId ?? ''}
                  aoMudar={(v) => {
                    setZonaId(v);
                    setPrevisto(null);
                  }}
                />
              )}
            </View>
          )}

          {(publico === 'clientes_cozinha' || publico === 'func_cozinha') && (
            <View style={{ marginTop: espaco.s }}>
              <Text style={{ color: cores.textoSuave, marginBottom: 4 }}>Cozinha</Text>
              {cozinhas.length === 0 ? (
                <Paragrafo suave>Ainda não há cozinhas.</Paragrafo>
              ) : (
                <Escolha
                  opcoes={cozinhas.map((c) => ({ valor: c.id, rotulo: c.nome }))}
                  valor={cozinhaId ?? ''}
                  aoMudar={(v) => {
                    setCozinhaId(v);
                    setPrevisto(null);
                  }}
                />
              )}
            </View>
          )}

          {publico === 'func_permissao' && (
            <View style={{ marginTop: espaco.s }}>
              <Text style={{ color: cores.textoSuave, marginBottom: 4 }}>Função</Text>
              <Escolha
                opcoes={FUNCOES}
                valor={funcao}
                aoMudar={(v) => {
                  setFuncao(v);
                  setPrevisto(null);
                }}
              />
            </View>
          )}

          {previsto !== null && (
            <Aviso tipo="aviso">
              Vai chegar a {previsto} {previsto === 1 ? 'pessoa' : 'pessoas'} com a app instalada.
            </Aviso>
          )}

          <View style={{ flexDirection: 'row', gap: espaco.s, marginTop: espaco.s }}>
            <View style={{ flex: 1 }}>
              <Botao titulo="Pré-ver" variante="secundario" aoCarregar={prever} desactivado={faltaAlvo} />
            </View>
            <View style={{ flex: 1 }}>
              <Botao titulo={aGuardar ? 'A enviar…' : 'Enviar'} aoCarregar={enviar} desactivado={!podeEnviar} />
            </View>
          </View>
        </Cartao>

        <Subtitulo>Avisos recentes</Subtitulo>
        {historico === null ? (
          <ACarregar />
        ) : historico.length === 0 ? (
          <Paragrafo suave>Ainda não enviaste nenhum aviso.</Paragrafo>
        ) : (
          historico.map((a) => (
            <Cartao key={a.id}>
              <Text style={{ fontWeight: '700', color: cores.texto }}>{a.titulo || 'Manda Bué'}</Text>
              <Text style={{ color: cores.texto }}>{a.corpo}</Text>
              <Text style={{ color: cores.textoSuave, fontSize: 13, marginTop: 4 }}>
                {rotuloPublico(a.publico)} · {a.total} {a.total === 1 ? 'pessoa' : 'pessoas'}
                {a.criado_por_nome ? ` · ${a.criado_por_nome}` : ''}
              </Text>
            </Cartao>
          ))
        )}
      </Ecra>
    </Guarda>
  );
}
