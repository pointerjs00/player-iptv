import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Reduzir movimento (definições de acessibilidade): as animações passam a instantâneas.
bool semAnimacoes(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// `d`, ou zero com "reduzir movimento".
Duration duracaoAnimada(BuildContext context, [Duration d = Tokens.duracaoMedia]) =>
    semAnimacoes(context) ? Duration.zero : d;

/// Acima disto não há cascata: numa lista grande cada item entraria tarde demais.
const maxIndiceCascata = 30;
const _passoCascata = Duration(milliseconds: 30);

/// A cascata só corre na abertura de um ecrã: um item construído mais tarde (volta a entrar
/// com o scroll do comando, troca de abas) aparece logo — senão o foco caía num cartão invisível.
const _janelaCascata = Duration(milliseconds: 1300);

/// Quando começou a cascata em cada rota (o instante do frame).
final _inicioCascata = Expando<Duration>('cascata');

/// Entrada de `filho` com fade + slide, atrasada conforme o `indice` (efeito cascata).
/// Só na abertura do ecrã; sem animação com "reduzir movimento" e para índices > 30; um item que
/// recebe o foco a meio aparece logo.
Widget entradaEmCascata(int indice, Widget filho) =>
    indice > maxIndiceCascata || indice < 0 ? filho : _EntradaCascata(indice: indice, child: filho);

class _EntradaCascata extends StatefulWidget {
  const _EntradaCascata({required this.indice, required this.child});
  final int indice;
  final Widget child;

  @override
  State<_EntradaCascata> createState() => _EntradaCascataState();
}

class _EntradaCascataState extends State<_EntradaCascata> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _curva;
  late final Animation<Offset> _deslize;
  bool _comecou = false;
  bool _estatico = false;

  @override
  void initState() {
    super.initState();
    final atraso = _passoCascata * widget.indice;
    final total = atraso + Tokens.duracaoLenta;
    _c = AnimationController(vsync: this, duration: total);
    // drive (sem listeners no pai): nada para libertar além do controlador
    _curva = _c.drive(CurveTween(curve: Interval(atraso.inMicroseconds / total.inMicroseconds, 1, curve: Tokens.curva)));
    _deslize = _curva.drive(Tween(begin: const Offset(0, .08), end: Offset.zero));
  }

  /// Já passou a abertura do ecrã? (a 1.ª cascata da rota marca o início)
  bool _depoisDaAbertura() {
    final rota = ModalRoute.of(context);
    final binding = SchedulerBinding.instance;
    if (rota == null || binding.schedulerPhase == SchedulerPhase.idle) return false;
    final agora = binding.currentFrameTimeStamp;
    final inicio = _inicioCascata[rota] ??= agora;
    return agora - inicio > _janelaCascata;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_comecou) return;
    _comecou = true;
    if (semAnimacoes(context) || _depoisDaAbertura()) {
      _estatico = true;
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _focou(bool f) {
    // o foco nunca fica num item meio transparente
    if (f && _c.value < 1) _c.value = 1;
  }

  @override
  Widget build(BuildContext context) {
    if (_estatico) return widget.child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: _focou,
      child: FadeTransition(
        opacity: _curva,
        child: SlideTransition(position: _deslize, child: widget.child),
      ),
    );
  }
}

/// Fade-through (Material 3): quem sai desvanece primeiro, a acelerar; quem entra aparece a
/// seguir, a subir um pouco e a crescer de 97 %, a desacelerar.
/// Com "reduzir movimento": quem entra aparece inteiro e quem sai fica logo escondido (os ecrãs
/// são transparentes sobre o fundo: nunca se pintam os dois ao mesmo tempo).
Widget transicaoSuave(BuildContext context, Animation<double> entrada, Animation<double> saida, Widget filho) {
  if (semAnimacoes(context)) {
    return AnimatedBuilder(
      animation: saida,
      builder: (_, f) => Opacity(opacity: saida.value > 0 ? 0 : 1, child: f),
      child: filho,
    );
  }
  final aparecer = entrada.drive(CurveTween(curve: const Interval(.3, 1, curve: Tokens.curva)));
  final desaparecer = saida.drive(CurveTween(curve: const Interval(0, .3, curve: Tokens.curvaSaida)));
  return FadeTransition(
    opacity: desaparecer.drive(Tween(begin: 1.0, end: 0.0)),
    child: FadeTransition(
      opacity: aparecer,
      child: SlideTransition(
        position: aparecer.drive(Tween(begin: const Offset(0, .02), end: Offset.zero)),
        child: ScaleTransition(scale: aparecer.drive(Tween(begin: .97, end: 1.0)), child: filho),
      ),
    ),
  );
}

/// A rota de todos os ecrãs da app: transição suave (fade-through); com "reduzir movimento"
/// dura zero (abrir e voltar).
PageRoute<T> rotaSuave<T>(Widget pagina) => _RotaSuave<T>(pagina);

class _RotaSuave<T> extends PageRouteBuilder<T> {
  _RotaSuave(Widget pagina)
      : super(
          transitionDuration: Tokens.duracaoLenta,
          reverseTransitionDuration: Tokens.duracaoMedia,
          pageBuilder: (_, _, _) => pagina,
          transitionsBuilder: (c, a, s, filho) => transicaoSuave(c, a, s, filho),
        );

  // lido ao criar o controlador (já com o navigator) e em cada push/pop
  bool get _semAnimacoes {
    final c = navigator?.context;
    return c != null && semAnimacoes(c);
  }

  @override
  Duration get transitionDuration => _semAnimacoes ? Duration.zero : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _semAnimacoes ? Duration.zero : super.reverseTransitionDuration;
}

/// Para o `pageTransitionsTheme`: as MaterialPageRoute (por exemplo o ecrã inicial) com a
/// mesma transição, para quem sai também desvanecer.
class TransicaoSuaveBuilder extends PageTransitionsBuilder {
  const TransicaoSuaveBuilder();

  @override
  Duration get transitionDuration => Tokens.duracaoLenta;

  @override
  Duration get reverseTransitionDuration => Tokens.duracaoMedia;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      transicaoSuave(context, animation, secondaryAnimation, child);
}
