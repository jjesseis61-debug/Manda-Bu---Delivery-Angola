import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Switch, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { LocalizacaoCozinha } from '@/components/LocalizacaoCozinha';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { guardarCozinha, guardarPrato, lerCardapio, lerCozinhas } from '@/lib/api';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { Cozinha, PratoCardapio } from '@/lib/tipos';

const VAZIA: Omit<Cozinha, 'id'> = {
  nome: '',
  responsavel: '',
  foto_url: null,
  historia: null,
  estado: 'activa',
  consentimento_publico: false,
};

type PratoEditado = Omit<PratoCardapio, 'id' | 'preco' | 'ordem'> & { id?: string; preco: string; ordem: string };

function Interruptor({ rotulo, valor, aoMudar }: { rotulo: string; valor: boolean; aoMudar: (v: boolean) => void }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
      <Text style={{ flex: 1 }}>{rotulo}</Text>
      <Switch value={valor} onValueChange={aoMudar} trackColor={{ true: cores.marca, false: cores.linha }} />
    </View>
  );
}

/** O6. Perfil da cozinha (estado, história, consentimento) e cardápio. Tudo fica na auditoria. */
export default function EditarCozinha() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const nova = id === 'nova';
  const [cozinha, setCozinha] = useState<Omit<Cozinha, 'id'> | null>(nova ? VAZIA : null);
  const [pratos, setPratos] = useState<PratoCardapio[]>([]);
  const [prato, setPrato] = useState<PratoEditado | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    if (nova) return;
    Promise.all([lerCozinhas(), lerCardapio(id)])
      .then(([cs, ps]) => {
        const c = cs.find((x) => x.id === id);
        if (!c) throw new Error('Cozinha não encontrada.');
        const { id: _id, ...resto } = c;
        setCozinha(resto);
        setPratos(ps);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [id, nova]);
  useEffect(carregar, [carregar]);

  async function correr(f: () => Promise<void>, mensagem: string) {
    setErro(null);
    setSucesso(null);
    setOcupado(true);
    try {
      await f();
      setSucesso(mensagem);
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  function guardar() {
    if (!cozinha) return;
    correr(async () => {
      await guardarCozinha(nova ? cozinha : { ...cozinha, id });
      if (nova) router.back();
      else carregar();
    }, 'Cozinha guardada.');
  }

  function guardarPratoEditado() {
    if (!prato) return;
    const { preco, ordem, ...resto } = prato;
    correr(async () => {
      await guardarPrato({ ...resto, preco: Number(preco), ordem: Number(ordem || 0) });
      setPrato(null);
      carregar();
    }, 'Prato guardado.');
  }

  if (!cozinha) return <Guarda permissoes={['cozinhas.gerir']}>{erro ? <Aviso tipo="erro">{erro}</Aviso> : <ACarregar />}</Guarda>;

  const precoValido = prato !== null && /^\d+$/.test(prato.preco) && Number(prato.preco) > 0;

  return (
    <Guarda permissoes={['cozinhas.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
        <Campo rotulo="Nome" value={cozinha.nome} onChangeText={(t) => setCozinha({ ...cozinha, nome: t })} />
        <Campo rotulo="Responsável" value={cozinha.responsavel ?? ''} onChangeText={(t) => setCozinha({ ...cozinha, responsavel: t })} />
        <Campo
          rotulo="História (perfil público)"
          value={cozinha.historia ?? ''}
          multiline
          onChangeText={(t) => setCozinha({ ...cozinha, historia: t || null })}
        />
        <Campo
          rotulo="Endereço da foto"
          value={cozinha.foto_url ?? ''}
          autoCapitalize="none"
          onChangeText={(t) => setCozinha({ ...cozinha, foto_url: t || null })}
        />
        <Escolha
          opcoes={[
            { valor: 'activa', rotulo: 'Activa' },
            { valor: 'pausada', rotulo: 'Pausada' },
            { valor: 'inactiva', rotulo: 'Inactiva' },
          ]}
          valor={cozinha.estado}
          aoMudar={(v) => setCozinha({ ...cozinha, estado: v })}
        />
        <Interruptor
          rotulo="A responsável autorizou o perfil público (nome, foto e história)"
          valor={cozinha.consentimento_publico}
          aoMudar={(v) => setCozinha({ ...cozinha, consentimento_publico: v })}
        />
        <Botao titulo="Guardar cozinha" aCarregar={ocupado} desactivado={!cozinha.nome.trim() || !cozinha.responsavel?.trim()} aoCarregar={guardar} />

        {!nova && <LocalizacaoCozinha cozinhaId={id} />}

        {!nova && (
          <>
            <Subtitulo>Cardápio</Subtitulo>
            {pratos.length === 0 && <Paragrafo suave>Sem pratos.</Paragrafo>}
            {pratos.map((p) => (
              <Cartao key={p.id}>
                <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                  <Text style={{ fontWeight: '700', color: p.disponivel ? cores.texto : cores.textoSuave }}>
                    {p.nome}
                    {p.do_dia ? ' · do dia' : ''}
                    {p.disponivel ? '' : ' · indisponível'}
                  </Text>
                  <Text>{formatarKz(p.preco)}</Text>
                </View>
                <View style={{ flexDirection: 'row', gap: espaco.s }}>
                  <Botao
                    titulo="Editar"
                    variante="texto"
                    aoCarregar={() => setPrato({ ...p, preco: String(p.preco), ordem: String(p.ordem) })}
                  />
                  {/* I9: grupos de opções do prato montável */}
                  <Botao
                    titulo="Opções"
                    variante="texto"
                    aoCarregar={() => router.push({ pathname: '/cozinhas/opcoes/[prato]', params: { prato: p.id, nome: p.nome } })}
                  />
                </View>
              </Cartao>
            ))}
            {prato ? (
              <Cartao>
                <View style={{ gap: espaco.s }}>
                  <Campo rotulo="Nome do prato" value={prato.nome} onChangeText={(t) => setPrato({ ...prato, nome: t })} />
                  <Campo rotulo="Descrição" value={prato.descricao ?? ''} onChangeText={(t) => setPrato({ ...prato, descricao: t || null })} />
                  <Campo rotulo="Categoria" value={prato.categoria ?? ''} onChangeText={(t) => setPrato({ ...prato, categoria: t || null })} />
                  <Campo
                    rotulo="Preço (Kz)"
                    value={prato.preco}
                    keyboardType="number-pad"
                    onChangeText={(t) => setPrato({ ...prato, preco: t.replace(/\D/g, '') })}
                  />
                  <Campo
                    rotulo="Ordem no cardápio"
                    value={prato.ordem}
                    keyboardType="number-pad"
                    onChangeText={(t) => setPrato({ ...prato, ordem: t.replace(/\D/g, '') })}
                  />
                  <Interruptor rotulo="Disponível" valor={prato.disponivel} aoMudar={(v) => setPrato({ ...prato, disponivel: v })} />
                  <Interruptor rotulo="Prato do dia" valor={prato.do_dia} aoMudar={(v) => setPrato({ ...prato, do_dia: v })} />
                  <Botao
                    titulo="Guardar prato"
                    aCarregar={ocupado}
                    desactivado={!prato.nome.trim() || !precoValido}
                    aoCarregar={guardarPratoEditado}
                  />
                  <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setPrato(null)} />
                </View>
              </Cartao>
            ) : (
              <Botao
                titulo="Novo prato"
                variante="secundario"
                aoCarregar={() =>
                  setPrato({
                    cozinha_id: id,
                    nome: '',
                    descricao: null,
                    categoria: null,
                    preco: '',
                    disponivel: true,
                    do_dia: false,
                    ordem: '0',
                  })
                }
              />
            )}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
