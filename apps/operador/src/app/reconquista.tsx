import { useFocusEffect } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { Linking, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import {
  clientesInativos,
  clientesInativosResumo,
  enviarCampanhaReconquista,
  lerZonasEntrega,
  listarCampanhasReconquista,
} from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { CampanhaReconquista, ClienteInativo, ResumoInativos, ZonaEntrega } from '@/lib/tipos';

// Escalões por recência, com a mensagem base desenhada à Bandura: autoeficácia ("é rápido, está tudo
// onde deixou"), modelo/pertença ("muitos voltaram", "sabor de casa") e expectativa de resultado.
const ESCALOES = [
  {
    valor: 'arrefecer',
    rotulo: 'A arrefecer (30–59 dias)',
    diasMin: 30,
    diasMax: 59 as number | null,
    titulo: 'O seu prato preferido espera por si',
    corpo: 'Sentimos a sua falta! Repetir o último pedido é rápido — está tudo onde deixou. 🍲',
  },
  {
    valor: 'frio',
    rotulo: 'Frio (60–89 dias)',
    diasMin: 60,
    diasMax: 89 as number | null,
    titulo: 'Há novidades na Manda Bué',
    corpo: 'Muitos clientes voltaram esta semana — volte também. É fácil e rápido, e temos algo para si no próximo pedido.',
  },
  {
    valor: 'adormecido',
    rotulo: 'Adormecido (90+ dias)',
    diasMin: 90,
    diasMax: null as number | null,
    titulo: 'Preparámos algo só para si',
    corpo: 'Já passou algum tempo! Volte ao sabor de casa — tratamos de tudo. Tem uma oferta de regresso à sua espera.',
  },
];

/** Reconquista: clientes que pararam de comprar — lista (com telefone), campanha de regresso e resultados. */
export default function Reconquista() {
  const [resumo, setResumo] = useState<ResumoInativos | null>(null);
  const [zonas, setZonas] = useState<ZonaEntrega[]>([]);
  const [historico, setHistorico] = useState<CampanhaReconquista[] | null>(null);

  const [escalao, setEscalao] = useState(ESCALOES[0].valor);
  const [zonaId, setZonaId] = useState<string | null>(null);
  const [titulo, setTitulo] = useState(ESCALOES[0].titulo);
  const [corpo, setCorpo] = useState(ESCALOES[0].corpo);
  const [controlo, setControlo] = useState('15');

  const [lista, setLista] = useState<ClienteInativo[] | null>(null);
  const [aListar, setAListar] = useState(false);
  const [aGuardar, setAGuardar] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);

  const def = useMemo(() => ESCALOES.find((e) => e.valor === escalao) ?? ESCALOES[0], [escalao]);

  const recarregar = useCallback(() => {
    clientesInativosResumo().then(setResumo).catch((e) => setErro(mensagemErro(e)));
    listarCampanhasReconquista().then(setHistorico).catch(() => undefined);
  }, []);

  useFocusEffect(
    useCallback(() => {
      recarregar();
      lerZonasEntrega().then(setZonas).catch(() => undefined);
    }, [recarregar]),
  );

  const mudarEscalao = (v: string) => {
    const e = ESCALOES.find((x) => x.valor === v) ?? ESCALOES[0];
    setEscalao(v);
    setTitulo(e.titulo);
    setCorpo(e.corpo);
    setLista(null);
    setSucesso(null);
  };

  async function verLista() {
    setErro(null);
    setAListar(true);
    try {
      setLista(await clientesInativos(def.diasMin, def.diasMax, zonaId));
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAListar(false);
    }
  }

  async function enviar() {
    if (corpo.trim().length === 0) return;
    setAGuardar(true);
    setErro(null);
    setSucesso(null);
    try {
      const pct = controlo.trim() === '' ? null : Math.max(0, Math.min(50, parseInt(controlo, 10) || 0));
      const r = await enviarCampanhaReconquista({
        diasMin: def.diasMin,
        diasMax: def.diasMax,
        zonaId,
        titulo: titulo.trim(),
        corpo: corpo.trim(),
        controloPct: pct,
      });
      setSucesso(
        `Campanha criada. ${r.enviados} para enviar (${r.enviados_push} por notificação), ${r.controlo} no controlo. ` +
          `${r.enviados - r.enviados_push} sem app — use a lista para telefonar.`,
      );
      setLista(null);
      recarregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAGuardar(false);
    }
  }

  return (
    <Guarda permissoes={['clientes.reconquista']}>
      <Ecra>
        <Subtitulo>Reconquista de clientes</Subtitulo>
        <Paragrafo suave>
          Clientes que compraram e pararam. Veja a lista (com telefone), envie um aviso de regresso e meça o efeito com
          um grupo de controlo.
        </Paragrafo>

        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}

        {!resumo ? (
          <ACarregar />
        ) : (
          <Cartao>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: espaco.s }}>
              <Metrica rotulo="A arrefecer" sub="30–59 dias" total={resumo.a_arrefecer.total} push={resumo.a_arrefecer.com_push} />
              <Metrica rotulo="Frio" sub="60–89 dias" total={resumo.frio.total} push={resumo.frio.com_push} />
              <Metrica rotulo="Adormecido" sub="90+ dias" total={resumo.adormecido.total} push={resumo.adormecido.com_push} />
            </View>
            <Paragrafo suave>“Com app” = quem recebe a notificação; os restantes só por telefone.</Paragrafo>
          </Cartao>
        )}

        <Cartao>
          <Text style={{ color: cores.textoSuave, marginBottom: 4 }}>Escalão</Text>
          <Escolha opcoes={ESCALOES.map((e) => ({ valor: e.valor, rotulo: e.rotulo }))} valor={escalao} aoMudar={mudarEscalao} />

          {zonas.length > 0 && (
            <>
              <Text style={{ color: cores.textoSuave, marginTop: espaco.s, marginBottom: 4 }}>Zona (opcional)</Text>
              <Escolha
                opcoes={[{ valor: '', rotulo: 'Todas' }, ...zonas.map((z) => ({ valor: z.id, rotulo: z.nome }))]}
                valor={zonaId ?? ''}
                aoMudar={(v) => {
                  setZonaId(v === '' ? null : v);
                  setLista(null);
                }}
              />
            </>
          )}

          <Botao titulo="Ver clientes" variante="texto" aCarregar={aListar} aoCarregar={verLista} />

          {lista && (
            <View style={{ marginTop: espaco.s }}>
              <Text style={{ color: cores.texto, fontWeight: '700' }}>
                {lista.length} {lista.length === 1 ? 'cliente' : 'clientes'} neste escalão
              </Text>
              {lista.slice(0, 50).map((c) => (
                <View
                  key={c.cliente_id}
                  style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.s, paddingVertical: 6, borderBottomWidth: 1, borderBottomColor: cores.contorno }}>
                  <View style={{ flex: 1 }}>
                    <Text style={{ color: cores.texto }}>{c.nome}</Text>
                    <Text style={{ color: cores.textoSuave, fontSize: 12 }}>
                      {c.dias_inativo} dias · {c.total_pedidos} {c.total_pedidos === 1 ? 'pedido' : 'pedidos'}
                      {c.tem_push ? ' · tem app' : ''}
                    </Text>
                  </View>
                  {c.telefone ? (
                    <Text style={{ color: cores.marca, fontWeight: '700' }} onPress={() => Linking.openURL(`tel:+244${c.telefone}`)}>
                      Ligar
                    </Text>
                  ) : (
                    <Text style={{ color: cores.textoSuave, fontSize: 12 }}>sem nº</Text>
                  )}
                </View>
              ))}
              {lista.length > 50 && <Paragrafo suave>A mostrar os primeiros 50.</Paragrafo>}
            </View>
          )}
        </Cartao>

        <Cartao>
          <Subtitulo>Enviar campanha de regresso</Subtitulo>
          <Campo rotulo="Título" value={titulo} onChangeText={setTitulo} maxLength={80} />
          <Campo rotulo="Mensagem" value={corpo} onChangeText={setCorpo} multiline maxLength={500} />
          <Campo
            rotulo="Grupo de controlo (%) — fica de fora para medir o efeito"
            value={controlo}
            onChangeText={setControlo}
            keyboardType="number-pad"
            maxLength={2}
            placeholder="15"
          />
          <Paragrafo suave>
            Só quem tem a app recebe a notificação; os outros ficam na lista para telefonar. Quem já recebeu uma campanha
            há pouco não volta a ser contactado.
          </Paragrafo>
          <Botao titulo="Enviar campanha" aCarregar={aGuardar} aoCarregar={enviar} />
        </Cartao>

        {historico && historico.length > 0 && (
          <Cartao>
            <Subtitulo>Campanhas anteriores</Subtitulo>
            {historico.map((h) => {
              const r = h.resultado;
              const taxa = (v: number, t: number) => (t > 0 ? Math.round((v / t) * 100) : 0);
              return (
                <View key={h.id} style={{ paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: cores.contorno }}>
                  <Text style={{ color: cores.texto, fontWeight: '700' }}>
                    {new Date(h.criado_em).toLocaleDateString('pt-PT')} · {h.dias_min}
                    {h.dias_max ? `–${h.dias_max}` : '+'} dias
                  </Text>
                  <Text style={{ color: cores.textoSuave, fontSize: 13 }}>
                    Enviados {r.enviados} (voltaram {r.enviados_voltaram} · {taxa(r.enviados_voltaram, r.enviados)}%) ·
                    Controlo {r.controlo} (voltaram {r.controlo_voltaram} · {taxa(r.controlo_voltaram, r.controlo)}%)
                  </Text>
                  <Text style={{ color: cores.textoSuave, fontSize: 12 }}>janela de {r.janela_dias} dias após o envio</Text>
                </View>
              );
            })}
          </Cartao>
        )}
      </Ecra>
    </Guarda>
  );
}

function Metrica({ rotulo, sub, total, push }: { rotulo: string; sub: string; total: number; push: number }) {
  return (
    <View style={{ minWidth: 92, flexGrow: 1, backgroundColor: cores.fundoSuave, borderRadius: 10, padding: espaco.s }}>
      <Text style={{ color: cores.texto, fontWeight: '800', fontSize: 22 }}>{total}</Text>
      <Text style={{ color: cores.texto, fontSize: 13 }}>{rotulo}</Text>
      <Text style={{ color: cores.textoSuave, fontSize: 11 }}>
        {sub} · {push} com app
      </Text>
    </View>
  );
}
