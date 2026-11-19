import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Um campo de texto que se usa com o comando da TV: receber o foco não abre o teclado no
/// ecrã (fica só de leitura até carregar em OK ou tocar), e as setas cima/baixo saem do campo
/// em vez de ficarem presas nele. Num campo de várias linhas, a escrever, cima/baixo movem o
/// cursor; Voltar (a tecla ou o "voltar" do sistema) acaba a edição e as setas voltam a mudar o foco.
class CampoTv extends StatefulWidget {
  const CampoTv({
    super.key,
    required this.decoration,
    this.onChanged,
    this.controller,
    this.minLines,
    this.maxLines = 1,
    this.autofocus = false,
    this.obscureText = false,
    this.focusNode,
  });

  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final int? minLines;
  final int? maxLines;
  final bool autofocus;

  /// Esconde o texto (passwords).
  final bool obscureText;

  /// O foco do campo, para o pôr nele de fora (sem ele, o campo tem um seu).
  final FocusNode? focusNode;

  @override
  State<CampoTv> createState() => _CampoTvState();
}

class _CampoTvState extends State<CampoTv> {
  FocusNode? _proprio;
  FocusNode get _foco => widget.focusNode ?? (_proprio ??= FocusNode());
  bool _aEscrever = false;

  @override
  void initState() {
    super.initState();
    _foco.addListener(_mudouFoco);
  }

  @override
  void didUpdateWidget(CampoTv old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _proprio)?.removeListener(_mudouFoco);
      _foco.addListener(_mudouFoco);
    }
  }

  void _mudouFoco() {
    if (!_foco.hasFocus && _aEscrever) setState(() => _aEscrever = false);
  }

  @override
  void dispose() {
    _foco.removeListener(_mudouFoco);
    _proprio?.dispose();
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
      final moveu =
          _foco.focusInDirection(k == LogicalKeyboardKey.arrowDown ? TraversalDirection.down : TraversalDirection.up);
      // sem nada nessa direção, quem está à volta decide (por exemplo CIMA no topo de uma secção
      // vai à barra das secções)
      return moveu ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    // sem estar a escrever, ESQUERDA/DIREITA também saem do campo (numa barra com botões ao lado)
    if (!_aEscrever && (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight)) {
      final moveu = _foco.focusInDirection(
          k == LogicalKeyboardKey.arrowLeft ? TraversalDirection.left : TraversalDirection.right);
      return moveu ? KeyEventResult.handled : KeyEventResult.ignored;
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
    // a escrever, o Voltar do sistema (no Android TV o IME come a tecla BACK e a app só recebe o
    // "voltar") acaba a edição em vez de fechar a página/diálogo; sem escrever, volta normalmente
    return PopScope(
      canPop: !_aEscrever,
      onPopInvokedWithResult: (fechou, _) {
        if (!fechou && _aEscrever) _pararDeEscrever();
      },
      child: Focus(
        onKeyEvent: _tecla,
        skipTraversal: true,
        canRequestFocus: false,
        child: TextField(
          focusNode: _foco,
          controller: widget.controller,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          autofocus: widget.autofocus,
          obscureText: widget.obscureText,
          readOnly: !_aEscrever,
          decoration: widget.decoration,
          onTap: _aEscrever ? null : _escrever,
          onChanged: widget.onChanged,
          onSubmitted: (_) => setState(() => _aEscrever = false),
        ),
      ),
    );
  }
}
