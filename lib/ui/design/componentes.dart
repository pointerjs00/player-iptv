import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show PipelineOwner, RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../realce_foco.dart';
import 'movimento.dart';
import 'sombra.dart';
import 'tokens.dart';

/// O fundo de todos os ecrãs: azul quase preto em gradiente, com faixas curvas de luz azul à
/// direita (em cima e em baixo) e uma linha clara ao longo da borda de cada uma. É sempre opaco (no
/// Android a `FlutterView` é transparente: o que não se pinta deixa ver o que está por baixo),
/// exceto enquanto houver um vídeo nativo montado ([videoPorBaixo]).
class FundoCinema extends SingleChildRenderObjectWidget {
  const FundoCinema({super.key, required Widget super.child});

  /// Quantas áreas de vídeo nativo (a `SurfaceView` do ExoPlayer, por baixo da interface) estão
  /// montadas: com alguma, o fundo não se pinta (senão tapava o vídeo). Pode mudar a meio de um
  /// build (pinta-se de novo no mesmo frame).
  static final videoPorBaixo = ValueNotifier<int>(0);

  static const decoracao = BoxDecoration(
    color: Tokens.fundo,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Tokens.fundoBrilho, Color(0xFF050C1F), Tokens.fundo],
      stops: [0, .5, 1],
    ),
  );

  /// As faixas curvas, desenhadas num ecrã de 1600 × 900 e esticadas ao tamanho real (os
  /// caminhos e as tintas fazem-se uma vez).
  static final List<(Path, Paint)> _faixas = () {
    Path faixa(List<double> p, {required bool fechar, required Offset canto}) {
      final c = Path()
        ..moveTo(p[0], p[1])
        ..cubicTo(p[2], p[3], p[4], p[5], p[6], p[7]);
      if (fechar) {
        c
          ..lineTo(canto.dx, canto.dy)
          ..close();
      }
      return c;
    }

    Paint enchimento(Color cor, double alfa, Offset de, Offset ate) =>
        Paint()..shader = ui.Gradient.linear(de, ate, [cor.withValues(alpha: alfa), cor.withValues(alpha: 0)]);
    Paint borda(double largura) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = largura
      ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(1600, 0), [
        Tokens.bordaFaixa.withValues(alpha: 0),
        Tokens.bordaFaixa.withValues(alpha: .35),
        const Color(0xFF6FA2FF).withValues(alpha: .25),
      ], [0, .55, 1]);

    const cimaA = [860.0, 0.0, 1080.0, 150.0, 1320.0, 120.0, 1600.0, 270.0];
    const cimaB = [1150.0, 0.0, 1290.0, 95.0, 1450.0, 120.0, 1600.0, 105.0];
    const baixoA = [960.0, 900.0, 1130.0, 720.0, 1350.0, 640.0, 1600.0, 560.0];
    const baixoB = [1230.0, 900.0, 1340.0, 790.0, 1470.0, 745.0, 1600.0, 725.0];
    const esquerda = [0.0, 690.0, 190.0, 670.0, 330.0, 750.0, 460.0, 900.0];
    return [
      (faixa(cimaA, fechar: true, canto: const Offset(1600, 0)),
          enchimento(Tokens.faixaFundo, .6, const Offset(1600, 0), const Offset(860, 162))),
      (faixa(cimaB, fechar: true, canto: const Offset(1600, 0)),
          enchimento(const Color(0xFF2556A6), .38, const Offset(1600, 0), const Offset(1240, 105))),
      (faixa(baixoA, fechar: true, canto: const Offset(1600, 900)),
          enchimento(const Color(0xFF16397A), .56, const Offset(1600, 900), const Offset(960, 662))),
      (faixa(baixoB, fechar: true, canto: const Offset(1600, 900)),
          enchimento(const Color(0xFF2459B0), .35, const Offset(1600, 900), const Offset(1341, 725))),
      (faixa(esquerda, fechar: true, canto: const Offset(0, 900)),
          enchimento(const Color(0xFF143270), .42, const Offset(0, 900), const Offset(460, 690))),
      (faixa(cimaA, fechar: false, canto: Offset.zero), borda(1.6)),
      (faixa(cimaB, fechar: false, canto: Offset.zero), borda(1.2)),
      (faixa(baixoA, fechar: false, canto: Offset.zero), borda(1.6)),
      (faixa(baixoB, fechar: false, canto: Offset.zero), borda(1.2)),
    ];
  }();

  /// Pinta as faixas curvas no retângulo `r` (por cima do gradiente).
  static void pintarFaixas(Canvas canvas, Rect r) {
    canvas
      ..save()
      ..clipRect(r)
      ..translate(r.left, r.top)
      ..scale(r.width / 1600, r.height / 900);
    for (final (caminho, tinta) in _faixas) {
      canvas.drawPath(caminho, tinta);
    }
    canvas.restore();
  }

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFundoCinema(createLocalImageConfiguration(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderFundoCinema).configuracao = createLocalImageConfiguration(context);
}

