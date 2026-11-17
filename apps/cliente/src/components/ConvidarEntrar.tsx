import { useRouter } from 'expo-router';
import { useState } from 'react';

import { BlocoContactos, temContacto } from '@/components/BlocoContactos';
import { LoginNecessario } from '@/components/LoginNecessario';
import { Botao, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { CONTACTO_AJUDA } from '@/lib/empresa';
import type { Destino } from '@/lib/visitante';

/** Separadores pessoais (Pedidos, Conta) para quem ainda não tem conta: o que ganha ao entrar */
export function ConvidarEntrar({ titulo, texto, destino, ajuda = false }: { titulo: string; texto: string; destino: Destino; ajuda?: boolean }) {
  const router = useRouter();
  const [folha, setFolha] = useState(false);
  return (
    <Ecra>
      <Cartao>
        <Subtitulo>{titulo}</Subtitulo>
        <Paragrafo suave>{texto}</Paragrafo>
        <Botao titulo="Entrar ou criar conta" aoCarregar={() => setFolha(true)} />
        <Paragrafo suave>Só precisas do teu número de telefone. Enviamos-te um código para confirmar.</Paragrafo>
      </Cartao>
      <Botao titulo="Ver o cardápio" variante="secundario" aoCarregar={() => router.replace('/inicio')} />
      {ajuda && temContacto(CONTACTO_AJUDA) && <BlocoContactos contacto={CONTACTO_AJUDA} titulo="Precisas de ajuda? Fala connosco" />}
      {ajuda && <Botao titulo="Política de privacidade" variante="texto" aoCarregar={() => router.push('/politica-privacidade')} />}
      <LoginNecessario visivel={folha} motivo={texto} destino={destino} aoFechar={() => setFolha(false)} />
    </Ecra>
  );
}
