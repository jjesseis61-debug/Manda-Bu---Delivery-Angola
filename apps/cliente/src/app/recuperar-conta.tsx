import { useRouter } from 'expo-router';
import { useState } from 'react';

import { Aviso, Botao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { recuperarConta } from '@/lib/api';
import { formatarData, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';

/**
 * Conta suspensa (apagada há menos de 60 dias): o único caminho é RECUPERAR.
 * Não há opção de "conta nova" aqui — isso protege os 60 dias. Só depois da purga
 * é que o mesmo número pode criar uma conta nova.
 */
export default function RecuperarConta() {
  const router = useRouter();
  const { perfil, actualizar, sair } = useSessao();
  const [ocupado, setOcupado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  async function recuperar() {
    setErro(null);
    setOcupado(true);
    try {
      await recuperarConta();
      await actualizar();
      router.replace('/inicio');
    } catch (e) {
      setErro(mensagemErro(e));
      setOcupado(false);
    }
  }

  async function sairAgora() {
    await sair().catch(() => undefined);
    router.replace('/entrar');
  }

  return (
    <Ecra>
      <Subtitulo>Bem-vindo de volta</Subtitulo>
      <Paragrafo>
        A tua conta está em processo de apagamento. Podes recuperá-la com tudo — nome, histórico e saldo.
      </Paragrafo>
      {perfil?.recuperar_ate && (
        <Paragrafo suave>Podes recuperar até {formatarData(perfil.recuperar_ate)}.</Paragrafo>
      )}
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Botao titulo="Recuperar a minha conta" aoCarregar={recuperar} aCarregar={ocupado} />
      <Botao titulo="Agora não" variante="texto" aoCarregar={sairAgora} desactivado={ocupado} />
    </Ecra>
  );
}
