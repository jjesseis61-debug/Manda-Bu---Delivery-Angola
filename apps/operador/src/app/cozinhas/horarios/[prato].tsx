import { useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { apagarHorario, guardarHorario, lerHorarios } from '@/lib/api';
import { mascaraData, mascaraHora, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { HorarioCardapio } from '@/lib/tipos';

const HORA_OK = /^([01]?\d|2[0-3]):[0-5]\d$/;
const DIAS = ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom']; // ISO 1..7

const hhmm = (t: string) => t.slice(0, 5);

/** 'YYYY-MM-DD' -> 'DD/MM' */
function isoParaDDMM(iso: string): string {
  const [, m, d] = iso.split('-');
  return `${d}/${m}`;
}
/** 'YYYY-MM-DD' -> 'DD/MM/AAAA' (para pré-preencher o campo ao editar) */
function isoParaDDMMAAAA(iso: string): string {
  const [a, m, d] = iso.split('-');
  return `${d}/${m}/${a}`;
}
/** 'DD/MM/AAAA' -> 'YYYY-MM-DD' (ou null) */
function ddmmParaIso(s: string): string | null {
  const m = s.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (!m) return null;
  const iso = `${m[3]}-${m[2]}-${m[1]}`;
  const dt = new Date(`${iso}T00:00:00`);
  return isNaN(dt.getTime()) ? null : iso;
}
function descricao(h: HorarioCardapio): string {
  const janela = `${hhmm(h.hora_inicio)}–${hhmm(h.hora_fim)}`;
  if (h.dia_semana) return `${DIAS[h.dia_semana]} · ${janela}`;
  return `${h.data ? isoParaDDMM(h.data) : ''} · ${janela}`;
}

/** Horários de um prato: janelas recorrentes (por dia da semana) ou de uma vez (por data). */
export default function HorariosPrato() {
  const { prato, nome } = useLocalSearchParams<{ prato: string; nome?: string }>();
  const [lista, setLista] = useState<HorarioCardapio[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const [modo, setModo] = useState<'semana' | 'data'>('semana');
  const [dia, setDia] = useState('1');
  const [data, setData] = useState('');
  const [ini, setIni] = useState('08:00');
  const [fim, setFim] = useState('11:00');
  const [editId, setEditId] = useState<string | null>(null); // horário a editar; null = acrescentar novo

  const carregar = useCallback(() => {
    if (!prato) return;
    lerHorarios(prato).then(setLista, (e) => setErro(mensagemErro(e)));
  }, [prato]);

  useEffect(carregar, [carregar]);

  const horasOk = HORA_OK.test(ini) && HORA_OK.test(fim);
  const dataIso = modo === 'data' ? ddmmParaIso(data) : null;
  const podeGuardar = horasOk && (modo === 'semana' || !!dataIso);

  // Repõe o formulário no modo "acrescentar novo"
  function limparFormulario() {
    setEditId(null);
    setModo('semana');
    setDia('1');
    setData('');
    setIni('08:00');
    setFim('11:00');
  }

  // Carrega um horário existente no formulário para o editar
  function editar(h: HorarioCardapio) {
    setErro(null);
    setEditId(h.id);
    if (h.dia_semana) {
      setModo('semana');
      setDia(String(h.dia_semana));
      setData('');
    } else {
      setModo('data');
      setData(h.data ? isoParaDDMMAAAA(h.data) : '');
    }
    setIni(hhmm(h.hora_inicio));
    setFim(hhmm(h.hora_fim));
  }

  async function guardar() {
    if (!prato || !podeGuardar) return;
    setOcupado(true);
    setErro(null);
    try {
      await guardarHorario({
        id: editId ?? undefined,
        cardapio_id: prato,
        dia_semana: modo === 'semana' ? Number(dia) : null,
        data: modo === 'data' ? dataIso : null,
        hora_inicio: ini,
        hora_fim: fim,
      });
      limparFormulario();
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  async function remover(id: string) {
    setErro(null);
    if (id === editId) limparFormulario(); // apagou o que estava a editar
    try {
      await apagarHorario(id);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    }
  }

  return (
    <Guarda permissoes={['cozinhas.gerir']}>
      <Ecra>
        {nome ? <Subtitulo>{nome}</Subtitulo> : null}
        <Paragrafo suave>
          O prato fica disponível só dentro destas janelas. Sem nenhuma, está sempre disponível (enquanto
          &quot;Disponível&quot; estiver ligado). Hora de Angola.
        </Paragrafo>

        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista && lista.length === 0 && <Paragrafo suave>Sem horários — sempre disponível.</Paragrafo>}
        {lista?.map((h) => (
          <Cartao key={h.id} estilo={h.id === editId ? { borderWidth: 1, borderColor: cores.marca } : undefined}>
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
              <Text style={{ fontWeight: '700', color: cores.texto }}>{descricao(h)}</Text>
              <View style={{ flexDirection: 'row', gap: espaco.s }}>
                <Botao titulo="Editar" variante="texto" aoCarregar={() => editar(h)} />
                <Botao titulo="Remover" variante="texto" aoCarregar={() => remover(h.id)} />
              </View>
            </View>
          </Cartao>
        ))}

        <Cartao estilo={{ gap: espaco.s }}>
          <Subtitulo>{editId ? 'Editar horário' : 'Acrescentar horário'}</Subtitulo>
          <Escolha
            opcoes={[
              { valor: 'semana', rotulo: 'Dia da semana (repete)' },
              { valor: 'data', rotulo: 'Data específica (uma vez)' },
            ]}
            valor={modo}
            aoMudar={setModo}
          />
          {modo === 'semana' ? (
            <Escolha opcoes={[1, 2, 3, 4, 5, 6, 7].map((n) => ({ valor: String(n), rotulo: DIAS[n] }))} valor={dia} aoMudar={setDia} />
          ) : (
            <Campo rotulo="Data (DD/MM/AAAA)" placeholder="30/10/2026" keyboardType="number-pad" maxLength={10} value={data} onChangeText={(t) => setData(mascaraData(t))} />
          )}
          <View style={{ flexDirection: 'row', gap: espaco.m }}>
            <View style={{ flex: 1 }}>
              <Campo rotulo="Das (HH:MM)" placeholder="08:00" keyboardType="number-pad" maxLength={5} value={ini} onChangeText={(t) => setIni(mascaraHora(t))} />
            </View>
            <View style={{ flex: 1 }}>
              <Campo rotulo="Às (HH:MM)" placeholder="11:00" keyboardType="number-pad" maxLength={5} value={fim} onChangeText={(t) => setFim(mascaraHora(t))} />
            </View>
          </View>
          {!horasOk && <Aviso tipo="erro">Escreve as horas no formato HH:MM (ex.: 08:00).</Aviso>}
          {modo === 'data' && data !== '' && !dataIso && <Aviso tipo="erro">Data inválida. Usa DD/MM/AAAA (ex.: 30/10/2026).</Aviso>}
          <Botao titulo={editId ? 'Guardar alterações' : 'Acrescentar horário'} aCarregar={ocupado} desactivado={!podeGuardar} aoCarregar={guardar} />
          {editId && <Botao titulo="Cancelar edição" variante="texto" aoCarregar={limparFormulario} />}
        </Cartao>
      </Ecra>
    </Guarda>
  );
}
