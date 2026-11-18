import 'package:material_ui/material_ui.dart';

/// O cartão "o canal não abriu" por cima do vídeo, com "Tentar de novo" e "Voltar".
///
/// Com o comando: ao aparecer, o foco vai para "Tentar de novo"; esquerda/direita andam entre os
/// dois botões e OK carrega no que tem o foco (o [ControlosPlayer] deixa passar estas teclas
/// enquanto o cartão está à vista). Ao sair, o foco volta ao player.
class CartaoErroCanal extends StatefulWidget {
  const CartaoErroCanal({super.key, required this.texto, required this.aoTentar, required this.aoVoltar});

  final String texto;
  final VoidCallback aoTentar;
  final VoidCallback aoVoltar;

  @override
  State<CartaoErroCanal> createState() => _CartaoErroCanalState();
}

class _CartaoErroCanalState extends State<CartaoErroCanal> {
  final _tentar = FocusNode(debugLabel: 'tentar de novo');

  @override
  void initState() {
    super.initState();
    // (o autofocus não serve: o player já tem o foco)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tentar.requestFocus();
    });
  }

  @override
  void dispose() {
    _tentar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
              const SizedBox(height: 8),
              Text(widget.texto, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FocusTraversalGroup(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  FilledButton(focusNode: _tentar, onPressed: widget.aoTentar, child: const Text('Tentar de novo')),
                  const SizedBox(width: 8),
                  TextButton(onPressed: widget.aoVoltar, child: const Text('Voltar')),
                ]),
              ),
            ]),
          ),
        ),
      );
}
