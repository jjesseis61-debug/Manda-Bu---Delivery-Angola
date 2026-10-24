import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { FotoEditavel } from '@/components/FotoEditavel';
import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import {
  arquivarReceita,
  avisarNovaReceita,
  definirFotoReceita,
  gerarRascunhoReceita,
  guardarReceita,
  lerCozinhas,
  lerReceitasGerir,
  publicarReceita,
} from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { Cozinha, Receita } from '@/lib/tipos';

const ESTADO: Record<Receita['estado'], string> = {
  rascunho: 'Rascunho',
  publicada: 'Publicada',
  arquivada: 'Arquivada',
};

type Edicao = { id?: string; titulo: string; resumo: string; corpo: string; cozinha_id: string; foto_url: string | null };
const VAZIA: Edicao = { titulo: '', resumo: '', corpo: '', cozinha_id: '', foto_url: null };

export default function Receitas() {
  const [lista, setLista] = useState<Receita[] | null>(null);
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [edicao, setEdicao] = useState<Edicao | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [tema, setTema] = useState('');
  const [aGerar, setAGerar] = useState(false);
  const [aviso, setAviso] = useState<string | null>(null);

  const carregar = useCallback(() => {
    Promise.all([lerReceitasGerir(), lerCozinhas()])
      .then(([rs, cs]) => {
        setLista(rs);
        setCozinhas(cs);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, []);

  useFocusEffect(useCallback(() => carregar(), [carregar]));

  async function guardar() {
    if (!edicao) return;
    if (!edicao.titulo.trim() || !edicao.corpo.trim()) {
      setErro('A receita precisa de título e de texto.');
      return;
    }
    setErro(null);
    setOcupado(true);
    try {
      const id = await guardarReceita({
        id: edicao.id,
        titulo: edicao.titulo.trim(),
        resumo: edicao.resumo.trim() || null,
        corpo: edicao.corpo.trim(),
        cozinha_id: edicao.cozinha_id || null,
      });
      // Fica em edição com o id, para já poder anexar a foto
      setEdicao({ ...edicao, id });
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  async function gerarComIA() {
    if (!tema.trim()) {
      setErro('Escreve um tema (ex.: Calulu de peixe).');
      return;
    }
    setErro(null);
    setAGerar(true);
    try {
      const id = await gerarRascunhoReceita(tema.trim());
      const rs = await lerReceitasGerir();
      setLista(rs);
      setTema('');
      const r = rs.find((x) => x.id === id);
      if (r) setEdicao({ id: r.id, titulo: r.titulo, resumo: r.resumo ?? '', corpo: r.corpo, cozinha_id: r.cozinha_id ?? '', foto_url: r.foto_url });
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAGerar(false);
    }
  }

  async function accao(fn: () => Promise<void>) {
    setErro(null);
    setOcupado(true);
    try {
      await fn();
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  if (!lista) return <ACarregar />;

  // ---- Editor ----
  if (edicao) {
    const opcoesCozinha = [{ valor: '', rotulo: 'Sem cozinha (sem botão de pedir)' }, ...cozinhas.map((c) => ({ valor: c.id, rotulo: c.nome }))];
    return (
      <Guarda permissoes={['receitas.gerir']}>
        <Ecra>
          <Subtitulo>{edicao.id ? 'Editar receita' : 'Nova receita'}</Subtitulo>
          {erro && <Aviso tipo="erro">{erro}</Aviso>}
          <Campo rotulo="Título" value={edicao.titulo} onChangeText={(t) => setEdicao({ ...edicao, titulo: t })} placeholder="Ex.: Calulu de peixe" />
          <Campo rotulo="Resumo (1 linha)" value={edicao.resumo} onChangeText={(t) => setEdicao({ ...edicao, resumo: t })} placeholder="Aparece na lista" />
          <Campo
            rotulo="Receita (ingredientes e passos)"
            value={edicao.corpo}
            onChangeText={(t) => setEdicao({ ...edicao, corpo: t })}
            placeholder="Ingredientes, passos e uma nota sobre o prato"
            multiline
            numberOfLines={10}
            style={{ minHeight: 160, textAlignVertical: 'top' }}
          />
          <Text style={{ fontWeight: '700' }}>Quem faz por ti (CTA)</Text>
          <Escolha opcoes={opcoesCozinha} valor={edicao.cozinha_id} aoMudar={(v) => setEdicao({ ...edicao, cozinha_id: v })} />
          <Botao titulo={edicao.id ? 'Guardar alterações' : 'Guardar (para poder pôr foto)'} aCarregar={ocupado} aoCarregar={guardar} />
          {edicao.id ? (
            <FotoEditavel
              tipo="receitas"
              id={edicao.id}
              url={edicao.foto_url}
              aoGravar={async (u) => {
                await definirFotoReceita(edicao.id as string, u);
                setEdicao({ ...edicao, foto_url: u });
                carregar();
              }}
            />
          ) : (
            <Paragrafo suave>Guarda a receita primeiro para lhe adicionares uma foto.</Paragrafo>
          )}
          <Botao titulo="Voltar à lista" variante="texto" desactivado={ocupado} aoCarregar={() => setEdicao(null)} />
        </Ecra>
      </Guarda>
    );
  }

  // ---- Lista ----
  return (
    <Guarda permissoes={['receitas.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {aviso && <Aviso>{aviso}</Aviso>}
        <Botao titulo="Nova receita" aoCarregar={() => setEdicao(VAZIA)} />
        <Cartao>
          <Campo rotulo="Gerar rascunho com IA" value={tema} onChangeText={setTema} placeholder="Tema ou prato (ex.: Calulu de peixe)" />
          <Botao titulo="Gerar rascunho com IA" variante="secundario" aCarregar={aGerar} aoCarregar={gerarComIA} />
          <Paragrafo suave>O Claude escreve um rascunho; tu revês e publicas.</Paragrafo>
        </Cartao>
        {lista.length === 0 && <Paragrafo suave>Ainda não há receitas. Cria a primeira — aparece aos clientes quando a publicares (e com o interruptor «receitas» ligado).</Paragrafo>}
        {lista.map((r) => (
          <Cartao key={r.id}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
              <Text style={{ fontWeight: '700', fontSize: 15, flexShrink: 1 }}>{r.titulo}</Text>
              <Text style={{ color: r.estado === 'publicada' ? cores.marca : cores.textoSuave, fontWeight: '600' }}>{ESTADO[r.estado]}</Text>
            </View>
            {r.resumo ? <Text style={{ color: cores.textoSuave }}>{r.resumo}</Text> : null}
            <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap', marginTop: espaco.s }}>
              <View style={{ flex: 1 }}>
                <Botao
                  titulo="Editar"
                  variante="leve"
                  desactivado={ocupado}
                  aoCarregar={() => setEdicao({ id: r.id, titulo: r.titulo, resumo: r.resumo ?? '', corpo: r.corpo, cozinha_id: r.cozinha_id ?? '', foto_url: r.foto_url })}
                />
              </View>
              <View style={{ flex: 1 }}>
                <Botao
                  titulo={r.estado === 'publicada' ? 'Repor a rascunho' : 'Publicar'}
                  variante="secundario"
                  desactivado={ocupado}
                  aoCarregar={() => accao(() => publicarReceita(r.id, r.estado !== 'publicada'))}
                />
              </View>
            </View>
            {r.estado === 'publicada' && (
              <Botao
                titulo="Avisar clientes"
                variante="texto"
                desactivado={ocupado}
                aoCarregar={() =>
                  accao(async () => {
                    const n = await avisarNovaReceita(r.id);
                    setAviso(`Aviso enviado a ${n} ${n === 1 ? 'cliente' : 'clientes'}.`);
                  })
                }
              />
            )}
            {r.estado !== 'arquivada' && (
              <Botao titulo="Arquivar" variante="texto" desactivado={ocupado} aoCarregar={() => accao(() => arquivarReceita(r.id))} />
            )}
          </Cartao>
        ))}
      </Ecra>
    </Guarda>
  );
}
