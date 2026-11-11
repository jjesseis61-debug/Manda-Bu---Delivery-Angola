import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';

import { ACarregar } from '@/components/ui';
import { ligarIndicacao } from '@/lib/api';
import { guardarCodigoPendente, limparCodigoPendente } from '@/lib/convite';
import { useSessao } from '@/lib/sessao';

/**
 * Prato partilhado: {site}/p/{prato}?r={código} (ou mandabue://p/{prato}?r=…).
 * Guarda o código de quem partilhou (o registo usa-o) e, se o cliente já tem conta e ainda pode
 * ser convidado, liga a indicação em silêncio. Depois abre o prato; sem conta, vai para a entrada
 * (entrar/registo) com o código já guardado.
 */
export default function PratoPartilhado() {
  const { id, r } = useLocalSearchParams<{ id: string; r?: string }>();
  const { carregado, sessao, perfil, ligada, actualizar } = useSessao();
  const [pronto, setPronto] = useState(false);
  const feito = useRef(false);

  useEffect(() => {
    if (!carregado || feito.current) return;
    feito.current = true;
    (async () => {
      const codigo = r ? await guardarCodigoPendente(String(r)).catch(() => null) : null;
      if (codigo && perfil && ligada('indicacao') && !perfil.tem_ligacao && perfil.cliente_novo && perfil.codigo !== codigo) {
        // As regras (antifraude, auto-convite, prazos) ficam no servidor; uma recusa não impede ver o prato
        const ok = await ligarIndicacao(codigo).then(() => true).catch(() => false);
        if (ok) {
          await limparCodigoPendente().catch(() => undefined);
          await actualizar().catch(() => undefined);
        }
      }
      setPronto(true);
    })();
  }, [carregado, perfil, r, ligada, actualizar]);

  if (!pronto) return <ACarregar />;
  if (!sessao || !perfil) return <Redirect href="/" />;
  return <Redirect href={{ pathname: '/montar/[id]', params: { id: String(id ?? '') } }} />;
}
