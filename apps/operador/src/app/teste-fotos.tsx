import { TesteExperiencia } from '@/components/TesteExperiencia';

/** Teste das fotografias do Início: A = fotografia grande (como era), B = fotografia média ao lado do nome */
export default function TesteFotos() {
  return (
    <TesteExperiencia
      experiencia="fotos_inicio"
      descricao="Metade dos clientes vê a fotografia grande (A, como era) e a outra metade a fotografia média ao lado do nome (B). Cada cliente fica sempre no mesmo grupo. Conta só pedidos não cancelados feitos no dia da visita."
      desligado="O teste está desligado: todos os clientes vêem a fotografia média. Liga «teste_fotos_inicio» em Parâmetros para começar."
      nomeA="Fotografia grande"
      nomeB="Fotografia média"
      ondeVisita="ao Início"
    />
  );
}
