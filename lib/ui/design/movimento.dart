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

/// Entrada de `filho` com fade + slide, atrasada conforme o `indice` (efeito cascata).
/// Sem animação com "reduzir movimento" e para índices > 30.
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
  bool _comecou = false;
  bool _estatico = false;

  @override
  void initState() {
    super.initState();
    final atraso = _passoCascata * widget.indice;
    final total = atraso + Tokens.duracaoLenta;
    _c = AnimationController(vsync: this, duration: total);
    _curva = CurvedAnimation(
      parent: _c,
      curve: Interval(atraso.inMicroseconds / total.inMicroseconds, 1, curve: Tokens.curva),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_comecou) return;
    _comecou = true;
    if (semAnimacoes(context)) {
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

  @override
  Widget build(BuildContext context) {
    if (_estatico) return widget.child;
    return FadeTransition(
      opacity: _curva,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .08), end: Offset.zero).animate(_curva),
        child: widget.child,
      ),
    );
  }
}

/// Fade-through: quem sai desvanece primeiro; quem entra aparece a seguir, a crescer de 94 %.
Widget transicaoSuave(BuildContext context, Animation<double> entrada, Animation<double> saida, Widget filho) {
  if (semAnimacoes(context)) return filho;
  final aparecer = CurvedAnimation(parent: entrada, curve: const Interval(.3, 1, curve: Tokens.curva));
  final desaparecer = CurvedAnimation(parent: saida, curve: const Interval(0, .3, curve: Curves.easeIn));
  return FadeTransition(
    opacity: ReverseAnimation(desaparecer),
    child: FadeTransition(
      opacity: aparecer,
      child: ScaleTransition(scale: Tween(begin: .94, end: 1.0).animate(aparecer), child: filho),
    ),
  );
}

/// A rota de todos os ecrãs da app: transição suave (fade-through).
PageRoute<T> rotaSuave<T>(Widget pagina) => PageRouteBuilder<T>(
      transitionDuration: Tokens.duracaoLenta,
      reverseTransitionDuration: Tokens.duracaoMedia,
      pageBuilder: (_, _, _) => pagina,
      transitionsBuilder: (c, a, s, filho) => transicaoSuave(c, a, s, filho),
    );

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
