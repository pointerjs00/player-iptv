import 'package:material_ui/material_ui.dart';

/// O cartão "o canal não abriu" por cima do vídeo, com as saídas: "Tentar de novo", "Abrir em
/// modo compatível", "Canal visto antes" (só se houver: [aoAnterior]) e "Voltar à lista".
///
/// Com o comando: ao aparecer, o foco vai para "Tentar de novo"; esquerda/direita andam entre os
/// botões e OK carrega no que tem o foco (o [ControlosPlayer] deixa passar estas teclas
/// enquanto o cartão está à vista). Ao sair, o foco volta ao player.
class CartaoErroCanal extends StatefulWidget {
  const CartaoErroCanal({super.key, required this.texto, required this.aoTentar, required this.aoCompativel,
      this.aoAnterior, required this.aoVoltar});

  final String texto;
  final VoidCallback aoTentar;

  /// Reabre o canal em modo compatível (só este canal, nesta sessão).
  final VoidCallback aoCompativel;

  /// Abre o canal visto antes; null = não há (o botão não aparece).
  final VoidCallback? aoAnterior;
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
                // (num ecrã estreito os botões passam à linha seguinte)
                child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                  FilledButton(focusNode: _tentar, onPressed: widget.aoTentar, child: const Text('Tentar de novo')),
                  TextButton(onPressed: widget.aoCompativel, child: const Text('Abrir em modo compatível')),
                  if (widget.aoAnterior != null)
                    TextButton(onPressed: widget.aoAnterior, child: const Text('Canal visto antes')),
                  TextButton(onPressed: widget.aoVoltar, child: const Text('Voltar à lista')),
                ]),
              ),
            ]),
          ),
        ),
      );
}
