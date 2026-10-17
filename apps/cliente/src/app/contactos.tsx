import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';

import { BlocoContactos, temContacto } from '@/components/BlocoContactos';
import { ACarregar, Aviso, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { lerContactos } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import type { Contactos as TContactos } from '@/lib/tipos';

/** Contactos da Manda Bué e de cada cozinha (os que a equipa preencheu) */
export default function Contactos() {
  const [contactos, setContactos] = useState<TContactos | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      lerContactos().then(setContactos, (e) => setErro(mensagemErro(e)));
    }, []),
  );

  if (erro) return <Ecra><Aviso tipo="erro">{erro}</Aviso></Ecra>;
  if (!contactos) return <ACarregar />;
  const geral = temContacto(contactos.geral) ? contactos.geral : null;

  return (
    <Ecra>
      <Subtitulo>Manda Bué</Subtitulo>
      {geral ? <BlocoContactos contacto={geral} /> : <Paragrafo suave>Os contactos gerais ainda não estão disponíveis.</Paragrafo>}
      {contactos.cozinhas.length > 0 && <Subtitulo>Cozinhas</Subtitulo>}
      {contactos.cozinhas.map((c) => (
        <BlocoContactos key={c.id} titulo={c.estado === 'pausada' ? `${c.nome} (em pausa)` : c.nome} contacto={c} />
      ))}
    </Ecra>
  );
}
