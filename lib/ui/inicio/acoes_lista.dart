/// As ações de um cartão do Player (pressão longa, clique direito ou OK mantido):
/// Atualizar canais, Verificar agora, Editar lista, Copiar link (só Windows), Enviar para o Gestor e
/// Remover lista. Abrir é o toque no cartão.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../modelo/conta.dart';
import '../campo_tv.dart';
import '../design/design.dart';
import '../realce_foco.dart';

enum AcaoLista {
  atualizar('Atualizar canais', Icons.refresh_rounded, 'Pede a lista de canais outra vez ao servidor'),
  verificar('Verificar agora', Icons.fact_check_outlined, 'Testa 3 canais · cerca de 20 s'),
  editar('Editar lista', Icons.edit_outlined, 'Nome, endereço, MAC ou utilizador'),
  copiarLink('Copiar link', Icons.link_rounded, 'Só no Windows · leva os dados de acesso'),
  enviarGestor('Enviar para o Gestor', Icons.send_outlined, 'Para verificar ou exportar com as outras'),
  eliminar('Remover lista', Icons.delete_outline_rounded, 'Pede confirmação · os favoritos desta lista saem');

  const AcaoLista(this.rotulo, this.icone, this.explicacao);
  final String rotulo;
  final IconData icone;

  /// A linha pequena por baixo do rótulo (ecrã 3).
  final String explicacao;
}

final _reMac = RegExp(r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$');

/// A conta com os campos editados, ou os erros por campo ('endereco', 'mac', 'utilizador',
/// 'password'). O tipo vem dos campos: com MAC é Stalker; com utilizador e password é Xtream; só
/// o endereço é M3U (um get.php com credenciais no endereço também é Xtream). Os outros campos do
/// Accounts.json de origem ficam.
({Conta? conta, Map<String, String> erros}) contaEditada(Conta antiga,
    {required String endereco, required String mac, required String utilizador, required String password}) {
  final end = endereco.trim(), m = mac.trim().toUpperCase(), u = utilizador.trim(), p = password.trim();
  final erros = <String, String>{};
  final uri = Uri.tryParse(end);
  if (end.isEmpty) {
    erros['endereco'] = 'Indique o endereço';
  } else if (uri == null || !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) || uri.host.isEmpty) {
    erros['endereco'] = 'O endereço tem de começar por http:// ou https://';
  }
  if (m.isNotEmpty && !_reMac.hasMatch(m)) erros['mac'] = 'MAC inválido (ex.: 00:1A:79:00:00:01)';
  if (m.isEmpty && (u.isEmpty != p.isEmpty)) {
    erros[u.isEmpty ? 'utilizador' : 'password'] =
        u.isEmpty ? 'Indique o utilizador (ou apague a password)' : 'Indique a password (ou apague o utilizador)';
  }
  if (erros.isNotEmpty) return (conta: null, erros: erros);
  final dict = <String, dynamic>{
    ...?antiga.original,
    'Name': antiga.original?['Name'] ?? antiga.nome,
    'Address': end, 'Mac': m, 'Username': u, 'Password': p,
  };
  final c = contaDeDict(dict)!;
  // o nome da conta (do Accounts.json) fica o mesmo
  return (
    conta: Conta(antiga.nome, c.tipo, c.endereco,
        mac: c.mac, utilizador: c.utilizador, password: c.password, original: c.original),
    erros: const {},
  );
}

/// O que "Copiar link" põe na área de transferência: o que se cola em "Adicionar listas"
/// (Stalker: "portal MAC"; Xtream: o get.php; M3U: a lista).
String linkParaCopiar(Conta c) => c.tipo == Tipo.stalker ? '${c.endereco} ${c.mac}' : linkConta(c);

/// Engole o OK mantido (as repetições e o soltar) dentro do menu: o OK mantido que abriu o
/// menu não pode escolher logo uma ação.
bool _eOk(LogicalKeyboardKey k) => teclasOk.contains(k);

