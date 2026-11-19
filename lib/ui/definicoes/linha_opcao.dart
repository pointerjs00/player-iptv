import 'package:material_ui/material_ui.dart';

import '../design/design.dart';

/// O espaço à volta do conteúdo de uma linha das Definições.
const paddingLinhaOpcao = EdgeInsets.symmetric(horizontal: Tokens.e8, vertical: Tokens.e8);

/// O título e a explicação de uma opção (a coluna da esquerda).
class TextoOpcao extends StatelessWidget {
  const TextoOpcao(this.titulo, this.explicacao, {super.key});
  final String titulo;
  final String explicacao;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Tokens.texto)),
        const SizedBox(height: 2),
        Text(explicacao, style: const TextStyle(fontSize: 13.5, color: Tokens.texto2)),
      ]);
}

/// Uma opção das Definições, em linha simples (sem caixa): título e explicação à esquerda e o
/// controlo à direita; por baixo do título quando `empilhar` ou quando a largura é curta. Sem
/// alturas fixas: cresce com a letra do sistema.
class LinhaOpcao extends StatelessWidget {
  const LinhaOpcao({super.key, required this.titulo, required this.explicacao, this.controlo, this.empilhar = false});

  final String titulo;
  final String explicacao;
  final Widget? controlo;
  final bool empilhar;

  /// Abaixo desta largura o controlo vai para baixo do título.
  static const larguraMinimaLado = 520.0;

  @override
  Widget build(BuildContext context) => Padding(
        padding: paddingLinhaOpcao,
        child: LayoutBuilder(builder: (context, c) {
          final texto = TextoOpcao(titulo, explicacao);
          final controlo = this.controlo;
          if (controlo == null) return SizedBox(width: double.infinity, child: texto);
          if (empilhar || c.maxWidth < larguraMinimaLado) {
            return SizedBox(
                width: double.infinity,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  texto,
                  const SizedBox(height: Tokens.e8),
                  controlo,
                ]));
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: texto),
            const SizedBox(width: Tokens.e16),
            // o controlo leva o que precisa (até 75 % da linha); o texto fica com o resto
            ConstrainedBox(constraints: BoxConstraints(maxWidth: c.maxWidth * .75), child: controlo),
          ]);
        }),
      );
}

/// O separador fino entre duas linhas.
class SeparadorOpcao extends StatelessWidget {
  const SeparadorOpcao({super.key});

  @override
  Widget build(BuildContext context) => const Divider(height: 1, thickness: 1, color: Tokens.bordaVidro);
}