class _RenderFundoCinema extends RenderProxyBox {
  _RenderFundoCinema(this.configuracao);

  ImageConfiguration configuracao;
  BoxPainter? _pintor;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    FundoCinema.videoPorBaixo.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    FundoCinema.videoPorBaixo.removeListener(markNeedsPaint);
    _pintor?.dispose();
    _pintor = null;
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (FundoCinema.videoPorBaixo.value <= 0) {
      _pintor ??= FundoCinema.decoracao.createBoxPainter(markNeedsPaint);
      _pintor!.paint(context.canvas, offset, configuracao.copyWith(size: size));
      FundoCinema.pintarFaixas(context.canvas, offset & size);
    }
    super.paint(context, offset);
  }
}

/// Um painel (as colunas de Ver TV, os painéis do Gestor e das Definições): escuro e quase
/// opaco, com uma borda azulada fina e sombra.
/// O conteúdo é recortado pelos cantos e pinta o "ink" (ListTile, InkWell) por cima do vidro.
class SuperficieVidro extends StatelessWidget {
  const SuperficieVidro({super.key, required this.child, this.padding = EdgeInsets.zero,
      this.raio = Tokens.raioCartao, this.elevacao = 1, this.cor = Tokens.cartao});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double raio;
  final int elevacao;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(raio);
    return SombraExterior(
      sombras: Tokens.sombra(elevacao),
      raio: raio,
      child: DecoratedBox(
        decoration: BoxDecoration(color: cor, borderRadius: r, border: Border.all(color: Tokens.bordaCartao)),
        child: Material(
          type: MaterialType.transparency,
          shape: RoundedRectangleBorder(borderRadius: r),
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// As teclas que "carregam" no widget com o foco (OK do comando, Enter, espaço, A do comando de jogos).
final teclasOk = <LogicalKeyboardKey>{
  LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA, LogicalKeyboardKey.space,
};

/// Quanto tempo o OK tem de ficar em baixo para contar como pressão longa.
const duracaoOkMantido = Duration(milliseconds: 500);

/// Um cartão de vidro que se toca/abre (InkWell). Com o foco do comando (modo "traditional"):
/// aumenta para 1.04, ganha a borda de realce, um brilho violeta e a sombra sobe. Com o rato por
/// cima só a sombra sobe. No toque (telemóvel), o foco automático não muda nada.
///
/// O realce é só do cartão em si (não quando o foco está num botão de dentro). Os botões de
/// dentro só entram na navegação com as setas quando o foco já está no cartão: ESQUERDA/DIREITA
/// entre cartões vão de cartão em cartão e BAIXO, no cartão, entra nos botões.
///
/// [onLongPress]: toque longo, clique direito do rato ou OK mantido no comando (o menu abre
/// ao fim de [duracaoOkMantido], ainda com o OK em baixo). Com ele, o OK curto abre ao soltar.
class CartaoModerno extends StatefulWidget {
  const CartaoModerno({super.key, required this.child, this.onTap, this.onLongPress, this.autofocus = false,
      this.focusNode, this.padding = const EdgeInsets.all(Tokens.e16), this.raio = Tokens.raioCartao,
      this.escalaFoco = 1.04, this.destaque = false});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry padding;
  final double raio;
  final double escalaFoco;

  /// Em destaque (por exemplo uma lista favorita): borda e reflexo dourados.
  final bool destaque;

  @override
  State<CartaoModerno> createState() => _CartaoModernoState();
}

class _CartaoModernoState extends State<CartaoModerno> {
  FocusNode? _proprio;
  final _interior = FocusNode(debugLabel: 'CartaoModerno.interior', canRequestFocus: false, skipTraversal: true);

  /// O foco é do próprio cartão.
  bool _focado = false;

  /// O foco está no cartão ou num botão dele.
  bool _dentro = false;
  bool _rato = false;

  /// O OK foi carregado com o foco neste cartão e ainda não foi solto.
  bool _okEmBaixo = false;
  bool _okLongo = false;
  Timer? _relogioOk;

  FocusNode get _no => widget.focusNode ?? (_proprio ??= FocusNode(debugLabel: 'CartaoModerno'));

  @override
  void initState() {
    super.initState();
    _no.addListener(_mudouFoco);
  }

  @override
  void didUpdateWidget(CartaoModerno antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.focusNode != widget.focusNode) {
      (antigo.focusNode ?? _proprio)?.removeListener(_mudouFoco);
      _no.addListener(_mudouFoco);
      _mudouFoco();
    }
  }

  @override
  void dispose() {
    _relogioOk?.cancel();
    _no.removeListener(_mudouFoco);
    _proprio?.dispose();
    _interior.dispose();
    super.dispose();
  }

  void _mudouFoco() {
    final f = _no.hasPrimaryFocus, d = _no.hasFocus;
    if (!f) _largarOk();
    if (mounted && (f != _focado || d != _dentro)) {
      setState(() {
        _focado = f;
        _dentro = d;
      });
    }
  }

  /// BAIXO com o foco no cartão: entra no primeiro botão de dentro (a navegação direcional só
  /// procura abaixo do cartão inteiro e saltaria para a fila de baixo).
  void _largarOk() {
    _relogioOk?.cancel();
    _okEmBaixo = false;
  }

  /// O OK com pressão longa: em baixo arranca o relógio; mantido abre o menu (uma vez); solto
  /// antes disso abre o cartão. As repetições nunca abrem nada (o OK que fechou o menu e
  /// continua em baixo não abre a lista).
  KeyEventResult _teclaOk(KeyEvent e) {
    if (e is KeyRepeatEvent) return KeyEventResult.handled;
    if (e is KeyDownEvent) {
      _largarOk();
      _okEmBaixo = true;
      _okLongo = false;
      _relogioOk = Timer(duracaoOkMantido, () {
        if (!mounted || !_okEmBaixo) return;
        _okLongo = true;
        widget.onLongPress?.call();
      });
      return KeyEventResult.handled;
    }
    // soltou
    if (!_okEmBaixo) return KeyEventResult.handled;
    final longo = _okLongo;
    _largarOk();
    if (!longo) widget.onTap?.call();
    return KeyEventResult.handled;
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (widget.onLongPress != null && _no.hasPrimaryFocus && teclasOk.contains(e.logicalKey)) return _teclaOk(e);
    if (e is KeyUpEvent || e.logicalKey != LogicalKeyboardKey.arrowDown || !_no.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    final botoes = _interior.traversalDescendants.where((n) => n.canRequestFocus);
    if (botoes.isEmpty) return KeyEventResult.ignored;
    botoes.first.requestFocus();
    return KeyEventResult.handled;
  }

  void _hover(bool h) {
    if (mounted && h != _rato) setState(() => _rato = h);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // reconstrói quando o modo de realce muda (TemaConformeRealce troca o tema)
    final verFoco = _focado && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final r = BorderRadius.circular(widget.raio);
    final d = duracaoAnimada(context, Tokens.duracaoRapida);
    return MolduraFoco(
      focado: _focado,
      raio: widget.raio,
      escala: widget.escalaFoco,
      child: SombraExterior(
        duration: d,
        raio: widget.raio,
        sombras: verFoco ? Tokens.sombraFoco : (_rato ? Tokens.sombra2 : Tokens.sombra1),
        child: AnimatedContainer(
          duration: d,
          curve: Tokens.curva,
          decoration: BoxDecoration(
            color: widget.destaque ? null : (verFoco || _rato ? Tokens.cartaoFoco : Tokens.cartao),
            gradient: widget.destaque
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Tokens.aviso.withValues(alpha: verFoco || _rato ? .16 : .11),
                      verFoco || _rato ? Tokens.cartaoFoco : Tokens.cartao,
                    ],
                  )
                : null,
            borderRadius: r,
            border: widget.destaque
                ? Border.all(color: Tokens.aviso.withValues(alpha: .55), width: 1.5)
                : Border.all(color: Tokens.bordaCartao),
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: RoundedRectangleBorder(borderRadius: r),
            clipBehavior: Clip.antiAlias,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              includeSemantics: false,
              onKeyEvent: _tecla,
              child: InkWell(
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                onSecondaryTap: widget.onLongPress,
                autofocus: widget.autofocus,
                focusNode: _no,
                // o fundo de foco só com o foco no próprio cartão (não num botão de dentro)
                focusColor: _focado ? null : Colors.transparent,
                onHover: _hover,
                child: Focus(
                  focusNode: _interior,
                  includeSemantics: false,
                  descendantsAreTraversable: _dentro,
                  child: Padding(padding: widget.padding, child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Um [Slider] para o comando: ESQUERDA/DIREITA mudam o valor e CIMA/BAIXO passam sempre ao
/// controlo de cima/de baixo. O Slider do Material, no modo de navegação "tradicional" (o que o
/// Android TV dá), também usa CIMA/BAIXO para mudar o valor e o foco ficava preso nele. Com o foco
/// (modo do comando), ganha a borda de realce.
class DeslizadorTv extends StatefulWidget {
  const DeslizadorTv({super.key, required this.value, required this.onChanged, this.min = 0, this.max = 1,
      this.divisions, this.label});

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final String? label;

  @override
  State<DeslizadorTv> createState() => _DeslizadorTvState();
}

class _DeslizadorTvState extends State<DeslizadorTv> {
  bool _focado = false;

  @override
  Widget build(BuildContext context) => MolduraFoco(
        focado: _focado,
        raio: Tokens.raioCampo,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          onFocusChange: (f) {
            if (mounted && f != _focado) setState(() => _focado = f);
          },
          // só o Slider vê a navegação "direcional": não apanha CIMA/BAIXO
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
            child: Slider(
              value: widget.value,
              onChanged: widget.onChanged,
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              label: widget.label,
            ),
          ),
        ),
      );
}

/// O título de uma secção (600–700), com subtítulo a 60 % e ações à direita.
class CabecalhoSeccao extends StatelessWidget {
  const CabecalhoSeccao({super.key, required this.titulo, this.subtitulo, this.icone, this.acoes = const [],
      this.padding = const EdgeInsets.only(bottom: Tokens.e12)});

  final String titulo;
  final String? subtitulo;
  final IconData? icone;
  final List<Widget> acoes;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (icone != null) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: Tokens.gradienteAcento,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icone, size: 18, color: Colors.white),
            ),
            const SizedBox(width: Tokens.e12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Tokens.texto)),
              if (subtitulo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitulo!, style: const TextStyle(fontSize: 12.5, color: Tokens.texto2)),
                ),
            ]),
          ),
          ...acoes,
        ]),
      );
}

