import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { criarFuncionario, definirTelefoneFuncionario, editarFuncionario, listarPessoal } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { PessoalItem } from '@/lib/tipos';

type Form = {
  id: string | null;
  nome: string;
  cargo: string;
  telefone: string;
  telefoneOriginal: string;
  estafeta: boolean;
  activo: boolean;
};

const novoForm = (): Form => ({ id: null, nome: '', cargo: '', telefone: '', telefoneOriginal: '', estafeta: true, activo: true });

const formDe = (p: PessoalItem): Form => ({
  id: p.id,
  nome: p.nome,
  cargo: p.cargo ?? '',
  telefone: p.telefone ?? '',
  telefoneOriginal: p.telefone ?? '',
  estafeta: p.estafeta,
  activo: p.activo,
});

/** Cadastro de pessoal: criar estafetas e outros funcionários, telefone de login e activar/desactivar. */
export default function Pessoal() {
  const [lista, setLista] = useState<PessoalItem[] | null>(null);
  const [form, setForm] = useState<Form | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [aGuardar, setAGuardar] = useState(false);

  const carregar = useCallback(() => {
    listarPessoal()
      .then(setLista)
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  const telefoneValido = (t: string) => t === '' || /^9\d{8}$/.test(t.replace(/\D/g, ''));

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
      if (!form.id) {
        await criarFuncionario({ nome: form.nome.trim(), cargo: form.cargo.trim() || null, telefone, estafeta: form.estafeta });
        setSucesso('Funcionário criado. Ele entra na app do operador com este número (SMS).');
      } else {
        await editarFuncionario({ id: form.id, nome: form.nome.trim(), cargo: form.cargo.trim() || null, estafeta: form.estafeta, activo: form.activo });
        if (form.telefone.trim() !== form.telefoneOriginal.trim()) {
          await definirTelefoneFuncionario(form.id, telefone);
        }
        setSucesso('Alterações guardadas.');
      }
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
            <Campo
              rotulo="Cargo (ex.: Estafeta)"
              value={form.cargo}
              onChangeText={(t) => setForm({ ...form, cargo: t })}
              maxLength={60}
            />
            <Campo
              rotulo="Telefone (login por SMS, 9 algarismos)"
              value={form.telefone}
              onChangeText={(t) => setForm({ ...form, telefone: t })}
              keyboardType="phone-pad"
              maxLength={15}
              placeholder="9XXXXXXXX"
            />
            <Text style={{ color: cores.textoSuave, fontSize: 13 }}>É estafeta? (faz entregas)</Text>
            <Escolha
              opcoes={[
                { valor: 'sim', rotulo: 'Sim, é estafeta' },
                { valor: 'nao', rotulo: 'Não' },
              ]}
              valor={form.estafeta ? 'sim' : 'nao'}
              aoMudar={(v) => setForm({ ...form, estafeta: v === 'sim' })}
            />
            {form.id && (
              <>
                <Text style={{ color: cores.textoSuave, fontSize: 13 }}>Estado</Text>
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
            </Text>
            {!p.administrador_principal && (
              <Botao titulo="Editar" variante="texto" aoCarregar={() => setForm(formDe(p))} />
            )}
          </Cartao>
        ))}
        <Paragrafo suave>
          O funcionário entra na app do operador com o número de telefone (código por SMS). "É estafeta" dá-lhe a
          permissão de marcar pedidos em entrega e de aparecer no mapa de acompanhamento.
        </Paragrafo>
      </Ecra>
    </Guarda>
  );
}

function Etiqueta({ texto, cor }: { texto: string; cor: string }) {
  return (
    <Text style={{ color: '#fff', backgroundColor: cor, fontSize: 11, fontWeight: '700', paddingHorizontal: 6, paddingVertical: 2, borderRadius: 6, overflow: 'hidden' }}>
      {texto}
    </Text>
  );
}
