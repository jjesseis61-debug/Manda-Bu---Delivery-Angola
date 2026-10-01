import type { Session } from '@supabase/supabase-js';
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { AppState } from 'react-native';

import { entrarComoFuncionario } from './api';
import { supabase } from './supabase';
import type { Funcionario, Permissao } from './tipos';

type Sessao = {
  carregado: boolean;
  sessao: Session | null;
  funcionario: Funcionario | null;
  /** Permissão efectiva do organograma (o servidor volta a verificar em cada acção) */
  pode: (p: Permissao) => boolean;
  actualizar: () => Promise<void>;
  sair: () => Promise<void>;
};

const Contexto = createContext<Sessao | null>(null);

export function SessaoProvider({ children }: { children: ReactNode }) {
  const [sessao, setSessao] = useState<Session | null>(null);
  const [funcionario, setFuncionario] = useState<Funcionario | null>(null);
  const [carregado, setCarregado] = useState(false);

  const carregar = useCallback(async (s: Session | null) => {
    if (!s) {
      setFuncionario(null);
      return;
    }
    try {
      setFuncionario(await entrarComoFuncionario());
    } catch {
      // Sem rede: mantém o que já tinha
    }
  }, []);

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      setSessao(data.session);
      await carregar(data.session);
      setCarregado(true);
    });
    const { data } = supabase.auth.onAuthStateChange((_e, nova) => {
      setSessao(nova);
      void carregar(nova);
    });
    return () => data.subscription.unsubscribe();
  }, [carregar]);

  // As permissões podem mudar no organograma: relê ao voltar à app
  useEffect(() => {
    const sub = AppState.addEventListener('change', (estado) => {
      if (estado === 'active') void carregar(sessao);
    });
    return () => sub.remove();
  }, [sessao, carregar]);

  const valor = useMemo<Sessao>(
    () => ({
      carregado,
      sessao,
      funcionario,
      pode: (p) => funcionario?.permissoes.includes(p) ?? false,
      actualizar: () => carregar(sessao),
      sair: async () => {
        await supabase.auth.signOut();
      },
    }),
    [carregado, sessao, funcionario, carregar],
  );
  return <Contexto.Provider value={valor}>{children}</Contexto.Provider>;
}

export function useSessao(): Sessao {
  const s = useContext(Contexto);
  if (!s) throw new Error('useSessao fora de SessaoProvider');
  return s;
}
