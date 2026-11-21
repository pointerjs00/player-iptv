import 'package:material_ui/material_ui.dart';

import 'ecra.dart';
import 'tokens.dart';

/// A barra de dicas de teclas ("OK ver", "Menu opções"...) em baixo. Só aparece na TV e no
/// computador ([mostrarDicasComando]; no telemóvel e no tablet não há teclas).
class BarraTeclas extends StatelessWidget {
  const BarraTeclas(this.itens, {super.key});
  final List<(String tecla, String acao)> itens;

  @override
  Widget build(BuildContext context) {
    if (!mostrarDicasComando(context)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.e16, vertical: Tokens.e8),
      child: Wrap(spacing: Tokens.e16, runSpacing: Tokens.e4, children: [
        for (final (tecla, acao) in itens)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.e8, vertical: 2),
              decoration: BoxDecoration(
                color: Tokens.superficie3,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Tokens.bordaVidro),
              ),
              child: Text(tecla,
                  style: const TextStyle(color: Tokens.texto, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: Tokens.e8),
            Flexible(
              child: Text(acao,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Tokens.texto2, fontSize: 13)),
            ),
          ]),
      ]),
    );
  }
}
