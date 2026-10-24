import { Redirect } from 'expo-router';

import { ACarregar } from '@/components/ui';
import { useSessao } from '@/lib/sessao';

/** Porta de entrada: sem sessão → entrar; sem cliente registado → registo; senão → início */
export default function Entrada() {
  const { carregado, sessao, perfil } = useSessao();
  if (!carregado) return <ACarregar />;
  if (!sessao) return <Redirect href="/entrar" />;
  if (!perfil) return <Redirect href="/registo" />;
  if (perfil.suspensa) return <Redirect href="/recuperar-conta" />;
  return <Redirect href="/inicio" />;
}
