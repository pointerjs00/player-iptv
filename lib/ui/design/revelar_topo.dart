import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Garante que o topo de uma página com scroll nunca fica cortado: quando o foco chega ao primeiro
/// controlo de uma área com scroll vertical (não há mais nenhum controlo alcançável por cima dele),
/// a área volta ao início, para mostrar também o que está por cima (títulos, textos).
///
/// O scroll por omissão só mostra o controlo focado. Só com navegação por teclas (no toque não mexe).
/// Os `rect` dos nós são globais, por isso continuam comparáveis dentro da área escalada (Compacto).
class RevelarTopo {
  RevelarTopo._();

  static FocusNode? _anterior;
  static bool _instalado = false;

  /// Liga o vigia (uma vez; chamar de novo não faz nada).
  static void instalar() {
    if (_instalado) return;
    _instalado = true;
    _anterior = FocusManager.instance.primaryFocus;
    FocusManager.instance.addListener(_aoMudarFoco);
  }

  /// Retira o vigia.
  static void retirar() {
    if (!_instalado) return;
    _instalado = false;
    FocusManager.instance.removeListener(_aoMudarFoco);
    _anterior = null;
  }

  static void _aoMudarFoco() {
    final foco = FocusManager.instance.primaryFocus;
    if (foco == _anterior) return;
    _anterior = foco;
    if (foco == null || foco is FocusScopeNode || foco.context == null) return;
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
    // depois do frame, para vencer o scroll até ao foco que a política de foco já pediu
    SchedulerBinding.instance.addPostFrameCallback((_) => _revelar(foco));
    SchedulerBinding.instance.scheduleFrame();
  }

  static void _revelar(FocusNode foco) {
    if (foco != FocusManager.instance.primaryFocus) return;
    final ctx = foco.context;
    if (ctx == null || !ctx.mounted) return;
    final scrollable = Scrollable.maybeOf(ctx, axis: Axis.vertical);
    if (scrollable == null) return;
    final pos = scrollable.position;
    if (pos.pixels <= pos.minScrollExtent) return;
    final topo = foco.rect.top;
    final escopo = foco.nearestScope;
    if (escopo == null) return;
    for (final n in escopo.traversalDescendants) {
      if (n == foco || !n.canRequestFocus || n.skipTraversal || n is FocusScopeNode) continue;
      final c = n.context;
      if (c == null || !c.mounted) continue;
      if (!_dentroDe(c, scrollable.context)) continue; // inclui listas verticais encaixadas
      if (n.rect.top < topo - 1) return; // ainda há controlos por cima
    }
    pos.animateTo(pos.minScrollExtent, duration: Tokens.duracaoRapida, curve: Curves.easeOut);
  }
}

/// Se [c] é descendente de [area] (mesmo dentro de outro scroll encaixado).
bool _dentroDe(BuildContext c, BuildContext area) {
  var dentro = false;
  c.visitAncestorElements((e) {
    if (e == area) {
      dentro = true;
      return false;
    }
    return true;
  });
  return dentro;
}

/// Liga o [RevelarTopo] (uma vez, na janela principal).
void instalarRevelarTopo() => RevelarTopo.instalar();