/// O menu de ações de uma lista (centrado, para o comando): devolve a ação escolhida (null =
/// Voltar). Sem `comGestor` não há "Enviar para o Gestor"; sem `comVerificar` não há "Verificar
/// agora"; "Copiar link" só no Windows (`windows`, para testes).
Future<AcaoLista?> mostrarMenuLista(BuildContext context, Lista lista,
        {bool comGestor = true, bool comVerificar = true, bool? windows}) =>
    showDialog<AcaoLista>(
      context: context,
      builder: (ctx) {
        final tv = ecraTv(ctx);
        final noWindows = windows ?? Platform.isWindows;
        final acoes = [
          for (final a in AcaoLista.values)
            if ((comGestor || a != AcaoLista.enviarGestor) &&
                (comVerificar || a != AcaoLista.verificar) &&
                (noWindows || a != AcaoLista.copiarLink))
              a,
        ];
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          onKeyEvent: (_, e) =>
              e is! KeyDownEvent && _eOk(e.logicalKey) ? KeyEventResult.handled : KeyEventResult.ignored,
          child: Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: tv ? 440 : 380),
              child: Padding(
                padding: const EdgeInsets.all(Tokens.e16),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Tokens.e8, Tokens.e4, Tokens.e8, Tokens.e12),
                    child: Text(lista.nomeMostrado, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: tv ? 20 : 18, fontWeight: FontWeight.w700)),
                  ),
                  // rola em ecrãs baixos (telemóvel na horizontal)
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, a) in acoes.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: RealceFoco(
                        construir: (_, aoMudarFoco) => ListTile(
                          autofocus: i == 0,
                          onFocusChange: aoMudarFoco,
                          leading: Icon(a.icone, color: a == AcaoLista.eliminar ? Tokens.mau : Tokens.texto2),
                          title: Text(a.rotulo, style: TextStyle(fontSize: tv ? 17 : 15, fontWeight: FontWeight.w500,
                              color: a == AcaoLista.eliminar ? Tokens.mau : null)),
                          subtitle: Text(a.explicacao,
                              style: TextStyle(fontSize: tv ? 14 : 12.5, color: Tokens.texto2)),
                          onTap: () => Navigator.pop(ctx, a),
                        ),
                      ),
                    ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );

/// "Remover lista": pede confirmação (a lista sai com os favoritos e a cache de canais).
Future<bool> confirmarEliminar(BuildContext context, Lista l) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: Tokens.mau, size: 32),
        title: const Text('Remover lista?'),
        content: Text('A lista ${l.nomeMostrado} sai do Player (os favoritos e a cache de canais também).'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    ) ==
    true;

/// "Editar": nome próprio (vazio = NNNHOST DDMMAA), endereço, MAC, utilizador e password.
/// Devolve a mensagem para mostrar (null = cancelado).
Future<String?> mostrarEditarLista(BuildContext context, Biblioteca biblioteca, Lista l) =>
    showDialog<String>(context: context, builder: (_) => _DialogoEditar(biblioteca: biblioteca, lista: l));

class _DialogoEditar extends StatefulWidget {
  const _DialogoEditar({required this.biblioteca, required this.lista});
  final Biblioteca biblioteca;
  final Lista lista;

  @override
  State<_DialogoEditar> createState() => _DialogoEditarState();
}

class _DialogoEditarState extends State<_DialogoEditar> {
  late final _nome = TextEditingController(text: widget.lista.nomeProprio);
  late final _endereco = TextEditingController(text: widget.lista.conta.endereco);
  late final _mac = TextEditingController(text: widget.lista.conta.mac);
  late final _utilizador = TextEditingController(text: widget.lista.conta.utilizador);
  late final _password = TextEditingController(text: widget.lista.conta.password);
  Map<String, String> _erros = const {};
  bool _aGuardar = false;

  @override
  void dispose() {
    for (final c in [_nome, _endereco, _mac, _utilizador, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_aGuardar) return;
    final r = contaEditada(widget.lista.conta,
        endereco: _endereco.text, mac: _mac.text, utilizador: _utilizador.text, password: _password.text);
    if (r.conta == null) {
      setState(() => _erros = r.erros);
      return;
    }
    setState(() {
      _erros = const {};
      _aGuardar = true;
    });
    try {
      final mantida = await widget.biblioteca.editar(widget.lista.id, r.conta!, nomeProprio: _nome.text);
      if (mounted) {
        Navigator.pop(context, mantida ? 'Lista guardada.' : 'Lista guardada. Os canais vão ser pedidos de novo ao abrir.');
      }
    } on ErroEdicao catch (e) {
      if (mounted) setState(() => _erros = {'endereco': 'Não foi guardada: ${e.mensagem}.'});
    } catch (_) {
      if (mounted) setState(() => _erros = {'endereco': 'Não foi possível guardar a lista.'});
    } finally {
      if (mounted) setState(() => _aGuardar = false);
    }
  }

  Widget _campo(String chave, TextEditingController c, String rotulo,
          {String? dica, bool segredo = false, bool primeiro = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Tokens.e12),
        child: CampoTv(
          key: Key('editar-$chave'),
          controller: c,
          autofocus: primeiro,
          obscureText: segredo,
          decoration: InputDecoration(labelText: rotulo, hintText: dica, errorText: _erros[chave]),
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const Icon(Icons.edit_outlined, color: Tokens.acento2, size: 32),
        title: const Text('Editar lista'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _campo('nome', _nome, 'Nome (opcional)',
                  dica: nomeLista(widget.lista.ordem, widget.lista.conta, widget.lista.ultima?.validade ?? ''),
                  primeiro: true),
              _campo('endereco', _endereco, 'Endereço'),
              _campo('mac', _mac, 'MAC (Stalker)'),
              _campo('utilizador', _utilizador, 'Utilizador (Xtream)'),
              _campo('password', _password, 'Password (Xtream)', segredo: true),
              const Text('Com MAC é Stalker; com utilizador e password é Xtream; só o endereço é M3U.',
                  style: TextStyle(color: Tokens.texto2, fontSize: 12.5)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _aGuardar ? null : _guardar, child: const Text('Guardar')),
        ],
      );
}
