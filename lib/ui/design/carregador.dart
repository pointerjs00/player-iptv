import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'componentes.dart';
import 'ecra.dart';
import 'movimento.dart';
import 'tokens.dart';
import '../../idioma/idioma.dart';

/// O loader de ecrã cheio enquanto se pedem os canais ao servidor: um anel em gradiente
/// índigo→violeta a girar num painel de vidro, o passo atual ("A pedir as categorias"), a barra
/// de progresso quando há total e "Cancelar" (com o foco). Com "reduzir movimento" fica parado.
class CarregadorCanais extends StatefulWidget {
  const CarregadorCanais({super.key, required this.passo, this.progresso, this.aoCancelar,
      this.titulo = 'A carregar os canais', this.focoCancelar});

  final String titulo;
  final String passo;

  /// 0–1, ou null quando não se sabe o total.
  final double? progresso;
  final VoidCallback? aoCancelar;
  final FocusNode? focoCancelar;

  @override
  State<CarregadorCanais> createState() => _CarregadorCanaisState();
}

class _CarregadorCanaisState extends State<CarregadorCanais> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (semAnimacoes(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final anel = tv ? 112.0 : 92.0;
    final p = widget.progresso;
    return ColoredBox(
      // por cima dos canais (ao atualizar) ou do esqueleto: quase opaco
      color: Tokens.fundo.withValues(alpha: .9),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tokens.e24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: tv ? 520 : 420),
            child: SuperficieVidro(
              elevacao: 3,
              cor: Tokens.vidroForte,
              padding: const EdgeInsets.fromLTRB(Tokens.e32, Tokens.e32, Tokens.e32, Tokens.e24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // o anel gira (RepaintBoundary: só ele se repinta a cada frame)
                RepaintBoundary(
                  child: SizedBox.square(
                    dimension: anel,
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (_, filho) => CustomPaint(painter: _Anel(_c.value), child: filho),
                      child: Center(
                        child: Icon(Icons.live_tv_rounded, size: anel * .34, color: Tokens.texto),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Tokens.e24),
                Text(tr(widget.titulo),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: tv ? 22 : 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: Tokens.e8),
                AnimatedSwitcher(
                  duration: duracaoAnimada(context, Tokens.duracaoMedia),
                  switchInCurve: Tokens.curva,
                  child: Text(widget.passo,
                      key: ValueKey(widget.passo),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Tokens.texto2, fontSize: tv ? 17 : 14)),
                ),
                if (p != null) ...[
                  const SizedBox(height: Tokens.e16),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: p),
                    duration: duracaoAnimada(context, Tokens.duracaoMedia),
                    builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 6, color: Color.lerp(
                        Tokens.acento, Tokens.acento2, v)),
                  ),
                ],
                const SizedBox(height: Tokens.e24),
                OutlinedButton(
                  focusNode: widget.focoCancelar,
                  autofocus: true,
                  onPressed: widget.aoCancelar,
                  child: Text(tr('Cancelar')),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// O anel: a pista de vidro e um arco em gradiente índigo→violeta (com brilho) a rodar.
class _Anel extends CustomPainter {
  const _Anel(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const traco = 6.0;
    final r = Rect.fromLTWH(traco, traco, size.width - 2 * traco, size.height - 2 * traco);
    canvas.drawArc(r, 0, 2 * math.pi, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = traco
          ..color = Tokens.vidroForte);
    final inicio = t * 2 * math.pi - math.pi / 2;
    const arco = math.pi * 1.4;
    final gradiente = SweepGradient(
      startAngle: 0,
      endAngle: arco,
      colors: const [Color(0x006C7BFF), Tokens.acento, Tokens.acento2],
      stops: const [0, .45, 1],
      transform: GradientRotation(inicio),
    ).createShader(r);
    // o brilho por baixo e o arco nítido por cima
    for (final (largura, desfoque) in [(traco * 2.2, 8.0), (traco, 0.0)]) {
      canvas.drawArc(r, inicio, arco, false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = largura
            ..strokeCap = StrokeCap.round
            ..shader = gradiente
            ..maskFilter = desfoque > 0 ? MaskFilter.blur(BlurStyle.normal, desfoque) : null);
    }
  }

  @override
  bool shouldRepaint(_Anel antigo) => antigo.t != t;
}
