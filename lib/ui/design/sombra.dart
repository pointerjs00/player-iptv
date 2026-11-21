import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'movimento.dart';
import 'tokens.dart';

/// Sombras (e brilhos) pintadas só por FORA de um retângulo de cantos redondos: por baixo do
/// vidro translúcido uma sombra normal escurecia (ou, o brilho violeta, pintava) o cartão.
/// Muda de sombra com uma animação curta (instantânea com "reduzir movimento").
class SombraExterior extends ImplicitlyAnimatedWidget {
  const SombraExterior({super.key, required this.sombras, required this.raio, required this.child,
      super.duration = Tokens.duracaoRapida, super.curve = Tokens.curva});

  final List<BoxShadow> sombras;
  final double raio;
  final Widget child;

  @override
  AnimatedWidgetBaseState<SombraExterior> createState() => _SombraExteriorState();
}

class _TweenSombras extends Tween<List<BoxShadow>> {
  _TweenSombras({super.begin});

  @override
  List<BoxShadow> lerp(double t) => BoxShadow.lerpList(begin, end, t) ?? const [];
}

class _SombraExteriorState extends AnimatedWidgetBaseState<SombraExterior> {
  _TweenSombras? _sombras;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _sombras = visitor(_sombras, widget.sombras,
        (v) => _TweenSombras(begin: v as List<BoxShadow>)) as _TweenSombras?;
  }

  @override
  Widget build(BuildContext context) {
    final s = semAnimacoes(context) ? widget.sombras : (_sombras?.evaluate(animation) ?? widget.sombras);
    return CustomPaint(painter: _PintorSombra(s, widget.raio), child: widget.child);
  }
}

class _PintorSombra extends CustomPainter {
  _PintorSombra(this.sombras, this.raio);
  final List<BoxShadow> sombras;
  final double raio;

  @override
  void paint(Canvas canvas, Size size) {
    if (sombras.isEmpty) return;
    final caixa = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(raio));
    var margem = 0.0;
    for (final s in sombras) {
      margem = [margem, s.blurRadius * 2 + s.spreadRadius + s.offset.distance].reduce((a, b) => a > b ? a : b);
    }
    // tudo menos o interior da caixa
    final fora = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(margem + 1))
      ..addRRect(caixa);
    canvas
      ..save()
      ..clipPath(fora);
    for (final s in sombras) {
      canvas.drawRRect(caixa.shift(s.offset).inflate(s.spreadRadius), s.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PintorSombra antigo) => antigo.raio != raio || !listEquals(antigo.sombras, sombras);
}
