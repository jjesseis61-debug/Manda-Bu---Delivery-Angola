import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Switch, Text, View } from 'react-native';

import { FotoEditavel } from '@/components/FotoEditavel';
import { Guarda } from '@/components/Guarda';
import { LocalizacaoCozinha } from '@/components/LocalizacaoCozinha';
import { ACarregar, Aviso, Botao, Campo, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import {
  definirComissaoCozinha,
  definirConvidaCozinha,
  definirFotoCozinha,
  guardarCozinha,
  lerComissaoCozinha,
  lerCozinhas,
} from '@/lib/api';
import { mensagemErro, telefoneValido } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Cozinha } from '@/lib/tipos';

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

function Interruptor({ rotulo, valor, aoMudar }: { rotulo: string; valor: boolean; aoMudar: (v: boolean) => void }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
      <Text style={{ flex: 1 }}>{rotulo}</Text>
      <Switch thumbColor="#FFFFFF" value={valor} onValueChange={aoMudar} trackColor={{ true: cores.marca, false: cores.contorno }} />
    </View>
  );
}

/** Comissão e Convida desta cozinha (só quem gere a plataforma): base do "a receber pela cozinha" */
function ComissaoCozinha({ cozinhaId }: { cozinhaId: string }) {
  const [comissao, setComissao] = useState('');
  const [convida, setConvida] = useState('');
  const [msg, setMsg] = useState<{ tipo: 'erro' | 'sucesso'; texto: string } | null>(null);
  const [ocupado, setOcupado] = useState(false);
  useEffect(() => {
    lerComissaoCozinha(cozinhaId)
      .then((v) => {
        setComissao(String(v.comissao).replace('.', ','));
        setConvida(String(v.convida).replace('.', ','));
      })
      .catch(() => undefined);
  }, [cozinhaId]);
  const num = (t: string) => Number(t.replace(',', '.'));
  const nComissao = num(comissao);
  const nConvida = num(convida);
  const valido =
    comissao.trim() !== '' && convida.trim() !== '' && nComissao >= 0 && nComissao <= 50 && nConvida >= 0 && nConvida <= 100;
  const quem = nConvida <= 0 ? 'a plataforma paga tudo' : nConvida >= 100 ? 'a cozinha paga tudo' : `a cozinha paga ${convida}%, a plataforma o resto`;

  function guardar() {
    setOcupado(true);
    setMsg(null);
    Promise.all([definirComissaoCozinha(cozinhaId, nComissao), definirConvidaCozinha(cozinhaId, nConvida)])
      .then(() => setMsg({ tipo: 'sucesso', texto: 'Comissão e Convida guardados.' }))
      .catch((e) => setMsg({ tipo: 'erro', texto: mensagemErro(e) }))
      .finally(() => setOcupado(false));
  }

  return (
    <>
      <Subtitulo>Comissão e Convida e Ganha</Subtitulo>
      <Paragrafo suave>
        O relatório mostra «a receber pela cozinha» = vendas − comissão − a parte do Convida paga pela cozinha.
      </Paragrafo>
      <Campo rotulo="Comissão da plataforma (%)" value={comissao} keyboardType="decimal-pad" maxLength={5} onChangeText={setComissao} />
      <Text style={{ fontWeight: '700', color: cores.texto }}>Quem paga o desconto de convite e o saldo Convida?</Text>
      <Escolha
        opcoes={[
          { valor: '0', rotulo: 'Plataforma' },
          { valor: '100', rotulo: 'Cozinha' },
          { valor: 'outra', rotulo: 'Dividir (%)' },
        ]}
        valor={nConvida === 0 && convida.trim() !== '' ? '0' : nConvida === 100 ? '100' : 'outra'}
        aoMudar={(v) => setConvida(v === 'outra' ? '50' : v)}
      />
      <Campo rotulo="Parte paga pela cozinha (%)" value={convida} keyboardType="decimal-pad" maxLength={6} onChangeText={setConvida} />
      <Paragrafo suave>Agora: {quem}. Cozinhas com fluxo → plataforma; cozinhas sem fluxo → cozinha.</Paragrafo>
      {msg && <Aviso tipo={msg.tipo}>{msg.texto}</Aviso>}
      <Botao titulo="Guardar comissão e Convida" variante="secundario" aCarregar={ocupado} desactivado={!valido} aoCarregar={guardar} />
    </>
  );
}

