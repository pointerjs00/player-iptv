/// As opções do ecrã de canais: esconder/mostrar grupos e a ordem dos canais. Abrem com o OK
/// mantido (ou toque longo) num grupo, ou com o botão "Opções dos canais" no topo.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../design/design.dart';
import '../realce_foco.dart';

enum OpcaoCanais { esconderGrupo, mostrarGrupo, ordemLista, ordemAz, verEscondidos, ocultarEscondidos }

/// O menu (centrado, para o comando). `grupo` null = sem ações de grupo; `soGrupo` = só as do grupo.
/// Devolve a opção escolhida (null = Voltar).
Future<OpcaoCanais?> mostrarOpcoesCanais(BuildContext context,
    {String? grupo, bool grupoEscondido = false, bool soGrupo = false, required OrdemCanais ordem,
    required bool verEscondidos, required int escondidos}) {
  final itens = <(OpcaoCanais, String, String?, IconData, bool)>[
    if (grupo != null)
      grupoEscondido
          ? (OpcaoCanais.mostrarGrupo, 'Mostrar o grupo', grupo, Icons.visibility_outlined, false)
          : (OpcaoCanais.esconderGrupo, 'Esconder o grupo', grupo, Icons.visibility_off_outlined, false),
    if (!soGrupo) ...[
      (OpcaoCanais.ordemLista, 'Ordem da lista', null, Icons.format_list_numbered_rounded, ordem == OrdemCanais.lista),
      (OpcaoCanais.ordemAz, 'Ordenar A–Z', null, Icons.sort_by_alpha_rounded, ordem == OrdemCanais.az),
      if (verEscondidos)
        (OpcaoCanais.ocultarEscondidos, 'Ocultar grupos escondidos', null, Icons.visibility_off_outlined, false)
      else if (escondidos > 0)
        (OpcaoCanais.verEscondidos, 'Mostrar grupos escondidos ($escondidos)', null, Icons.visibility_outlined, false),
    ],
  ];
  return showDialog<OpcaoCanais>(
    context: context,
    builder: (ctx) {
      final tv = ecraTv(ctx);
      return Focus(
        // o OK mantido que abriu o menu (repetições e o soltar) não escolhe logo uma opção
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: (_, e) =>
            e is! KeyDownEvent && teclasOk.contains(e.logicalKey) ? KeyEventResult.handled : KeyEventResult.ignored,
        child: Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: tv ? 440 : 380),
            child: Padding(
              padding: const EdgeInsets.all(Tokens.e16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, (o, titulo, sub, icone, atual)) in itens.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: RealceFoco(
                      construir: (_, aoMudarFoco) => ListTile(
                        autofocus: i == 0,
                        onFocusChange: aoMudarFoco,
                        leading: Icon(icone, color: Tokens.texto2),
                        title: Text(titulo, style: TextStyle(fontSize: tv ? 17 : 15, fontWeight: FontWeight.w500)),
                        subtitle: sub == null ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: atual ? const Icon(Icons.check_rounded, color: Tokens.acento) : null,
                        selected: atual,
                        onTap: () => Navigator.pop(ctx, o),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
    },
  );
}

/// OK no comando: solto antes de [duracaoOkMantido] é um toque ([aoCarregar]); mantido abre o
/// menu ([aoManter], uma vez). As repetições e um soltar sem carregar (o OK que fechou um
/// diálogo) não fazem nada.
class OkMantido extends StatefulWidget {
  const OkMantido({super.key, required this.aoCarregar, required this.aoManter, required this.child});
  final VoidCallback aoCarregar, aoManter;
  final Widget child;

  @override
  State<OkMantido> createState() => _OkMantidoState();
}

class _OkMantidoState extends State<OkMantido> {
  Timer? _relogio;
  bool _emBaixo = false, _longo = false;

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (!teclasOk.contains(e.logicalKey)) return KeyEventResult.ignored;
    if (e is KeyRepeatEvent) return KeyEventResult.handled;
    if (e is KeyDownEvent) {
      _relogio?.cancel();
      _emBaixo = true;
      _longo = false;
      _relogio = Timer(duracaoOkMantido, () {
        if (!mounted || !_emBaixo) return;
        _longo = true;
        widget.aoManter();
      });
      return KeyEventResult.handled;
    }
    if (!_emBaixo) return KeyEventResult.handled;
    _relogio?.cancel();
    _emBaixo = false;
    if (!_longo) widget.aoCarregar();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(canRequestFocus: false, skipTraversal: true, includeSemantics: false, onKeyEvent: _tecla, child: widget.child);
}
