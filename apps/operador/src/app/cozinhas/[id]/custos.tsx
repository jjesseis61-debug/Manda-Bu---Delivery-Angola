import { useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { custosDaCozinha, definirCustoItem, type CustoItem } from '@/lib/api';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { margemPct } from '@/lib/relatorio';
import { cores, espaco } from '@/lib/tema';

/** Custo de uma dose de cada prato (e de cada opção dos montáveis) e a margem que fica */
export default function CustosEMargens() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [itens, setItens] = useState<CustoItem[] | null>(null);
  const [editados, setEditados] = useState<Record<string, string>>({});
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    custosDaCozinha(String(id))
      .then((l) => {
        setItens(l);
        setEditados({});
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [id]);
  useFocusEffect(carregar);

  const alterados = Object.entries(editados).filter(([k, v]) => {
    const i = itens?.find((x) => x.item_id === k);
    return i && v !== (i.custo == null ? '' : String(i.custo));
  });
  const valido = alterados.every(([, v]) => v === '' || (/^\d+$/.test(v) && Number(v) <= 1000000));

  async function guardar() {
    setOcupado(true);
    setErro(null);
    setAviso(null);
    try {
      for (const [k, v] of alterados) await definirCustoItem(k, v === '' ? null : Number(v));
      setAviso(`${alterados.length} custo(s) guardado(s).`);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  const pratos = (itens ?? []).filter((i) => i.tipo === 'prato');
  const semCusto = pratos.filter((p) => p.custo == null && !(itens ?? []).some((o) => o.prato_id === p.item_id && o.tipo === 'opcao')).length;

  function linha(i: CustoItem) {
    const v = editados[i.item_id] ?? (i.custo == null ? '' : String(i.custo));
    const custo = v === '' ? null : Number(v);
    const m = margemPct(i.preco, custo);
    return (
      <View key={i.item_id} style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.s, paddingLeft: i.tipo === 'opcao' ? espaco.l : 0 }}>
        <View style={{ flex: 1 }}>
          <Text style={{ color: cores.texto, fontWeight: i.tipo === 'prato' ? '700' : '400' }}>
            {i.tipo === 'opcao' ? '• ' : ''}
            {i.nome}
            {!i.disponivel ? ' (indisponível)' : ''}
          </Text>
          <Text style={{ color: cores.textoSuave, fontSize: 12 }}>
            {i.tipo === 'opcao' ? `${i.grupo ?? ''} · +` : 'Preço '}
            {formatarKz(i.preco)}
            {m != null ? ` · margem ${String(m).replace('.', ',')}%` : ''}
          </Text>
        </View>
        <View style={{ width: 120 }}>
          <Campo
            rotulo={`Custo de ${i.nome}`}
            placeholder="Kz"
            value={v}
            keyboardType="number-pad"
            maxLength={7}
            onChangeText={(t) => setEditados((e) => ({ ...e, [i.item_id]: t.replace(/\D/g, '') }))}
          />
        </View>
      </View>
    );
  }

  return (
    <Guarda permissoes={['cardapio.gerir', 'cozinhas.gerir', 'financas.gerir']}>
      <Ecra>
        <Paragrafo>
          Quanto custa fazer <Text style={{ fontWeight: '700' }}>uma dose</Text> (ingredientes, embalagem, gás da
          confecção). Nos montáveis, o custo vem de cada opção escolhida. Só a equipa vê estes valores.
        </Paragrafo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {aviso && <Aviso tipo="sucesso">{aviso}</Aviso>}
        {semCusto > 0 && <Aviso>{semCusto} prato(s) sem custo: o relatório não consegue calcular a margem deles.</Aviso>}
        {!itens && !erro && <ACarregar />}
        {itens && itens.length === 0 && <Paragrafo suave>Sem pratos no cardápio.</Paragrafo>}
        {pratos.map((p) => (
          <Cartao key={p.item_id} estilo={{ gap: espaco.s }}>
            {linha(p)}
            {(itens ?? []).filter((o) => o.tipo === 'opcao' && o.prato_id === p.item_id).map(linha)}
          </Cartao>
        ))}
        {itens && itens.length > 0 && (
          <Botao
            titulo={alterados.length ? `Guardar ${alterados.length} alteração(ões)` : 'Sem alterações'}
            desactivado={alterados.length === 0 || !valido}
            aCarregar={ocupado}
            aoCarregar={guardar}
          />
        )}
      </Ecra>
    </Guarda>
  );
}
