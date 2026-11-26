import 'package:material_ui/material_ui.dart';

import 'movimento.dart';

/// O ponto vermelho do direto: ao aparecer pulsa três vezes (uma onda que cresce e se apaga) e
/// depois fica aceso. Parado com «reduzir movimento».
class PontoDireto extends StatefulWidget {
  const PontoDireto({super.key, this.tamanho = 8});
  final double tamanho;

  @override
  State<PontoDireto> createState() => _PontoDiretoState();
}

class _PontoDiretoState extends State<PontoDireto> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (semAnimacoes(context)) {
      _c.stop();
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.repeat(count: 3);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const _vermelho = Color(0xFFFF4D61);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = Curves.easeOut.transform(_c.value);
          return Container(
            key: const Key('ponto-direto'),
            width: widget.tamanho,
            height: widget.tamanho,
            decoration: BoxDecoration(
              color: _vermelho,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: _vermelho.withValues(alpha: .75 * (1 - t)), spreadRadius: widget.tamanho * t),
              ],
            ),
          );
        },
      );
}
