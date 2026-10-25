import { useEffect, useRef, useState } from 'react';
import { Switch, Text, View } from 'react-native';

import { definirFotoPrato, guardarPrato } from '@/lib/api';
import { mensagemErro, textoJanela } from '@/lib/formatar';
import { enviarFotoPublica } from '@/lib/fotos';
import { cores, espaco } from '@/lib/tema';
import type { PratoCardapio } from '@/lib/tipos';

import { FotoEditavel } from './FotoEditavel';
import { Aviso, Botao, Campo, Escolha, Paragrafo, Subtitulo } from './ui';

type PratoEditado = Omit<PratoCardapio, 'id' | 'preco' | 'ordem' | 'doses_dia'> & {
  id?: string;
  preco: string;
  ordem: string;
  doses: string;
};

function Interruptor({ rotulo, valor, aoMudar }: { rotulo: string; valor: boolean; aoMudar: (v: boolean) => void }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
      <Text style={{ flex: 1 }}>{rotulo}</Text>
      <Switch thumbColor="#FFFFFF" value={valor} onValueChange={aoMudar} trackColor={{ true: cores.marca, false: cores.contorno }} />
    </View>
  );
}

function paraEditado(p: PratoCardapio): PratoEditado {
  const { preco, ordem, doses_dia, ...resto } = p;
  return { ...resto, preco: String(preco), ordem: String(ordem), doses: doses_dia == null ? '' : String(doses_dia) };
}

function pratoNovo(cozinhaId: string): PratoEditado {
  return { cozinha_id: cozinhaId, nome: '', descricao: null, categoria: null, preco: '', disponivel: true, do_dia: false, visivel_online: true, ordem: '0', doses: '', disponivel_de: null, disponivel_ate: null };
}

const HORA_OK = /^([01]?\d|2[0-3]):[0-5]\d$/;

/**
 * Agendamento da disponibilidade de um prato: preparar hoje o cardápio de amanhã.
 * Sem dependência nativa (presets + hora em texto). Início por dia + hora; fim por duração,
 * fim do dia, ou sem fim. Devolve as datas em ISO (hora local do aparelho — Angola, UTC+1).
 */
