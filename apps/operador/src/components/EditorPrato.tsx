import { useState } from 'react';
import { Switch, Text, View } from 'react-native';

import { definirFotoPrato, guardarPrato } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
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
      {!novo && <Paragrafo suave>Para agendar horários (ex.: Seg/Qua 08–11), usa &quot;Horários&quot; no cartão do prato.</Paragrafo>}
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
