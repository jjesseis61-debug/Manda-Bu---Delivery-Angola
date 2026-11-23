import { useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { apagarDespesa, despesasCozinha, lancarDespesa, type Despesa } from '@/lib/api';
import { diaLuanda, formatarDia, formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import { CampoData } from '@/components/CamposData';
import { hojeIso } from '@/lib/datas';

export const CATEGORIAS_DESPESA = ['Gás', 'Renda', 'Salários', 'Transporte', 'Embalagens', 'Água e luz', 'Manutenção', 'Outros'];

/** Primeiro e último dia de um mês (desvio 0 = este mês, -1 = anterior) no dia de Luanda */
export function mesDe(desvio: number, agora = new Date()): { inicio: string; fim: string; nome: string } {
  const hoje = diaLuanda(0, agora);
  const d = new Date(`${hoje.slice(0, 8)}01T00:00:00Z`);
  d.setUTCMonth(d.getUTCMonth() + desvio);
  const inicio = d.toISOString().slice(0, 10);
  const f = new Date(d);
  f.setUTCMonth(f.getUTCMonth() + 1);
  f.setUTCDate(0);
  const meses = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];
  return { inicio, fim: f.toISOString().slice(0, 10), nome: `${meses[d.getUTCMonth()]} ${d.getUTCFullYear()}` };
}

/** Despesas da cozinha (gás, renda, salários...): entram no resultado do relatório */
export default function Despesas() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [desvio, setDesvio] = useState(0);
  const [lista, setLista] = useState<Despesa[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [nova, setNova] = useState({ data: diaLuanda(), categoria: 'Gás', valor: '', descricao: '' });
  const [ocupado, setOcupado] = useState(false);
  const mes = mesDe(desvio);

  const carregar = useCallback(() => {
    setLista(null);
    despesasCozinha(String(id), mes.inicio, mes.fim)
      .then(setLista)
      .catch((e) => setErro(mensagemErro(e)));
  }, [id, mes.inicio, mes.fim]);
  useFocusEffect(carregar);

  const valor = Number(nova.valor);
  const dataOk = /^\d{4}-\d{2}-\d{2}$/.test(nova.data) && nova.data <= hojeIso();

  async function lancar() {
    setOcupado(true);
    setErro(null);
    try {
      await lancarDespesa(String(id), nova.data, nova.categoria, nova.descricao, valor);
      setNova({ ...nova, valor: '', descricao: '' });
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  const total = (lista ?? []).reduce((s, d) => s + d.valor, 0);

  return (
    <Guarda permissoes={['financas.gerir', 'cardapio.gerir', 'cozinhas.gerir']}>
      <Ecra>
        <Cartao estilo={{ gap: espaco.s }}>
          <Subtitulo>Nova despesa</Subtitulo>
          <Escolha
            opcoes={CATEGORIAS_DESPESA.map((c) => ({ valor: c, rotulo: c }))}
            valor={nova.categoria}
            aoMudar={(c) => setNova({ ...nova, categoria: c })}
          />
          <Campo rotulo="Valor (Kz)" value={nova.valor} keyboardType="number-pad" maxLength={9}
            onChangeText={(t) => setNova({ ...nova, valor: t.replace(/\D/g, '') })} />
          <CampoData rotulo="Data" valor={nova.data} aoMudar={(t) => setNova((n) => ({ ...n, data: t }))}
            erro={nova.data > hojeIso() ? 'A despesa não pode ser no futuro.' : null} />
          <Campo rotulo="Descrição (opcional)" value={nova.descricao} maxLength={200}
            onChangeText={(t) => setNova({ ...nova, descricao: t })} />
          <Botao titulo="Lançar despesa" aCarregar={ocupado} desactivado={!(valor > 0) || !dataOk} aoCarregar={lancar} />
        </Cartao>

        <Escolha
          opcoes={[{ valor: '0', rotulo: 'Este mês' }, { valor: '-1', rotulo: 'Mês anterior' }, { valor: '-2', rotulo: 'Há 2 meses' }]}
          valor={String(desvio)}
          aoMudar={(v) => setDesvio(Number(v))}
        />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista && (
          <Cartao estilo={{ gap: espaco.xs }}>
            <Subtitulo>
              {mes.nome}: {formatarKz(total)}
            </Subtitulo>
            {lista.length === 0 && <Paragrafo suave>Sem despesas lançadas neste mês.</Paragrafo>}
            {lista.map((d) => (
              <View key={d.id} style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.s, borderTopWidth: 1, borderTopColor: cores.linha, paddingTop: espaco.xs }}>
                <View style={{ flex: 1 }}>
                  <Text style={{ color: cores.texto, fontWeight: '600' }}>
                    {d.categoria} · {formatarKz(d.valor)}
                  </Text>
                  <Text style={{ color: cores.textoSuave, fontSize: 12 }}>
                    {formatarDia(d.data)}
                    {d.descricao ? ` · ${d.descricao}` : ''}
                  </Text>
                </View>
                <Botao titulo="Apagar" variante="texto" aoCarregar={() => apagarDespesa(d.id).then(carregar).catch((e) => setErro(mensagemErro(e)))} />
              </View>
            ))}
          </Cartao>
        )}
      </Ecra>
    </Guarda>
  );
}
