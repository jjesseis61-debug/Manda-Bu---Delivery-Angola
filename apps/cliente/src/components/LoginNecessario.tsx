import { useRouter } from 'expo-router';

import { Confirmar } from '@/components/Confirmar';
import { guardarDestino, type Destino } from '@/lib/visitante';

/**
 * Folha «entra na tua conta» para o visitante: aparece ao tocar numa função pessoal (avisos,
 * pacote, grupo…), diz porquê e, depois de entrar, volta ao sítio de onde veio (`destino`).
 */
export function LoginNecessario({
  visivel,
  motivo,
  destino,
  aoFechar,
}: {
  visivel: boolean;
  motivo: string;
  destino: Destino;
  aoFechar: () => void;
}) {
  const router = useRouter();
  return (
    <Confirmar
      visivel={visivel}
      titulo="Entra na tua conta"
      mensagem={`${motivo} Só precisas do teu número de telefone: enviamos-te um código para confirmar.`}
      textoConfirmar="Entrar"
      textoCancelar="Agora não"
      aoConfirmar={async () => {
        aoFechar();
        await guardarDestino(destino);
        router.push('/entrar');
      }}
      aoCancelar={aoFechar}
    />
  );
}
