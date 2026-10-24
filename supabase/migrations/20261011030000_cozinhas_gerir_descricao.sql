-- Clareza no ecrã Pessoal: a permissão cozinhas.gerir é, na prática, a "chave mestra" que dá acesso a
-- TODAS as cozinhas e caixas (pode_na_cozinha devolve true para qualquer cozinha a quem a tenha). A
-- descrição antiga só falava de criar/editar cozinhas. Explicita o acesso total entre cozinhas, para
-- quem atribui perceber a diferença entre um gestor geral e um gerente limitado à sua cozinha.
update permissoes
   set descricao = 'Criar/editar cozinhas e gerir TODAS as cozinhas e caixas (acesso total entre cozinhas). Sem esta, o funcionário fica limitado às cozinhas que lhe forem atribuídas.'
 where chave = 'cozinhas.gerir';
