import { useRouter } from 'expo-router';

import { CasosAgente, type OpcoesCasos } from '@/components/CasosAgente';
import { Guarda } from '@/components/Guarda';
import { Botao, Ecra } from '@/components/ui';
import { abrirVigilancia, decidirCasoConvida, lerCasosConvida, vigiarDeNovo } from '@/lib/api';
import { diaLuanda, formatarKz } from '@/lib/formatar';
import type { CasoConvida } from '@/lib/tipos';

const opcoes: OpcoesCasos<CasoConvida> = {
  descricao:
    'O agente procura redes de contas no Convida e Ganha: o mesmo telemóvel em várias contas, levantamentos para o número de ' +
    'um indicado, indicados que só fazem o pedido do desconto, muitos no mesmo dia ou no mesmo local. Vizinhos e famílias ' +
    'são legítimos. Só lê dados (sem nomes nem telefones): quem decide és tu, na Verificação dos ganhos.',
  carregar: lerCasosConvida,
  abrir: abrirVigilancia,
  decidir: decidirCasoConvida,
  deNovo: vigiarDeNovo,
  titulo: (c) => `${c.indicador}${c.codigo ? ` · código ${c.codigo}` : ''}`,
  sinais: (c) =>
    `${c.sinais.indicados} indicados · ${c.sinais.telemovel_partilhado} com o mesmo telemóvel · ` +
    `${c.sinais.levantamento_para_indicado} levantamentos para um indicado · ${c.sinais.so_um_pedido} só com o pedido do desconto · ` +
    `${c.sinais.mesmo_local} no mesmo local · ganhos ${formatarKz(c.sinais.ganhos_kz)}`,
  perguntarA: () => null,
  textoAbrir: 'Abrir vigilância do período',
};

/** Vigilância do Convida e Ganha: casos do agente vigilante */
export default function Vigilancia() {
  const router = useRouter();
  const hoje = diaLuanda();
  return (
    <Guarda permissoes={['indicacoes.verificar']}>
      <Ecra>
        <CasosAgente inicioPadrao={diaLuanda(-28)} fimPadrao={hoje} opcoes={opcoes} />
        <Botao titulo="Ir para a Verificação dos ganhos" variante="texto" aoCarregar={() => router.push('/verificacao')} />
      </Ecra>
    </Guarda>
  );
}
