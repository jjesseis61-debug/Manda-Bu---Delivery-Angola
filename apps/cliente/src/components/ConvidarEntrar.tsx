import { useRouter } from 'expo-router';

import { BlocoContactos, temContacto } from '@/components/BlocoContactos';
import { Botao, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { CONTACTO_AJUDA } from '@/lib/empresa';

/** Separadores pessoais (Pedidos, Conta) para quem ainda não tem conta: o que ganha ao entrar */
export function ConvidarEntrar({ titulo, texto, ajuda = false }: { titulo: string; texto: string; ajuda?: boolean }) {
  const router = useRouter();
  return (
    <Ecra>
      <Cartao>
        <Subtitulo>{titulo}</Subtitulo>
        <Paragrafo suave>{texto}</Paragrafo>
        <Botao titulo="Entrar ou criar conta" aoCarregar={() => router.push('/entrar')} />
        <Paragrafo suave>Só precisas do teu número de telefone. Enviamos-te um código para confirmar.</Paragrafo>
      </Cartao>
      <Botao titulo="Ver o cardápio" variante="secundario" aoCarregar={() => router.replace('/inicio')} />
      {ajuda && temContacto(CONTACTO_AJUDA) && <BlocoContactos contacto={CONTACTO_AJUDA} titulo="Precisas de ajuda? Fala connosco" />}
      {ajuda && <Botao titulo="Política de privacidade" variante="texto" aoCarregar={() => router.push('/politica-privacidade')} />}
    </Ecra>
  );
}
