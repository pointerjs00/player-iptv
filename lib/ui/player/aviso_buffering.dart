import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../design/componentes.dart';
import '../design/movimento.dart';
import '../design/tokens.dart';

/// "A carregar… 45%" sobre o vídeo quando o canal, já aberto, para à espera de dados
/// (`buffering` do media_kit: paused-for-cache do mpv). Só aparece se durar mais de `atraso`
/// (um engasgo curto não pisca) e sai logo que volta a tocar. Não apanha teclas nem toques:
/// o zapping e o Voltar continuam a funcionar.
class AvisoBuffering extends StatefulWidget {
  const AvisoBuffering({super.key, required this.aberto, required this.buffering, this.percentagem,
      this.atraso = const Duration(milliseconds: 300)});

  /// O canal já abriu (até lá quem mostra o progresso é o indicador de abertura do player).
  final bool aberto;
  final bool buffering;

  /// 0–100, do `cache-buffering-state` do mpv (null se não se sabe).
  final double? percentagem;
  final Duration atraso;

  @override
  State<AvisoBuffering> createState() => _AvisoBufferingState();
}

class _AvisoBufferingState extends State<AvisoBuffering> {
  Timer? _timer;
  bool _visivel = false;

  bool get _aCarregar => widget.aberto && widget.buffering;

  @override
  void initState() {
    super.initState();
    _atualizar();
  }

  @override
  void didUpdateWidget(AvisoBuffering antigo) {
    super.didUpdateWidget(antigo);
    if ((antigo.aberto && antigo.buffering) != _aCarregar) _atualizar();
  }

  void _atualizar() {
    _timer?.cancel();
    if (!_aCarregar) {
      _visivel = false;
      return;
    }
    _timer = Timer(widget.atraso, () {
      if (mounted && _aCarregar) setState(() => _visivel = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visivel) return const SizedBox.shrink();
    final p = widget.percentagem;
    final texto = p == null ? 'A carregar…' : 'A carregar… ${p.clamp(0, 100).round()}%';
    return IgnorePointer(
      child: ExcludeFocus(
        child: Center(
          child: SuperficieVidro(
            cor: const Color(0xCC0B0F17),
            raio: Tokens.raioCartao,
            elevacao: 2,
            padding: const EdgeInsets.symmetric(horizontal: Tokens.e24, vertical: Tokens.e16),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const AnelCarregamento(),
              const SizedBox(width: Tokens.e16),
              Text(texto,
                  style: const TextStyle(color: Tokens.texto, fontSize: 18, fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Anel em gradiente índigo→violeta a rodar (parado com "reduzir movimento").
class AnelCarregamento extends StatefulWidget {
  const AnelCarregamento({super.key, this.tamanho = 36});
  final double tamanho;

  @override
  State<AnelCarregamento> createState() => _AnelCarregamentoState();
}

class _AnelCarregamentoState extends State<AnelCarregamento> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

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
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.tamanho,
        child: RotationTransition(turns: _c, child: const CustomPaint(painter: _PintorAnel())),
      );
}

class _PintorAnel extends CustomPainter {
  const _PintorAnel();

  @override
  void paint(Canvas canvas, Size size) {
    const largura = 4.0;
    final r = Offset.zero & size;
    final arco = r.deflate(largura / 2);
    canvas.drawArc(arco, 0, 2 * math.pi, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = largura
          ..color = Tokens.vidroForte);
    canvas.drawArc(arco, 0, 1.6 * math.pi, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = largura
          ..strokeCap = StrokeCap.round
          ..shader = const SweepGradient(
            colors: [Color(0x006C7BFF), Tokens.acento, Tokens.acento2],
            stops: [0, .5, .8],
          ).createShader(r));
  }

  @override
  bool shouldRepaint(_PintorAnel antigo) => false;
}
