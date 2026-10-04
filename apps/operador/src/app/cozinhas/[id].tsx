import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Image, Switch, Text, View } from 'react-native';

import { FotoEditavel } from '@/components/FotoEditavel';
import { Guarda } from '@/components/Guarda';
import { LocalizacaoCozinha } from '@/components/LocalizacaoCozinha';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { definirFotoCozinha, definirFotoPrato, guardarCozinha, guardarPrato, lerCardapio, lerCozinhas, lerDosesCardapio } from '@/lib/api';
import { formatarKz, mensagemErro, telefoneValido } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { Cozinha, DosesPrato, PratoCardapio } from '@/lib/tipos';

const VAZIA: Omit<Cozinha, 'id'> = {
  nome: '',
  responsavel: '',
  foto_url: null,
  historia: null,
  estado: 'activa',
  consentimento_publico: false,
  telefone_publico: null,
  whatsapp_publico: null,
  horario_publico: null,
};

type PratoEditado = Omit<PratoCardapio, 'id' | 'preco' | 'ordem' | 'doses_dia'> & { id?: string; preco: string; ordem: string; doses: string };

function Interruptor({ rotulo, valor, aoMudar }: { rotulo: string; valor: boolean; aoMudar: (v: boolean) => void }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
      <Text style={{ flex: 1 }}>{rotulo}</Text>
      <Switch thumbColor="#FFFFFF" value={valor} onValueChange={aoMudar} trackColor={{ true: cores.marca, false: cores.contorno }} />
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
  const [doses, setDoses] = useState<Map<string, DosesPrato>>(new Map());
  const [categoriaNova, setCategoriaNova] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    if (nova) return;
    Promise.all([lerCozinhas(), lerCardapio(id), lerDosesCardapio(id).catch(() => [])])
      .then(([cs, ps, ds]) => {
        setDoses(new Map(ds.map((d) => [d.cardapio_id, d])));
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
    const limpo = (t: string | null) => t?.trim() || null;
    const dados = {
      ...cozinha,
      telefone_publico: limpo(cozinha.telefone_publico),
      whatsapp_publico: limpo(cozinha.whatsapp_publico),
      horario_publico: limpo(cozinha.horario_publico),
    };
    correr(async () => {
      await guardarCozinha(nova ? dados : { ...dados, id });
      if (nova) router.back();
      else carregar();
    }, 'Cozinha guardada.');
  }

  function guardarPratoEditado() {
    if (!prato) return;
    const { preco, ordem, doses: dosesTexto, ...resto } = prato;
    correr(async () => {
      await guardarPrato({ ...resto, preco: Number(preco), ordem: Number(ordem || 0), doses_dia: dosesTexto === '' ? null : Number(dosesTexto) });
      setPrato(null);
      carregar();
    }, 'Prato guardado.');
  }

  if (!cozinha) return <Guarda permissoes={['cozinhas.gerir']}>{erro ? <Aviso tipo="erro">{erro}</Aviso> : <ACarregar />}</Guarda>;

  const contactosValidos = [cozinha.telefone_publico, cozinha.whatsapp_publico].every((t) => !t || telefoneValido(t));
  // 0 Kz só para pratos montáveis cujo preço vem todo das opções (o servidor recusa-o sem opções obrigatórias)
  // Categorias que a cozinha já usa (escolher de uma lista evita secções repetidas no cardápio do cliente)
  const categorias = [...new Set(pratos.map((p) => p.categoria).filter((c): c is string => !!c))];
  const precoValido = prato !== null && /^\d+$/.test(prato.preco);

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
        {!nova && (
          <FotoEditavel
            tipo="cozinhas"
            id={id}
            url={cozinha.foto_url}
            aoGravar={async (url) => {
              await definirFotoCozinha(id, url);
              setCozinha({ ...cozinha, foto_url: url });
            }}
          />
        )}
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
        <Subtitulo>Contactos para os clientes</Subtitulo>
        <Paragrafo suave>Aparecem em Contactos e na página da cozinha. Deixa em branco o que não quiseres mostrar.</Paragrafo>
        <Campo
          rotulo="Telefone da cozinha"
          value={cozinha.telefone_publico ?? ''}
          keyboardType="phone-pad"
          maxLength={20}
          onChangeText={(t) => setCozinha({ ...cozinha, telefone_publico: t.trim() ? t : null })}
        />
        <Campo
          rotulo="WhatsApp da cozinha"
          value={cozinha.whatsapp_publico ?? ''}
          keyboardType="phone-pad"
          maxLength={20}
          onChangeText={(t) => setCozinha({ ...cozinha, whatsapp_publico: t.trim() ? t : null })}
        />
        <Campo
          rotulo="Horário da cozinha"
          value={cozinha.horario_publico ?? ''}
          maxLength={120}
          onChangeText={(t) => setCozinha({ ...cozinha, horario_publico: t.trim() ? t : null })}
        />
        {!contactosValidos && <Aviso>O telefone e o WhatsApp levam só algarismos (9 a 20), com + opcional.</Aviso>}
        <Botao
          titulo="Guardar cozinha"
          aCarregar={ocupado}
          desactivado={!cozinha.nome.trim() || !cozinha.responsavel?.trim() || !contactosValidos}
          aoCarregar={guardar}
        />

        {!nova && <LocalizacaoCozinha cozinhaId={id} />}

        {!nova && (
          <>
            <Subtitulo>Cardápio</Subtitulo>
            {pratos.length === 0 && <Paragrafo suave>Sem pratos.</Paragrafo>}
            {pratos.map((p) => (
              <Cartao key={p.id}>
                <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: espaco.s }}>
                  {p.foto_url ? (
                    <Image source={{ uri: p.foto_url }} style={{ width: 44, height: 44, borderRadius: 6 }} accessibilityLabel={p.nome} />
                  ) : null}
                  <Text style={{ fontWeight: '700', flex: 1, color: p.disponivel ? cores.texto : cores.textoSuave }}>
                    {p.nome}
                    {p.do_dia ? ' · do dia' : ''}
                    {p.disponivel ? '' : ' · indisponível'}
                    {doses.has(p.id) ? (doses.get(p.id)!.restantes === 0 ? ' · esgotado hoje' : ` · restam ${doses.get(p.id)!.restantes} de ${doses.get(p.id)!.lancadas}`) : ''}
                  </Text>
                  <Text>{formatarKz(p.preco)}</Text>
                </View>
                <View style={{ flexDirection: 'row', gap: espaco.s }}>
                  <Botao
                    titulo="Editar"
                    variante="texto"
                    aoCarregar={() => {
                      const { doses_dia: _d, ...resto } = p;
                      // As doses de hoje: o que resta (as de dias anteriores já não valem)
                      setPrato({ ...resto, preco: String(p.preco), ordem: String(p.ordem), doses: doses.has(p.id) ? String(doses.get(p.id)!.restantes) : '' });
                      setCategoriaNova(false);
                    }}
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
                  <Campo
                    rotulo="Preço (Kz)"
                    value={prato.preco}
                    keyboardType="number-pad"
                    onChangeText={(t) => setPrato({ ...prato, preco: t.replace(/\D/g, '') })}
                  />
                  {prato.preco === '0' && (
                    <Aviso>Preço 0: só para pratos montáveis em que o preço vem das opções obrigatórias (em Opções).</Aviso>
                  )}
                  <Campo
                    rotulo="Ordem no cardápio"
                    value={prato.ordem}
                    keyboardType="number-pad"
                    onChangeText={(t) => setPrato({ ...prato, ordem: t.replace(/\D/g, '') })}
                  />
                  <Campo
                    rotulo="Doses disponíveis hoje (em branco = sem limite)"
                    value={prato.doses}
                    keyboardType="number-pad"
                    onChangeText={(t) => setPrato({ ...prato, doses: t.replace(/\D/g, '') })}
                  />
                  <Paragrafo suave>Cada pedido gasta doses e um cancelado devolve-as. A 0 o prato fica esgotado na app; amanhã o limite deixa de valer.</Paragrafo>
                  <Interruptor rotulo="Disponível" valor={prato.disponivel} aoMudar={(v) => setPrato({ ...prato, disponivel: v })} />
                  <Interruptor rotulo="Prato do dia" valor={prato.do_dia} aoMudar={(v) => setPrato({ ...prato, do_dia: v })} />
                  {prato.id ? (
                    <FotoEditavel
                      tipo="pratos"
                      id={prato.id}
                      url={prato.foto_url}
                      aoGravar={async (url) => {
                        await definirFotoPrato(prato.id as string, url);
                        setPrato({ ...prato, foto_url: url });
                        carregar();
                      }}
                    />
                  ) : (
                    <Paragrafo suave>Guarda o prato para lhe juntar a foto.</Paragrafo>
                  )}
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
                    doses: '',
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
