-- Permissão por-cozinha para o cardápio: quem tem "cardapio.gerir" edita o cardápio e o perfil
-- APENAS das cozinhas de que é membro (equipa/turno). "cozinhas.gerir" (chave-mestra) continua a
-- poder tudo e é o único que cria/apaga cozinhas. As fotos dos pratos ficam, por agora, com a
-- chave-mestra (o caminho no armazenamento não tem a cozinha) — fica para uma 2.ª fase.

-- Catálogo: nova permissão (grupo Cozinhas).
insert into permissoes (chave, grupo, descricao, dispositivo_id)
values ('cardapio.gerir', 'Cozinhas', 'Editar o cardápio e o perfil da própria cozinha', 'servidor')
on conflict (chave) do nothing;

-- cardapio: pratos (nome, preço, disponibilidade, prato do dia) — cozinha_id directo.
alter policy "criar" on public.cardapio
  with check ((select tem_permissao('cozinhas.gerir')) or pode_na_cozinha('cardapio.gerir', cozinha_id));
alter policy "editar" on public.cardapio
  using ((select tem_permissao('cozinhas.gerir')) or pode_na_cozinha('cardapio.gerir', cozinha_id))
  with check ((select tem_permissao('cozinhas.gerir')) or pode_na_cozinha('cardapio.gerir', cozinha_id));

-- opcoes_grupos: grupos de opções de um prato — cozinha via cardapio_id.
alter policy "criar" on public.opcoes_grupos
  with check ((select tem_permissao('cozinhas.gerir'))
              or pode_na_cozinha('cardapio.gerir', (select cozinha_id from cardapio where id = cardapio_id)));
alter policy "editar" on public.opcoes_grupos
  using ((select tem_permissao('cozinhas.gerir'))
         or pode_na_cozinha('cardapio.gerir', (select cozinha_id from cardapio where id = cardapio_id)))
  with check ((select tem_permissao('cozinhas.gerir'))
              or pode_na_cozinha('cardapio.gerir', (select cozinha_id from cardapio where id = cardapio_id)));

-- opcoes: opções dentro de um grupo — cozinha via grupo_id -> cardapio.
alter policy "criar" on public.opcoes
  with check ((select tem_permissao('cozinhas.gerir'))
              or pode_na_cozinha('cardapio.gerir',
                   (select c.cozinha_id from opcoes_grupos og join cardapio c on c.id = og.cardapio_id where og.id = grupo_id)));
alter policy "editar" on public.opcoes
  using ((select tem_permissao('cozinhas.gerir'))
         or pode_na_cozinha('cardapio.gerir',
              (select c.cozinha_id from opcoes_grupos og join cardapio c on c.id = og.cardapio_id where og.id = grupo_id)))
  with check ((select tem_permissao('cozinhas.gerir'))
              or pode_na_cozinha('cardapio.gerir',
                   (select c.cozinha_id from opcoes_grupos og join cardapio c on c.id = og.cardapio_id where og.id = grupo_id)));

-- cozinhas: EDITAR o perfil da própria cozinha. CRIAR cozinha nova continua só com a chave-mestra.
alter policy "editar" on public.cozinhas
  using ((select tem_permissao('cozinhas.gerir')) or pode_na_cozinha('cardapio.gerir', id))
  with check ((select tem_permissao('cozinhas.gerir')) or pode_na_cozinha('cardapio.gerir', id));

-- cozinhas_localizacao: morada / "como chegar" — cozinha_id directo.
alter policy "criar" on public.cozinhas_localizacao
  with check ((select tem_permissao('cozinhas.gerir')) or pode_na_cozinha('cardapio.gerir', cozinha_id));
alter policy "editar" on public.cozinhas_localizacao
  using ((select tem_permissao('cozinhas.gerir')) or pode_na_cozinha('cardapio.gerir', cozinha_id))
  with check ((select tem_permissao('cozinhas.gerir')) or pode_na_cozinha('cardapio.gerir', cozinha_id));
