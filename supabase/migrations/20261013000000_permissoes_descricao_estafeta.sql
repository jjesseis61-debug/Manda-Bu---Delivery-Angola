-- Descrições mais claras das permissões do grupo Pedidos: dizer logo o PAPEL (estafeta vs gerente),
-- em vez do jargão técnico. O texto é o que o admin lê no ecrã Pessoal ao dar permissões.
update permissoes
   set descricao = 'Estafeta — levar entregas: marcar «saiu para entrega» e «entregue e pago»'
 where chave = 'entregas.registar';

update permissoes
   set descricao = 'Gerir pedidos — confirmar, preparar, cancelar e atribuir entregas a estafetas'
 where chave = 'pedidos.gerir';