/** O6. Perfil da cozinha (estado, história, consentimento, contactos). O cardápio está num ecrã à parte. */
export default function EditarCozinha() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { pode } = useSessao();
  const nova = id === 'nova';
  const [cozinha, setCozinha] = useState<Omit<Cozinha, 'id'> | null>(nova ? VAZIA : null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    if (nova) return;
    lerCozinhas()
      .then((cs) => {
        const c = cs.find((x) => x.id === id);
        if (!c) throw new Error('Cozinha não encontrada.');
        const { id: _id, ...resto } = c;
        setCozinha(resto);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [id, nova]);
  useEffect(carregar, [carregar]);

  function guardar() {
    if (!cozinha) return;
    const limpo = (t: string | null) => t?.trim() || null;
    const dados = {
      ...cozinha,
      telefone_publico: limpo(cozinha.telefone_publico),
      whatsapp_publico: limpo(cozinha.whatsapp_publico),
      horario_publico: limpo(cozinha.horario_publico),
    };
    setErro(null);
    setSucesso(null);
    setOcupado(true);
    (async () => {
      try {
        await guardarCozinha(nova ? dados : { ...dados, id });
        if (nova) router.back();
        else {
          setSucesso('Cozinha guardada.');
          carregar();
        }
      } catch (e) {
        setErro(mensagemErro(e));
      } finally {
        setOcupado(false);
      }
    })();
  }

  if (!cozinha) return <Guarda permissoes={['cozinhas.gerir', 'cozinha.perfil']}>{erro ? <Aviso tipo="erro">{erro}</Aviso> : <ACarregar />}</Guarda>;

  const contactosValidos = [cozinha.telefone_publico, cozinha.whatsapp_publico].every((t) => !t || telefoneValido(t));

  return (
    <Guarda permissoes={['cozinhas.gerir', 'cozinha.perfil']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
        <Campo rotulo="Nome" value={cozinha.nome} onChangeText={(t) => setCozinha({ ...cozinha, nome: t })} />
        <Campo rotulo="Responsável" value={cozinha.responsavel ?? ''} onChangeText={(t) => setCozinha({ ...cozinha, responsavel: t })} />
        <Campo rotulo="História (perfil público)" value={cozinha.historia ?? ''} multiline onChangeText={(t) => setCozinha({ ...cozinha, historia: t || null })} />
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
        <Campo rotulo="Telefone da cozinha" value={cozinha.telefone_publico ?? ''} keyboardType="phone-pad" maxLength={20} onChangeText={(t) => setCozinha({ ...cozinha, telefone_publico: t.trim() ? t : null })} />
        <Campo rotulo="WhatsApp da cozinha" value={cozinha.whatsapp_publico ?? ''} keyboardType="phone-pad" maxLength={20} onChangeText={(t) => setCozinha({ ...cozinha, whatsapp_publico: t.trim() ? t : null })} />
        <Campo rotulo="Horário da cozinha" value={cozinha.horario_publico ?? ''} maxLength={120} onChangeText={(t) => setCozinha({ ...cozinha, horario_publico: t.trim() ? t : null })} />
        {!contactosValidos && <Aviso>O telefone e o WhatsApp levam só algarismos (9 a 20), com + opcional.</Aviso>}
        <Botao
          titulo="Guardar cozinha"
          aCarregar={ocupado}
          desactivado={!cozinha.nome.trim() || !cozinha.responsavel?.trim() || !contactosValidos}
          aoCarregar={guardar}
        />

        {!nova && <LocalizacaoCozinha cozinhaId={id} />}
        {!nova && pode('plataforma.parametros') && <ComissaoCozinha cozinhaId={id} />}

        {!nova && (
          <>
            <Botao titulo="Gerir cardápio →" variante="secundario" aoCarregar={() => router.push({ pathname: '/cozinhas/[id]/cardapio', params: { id } })} />
            {pode('auditoria.ver') && (
              <Botao
                titulo="Histórico de alterações"
                variante="texto"
                aoCarregar={() => router.push({ pathname: '/cozinhas/historico', params: { cozinha: id } })}
              />
            )}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
