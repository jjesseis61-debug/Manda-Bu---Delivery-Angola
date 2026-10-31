import { useRouter } from 'expo-router';
import { useState } from 'react';

import { Aviso, Botao, Cartao, Ecra, Linha, Paragrafo } from '@/components/ui';
import { sairDeTodosOsDispositivos } from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';

export default function Conta() {
  const router = useRouter();
  const { perfil, sair, ligada } = useSessao();
  const carrinho = useCarrinho();
  const [protegerConfirmar, setProtegerConfirmar] = useState(false);
  const [ocupado, setOcupado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  async function protegerConta() {
    setErro(null);
    setOcupado(true);
    try {
      await sairDeTodosOsDispositivos();
      carrinho.limpar();
      router.replace('/entrar');
    } catch (e) {
      setErro(mensagemErro(e));
      setOcupado(false);
    }
  }

  return (
    <Ecra>
      <Cartao>
        <Linha esquerda="Nome" direita={perfil?.nome ?? ''} />
        <Linha esquerda="Telefone" direita={perfil?.telefone ?? ''} />
        {ligada('indicacao') && perfil?.codigo && <Linha esquerda="Código de convite" direita={perfil.codigo} />}
      </Cartao>
      {ligada('agente_atendimento') && <Botao titulo="Ajuda" variante="secundario" aoCarregar={() => router.push('/ajuda')} />}
      <Botao titulo="Contactos" variante="secundario" aoCarregar={() => router.push('/contactos')} />
      <Botao titulo="Endereços" variante="secundario" aoCarregar={() => router.push('/enderecos')} />
      {ligada('pacotes') && <Botao titulo="Pacote do mês" variante="secundario" aoCarregar={() => router.push('/pacotes')} />}
      {(ligada('indicacao') || ligada('destaques')) && (
        <Botao titulo="Notificações" variante="secundario" aoCarregar={() => router.push('/notificacoes')} />
      )}
      {ligada('indicacao') && <Botao titulo="Como funciona o Convida e Ganha" variante="texto" aoCarregar={() => router.push('/como-funciona')} />}
      <Botao titulo="Política de privacidade" variante="texto" aoCarregar={() => router.push('/politica-privacidade')} />
      <Paragrafo suave>Cozinha da Alexandra · entregue por Manda Bué</Paragrafo>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {protegerConfirmar ? (
        <>
          <Aviso>Sais em todos os dispositivos, incluindo este. Para voltar a entrar precisas do código SMS do teu número.</Aviso>
          <Botao titulo="Sim, sair em todos os dispositivos" aoCarregar={protegerConta} aCarregar={ocupado} />
          <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setProtegerConfirmar(false)} desactivado={ocupado} />
        </>
      ) : (
        <Botao
          titulo="Proteger a conta — sair em todos os dispositivos"
          variante="secundario"
          aoCarregar={() => setProtegerConfirmar(true)}
        />
      )}
      <Botao
        titulo="Sair da conta"
        variante="texto"
        aoCarregar={async () => {
          carrinho.limpar();
          await sair();
          router.replace('/entrar');
        }}
      />
      <Botao titulo="Apagar a conta" variante="texto" aoCarregar={() => router.push('/apagar-conta')} />
    </Ecra>
  );
}
