import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Cartao, Ecra, Linha, Subtitulo } from '@/components/ui';
import { obrigacoesResumo } from '@/lib/api';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import type { Obrigacoes as Dados } from '@/lib/tipos';

/** Obrigações e tesouraria: o que a plataforma deve e o que tem a receber, num só sítio */
export default function Obrigacoes() {
  const [d, setD] = useState<Dados | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  const carregar = useCallback(() => {
    setD(null);
    obrigacoesResumo()
      .then(setD)
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  const totalPagar = d ? Object.values(d.a_pagar).reduce((s, v) => s + v, 0) : 0;
  const totalReceber = d ? d.a_receber.acertos_cozinhas + d.a_receber.empresas : 0;

  return (
    <Guarda permissoes={['financas.obrigacoes']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!d && !erro && <ACarregar />}
        {d && (
          <>
            {(d.por_fechar.semanas_acertos > 0 || d.por_fechar.vendas_sem_fatura > 0) && (
              <Aviso>
                {[
                  d.por_fechar.semanas_acertos > 0 ? `${d.por_fechar.semanas_acertos} acerto(s) da semana passada por fechar` : null,
                  d.por_fechar.vendas_sem_fatura > 0 ? `${d.por_fechar.vendas_sem_fatura} venda(s) sem fatura nos últimos 30 dias` : null,
                ]
                  .filter(Boolean)
                  .join(' · ')}
              </Aviso>
            )}
            <Cartao>
              <Subtitulo>A plataforma deve</Subtitulo>
              <Linha esquerda="Saldos Convida dos clientes" direita={formatarKz(d.a_pagar.saldos_convida)} />
              <Linha esquerda="Levantamentos pedidos" direita={formatarKz(d.a_pagar.levantamentos_pedidos)} />
              <Linha esquerda="Pacotes pagos por consumir" direita={formatarKz(d.a_pagar.pacotes_por_consumir)} />
              <Linha esquerda="Acertos a pagar às cozinhas" direita={formatarKz(d.a_pagar.acertos_cozinhas)} />
              <Linha esquerda="Compensações por pagar" direita={formatarKz(d.a_pagar.compensacoes)} />
              <Linha esquerda="Estafetas (meses anteriores)" direita={formatarKz(d.a_pagar.estafetas_meses_anteriores)} />
              <Linha esquerda="Serviço de entregas (meses anteriores)" direita={formatarKz(d.a_pagar.servico_entregas_meses_anteriores)} />
              <Linha esquerda="Total" direita={formatarKz(totalPagar)} forte />
            </Cartao>
            <Cartao>
              <Subtitulo>A plataforma tem a receber</Subtitulo>
              <Linha esquerda="Acertos das cozinhas" direita={formatarKz(d.a_receber.acertos_cozinhas)} />
              <Linha esquerda="Faturas das empresas" direita={formatarKz(d.a_receber.empresas)} />
              {d.a_receber.empresas_em_atraso > 0 && <Linha esquerda="…das quais em atraso" direita={formatarKz(d.a_receber.empresas_em_atraso)} />}
              <Linha esquerda="Total" direita={formatarKz(totalReceber)} forte />
            </Cartao>
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
