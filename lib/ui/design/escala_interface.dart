import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/preferencias.dart';
import 'ecra.dart';

export '../../dados/preferencias.dart' show TamanhoInterface;

/// A escala do Compacto (na TV e no Windows).
const escalaCompacto = .8;

/// A escala da interface para o tamanho [t]: 0,8 no Compacto na TV e no Windows (ou outro
/// computador); 1 no telemóvel e no Normal. [context] é o de fora da área escalada.
double escalaPara(BuildContext context, TamanhoInterface t) {
  if (t == TamanhoInterface.normal) return 1;
  final computador = switch (defaultTargetPlatform) {
    TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
    _ => false,
  };
  return computador || ecraTv(context) ? escalaCompacto : 1;
}

/// Desenha [child] mais pequeno: com `escala < 1`, o filho tem uma área de `tamanho / escala`
/// (a MediaQuery dividida: `size`, `padding`, `viewPadding`, `viewInsets`) e é reduzido a partir
/// do canto superior esquerdo, de modo a encher a janela. Os toques e o foco seguem a redução.
/// Com 1 devolve o filho. O filho guarda o estado quando a escala muda (Compacto ↔ Normal).
class EscalaInterface extends StatefulWidget {
  const EscalaInterface({super.key, required this.escala, required this.child});

  final double escala;
  final Widget child;

  @override
  State<EscalaInterface> createState() => _EscalaInterfaceState();
}

class _EscalaInterfaceState extends State<EscalaInterface> {
  /// Mudar de escala muda os pais do filho: a chave global leva-o (com o estado) para o sítio novo.
  final _chave = GlobalKey(debugLabel: 'EscalaInterface');

  @override
  Widget build(BuildContext context) {
    final filho = KeyedSubtree(key: _chave, child: widget.child);
    final e = widget.escala;
    if (e >= 1) return filho;
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        size: mq.size / e,
        padding: mq.padding / e,
        viewPadding: mq.viewPadding / e,
        viewInsets: mq.viewInsets / e,
      ),
      child: LayoutBuilder(
        builder: (context, c) => OverflowBox(
          // a área maior, presa ao canto superior esquerdo; a redução põe-na dentro da janela
          alignment: Alignment.topLeft,
          minWidth: c.maxWidth / e,
          maxWidth: c.maxWidth / e,
          minHeight: c.maxHeight / e,
          maxHeight: c.maxHeight / e,
          child: Transform.scale(scale: e, alignment: Alignment.topLeft, child: filho),
        ),
      ),
    );
  }
}

/// A [EscalaInterface] com o tamanho escolhido nas [preferencias]: muda logo que se muda a opção.
class EscalaConformePreferencias extends StatelessWidget {
  const EscalaConformePreferencias({super.key, required this.preferencias, required this.child});

  final Preferencias preferencias;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: preferencias,
        builder: (context, _) =>
            EscalaInterface(escala: escalaPara(context, preferencias.tamanhoInterface), child: child),
      );
}
