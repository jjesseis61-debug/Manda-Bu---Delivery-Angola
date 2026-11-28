import { type Href, Redirect } from 'expo-router';
import { useEffect, useState } from 'react';

import { ACarregar } from '@/components/ui';
import { useSessao } from '@/lib/sessao';
import { tirarDestino } from '@/lib/visitante';

/**
 * Porta de entrada: sem sessão → início do visitante; sem cliente registado → registo; senão → início.
 * Quem montou o carrinho como visitante e entrou agora volta ao carrinho.
 */
export default function Entrada() {
  const { carregado, sessao, perfil } = useSessao();
  const [destino, setDestino] = useState<Href | null | undefined>(undefined);
  const pronto = carregado && !!sessao && !!perfil && !perfil.suspensa;

  useEffect(() => {
    if (!pronto) return;
    let vivo = true;
    tirarDestino().then((d) => vivo && setDestino(d ?? '/inicio'));
    return () => {
      vivo = false;
    };
  }, [pronto]);

  if (!carregado) return <ACarregar />;
  // Sem conta: a app abre no Início, como para quem já entrou (o número só é pedido no «Pedir»)
  if (!sessao) return <Redirect href="/inicio" />;
  if (!perfil) return <Redirect href="/registo" />;
  if (perfil.suspensa) return <Redirect href="/recuperar-conta" />;
  if (destino === undefined) return <ACarregar />;
  return <Redirect href={destino ?? '/inicio'} />;
}
