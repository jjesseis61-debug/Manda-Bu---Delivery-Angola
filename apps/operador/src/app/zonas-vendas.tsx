import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { vendasPorZona, type ZonaVendas } from '@/lib/api';
import { exportarCsv } from '@/lib/exportar';
import { formatarKz, mensagemErro, paraCsv } from '@/lib/formatar';
import { linhasCsvZonas, periodoRel, tendencia, type PeriodoRel } from '@/lib/relatorio';
import { cores, espaco } from '@/lib/tema';

/** Administrador: o que se compra em cada zona, somando todas as cozinhas (zona = onde o cliente recebe) */
export default function ZonasVendas() {
  const [periodo, setPeriodo] = useState<PeriodoRel>('mes');
  const [de, setDe] = useState('');
  const [ate, setAte] = useState('');
  const [zonas, setZonas] = useState<ZonaVendas[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const intervalo = periodoRel(periodo, new Date(), de, ate);

  const carregar = useCallback(() => {
    if (!intervalo) return;
    setErro(null);
    vendasPorZona(intervalo[0], intervalo[1])
      .then((r) => setZonas(r.zonas))
      .catch((e) => setErro(mensagemErro(e)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [intervalo?.[0], intervalo?.[1]]);
  useFocusEffect(carregar);

  return (
    <Guarda permissoes={['relatorios.exportar']}>
      <Ecra>
        <Escolha<PeriodoRel>
          opcoes={[
            { valor: '7', rotulo: '7 dias' },
            { valor: 'mes', rotulo: 'Este mês' },
            { valor: 'mes_anterior', rotulo: 'Mês anterior' },
            { valor: 'datas', rotulo: 'Datas…' },
          ]}
          valor={periodo}
          aoMudar={setPeriodo}
        />
        {periodo === 'datas' && (
          <View style={{ flexDirection: 'row', gap: espaco.s }}>
            <View style={{ flex: 1 }}>
              <Campo rotulo="De (aaaa-mm-dd)" value={de} onChangeText={setDe} maxLength={10} />
            </View>
            <View style={{ flex: 1 }}>
              <Campo rotulo="Até (opcional)" value={ate} onChangeText={setAte} maxLength={10} />
            </View>
          </View>
        )}
        <Paragrafo suave>
          Zona = onde o cliente recebe. Ajuda a decidir que pratos pôr numa cozinha nova (ou num condomínio) e o que promover em cada zona.
        </Paragrafo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!zonas && !erro && <ACarregar />}
        {zonas && zonas.length === 0 && <Paragrafo suave>Sem vendas no período.</Paragrafo>}
        {zonas?.map((z) => (
          <Cartao key={z.zona} estilo={{ gap: espaco.xs }}>
            <Subtitulo>{z.zona}</Subtitulo>
            <Paragrafo suave>{`${z.pedidos} pedidos · ${formatarKz(z.vendas)} · ${z.cozinhas ?? 0} cozinha(s) entregam aqui`}</Paragrafo>
            {z.pratos.map((p, i) => (
              <Linha
                key={p.nome}
                esquerda={`${i + 1}. ${p.nome}${p.cozinha_top ? ` · ${p.cozinha_top}` : ''}`}
                direita={`${p.qtd}×${tendencia(p.qtd, p.qtd_anterior) ? ` · ${tendencia(p.qtd, p.qtd_anterior)}` : ''}`}
              />
            ))}
            {z.opcoes.length > 0 && (
              <Paragrafo suave>{`Montados — opções preferidas: ${z.opcoes.map((o) => `${o.nome} (${o.qtd})`).join(', ')}`}</Paragrafo>
            )}
            {(z.a_crescer ?? []).length > 0 && (
              <Text style={{ color: cores.sucesso, fontWeight: '700' }}>
                {`A crescer: ${(z.a_crescer ?? []).map((g) => `${g.nome} (${g.qtd_anterior}→${g.qtd})`).join(', ')}`}
              </Text>
            )}
          </Cartao>
        ))}
        {zonas && zonas.length > 0 && intervalo && (
          <Botao
            titulo="⬇ Exportar (CSV)"
            variante="secundario"
            aoCarregar={() =>
              exportarCsv(`zonas-${intervalo[0]}-${intervalo[1]}.csv`, paraCsv(linhasCsvZonas(zonas))).catch((e) => setErro(mensagemErro(e)))
            }
          />
        )}
      </Ecra>
    </Guarda>
  );
}
