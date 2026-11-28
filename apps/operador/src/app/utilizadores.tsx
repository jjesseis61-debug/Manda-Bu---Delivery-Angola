import { useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import {
  bloquearUtilizador,
  desbloquearUtilizador,
  listarUtilizadoresBloqueados,
  procurarUtilizadores,
} from '@/lib/api';
import { formatarData, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import type { UtilizadorBloqueado, UtilizadorEncontrado } from '@/lib/tipos';

const nomeTipo: Record<UtilizadorEncontrado['tipo'], string> = {
  cliente: 'Cliente',
  equipa: 'Equipa',
  login: 'Só login',
};

function Etiqueta({ texto, cor, fundo }: { texto: string; cor: string; fundo: string }) {
  return (
    <View style={{ backgroundColor: fundo, paddingHorizontal: 8, paddingVertical: 2, borderRadius: raio, alignSelf: 'flex-start' }}>
      <Text style={{ color: cor, fontSize: 12, fontWeight: '700' }}>{texto}</Text>
    </View>
  );
}

/** Utilizadores: procurar clientes, equipa e contas de login (OTP) por nome ou número; o administrador
 *  principal pode bloquear ou desbloquear um número. */
export default function Utilizadores() {
  const { funcionario } = useSessao();
  const admin = !!funcionario?.administrador_principal;

  const [aba, setAba] = useState<'procurar' | 'bloqueados'>('procurar');
  const [termo, setTermo] = useState('');
  const [resultados, setResultados] = useState<UtilizadorEncontrado[] | null>(null);
  const [bloqueados, setBloqueados] = useState<UtilizadorBloqueado[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  // Bloqueio em curso: número a bloquear e o motivo a escrever
  const [aBloquear, setABloquear] = useState<{ telefone: string; nome: string } | null>(null);
  const [motivo, setMotivo] = useState('');

  // Procura com um pequeno atraso para não chamar o servidor a cada tecla
  useEffect(() => {
    if (aba !== 'procurar') return;
    const t = termo.trim();
    if (t.length < 2) {
      setResultados(null);
      return;
    }
    let activo = true;
    const id = setTimeout(() => {
      procurarUtilizadores(t)
        .then((r) => activo && setResultados(r))
        .catch((e) => activo && setErro(mensagemErro(e)));
    }, 400);
    return () => {
      activo = false;
      clearTimeout(id);
    };
  }, [termo, aba]);

  const carregarBloqueados = useCallback(() => {
    listarUtilizadoresBloqueados()
      .then(setBloqueados)
      .catch((e) => setErro(mensagemErro(e)));
  }, []);

  useFocusEffect(
    useCallback(() => {
      if (aba === 'bloqueados') carregarBloqueados();
    }, [aba, carregarBloqueados]),
  );

  async function confirmarBloqueio() {
    if (!aBloquear) return;
    setErro(null);
    setOcupado(true);
    try {
      await bloquearUtilizador(aBloquear.telefone, motivo.trim() || null);
      setABloquear(null);
      setMotivo('');
      if (aba === 'procurar') setResultados(await procurarUtilizadores(termo.trim()));
      else carregarBloqueados();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  async function desbloquear(telefone: string) {
    setErro(null);
    setOcupado(true);
    try {
      await desbloquearUtilizador(telefone);
      if (aba === 'procurar') setResultados(await procurarUtilizadores(termo.trim()));
      else carregarBloqueados();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  return (
    <Guarda permissoes={['utilizadores.ver']}>
      <Ecra>
        <Escolha
          opcoes={[
            { valor: 'procurar', rotulo: 'Procurar' },
            { valor: 'bloqueados', rotulo: 'Bloqueados' },
          ]}
          valor={aba}
          aoMudar={(v) => {
            setErro(null);
            setABloquear(null);
            setAba(v as 'procurar' | 'bloqueados');
          }}
        />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}

        {aba === 'procurar' && (
          <>
            <Campo
              rotulo="Nome ou número"
              value={termo}
              onChangeText={setTermo}
              placeholder="Ex.: Alegria ou 924287222"
              autoCapitalize="none"
            />
            {resultados === null && termo.trim().length < 2 && (
              <Paragrafo suave>Escreve pelo menos 2 letras do nome, ou 3 dígitos do número.</Paragrafo>
            )}
            {resultados !== null && resultados.length === 0 && (
              <Paragrafo suave>Ninguém inscrito corresponde a “{termo.trim()}”.</Paragrafo>
            )}
            {resultados?.map((u) => (
              <CartaoUtilizador
                key={`${u.tipo}-${u.id}`}
                u={u}
                admin={admin}
                ocupado={ocupado}
                aoBloquear={() => setABloquear({ telefone: u.telefone ?? '', nome: u.nome ?? u.telefone ?? 'utilizador' })}
                aoDesbloquear={() => u.telefone && desbloquear(u.telefone)}
              />
            ))}
          </>
        )}

        {aba === 'bloqueados' && (
          <>
            {!bloqueados && <ACarregar />}
            {bloqueados && bloqueados.length === 0 && <Paragrafo suave>Não há números bloqueados.</Paragrafo>}
            {bloqueados?.map((b) => (
              <Cartao key={b.telefone}>
                <View style={{ gap: 4 }}>
                  <Etiqueta texto="Bloqueado" cor="#fff" fundo={cores.marca} />
                  <Text style={{ fontWeight: '700', fontSize: 16 }}>{b.nome ?? 'Sem perfil'}</Text>
                  <Text style={{ color: cores.textoSuave }}>{b.telefone}</Text>
                  {b.motivo && <Text style={{ color: cores.texto }}>Motivo: {b.motivo}</Text>}
                  <Text style={{ color: cores.textoSuave }}>
                    Desde {formatarData(b.bloqueado_em, true)}
                    {b.bloqueado_por_nome ? ` · por ${b.bloqueado_por_nome}` : ''}
                  </Text>
                  {admin && <Botao titulo="Desbloquear" variante="secundario" aCarregar={ocupado} aoCarregar={() => desbloquear(b.telefone)} />}
                </View>
              </Cartao>
            ))}
          </>
        )}

        {aBloquear && (
          <Cartao estilo={{ borderColor: cores.marca, borderWidth: 1 }}>
            <View style={{ gap: espaco.s }}>
              <Subtitulo>Bloquear {aBloquear.nome}</Subtitulo>
              <Paragrafo suave>
                Deixa de poder entrar e registar-se com este número. As sessões já abertas podem demorar até cerca de 1 hora a cair.
              </Paragrafo>
              <Campo rotulo="Motivo (opcional)" value={motivo} onChangeText={setMotivo} placeholder="Ex.: abuso / spam" maxLength={120} />
              <Botao titulo="Confirmar bloqueio" aCarregar={ocupado} aoCarregar={confirmarBloqueio} />
              <Botao
                titulo="Cancelar"
                variante="texto"
                aoCarregar={() => {
                  setABloquear(null);
                  setMotivo('');
                }}
              />
            </View>
          </Cartao>
        )}
      </Ecra>
    </Guarda>
  );
}

function CartaoUtilizador({
  u,
  admin,
  ocupado,
  aoBloquear,
  aoDesbloquear,
}: {
  u: UtilizadorEncontrado;
  admin: boolean;
  ocupado: boolean;
  aoBloquear: () => void;
  aoDesbloquear: () => void;
}) {
  const podeBloquear = admin && u.tipo !== 'equipa' && !!u.telefone; // a equipa gere-se em Pessoal
  return (
    <Cartao estilo={u.bloqueado ? { borderColor: cores.marca, borderWidth: 1 } : undefined}>
      <View style={{ gap: 4 }}>
        <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
          <Etiqueta texto={nomeTipo[u.tipo]} cor={cores.texto} fundo={cores.marcaClara} />
          {u.bloqueado && <Etiqueta texto="Bloqueado" cor="#fff" fundo={cores.marca} />}
        </View>
        <Text style={{ fontWeight: '700', fontSize: 16 }}>{u.nome ?? 'Sem perfil (só login)'}</Text>
        {u.telefone && <Text style={{ color: cores.textoSuave }}>{u.telefone}</Text>}
        {u.tipo === 'equipa' && u.cargo && <Text style={{ color: cores.textoSuave }}>Cargo: {u.cargo}</Text>}
        <Text style={{ color: cores.textoSuave }}>
          Inscrito em {formatarData(u.inscrito_em, true)}
          {u.tem_login ? ' · tem login' : ' · sem login'}
        </Text>
        {u.tipo === 'cliente' && (
          <Text style={{ color: cores.textoSuave }}>
            {u.total_pedidos > 0 ? `${u.total_pedidos} pedido(s); último em ${formatarData(u.ultimo_pedido)}` : 'Ainda sem pedidos entregues'}
          </Text>
        )}
        {u.bloqueado && u.motivo_bloqueio && <Text style={{ color: cores.texto }}>Motivo: {u.motivo_bloqueio}</Text>}
        {podeBloquear &&
          (u.bloqueado ? (
            <Botao titulo="Desbloquear" variante="secundario" aCarregar={ocupado} aoCarregar={aoDesbloquear} />
          ) : (
            <Botao titulo="Bloquear" variante="secundario" aCarregar={ocupado} aoCarregar={aoBloquear} />
          ))}
      </View>
    </Cartao>
  );
}
