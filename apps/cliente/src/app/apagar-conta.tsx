import { useRouter } from 'expo-router';
import { useState } from 'react';

import { Aviso, Botao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { apagarConta } from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';

/** Apagar a conta (exigido pela Google Play e pela App Store): explica o que sai e pede confirmação */
export default function ApagarConta() {
  const router = useRouter();
  const { sair } = useSessao();
  const carrinho = useCarrinho();
  const [confirmar, setConfirmar] = useState(false);
  const [aApagar, setAApagar] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  async function apagar() {
    setErro(null);
    setAApagar(true);
    try {
      await apagarConta();
      carrinho.limpar();
      // O utilizador já não existe no servidor: sair só limpa a sessão guardada no telemóvel
      await sair().catch(() => undefined);
      router.replace('/entrar');
    } catch (e) {
      setErro(mensagemErro(e));
      setAApagar(false);
    }
  }

  return (
    <Ecra>
      <Subtitulo>O que acontece</Subtitulo>
      <Paragrafo>
        A tua conta fica desativada e podes recuperá-la durante 60 dias — com o nome, o histórico e o saldo. Ao fim
        de 60 dias é apagada definitivamente.
      </Paragrafo>
      <Paragrafo>
        Os pedidos e pagamentos já feitos ficam guardados (a empresa precisa deles para as contas, por lei). Deixas
        de aparecer nos destaques e não voltas a receber mensagens nossas.
      </Paragrafo>
      <Paragrafo suave>
        Ao apagar, sais de todos os dispositivos. Para voltar a entrar precisas do código SMS do teu número.
      </Paragrafo>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {confirmar ? (
        <>
          <Aviso>Tens a certeza? A conta fica desativada (podes recuperá-la durante 60 dias).</Aviso>
          <Botao titulo="Sim, apagar a minha conta" aoCarregar={apagar} aCarregar={aApagar} />
          <Botao titulo="Não, voltar" variante="texto" aoCarregar={() => router.back()} desactivado={aApagar} />
        </>
      ) : (
        <Botao titulo="Apagar a minha conta" variante="secundario" aoCarregar={() => setConfirmar(true)} />
      )}
    </Ecra>
  );
}
