import { useRouter } from 'expo-router';

import { Botao, Cartao, Ecra, Linha, Paragrafo } from '@/components/ui';
import { useCarrinho } from '@/lib/carrinho';
import { useSessao } from '@/lib/sessao';

export default function Conta() {
  const router = useRouter();
  const { perfil, sair, ligada } = useSessao();
  const carrinho = useCarrinho();

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
      <Paragrafo suave>Manda Bué — Delivery Angola</Paragrafo>
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
