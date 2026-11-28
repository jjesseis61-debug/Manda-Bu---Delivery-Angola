import { useFocusEffect } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import {
  criarFuncionario,
  definirCozinhas,
  definirPermissoes,
  definirTelefoneFuncionario,
  editarFuncionario,
  lerCozinhas,
  listarPessoal,
  permissoesCatalogo,
} from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { cores, espaco, raio } from '@/lib/tema';
import type { Cozinha, PermissaoCatalogo, PessoalItem } from '@/lib/tipos';

type Form = {
  id: string | null;
  nome: string;
  cargo: string;
  telefone: string;
  telefoneOriginal: string;
  permissoes: Record<string, boolean>;
  cozinhas: string[];
  activo: boolean;
};

const novoForm = (): Form => ({ id: null, nome: '', cargo: '', telefone: '', telefoneOriginal: '', permissoes: {}, cozinhas: [], activo: true });

const formDe = (p: PessoalItem): Form => ({
  id: p.id,
  nome: p.nome,
  cargo: p.cargo ?? '',
  telefone: p.telefone ?? '',
  telefoneOriginal: p.telefone ?? '',
  permissoes: { ...p.permissoes },
  cozinhas: [...p.cozinhas],
  activo: p.activo,
});

/** Cadastro de pessoal: criar funcionários, telefone de login, permissões (por função) e cozinhas. */
export default function Pessoal() {
  const [lista, setLista] = useState<PessoalItem[] | null>(null);
  const [catalogo, setCatalogo] = useState<PermissaoCatalogo[]>([]);
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [form, setForm] = useState<Form | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [aGuardar, setAGuardar] = useState(false);

  const carregar = useCallback(() => {
    listarPessoal().then(setLista).catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(
    useCallback(() => {
      carregar();
      permissoesCatalogo().then(setCatalogo).catch(() => undefined);
      lerCozinhas().then(setCozinhas).catch(() => undefined);
    }, [carregar]),
  );

  // Permissões agrupadas pelo grupo do catálogo, na ordem em que vêm
  const grupos = useMemo(() => {
    const m = new Map<string, PermissaoCatalogo[]>();
    for (const p of catalogo) {
      const g = m.get(p.grupo) ?? [];
      g.push(p);
      m.set(p.grupo, g);
    }
    return [...m.entries()];
  }, [catalogo]);

  const telefoneValido = (t: string) => t === '' || /^9\d{8}$/.test(t.replace(/\D/g, ''));

  const alternarPermissao = (chave: string) =>
    form && setForm({ ...form, permissoes: { ...form.permissoes, [chave]: !form.permissoes[chave] } });
  const alternarCozinha = (id: string) =>
    form && setForm({ ...form, cozinhas: form.cozinhas.includes(id) ? form.cozinhas.filter((c) => c !== id) : [...form.cozinhas, id] });

  async function guardar() {
    if (!form) return;
    setErro(null);
    setSucesso(null);
    if (form.nome.trim().length === 0) {
      setErro('Escreve o nome.');
      return;
    }
    if (!telefoneValido(form.telefone)) {
      setErro('O telefone é o número angolano de 9 algarismos (começa por 9), ou deixa vazio.');
      return;
    }
    setAGuardar(true);
    try {
      const telefone = form.telefone.trim() === '' ? null : form.telefone.replace(/\D/g, '');
      let id = form.id;
      if (!id) {
        id = await criarFuncionario({ nome: form.nome.trim(), cargo: form.cargo.trim() || null, telefone, estafeta: false });
      } else {
        await editarFuncionario({ id, nome: form.nome.trim(), cargo: form.cargo.trim() || null, activo: form.activo });
        if (form.telefone.trim() !== form.telefoneOriginal.trim()) await definirTelefoneFuncionario(id, telefone);
      }
      await definirPermissoes(id, form.permissoes);
      await definirCozinhas(id, form.cozinhas);
      setSucesso(form.id ? 'Alterações guardadas.' : 'Funcionário criado. Ele entra na app com este número (SMS).');
      setForm(null);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAGuardar(false);
    }
  }

  return (
    <Guarda permissoes={[]} permitir={(f) => f.administrador_principal}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}

        {form ? (
          <Cartao>
            <Subtitulo>{form.id ? 'Editar funcionário' : 'Novo funcionário'}</Subtitulo>
            <Campo rotulo="Nome" value={form.nome} onChangeText={(t) => setForm({ ...form, nome: t })} maxLength={120} />
            <Campo rotulo="Cargo (ex.: Gerente, Estafeta)" value={form.cargo} onChangeText={(t) => setForm({ ...form, cargo: t })} maxLength={60} />
            <Campo
              rotulo="Telefone (login por SMS, 9 algarismos)"
              value={form.telefone}
              onChangeText={(t) => setForm({ ...form, telefone: t })}
              keyboardType="phone-pad"
              maxLength={15}
              placeholder="9XXXXXXXX"
            />

            <Subtitulo>Permissões</Subtitulo>
            <Paragrafo suave>Escolhe o que este funcionário pode fazer. O cargo acima é só o nome da função.</Paragrafo>
            {grupos.map(([grupo, permissoes]) => (
              <View key={grupo} style={{ marginBottom: espaco.s }}>
                <Text style={{ color: cores.textoSuave, fontSize: 12, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.5 }}>{grupo}</Text>
                {permissoes.map((p) => (
                  <Opcao key={p.chave} titulo={p.descricao} marcado={!!form.permissoes[p.chave]} aoTocar={() => alternarPermissao(p.chave)} />
                ))}
              </View>
            ))}

            <Subtitulo>Cozinhas</Subtitulo>
            <Paragrafo suave>A que cozinhas pertence (preciso para gerir pedidos/caixa dessa cozinha).</Paragrafo>
            {cozinhas.length === 0 ? (
              <Paragrafo suave>Ainda não há cozinhas.</Paragrafo>
            ) : (
              cozinhas.map((c) => <Opcao key={c.id} titulo={c.nome} marcado={form.cozinhas.includes(c.id)} aoTocar={() => alternarCozinha(c.id)} />)
            )}

            {form.id && (
              <>
                <Subtitulo>Estado</Subtitulo>
                <Escolha
                  opcoes={[
                    { valor: 'activo', rotulo: 'Activo' },
                    { valor: 'inactivo', rotulo: 'Fora da equipa' },
                  ]}
                  valor={form.activo ? 'activo' : 'inactivo'}
                  aoMudar={(v) => setForm({ ...form, activo: v === 'activo' })}
                />
              </>
            )}
            <Botao titulo="Guardar" aCarregar={aGuardar} aoCarregar={guardar} />
            <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setForm(null)} />
          </Cartao>
        ) : (
          <Botao titulo="Novo funcionário" aoCarregar={() => setForm(novoForm())} />
        )}

        {!lista && !erro && <ACarregar />}
        {lista?.map((p) => (
          <Cartao key={p.id} estilo={p.activo ? undefined : { opacity: 0.6 }}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: espaco.s }}>
              <Text style={{ fontWeight: '700', color: cores.texto, flex: 1 }}>{p.nome}</Text>
              {p.administrador_principal && <Etiqueta texto="Admin" cor={cores.marca} />}
              {p.estafeta && <Etiqueta texto="Estafeta" cor={cores.sucesso} />}
              {!p.activo && <Etiqueta texto="Inactivo" cor={cores.textoSuave} />}
            </View>
            <Text style={{ color: cores.textoSuave }}>
              {p.cargo ?? 'Sem cargo'}
              {p.telefone ? ` · ${p.telefone}` : ' · sem telefone'}
              {!p.administrador_principal ? ` · ${Object.values(p.permissoes).filter(Boolean).length} permissões` : ''}
            </Text>
            {!p.administrador_principal && <Botao titulo="Editar" variante="texto" aoCarregar={() => setForm(formDe(p))} />}
          </Cartao>
        ))}
        <Paragrafo suave>O funcionário entra na app com o número de telefone (código por SMS) e vê apenas o que as permissões deixarem.</Paragrafo>
      </Ecra>
    </Guarda>
  );
}

function Opcao({ titulo, marcado, aoTocar }: { titulo: string; marcado: boolean; aoTocar: () => void }) {
  return (
    <Pressable
      accessibilityRole="checkbox"
      accessibilityState={{ checked: marcado }}
      onPress={aoTocar}
      style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.s, paddingVertical: 8 }}>
      <View
        style={{
          width: 22,
          height: 22,
          borderRadius: 6,
          borderWidth: 2,
          borderColor: marcado ? cores.marca : cores.contorno,
          backgroundColor: marcado ? cores.marca : 'transparent',
          alignItems: 'center',
          justifyContent: 'center',
        }}>
        {marcado && <Text style={{ color: '#fff', fontWeight: '900', fontSize: 14 }}>✓</Text>}
      </View>
      <Text style={{ color: cores.texto, flex: 1 }}>{titulo}</Text>
    </Pressable>
  );
}

function Etiqueta({ texto, cor }: { texto: string; cor: string }) {
  return (
    <Text style={{ color: '#fff', backgroundColor: cor, fontSize: 11, fontWeight: '700', paddingHorizontal: 6, paddingVertical: 2, borderRadius: raio, overflow: 'hidden' }}>
      {texto}
    </Text>
  );
}
