-- Interruptor da geração por IA das receitas (botão "Gerar rascunho com IA"). Nasce DESLIGADO:
-- por agora as receitas fazem-se à mão. Ligado, o operador pode pedir um rascunho ao Claude.
-- O gate real é no servidor (a edge function receita-rascunho verifica este interruptor); a app
-- apenas esconde o botão quando está desligado.
insert into funcionalidades (chave, activa, dispositivo_id) values ('receitas_ia', false, 'servidor')
  on conflict (chave) do nothing;