/// O brilho a passar por cima de blocos (esqueleto enquanto carrega). `child` dá as formas
/// (por exemplo [BlocoEsqueleto]); com "reduzir movimento" fica parado.
class EsqueletoBrilho extends StatefulWidget {
  const EsqueletoBrilho({super.key, required this.child});
  final Widget child;

  @override
  State<EsqueletoBrilho> createState() => _EsqueletoBrilhoState();
}

class _EsqueletoBrilhoState extends State<EsqueletoBrilho> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  static const _base = Color(0x12FFFFFF);
  static const _luz = Color(0x2EFFFFFF);

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
  // RepaintBoundary: o brilho repinta-se a cada frame sem arrastar o resto do ecrã
  Widget build(BuildContext context) => RepaintBoundary(child: AnimatedBuilder(
        animation: _c,
        builder: (_, filho) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(
            colors: const [_base, _luz, _base],
            stops: const [.35, .5, .65],
            transform: _Deslizar(_c.isAnimating ? _c.value : -1),
          ).createShader(r),
          child: filho,
        ),
        child: widget.child,
      ));
}

class _Deslizar extends GradientTransform {
  const _Deslizar(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

/// Um bloco do esqueleto (a forma; a cor vem do [EsqueletoBrilho]).
class BlocoEsqueleto extends StatelessWidget {
  const BlocoEsqueleto({super.key, this.largura, required this.altura, this.raio = 8});
  final double? largura;
  final double altura;
  final double raio;

  @override
  Widget build(BuildContext context) => Container(
        width: largura,
        height: altura,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(raio)),
      );
}
