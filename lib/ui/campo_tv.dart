import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Um campo de texto que se usa com o comando da TV: receber o foco não abre o teclado no
/// ecrã (fica só de leitura até carregar em OK ou tocar), e as setas cima/baixo saem do campo
/// em vez de ficarem presas nele.
class CampoTv extends StatefulWidget {
  const CampoTv({super.key, required this.decoration, required this.onChanged});

  final InputDecoration decoration;
  final ValueChanged<String> onChanged;

  @override
  State<CampoTv> createState() => _CampoTvState();
}

class _CampoTvState extends State<CampoTv> {
  final _foco = FocusNode();
  bool _aEscrever = false;

  @override
  void initState() {
    super.initState();
    _foco.addListener(() {
      if (!_foco.hasFocus && _aEscrever) setState(() => _aEscrever = false);
    });
  }

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

  void _escrever() {
    setState(() => _aEscrever = true);
    // o campo deixa de ser só de leitura no próximo frame: aí pede-se o teclado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _foco.hasFocus) SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) {
      _foco.focusInDirection(k == LogicalKeyboardKey.arrowDown ? TraversalDirection.down : TraversalDirection.up);
      return KeyEventResult.handled;
    }
    if (!_aEscrever &&
        (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.gameButtonA)) {
      _escrever();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
        onKeyEvent: _tecla,
        skipTraversal: true,
        canRequestFocus: false,
        child: TextField(
          focusNode: _foco,
          readOnly: !_aEscrever,
          decoration: widget.decoration,
          onTap: _aEscrever ? null : _escrever,
          onChanged: widget.onChanged,
          onSubmitted: (_) => setState(() => _aEscrever = false),
        ),
      );
}
