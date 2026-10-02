import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { painel } from '@/lib/api';
import { diaLuanda, formatarKz, formatarPercentagem, inicioMesLuanda, mensagemErro } from '@/lib/formatar';
import { cores } from '@/lib/tema';
import type { Painel } from '@/lib/tipos';

/** O1. Painel do programa */
export default function PainelPrograma() {
  const [periodo, setPeriodo] = useState<'semana' | 'mes'>('semana');
  const [dados, setDados] = useState<Painel | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      setDados(null);
      const inicio = periodo === 'semana' ? diaLuanda(-6) : inicioMesLuanda();
      painel(inicio, diaLuanda())
        .then(setDados)
        .catch((e) => setErro(mensagemErro(e)));
    }, [periodo]),
  );

  return (
    <Guarda permissoes={['indicacoes.ver']}>
      <Ecra>
        <Escolha
          opcoes={[
            { valor: 'semana', rotulo: 'Últimos 7 dias' },
            { valor: 'mes', rotulo: 'Este mês' },
          ]}
          valor={periodo}
          aoMudar={setPeriodo}
        />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!dados && !erro && <ACarregar />}
        {dados && (
          <>
            <Cartao>
              <Linha esquerda="Custo do programa" direita={formatarKz(dados.custo)} forte />
              <Linha esquerda="· ganhos dos indicadores" direita={formatarKz(dados.ganhos)} />
              <Linha esquerda="· descontos dos indicados" direita={formatarKz(dados.descontos)} />
              <Linha esquerda="Vendas vindas de indicação" direita={formatarKz(dados.vendas_indicacao)} />
              <Linha esquerda="Peso das comissões" direita={formatarPercentagem(dados.custo, dados.vendas_indicacao)} />
            </Cartao>
            <Cartao>
              <Linha esquerda="Clientes novos por indicação" direita={String(dados.clientes_novos)} />
              <Linha esquerda="Indicadores activos" direita={String(dados.indicadores_activos)} />
              <Linha
                esquerda={`Retenção após o período (${dados.periodos_terminados} terminados)`}
                direita={formatarPercentagem(dados.retidos, dados.periodos_terminados)}
              />
              <Linha esquerda="Anulados na verificação" direita={formatarPercentagem(dados.anulados_verificacao, dados.revistos)} />
              <Linha esquerda="À espera de verificação (agora)" direita={String(dados.em_verificacao)} />
            </Cartao>
            <Subtitulo>Top indicadores</Subtitulo>
            <Text style={{ color: cores.textoSuave, fontSize: 13 }}>Nomes reais: só para uso interno.</Text>
            {dados.top.length === 0 && <Paragrafo suave>Sem ganhos no período.</Paragrafo>}
            {dados.top.map((t, i) => (
              <Linha
                key={t.indicador_id}
                esquerda={`${i + 1}. ${t.nome}${t.nivel === 'embaixador' ? ' ★' : ''} · ${t.amigos} amigos`}
                direita={formatarKz(t.valor)}
              />
            ))}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
