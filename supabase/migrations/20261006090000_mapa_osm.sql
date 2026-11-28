-- Mapa: por defeito a app usa o OpenStreetMap (grátis, sem chave, sem faturação).
-- Interruptor `mapa_google` (desligado): quando ligado — e se o build tiver a chave do Google Maps
-- (Android) ou no iOS (Apple Maps) — a app passa a usar o Google/Apple Maps em vez do OSM.
-- É um interruptor só da app (não há função SECURITY DEFINER a lê-lo no servidor).
insert into funcionalidades (chave, activa, dispositivo_id) values ('mapa_google', false, 'servidor')
on conflict (chave) do nothing;
