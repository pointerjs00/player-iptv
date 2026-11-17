import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Um campo de texto que se usa com o comando da TV: receber o foco não abre o teclado no
/// ecrã (fica só de leitura até carregar em OK ou tocar), e as setas cima/baixo saem do campo
/// em vez de ficarem presas nele. Num campo de várias linhas, a escrever, cima/baixo movem o
/// cursor; Voltar (ou fechar o teclado) acaba a edição e as setas voltam a mudar o foco.
class CampoTv extends StatefulWidget {
  const CampoTv({
    super.key,
    required this.decoration,
    this.onChanged,
    this.controller,
    this.minLines,
    this.maxLines = 1,
  });

  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final int? minLines;
  final int? maxLines;

  @override
  State<CampoTv> createState() => _CampoTvState();
}

class _CampoTvState extends State<CampoTv> {
  final _foco = FocusNode();
  bool _aEscrever = false;
  bool _tecladoVisivel = false;

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

  void _pararDeEscrever() {
    setState(() => _aEscrever = false);
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (_aEscrever && (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape)) {
      // Voltar fecha o teclado (não a página/diálogo) e devolve as setas à navegação
      _pararDeEscrever();
      return KeyEventResult.handled;
    }
    final variasLinhas = widget.maxLines != 1;
    if ((k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) && !(variasLinhas && _aEscrever)) {
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
  Widget build(BuildContext context) {
    // no Android o Voltar com o teclado aberto só fecha o teclado (a app não vê a tecla):
    // quando o teclado desaparece, a edição acaba
    final teclado = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (_tecladoVisivel && !teclado && _aEscrever) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _aEscrever) setState(() => _aEscrever = false);
      });
    }
    _tecladoVisivel = teclado;
    return Focus(
      onKeyEvent: _tecla,
      skipTraversal: true,
      canRequestFocus: false,
      child: TextField(
        focusNode: _foco,
        controller: widget.controller,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        readOnly: !_aEscrever,
        decoration: widget.decoration,
        onTap: _aEscrever ? null : _escrever,
        onChanged: widget.onChanged,
        onSubmitted: (_) => setState(() => _aEscrever = false),
      ),
    );
  }
}
