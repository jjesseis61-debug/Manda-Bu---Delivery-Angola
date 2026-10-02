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
        Apagamos o teu nome, telefone, NIF, endereços e o registo deste telemóvel para notificações. Deixas de
        aparecer nos destaques e não voltas a receber mensagens nossas.
      </Paragrafo>
      <Paragrafo>
        Os pedidos e pagamentos já feitos ficam guardados sem o teu nome, porque a empresa precisa deles para as
        contas. O saldo do Convida e Ganha que ainda não levantaste perde-se.
      </Paragrafo>
      <Paragrafo suave>Não é possível desfazer. Podes criar uma conta nova mais tarde com o mesmo número.</Paragrafo>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {confirmar ? (
        <>
          <Aviso>Tens a certeza? A conta é apagada já.</Aviso>
          <Botao titulo="Sim, apagar a minha conta" aoCarregar={apagar} aCarregar={aApagar} />
          <Botao titulo="Não, voltar" variante="texto" aoCarregar={() => router.back()} desactivado={aApagar} />
        </>
      ) : (
        <Botao titulo="Apagar a minha conta" variante="secundario" aoCarregar={() => setConfirmar(true)} />
      )}
    </Ecra>
  );
}
