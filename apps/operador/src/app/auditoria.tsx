import { useEffect, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Cartao, Ecra, Escolha, Paragrafo } from '@/components/ui';
import { auditoriaLista } from '@/lib/api';
import { formatarData, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { LinhaAuditoria } from '@/lib/tipos';

type Categoria = '' | 'login' | 'cardapio' | 'equipa' | 'caixa' | 'clientes' | 'config';
type Periodo = '1' | '7' | '30' | 'tudo';

/** "há quantos dias" -> data a partir da qual mostrar (ou null = tudo) */
function desdeDe(p: Periodo): string | null {
  if (p === 'tudo') return null;
  const d = new Date();
  d.setDate(d.getDate() - Number(p));
  return d.toISOString();
}

/** Registo de auditoria (geral): tudo o que aconteceu, com filtro por categoria e período. */
export default function Auditoria() {
  const [categoria, setCategoria] = useState<Categoria>('');
  const [periodo, setPeriodo] = useState<Periodo>('7');
  const [linhas, setLinhas] = useState<LinhaAuditoria[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;
    setLinhas(null);
    setErro(null);
    auditoriaLista(categoria || null, desdeDe(periodo)).then(
      (r) => vivo && setLinhas(r),
      (e) => vivo && setErro(mensagemErro(e)),
    );
    return () => {
      vivo = false;
    };
  }, [categoria, periodo]);

  return (
    <Guarda permissoes={['auditoria.ver']}>
      <Ecra>
        <Paragrafo suave>Tudo o que aconteceu na plataforma: quem fez o quê e quando. O registo não se edita nem se apaga.</Paragrafo>
        <Escolha
          opcoes={[
            { valor: '', rotulo: 'Tudo' },
            { valor: 'login', rotulo: 'Logins' },
            { valor: 'cardapio', rotulo: 'Cardápio' },
            { valor: 'equipa', rotulo: 'Equipa' },
            { valor: 'caixa', rotulo: 'Caixa' },
            { valor: 'clientes', rotulo: 'Clientes' },
            { valor: 'config', rotulo: 'Configuração' },
          ]}
          valor={categoria}
          aoMudar={setCategoria}
        />
        <Escolha
          opcoes={[
            { valor: '1', rotulo: 'Hoje' },
            { valor: '7', rotulo: '7 dias' },
            { valor: '30', rotulo: '30 dias' },
            { valor: 'tudo', rotulo: 'Tudo' },
          ]}
          valor={periodo}
          aoMudar={setPeriodo}
        />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!linhas && !erro && <ACarregar />}
        {linhas && linhas.length === 0 && <Paragrafo suave>Sem registos neste filtro.</Paragrafo>}
        {linhas?.map((l) => (
          <Cartao key={l.id}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: espaco.s }}>
              <Text style={{ fontWeight: '700', flex: 1, color: cores.texto }}>
                {l.bloqueado ? '⛔ ' : ''}
                {l.acao.replace(/_/g, ' ')}
              </Text>
              <Text style={{ color: cores.textoSuave, fontSize: 12 }}>{formatarData(l.criado_em, true)}</Text>
            </View>
            <Text style={{ color: cores.textoSuave, fontSize: 13 }}>
              {l.quem}
              {l.ref_tipo ? ` · ${l.ref_tipo}` : ''}
            </Text>
            {l.detalhe && l.detalhe !== '{}' && (
              <Text style={{ color: cores.textoSuave, fontSize: 12 }} numberOfLines={3}>
                {l.detalhe}
              </Text>
            )}
          </Cartao>
        ))}
      </Ecra>
    </Guarda>
  );
}
