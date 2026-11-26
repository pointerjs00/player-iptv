import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'design/ecra.dart';
import 'design/movimento.dart';
import 'design/sombra.dart';
import 'design/tokens.dart';
import 'tema.dart';

/// O realce do foco para o comando da TV: uma borda de 3 px no azul claro do anel de foco com um
/// brilho azul por fora, e um fundo ligeiramente mais claro (e, nos cartões, um aumento).
abstract final class Realce {
  static const borda = BorderSide(color: Tokens.anelFoco, width: 3);

  /// Nos botões cheios (já da cor de acento) a borda clara vê-se melhor.
  static const bordaClara = BorderSide(color: Cores.texto, width: 3);

  /// O fundo de quem tem o foco (o `focusColor` do tema e o overlay dos botões).
  static final fundo = Cores.acento.withValues(alpha: .22);
  static const duracao = Tokens.duracaoRapida;

  /// O brilho azul à volta de quem tem o foco (pintado só por fora: não tapa o conteúdo).
  static final brilho = [BoxShadow(color: Tokens.anelFoco.withValues(alpha: .55), blurRadius: 16)];
}

const _canalTv = MethodChannel('player_iptv/tv');

/// Android TV (ou sem ecrã tátil)? Pergunta-se ao Android (MainActivity).
Future<bool> _eTvAndroid() async =>
    Platform.isAndroid && (await _canalTv.invokeMethod<bool>('eTv') ?? false);

/// Na TV o realce do foco fica sempre ligado: no modo automático, um toque (por exemplo no
/// emulador ou num comando com rato) escondia-o e com as setas não voltava.
/// `computador`: só para os testes (por omissão, Windows/Linux/macOS).
Future<void> configurarRealceFoco({Future<bool> Function()? eTv, bool? computador}) async {
  bool tv;
  try {
    tv = await (eTv ?? _eTvAndroid)();
  } catch (_) {
    tv = false;
  }
  EcraTv.nativo = tv; // ecraTv(): tamanhos maiores (vista de longe)
  // no computador, o Flutter conta o rato como "teclado" (realce ligado): o cartão que tinha o
  // foco ficava com o anel depois de se clicar noutro. O rato passa a contar como toque
  final pc = !tv && (computador ?? (Platform.isWindows || Platform.isLinux || Platform.isMacOS));
  if (!pc) {
    _vigiaEntrada?.desinstalar();
    _vigiaEntrada = null;
  } else {
    _vigiaEntrada ??= RealceConformeEntrada()..instalar();
  }
  if (tv) FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
}

/// O vigia do computador (um só, mesmo que se configure mais de uma vez).
RealceConformeEntrada? _vigiaEntrada;

/// O modo de realce do foco conforme a última entrada: rato ou toque → sem realce; uma tecla de
/// navegação → com realce. (No modo automático do Flutter, o rato também liga o realce.)
class RealceConformeEntrada {
  static final _teclas = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.contextMenu,
  };

  void _modo(FocusHighlightStrategy s) {
    if (FocusManager.instance.highlightStrategy != s) FocusManager.instance.highlightStrategy = s;
  }

  void _ponteiro(PointerEvent e) {
    if (e is PointerDownEvent) _modo(FocusHighlightStrategy.alwaysTouch);
  }

  bool _tecla(KeyEvent e) {
    if (e is KeyDownEvent && _teclas.contains(e.logicalKey)) _modo(FocusHighlightStrategy.alwaysTraditional);
    return false; // só observa: a tecla segue para quem a trata
  }

  void instalar() {
    // ao abrir ainda não houve entrada: sem realce até uma tecla (o cartão com foco automático,
    // como o "Continuar a ver", não brilha com o rato)
    _modo(FocusHighlightStrategy.alwaysTouch);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_ponteiro);
    HardwareKeyboard.instance.addHandler(_tecla);
  }

  void desinstalar() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_ponteiro);
    HardwareKeyboard.instance.removeHandler(_tecla);
  }
}

/// Mostra o realce à volta de `child` quando `focado` (e o modo de realce é o do teclado/comando):
/// a borda, o brilho, o aumento e a mira (os quatro cantos de visor que se fecham sobre ele).
class MolduraFoco extends StatelessWidget {
  const MolduraFoco({super.key, required this.focado, required this.child, this.raio = 12, this.escala = 1});

  final bool focado;
  final Widget child;
  final double raio;

