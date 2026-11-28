import { TesteExperiencia } from '@/components/TesteExperiencia';

/** Teste do balcão de panelas no «Servir o prato»: A = lista (como era), B = balcão de panelas */
export default function TesteBalcao() {
  return (
    <TesteExperiencia
      experiencia="balcao_recipientes"
      descricao="Contagem nova desde o balcão com recipientes próprios (cartucho, travessa, malga, taça, fruteira…), sobremesa e fruta no tabuleiro. Metade dos clientes monta o prato na lista de sempre (A) e a outra metade no balcão (B: um passo de cada vez, com o tabuleiro em baixo). Cada cliente fica sempre no mesmo grupo. Conta só pedidos não cancelados feitos no dia em que abriram o Servir o prato."
      desligado="O teste está desligado: todos os clientes vêem a lista. Liga «teste_balcao_recipientes» em Parâmetros para começar."
      nomeA="Lista"
      nomeB="Balcão com recipientes"
      ondeVisita="ao Servir o prato"
    />
  );
}
