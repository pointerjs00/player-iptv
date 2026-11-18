/// CIMA/BAIXO com o comando num ecrã feito de blocos (por exemplo os passos do Gestor).
///
/// A procura direcional do Flutter prefere o que está "na mesma coluna" do foco: de um botão à
/// direita, BAIXO saltava blocos inteiros que só têm botões à esquerda (ia parar às listas lá
/// em baixo). Aqui, BAIXO vai à linha seguinte do mesmo bloco (o mais perto na horizontal) e, no
/// fim do bloco, ao primeiro controlo do bloco seguinte; CIMA faz o contrário (no princípio do
/// bloco, vai ao início da última linha do bloco de cima). ESQUERDA/DIREITA andam só na mesma
/// linha do bloco: no fim da linha o foco fica (não salta para um botão qualquer noutro sítio,
/// por exemplo o "+" lá em cima).
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Os controlos de um bloco que o comando alcança.
List<FocusNode> controlosDe(FocusNode bloco) => [
      for (final n in bloco.traversalDescendants)
        if (n.canRequestFocus && !n.skipTraversal && n.context != null && n is! FocusScopeNode) n,
    ];

/// O controlo de cima à esquerda (`ultimaLinha`: o da esquerda na linha de baixo).
FocusNode? cantoDe(List<FocusNode> nos, {bool ultimaLinha = false}) {
  if (nos.isEmpty) return null;
  final ys = nos.map((n) => n.rect.center.dy);
  final y = ultimaLinha ? ys.reduce((a, b) => a > b ? a : b) : ys.reduce((a, b) => a < b ? a : b);
  final linha = nos.where((n) => (n.rect.center.dy - y).abs() < _mesmaLinha);
  return linha.reduce((a, b) => a.rect.left <= b.rect.left ? a : b);
}

/// Dois controlos estão na mesma linha se os centros diferem menos do que isto.
const _mesmaLinha = 10.0;

/// Trata CIMA/BAIXO com o foco dentro de um dos `blocos` (pela ordem de cima para baixo).
/// `ignored` quando o foco não está em nenhum bloco ou não há para onde ir (a procura normal
/// continua: por exemplo do último bloco para uma lista por baixo, ou do primeiro para as abas).
KeyEventResult moverEntreBlocos(List<FocusNode> blocos, KeyEvent e) {
  if (e is KeyUpEvent) return KeyEventResult.ignored;
  final k = e.logicalKey;
  final baixo = k == LogicalKeyboardKey.arrowDown;
  final lado = k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight;
  if (!baixo && !lado && k != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
  final atual = FocusManager.instance.primaryFocus;
  if (atual == null || atual.context == null) return KeyEventResult.ignored;
  final i = blocos.indexWhere((b) => atual.ancestors.contains(b));
  if (i < 0) return KeyEventResult.ignored;
  final r = atual.rect;
  if (lado) {
    final direita = k == LogicalKeyboardKey.arrowRight;
    final naLinha = [
      for (final n in controlosDe(blocos[i]))
        if (n != atual &&
            (n.rect.center.dy - r.center.dy).abs() < _mesmaLinha &&
            (direita ? n.rect.center.dx > r.right - 1 : n.rect.center.dx < r.left + 1))
          n,
    ];
    if (naLinha.isNotEmpty) {
      double dh(FocusNode n) => (n.rect.center.dx - r.center.dx).abs();
      FocusTraversalPolicy.defaultTraversalRequestFocusCallback(naLinha.reduce((a, b) => dh(a) <= dh(b) ? a : b),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    }
    return KeyEventResult.handled;
  }
  final seguintes = [
    for (final n in controlosDe(blocos[i]))
      if (n != atual && (baixo ? n.rect.center.dy >= r.bottom - 1 : n.rect.center.dy <= r.top + 1)) n,
  ];
  FocusNode? alvo;
  if (seguintes.isNotEmpty) {
    // a linha mais perto nessa direção; nela, o mais perto na horizontal
    double dv(FocusNode n) => (n.rect.center.dy - r.center.dy).abs();
    final perto = seguintes.map(dv).reduce((a, b) => a < b ? a : b);
    double dh(FocusNode n) => (n.rect.center.dx - r.center.dx).abs();
    alvo = seguintes.where((n) => dv(n) - perto < _mesmaLinha).reduce((a, b) => dh(a) <= dh(b) ? a : b);
  } else {
    for (var j = baixo ? i + 1 : i - 1; j >= 0 && j < blocos.length && alvo == null; j += baixo ? 1 : -1) {
      alvo = cantoDe(controlosDe(blocos[j]), ultimaLinha: !baixo);
    }
  }
  if (alvo == null) return KeyEventResult.ignored;
  FocusTraversalPolicy.defaultTraversalRequestFocusCallback(alvo,
      alignmentPolicy:
          baixo ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd : ScrollPositionAlignmentPolicy.keepVisibleAtStart);
  return KeyEventResult.handled;
}