function Agendamento({ de, ate, aoMudar }: { de: string | null; ate: string | null; aoMudar: (de: string | null, ate: string | null) => void }) {
  const [ligado, setLigado] = useState(!!(de || ate));
  const [dia, setDia] = useState<'hoje' | 'amanha' | 'depois'>('amanha');
  const [hora, setHora] = useState('11:00');
  const [fim, setFim] = useState<'sem' | '2' | '3' | '4' | 'dia'>('sem');
  const iniciado = useRef(false);

  // Repõe os controlos a partir de um agendamento já existente (uma vez).
  useEffect(() => {
    if (iniciado.current) return;
    iniciado.current = true;
    if (de) {
      const d = new Date(de);
      const meiaHoje = new Date(); meiaHoje.setHours(0, 0, 0, 0);
      const meiaD = new Date(d); meiaD.setHours(0, 0, 0, 0);
      const off = Math.round((meiaD.getTime() - meiaHoje.getTime()) / 86400000);
      setDia(off <= 0 ? 'hoje' : off === 1 ? 'amanha' : 'depois');
      setHora(`${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`);
      if (ate) {
        const a = new Date(ate);
        const h = (a.getTime() - d.getTime()) / 3600000;
        setFim(Math.abs(h - 2) < 0.02 ? '2' : Math.abs(h - 3) < 0.02 ? '3' : Math.abs(h - 4) < 0.02 ? '4'
          : a.getHours() === 23 && a.getMinutes() === 59 ? 'dia' : 'sem');
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function recompor(l: boolean, d: typeof dia, h: string, f: typeof fim) {
    if (!l || !HORA_OK.test(h)) { aoMudar(null, null); return; }
    const base = new Date();
    base.setDate(base.getDate() + (d === 'hoje' ? 0 : d === 'amanha' ? 1 : 2));
    const [hh, mm] = h.split(':').map(Number);
    base.setHours(hh, mm, 0, 0);
    let ateDate: Date | null = null;
    if (f === '2' || f === '3' || f === '4') { ateDate = new Date(base); ateDate.setHours(ateDate.getHours() + Number(f)); }
    else if (f === 'dia') { ateDate = new Date(base); ateDate.setHours(23, 59, 0, 0); }
    aoMudar(base.toISOString(), ateDate ? ateDate.toISOString() : null);
  }

  const preview = textoJanela(de, ate);

  return (
    <View style={{ gap: espaco.s }}>
      <Interruptor
        rotulo="Agendar disponibilidade"
        valor={ligado}
        aoMudar={(v) => { setLigado(v); recompor(v, dia, hora, fim); }}
      />
      {ligado && (
        <>
          <Text style={{ color: cores.textoSuave }}>Fica disponível em</Text>
          <Escolha
            opcoes={[{ valor: 'hoje', rotulo: 'Hoje' }, { valor: 'amanha', rotulo: 'Amanhã' }, { valor: 'depois', rotulo: 'Depois de amanhã' }]}
            valor={dia}
            aoMudar={(v) => { setDia(v); recompor(ligado, v, hora, fim); }}
          />
          <Campo
            rotulo="Hora (HH:MM)"
            value={hora}
            keyboardType="numbers-and-punctuation"
            placeholder="11:00"
            onChangeText={(t) => { setHora(t); recompor(ligado, dia, t, fim); }}
          />
          <Text style={{ color: cores.textoSuave }}>Fica disponível durante</Text>
          <Escolha
            opcoes={[
              { valor: 'sem', rotulo: 'Sem fim' }, { valor: '2', rotulo: '2 h' }, { valor: '3', rotulo: '3 h' },
              { valor: '4', rotulo: '4 h' }, { valor: 'dia', rotulo: 'Até fim do dia' },
            ]}
            valor={fim}
            aoMudar={(v) => { setFim(v); recompor(ligado, dia, hora, v); }}
          />
          {!HORA_OK.test(hora) && <Aviso tipo="erro">Escreve a hora no formato HH:MM (ex.: 11:00).</Aviso>}
          {preview && <Paragrafo suave>{preview}</Paragrafo>}
        </>
      )}
    </View>
  );
}

/**
 * Editor completo de um prato (nome, preço, categoria, foto, interruptores). Pensado para um modal.
 * As doses só são editáveis aqui pelo admin principal ou num prato novo (lançamento inicial);
 * para o operador normal, as doses de um prato já existente mexem-se no cartão (só acrescentar).
 */
export function EditorPrato({
  cozinhaId,
  pratoInicial,
  categorias,
  ehAdmin,
  aoGuardado,
  aoFechar,
}: {
  cozinhaId: string;
  pratoInicial: PratoCardapio | null;
  categorias: string[];
  ehAdmin: boolean;
  aoGuardado: () => void;
  aoFechar: () => void;
}) {
  const [prato, setPrato] = useState<PratoEditado>(pratoInicial ? paraEditado(pratoInicial) : pratoNovo(cozinhaId));
  const [categoriaNova, setCategoriaNova] = useState(false);
  const [fotoLocal, setFotoLocal] = useState<string | null>(null); // foto escolhida antes de criar o prato
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const novo = !prato.id;
  const mostrarDoses = novo || ehAdmin; // operador não mexe nas doses de um prato já existente
  const precoValido = /^\d+$/.test(prato.preco);

  async function guardar() {
    setErro(null);
    setOcupado(true);
    try {
      const { preco, ordem, doses, ...resto } = prato;
      // Operador a editar um prato existente: as doses ficam como estavam (mexe-as no cartão).
      const doses_dia = mostrarDoses ? (doses === '' ? null : Number(doses)) : (pratoInicial?.doses_dia ?? null);
      const id = await guardarPrato({ ...resto, preco: Number(preco), ordem: Number(ordem || 0), doses_dia });
      // Prato novo com foto escolhida: cria primeiro, depois envia a foto para o id novo.
      if (!prato.id && fotoLocal) {
        const nova = await enviarFotoPublica('pratos', id, fotoLocal);
        await definirFotoPrato(id, nova);
      }
      aoGuardado();
    } catch (e) {
      setErro(mensagemErro(e));
      setOcupado(false);
    }
  }

  return (
    <View style={{ gap: espaco.s }}>
      <Subtitulo>{novo ? 'Novo prato' : 'Editar prato'}</Subtitulo>
      <Campo rotulo="Nome do prato" value={prato.nome} onChangeText={(t) => setPrato({ ...prato, nome: t })} />
      <Campo rotulo="Descrição" value={prato.descricao ?? ''} onChangeText={(t) => setPrato({ ...prato, descricao: t || null })} />
      <Text style={{ color: cores.textoSuave }}>Categoria: divide o cardápio em secções na app do cliente (ex.: Pratos, Bebidas).</Text>
      {categorias.length > 0 && (
        <Escolha
          opcoes={[
            ...categorias.map((c) => ({ valor: c, rotulo: c })),
            { valor: '__nova', rotulo: 'Outra…' },
            { valor: '__nenhuma', rotulo: 'Sem categoria' },
          ]}
          valor={categoriaNova ? '__nova' : (prato.categoria ?? '__nenhuma')}
          aoMudar={(v) => {
            setCategoriaNova(v === '__nova');
            setPrato({ ...prato, categoria: v === '__nova' || v === '__nenhuma' ? null : v });
          }}
        />
      )}
      {(categoriaNova || categorias.length === 0 || (!!prato.categoria && !categorias.includes(prato.categoria))) && (
        <Campo rotulo="Nova categoria" value={prato.categoria ?? ''} maxLength={40} onChangeText={(t) => setPrato({ ...prato, categoria: t || null })} />
      )}
      <Campo rotulo="Preço (Kz)" value={prato.preco} keyboardType="number-pad" onChangeText={(t) => setPrato({ ...prato, preco: t.replace(/\D/g, '') })} />
      {prato.preco === '0' && <Aviso>Preço 0: só para pratos montáveis em que o preço vem das opções obrigatórias (em Opções).</Aviso>}
      <Campo rotulo="Ordem no cardápio" value={prato.ordem} keyboardType="number-pad" onChangeText={(t) => setPrato({ ...prato, ordem: t.replace(/\D/g, '') })} />
      {mostrarDoses ? (
        <>
          <Campo
            rotulo="Doses de hoje (em branco = sem limite)"
            value={prato.doses}
            keyboardType="number-pad"
            onChangeText={(t) => setPrato({ ...prato, doses: t.replace(/\D/g, '') })}
          />
          <Paragrafo suave>
            {novo
              ? 'Quantas doses tens para hoje. Cada pedido gasta doses; a 0 fica esgotado na app.'
              : 'Como administrador podes corrigir as doses de hoje (incluindo reduzir).'}
          </Paragrafo>
        </>
      ) : (
        <Paragrafo suave>As doses de hoje mexem-se no cartão do prato (só acrescentar).</Paragrafo>
      )}
      <Interruptor rotulo="Disponível" valor={prato.disponivel} aoMudar={(v) => setPrato({ ...prato, disponivel: v })} />
      <Interruptor rotulo="Prato do dia" valor={prato.do_dia} aoMudar={(v) => setPrato({ ...prato, do_dia: v })} />
      <Interruptor rotulo="Visível online (desligar = só feira)" valor={prato.visivel_online ?? true} aoMudar={(v) => setPrato({ ...prato, visivel_online: v })} />
      <Agendamento
        de={prato.disponivel_de ?? null}
        ate={prato.disponivel_ate ?? null}
        aoMudar={(de, ate) => setPrato({ ...prato, disponivel_de: de, disponivel_ate: ate })}
      />
      {prato.id ? (
        <FotoEditavel
          tipo="pratos"
          id={prato.id}
          url={prato.foto_url}
          aoGravar={async (url) => {
            await definirFotoPrato(prato.id as string, url);
            setPrato({ ...prato, foto_url: url });
          }}
        />
      ) : (
        <FotoEditavel tipo="pratos" localUri={fotoLocal} aoEscolherLocal={setFotoLocal} />
      )}
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Botao titulo="Guardar prato" aCarregar={ocupado} desactivado={!prato.nome.trim() || !precoValido} aoCarregar={guardar} />
      <Botao titulo="Cancelar" variante="texto" aoCarregar={aoFechar} />
    </View>
  );
}
