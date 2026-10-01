import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';

import { ACarregar } from '@/components/ui';
import { guardarCodigoPendente } from '@/lib/convite';

/** Link de convite (mandabue://convite/MB-1234): guarda o código para pré-preencher C2 */
export default function Convite() {
  const { codigo } = useLocalSearchParams<{ codigo: string }>();
  const [pronto, setPronto] = useState(false);

  useEffect(() => {
    guardarCodigoPendente(String(codigo ?? '')).finally(() => setPronto(true));
  }, [codigo]);

  return pronto ? <Redirect href="/" /> : <ACarregar />;
}
