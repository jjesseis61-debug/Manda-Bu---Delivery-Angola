// Estado do cadeado na app: bloqueia ao abrir e ao voltar depois de GRACA_MS em segundo plano,
// e confirma acções sensíveis (levantamento, apagar conta). Sem cadeado ligado, não faz nada.
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { AppState } from 'react-native';

import { GRACA_MS, estaActivo, removerCadeado } from './cadeado';
import { useSessao } from './sessao';

/** Pedido de confirmação de uma acção sensível (o ecrã de cadeado resolve-o) */
export type PedidoConfirmacao = { motivo: string; resolver: (ok: boolean) => void };

type Cadeado = {
  /** 'a_verificar' enquanto lê o cofre ao arrancar (o ecrã fica tapado, sem mostrar dados) */
  estado: 'a_verificar' | 'aberto' | 'bloqueado';
  activo: boolean;
  desbloquear: () => void;
  /** Volta a ler se o cadeado está ligado (depois de o ligar/desligar em Conta) */
  recarregar: () => Promise<void>;
  /** Resolve true sem perguntar quando o cadeado está desligado */
  confirmar: (motivo: string) => Promise<boolean>;
  pedido: PedidoConfirmacao | null;
};

const Contexto = createContext<Cadeado | null>(null);

export function CadeadoProvider({ children }: { children: ReactNode }) {
  const { carregado, sessao } = useSessao();
  const [activo, setActivo] = useState(false);
  const [estado, setEstado] = useState<Cadeado['estado']>('a_verificar');
  const [pedido, setPedido] = useState<PedidoConfirmacao | null>(null);
  const saiuEm = useRef<number | null>(null);
  const comSessao = !!sessao;

  // Ao arrancar (ou ao entrar/sair da conta): com cadeado ligado e sessão, começa bloqueado
  useEffect(() => {
    if (!carregado) return;
    let vivo = true;
    (async () => {
      if (!comSessao) {
        // Sem conta neste aparelho: nada a proteger, e quem entrar a seguir começa sem cadeado
        await removerCadeado();
        if (vivo) {
          setActivo(false);
          setEstado('aberto');
        }
        return;
      }
      const a = await estaActivo();
      if (!vivo) return;
      setActivo(a);
      setEstado(a ? 'bloqueado' : 'aberto');
    })();
    return () => {
      vivo = false;
    };
  }, [carregado, comSessao]);

  // Segundo plano: volta a bloquear se esteve fora mais do que a graça
  useEffect(() => {
    const sub = AppState.addEventListener('change', (e) => {
      if (e === 'background' || e === 'inactive') {
        if (saiuEm.current === null) saiuEm.current = Date.now();
      } else if (e === 'active') {
        const fora = saiuEm.current === null ? 0 : Date.now() - saiuEm.current;
        saiuEm.current = null;
        if (activo && comSessao && fora >= GRACA_MS) setEstado('bloqueado');
      }
    });
    return () => sub.remove();
  }, [activo, comSessao]);

  const recarregar = useCallback(async () => {
    setActivo(await estaActivo());
  }, []);

  const confirmar = useCallback(
    (motivo: string) => {
      if (!activo) return Promise.resolve(true);
      return new Promise<boolean>((resolver) => {
        setPedido({
          motivo,
          resolver: (ok) => {
            setPedido(null);
            resolver(ok);
          },
        });
      });
    },
    [activo],
  );

  const valor = useMemo<Cadeado>(
    () => ({ estado, activo, desbloquear: () => setEstado('aberto'), recarregar, confirmar, pedido }),
    [estado, activo, recarregar, confirmar, pedido],
  );
  return <Contexto.Provider value={valor}>{children}</Contexto.Provider>;
}

export function useCadeado(): Cadeado {
  const c = useContext(Contexto);
  if (!c) throw new Error('useCadeado fora de CadeadoProvider');
  return c;
}
