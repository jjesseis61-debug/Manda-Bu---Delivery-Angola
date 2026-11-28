import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';

import { ACarregar } from '@/components/ui';
import { guardarCodigoPendente } from '@/lib/convite';
import { useSessao } from '@/lib/sessao';

/** Link de convite (mandabue://convite/MB1234): guarda o código para pré-preencher C2 */
export default function Convite() {
  const { codigo } = useLocalSearchParams<{ codigo: string }>();
  const { carregado, perfil } = useSessao();
  const [pronto, setPronto] = useState(false);

  useEffect(() => {
    if (!carregado) return;
    // O próprio código não se guarda (quem abre o seu link)
    guardarCodigoPendente(String(codigo ?? ''), perfil?.codigo).finally(() => setPronto(true));
  }, [codigo, carregado, perfil?.codigo]);

  return pronto ? <Redirect href="/" /> : <ACarregar />;
}