  /// O tamanho com o foco (1 = não cresce).
  final double escala;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // reconstrói quando o modo de realce muda (TemaConformeRealce troca o tema)
    final ver = focado && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final r = BorderRadius.circular(raio);
    return AnimatedScale(
      scale: ver ? escala : 1,
      duration: duracaoAnimada(context, Realce.duracao),
      curve: Tokens.curva,
      child: Mira(
        visivel: ver,
        raio: raio,
      // o brilho só por fora (por baixo pintaria de violeta um cartão de vidro)
      child: SombraExterior(
        duration: duracaoAnimada(context, Realce.duracao),
        raio: raio,
        sombras: ver ? Realce.brilho : const [],
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: ver
              // só a borda: o fundo mais claro é o focusColor do tema (o InkWell pinta-o; uma cor
              // aqui esconderia o ink do ListTile)
              ? BoxDecoration(borderRadius: r, border: Border.fromBorderSide(Realce.borda))
              : BoxDecoration(borderRadius: r),
          child: child,
        ),
      ),
      ),
    );
  }
}

/// A mira do foco: quatro cantos de visor à volta de `child`, por fora dele, que se fecham sobre
/// ele ao aparecer (de [Mira.longe] a [Mira.perto] px) com um brilho suave. Não ocupa espaço nem
/// recebe toques; escondida, não pinta nada.
class Mira extends StatelessWidget {
  const Mira({super.key, required this.visivel, required this.child, this.raio = 12});

  final bool visivel;
  final Widget child;
  final double raio;

  /// A distância dos cantos ao elemento: ao começar a aparecer e no fim.
  static const longe = 14.0;
  static const perto = 6.0;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: visivel ? 1 : 0),
        duration: duracaoAnimada(context, Tokens.duracaoMedia),
        curve: visivel ? Tokens.curva : Tokens.curvaSaida,
        child: child,
        builder: (_, t, filho) => CustomPaint(foregroundPainter: _PintorMira(t, raio), child: filho),
      );
}

class _PintorMira extends CustomPainter {
  _PintorMira(this.t, this.raio);

  /// 0 = escondida, 1 = fechada sobre o elemento.
  final double t;
  final double raio;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final folga = Mira.longe + (Mira.perto - Mira.longe) * t;
    final r = (Offset.zero & size).inflate(folga);
    final braco = (r.shortestSide / 3).clamp(8.0, 24.0);
    final curva = (raio + folga / 2).clamp(0.0, braco);
    final caminho = Path();
    void canto(Offset o, double dx, double dy) {
      // um "L" com o canto arredondado: braço vertical, curva, braço horizontal
      caminho
        ..moveTo(o.dx, o.dy + dy * braco)
        ..lineTo(o.dx, o.dy + dy * curva)
        ..quadraticBezierTo(o.dx, o.dy, o.dx + dx * curva, o.dy)
        ..lineTo(o.dx + dx * braco, o.dy);
    }

    canto(r.topLeft, 1, 1);
    canto(r.topRight, -1, 1);
    canto(r.bottomLeft, 1, -1);
    canto(r.bottomRight, -1, -1);
    final alfa = t.clamp(0.0, 1.0);
    canvas.drawPath(
        caminho,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = Tokens.acento.withValues(alpha: .55 * alfa)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawPath(
        caminho,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = Tokens.anelFoco.withValues(alpha: alfa));
  }

  @override
  bool shouldRepaint(_PintorMira antes) => antes.t != t || antes.raio != raio;
}

/// Para widgets que dizem quando ganham/perdem o foco (`onFocusChange` do ListTile, InkWell...):
/// `construir(context, aoMudarFoco)` passa `aoMudarFoco` ao widget e o realce fica à volta dele.
class RealceFoco extends StatefulWidget {
  const RealceFoco({super.key, required this.construir, this.raio = 12, this.escala = 1});

  final Widget Function(BuildContext context, ValueChanged<bool> aoMudarFoco) construir;
  final double raio;
  final double escala;

  @override
  State<RealceFoco> createState() => _RealceFocoState();
}

class _RealceFocoState extends State<RealceFoco> {
  bool _focado = false;

  void _mudou(bool f) {
    if (mounted && f != _focado) setState(() => _focado = f);
  }

  @override
  Widget build(BuildContext context) => MolduraFoco(
        focado: _focado,
        raio: widget.raio,
        escala: widget.escala,
        child: widget.construir(context, _mudou),
      );
}

/// Para o `builder` do MaterialApp: o tema com o realce de foco só no modo de realce do
/// teclado/comando. No telemóvel ou com o rato (modo toque), um botão com foco automático não
/// ganha borda; ao carregar numa tecla, o tema muda e os widgets focados mostram o realce.
class TemaConformeRealce extends StatefulWidget {
  const TemaConformeRealce({super.key, required this.child});
  final Widget child;

  @override
  State<TemaConformeRealce> createState() => _TemaConformeRealceState();
}

class _TemaConformeRealceState extends State<TemaConformeRealce> {
  static final _comRealce = temaApp();
  static final _semRealce = temaApp(realceFoco: false);

  void _mudou(FocusHighlightMode _) {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_mudou);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_mudou);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: FocusManager.instance.highlightMode == FocusHighlightMode.traditional ? _comRealce : _semRealce,
        child: widget.child,
      );
}
