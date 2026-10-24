-- Contactos públicos: os gerais da Manda Bué (em parametros, editados em Parâmetros com alterar_parametros, que
-- fica na auditoria) e os de cada cozinha (telefone, WhatsApp e horário públicos, editados no ecrã da cozinha por
-- quem tem cozinhas.gerir). Os clientes com sessão lêem-nos com contactos(), que só devolve estes campos públicos
-- (como as outras funções SECURITY DEFINER, não é chamável sem sessão). Os contactos de uma cozinha não
-- dependem do consentimento do perfil público (que é sobre o nome, a foto e a história da responsável): só aparecem
-- os que forem preenchidos nestes campos, e cozinhas inactivas não aparecem. O assistente do atendimento também
-- os conhece (atd_informacoes).

alter table parametros
  add column contacto_telefone text check (contacto_telefone ~ '^\+?[0-9 ]{9,20}$'),
  add column contacto_whatsapp text check (contacto_whatsapp ~ '^\+?[0-9 ]{9,20}$'),
  add column contacto_email    text check (contacto_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(contacto_email) <= 120),
  add column contacto_horario  text check (char_length(contacto_horario) <= 120),
  add column contacto_morada   text check (char_length(contacto_morada) <= 200);
comment on column parametros.contacto_telefone is 'Telefone geral da Manda Bué mostrado aos clientes (Contactos)';
comment on column parametros.contacto_whatsapp is 'WhatsApp geral mostrado aos clientes (com ou sem +244)';
comment on column parametros.contacto_email is 'Email geral mostrado aos clientes (também o contacto de privacidade)';
comment on column parametros.contacto_horario is 'Horário de atendimento mostrado aos clientes, em texto livre';
comment on column parametros.contacto_morada is 'Morada da loja ou escritório mostrada aos clientes';

alter table cozinhas
  add column telefone_publico text check (telefone_publico ~ '^\+?[0-9 ]{9,20}$'),
  add column whatsapp_publico text check (whatsapp_publico ~ '^\+?[0-9 ]{9,20}$'),
  add column horario_publico  text check (char_length(horario_publico) <= 120);
comment on column cozinhas.telefone_publico is 'Telefone da cozinha mostrado aos clientes (Contactos e página da cozinha)';
comment on column cozinhas.whatsapp_publico is 'WhatsApp da cozinha mostrado aos clientes';
comment on column cozinhas.horario_publico is 'Horário da cozinha mostrado aos clientes, em texto livre';

create or replace function contactos() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'geral', (select jsonb_build_object('telefone', contacto_telefone, 'whatsapp', contacto_whatsapp, 'email', contacto_email,
                                        'horario', contacto_horario, 'morada', contacto_morada)
                from parametros where unico),
    'cozinhas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nome', trim(c.nome), 'estado', c.estado,
                                                             'telefone', c.telefone_publico, 'whatsapp', c.whatsapp_publico,
                                                             'horario', c.horario_publico) order by c.criado_em)
                            from cozinhas c
                           where c.deletado_em is null and c.estado <> 'inactiva'
                             and coalesce(c.telefone_publico, c.whatsapp_publico, c.horario_publico) is not null), '[]'));
$$;
revoke execute on function contactos() from public, anon;
grant execute on function contactos() to authenticated;

-- O assistente do atendimento passa a conhecer os contactos
create or replace function atd_informacoes() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'cozinhas', coalesce((select jsonb_agg(jsonb_build_object(
        'cozinha', trim(z.nome), 'estado', z.estado,
        'pratos_disponiveis', coalesce((select jsonb_agg(jsonb_build_object('prato', c.nome, 'descricao', c.descricao,
                                                                           'preco_kz', c.preco, 'prato_do_dia', c.do_dia) order by c.ordem)
                                          from cardapio c where c.cozinha_id = z.id and c.disponivel and c.deletado_em is null), '[]')))
        from cozinhas z where z.deletado_em is null), '[]'),
    'zonas', coalesce((select jsonb_agg(jsonb_build_object('zona', nome, 'taxa_kz', taxa, 'tipo', tipo,
                                                          'por_km_kz', case when modo_calculo = 'Distância' then tarifa_por_km end) order by nome)
                         from zonas where deletado_em is null), '[]'),
    'regras', (select jsonb_build_object(
        'tempo_de_entrega_min', tempo_entrega_min,
        'convida_e_ganha', jsonb_build_object('desconto_do_amigo_no_1o_pedido_kz', desconto_indicado,
                                              'ganho_por_pedido_do_amigo_kz', ganho_por_pedido, 'durante_dias', duracao_dias,
                                              'levantamento_minimo_kz', levantamento_minimo),
        'pacotes', (select coalesce(jsonb_agg(jsonb_build_object('pacote', nome, 'refeicoes', refeicoes + refeicoes_oferta,
                                                                 'preco_kz', preco, 'validade_dias', validade_dias,
                                                                 'entrega_gratis', entrega_gratis) order by ordem), '[]')
                      from pacotes where activo and deletado_em is null))
                from parametros where unico),
    'contactos', contactos(),
    'agora', to_char(now() at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'));
$$;
revoke execute on function atd_informacoes() from public, anon, authenticated;
grant execute on function atd_informacoes() to service_role;
