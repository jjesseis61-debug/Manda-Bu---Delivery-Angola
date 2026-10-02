import { Aviso, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { EMPRESA } from '@/lib/empresa';

/** Política de privacidade: o que a app guarda, para quê, quem vê e como apagar (exigida pelas lojas) */
export default function PoliticaPrivacidade() {
  return (
    <Ecra>
      <Paragrafo suave>Última actualização: {EMPRESA.actualizadaEm}</Paragrafo>

      <Subtitulo>O que guardamos</Subtitulo>
      <Paragrafo>
        O teu número de telefone (para entrares com um código por SMS), o teu nome e, se fores uma empresa, o NIF.
      </Paragrafo>
      <Paragrafo>
        Os endereços de entrega que gravas, com o ponto que marcas no mapa. Só usamos a localização do telemóvel
        quando carregas em &quot;Usar a minha localização&quot;, e só para marcar esse ponto.
      </Paragrafo>
      <Paragrafo>
        Os teus pedidos, pagamentos, convites e ganhos do Convida e Ganha, as avaliações e fotos que envias, e um
        código do telemóvel para te enviarmos notificações.
      </Paragrafo>
      <Paragrafo>
        Enquanto o teu pedido está a caminho, mostramos-te no mapa a posição do estafeta. A posição dele só fica
        guardada durante a entrega e não guardamos o percurso.
      </Paragrafo>

      <Subtitulo>Para quê</Subtitulo>
      <Paragrafo>
        Para preparar e entregar os pedidos, calcular descontos e ganhos, evitar fraude nos convites e enviar avisos
        sobre os teus pedidos. Não vendemos os teus dados nem os usamos para publicidade de outras empresas.
      </Paragrafo>

      <Subtitulo>Quem vê</Subtitulo>
      <Paragrafo>
        A equipa do Manda Bué que trata do teu pedido (cozinha, entrega, apoio), cada pessoa só no que precisa
        para o seu trabalho. Nas listas públicas (destaques e avaliações) aparece só o teu pseudónimo ou o primeiro
        nome, se o escolheres. Os dados ficam guardados no Supabase; as notificações passam pela Expo e o SMS pelo
        fornecedor de SMS.
      </Paragrafo>

      <Subtitulo>Os teus direitos</Subtitulo>
      <Paragrafo>
        Podes ver e corrigir os teus dados na app e apagar a conta em Conta → Apagar a conta. Ao apagar, saem o
        nome, o telefone, o NIF, os endereços e o registo do telemóvel; os pedidos e pagamentos ficam sem o teu nome,
        para as contas da empresa.
      </Paragrafo>

      <Subtitulo>Contacto</Subtitulo>
      {EMPRESA.contactoPrivacidade ? (
        <Paragrafo>{EMPRESA.contactoPrivacidade}</Paragrafo>
      ) : (
        <Aviso>Contacto por definir.</Aviso>
      )}
    </Ecra>
  );
}
