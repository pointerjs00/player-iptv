import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../design/design.dart';
import '../realce_foco.dart';
import 'linha_opcao.dart';

/// Uma linha das Definições com um número: título e descrição à esquerda, `− valor +` à direita.
/// A linha toda é uma paragem do foco: ← → mudam o valor em `passo` (sem sair de `min`..`max`) e
/// ↑ ↓ seguem o percurso normal. Os botões − / + também respondem ao toque e ao rato, mas não são
/// paragens do foco.
class SeletorNumero extends StatelessWidget {
  const SeletorNumero({
    super.key,
    required this.titulo,
    required this.descricao,
    required this.valor,
    required this.min,
    required this.max,
    this.passo = 1,
    this.formatar,
    required this.aoMudar,
    this.focusNode,
    this.autofocus = false,
  });

  final String titulo;
  final String descricao;
  final int valor;
  final int min;
  final int max;
  final int passo;

  /// Como se escreve o valor (por omissão, o número).
  final String Function(int)? formatar;
  final ValueChanged<int> aoMudar;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Abaixo desta largura (da linha) o `− valor +` vai para baixo do título: ao lado, o título e a
  /// descrição ficavam com menos de metade da linha.
  static const larguraMinimaLado = 400.0;

  String _texto(int v) => formatar?.call(v) ?? '$v';

  void _mudar(int delta) {
    final novo = (valor + delta * passo).clamp(min, max);
    if (novo != valor) aoMudar(novo);
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    final k = e.logicalKey;
    if (k != LogicalKeyboardKey.arrowLeft && k != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
    // nos extremos a tecla fica aqui: não salta para outro sítio
    if (e is! KeyUpEvent) _mudar(k == LogicalKeyboardKey.arrowLeft ? -1 : 1);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => RealceFoco(
          raio: Tokens.raioBotao,
          construir: (context, aoMudarFoco) => Semantics(
            container: true,
            label: titulo,
            value: _texto(valor),
            increasedValue: _texto((valor + passo).clamp(min, max)),
            decreasedValue: _texto((valor - passo).clamp(min, max)),
            onIncrease: valor < max ? () => _mudar(1) : null,
            onDecrease: valor > min ? () => _mudar(-1) : null,
            child: Focus(
              focusNode: focusNode,
              autofocus: autofocus,
              onFocusChange: aoMudarFoco,
              onKeyEvent: _tecla,
              includeSemantics: false,
              child: Padding(
                padding: paddingLinhaOpcao,
                child: LayoutBuilder(builder: (context, c) {
                  final texto = ExcludeSemantics(child: TextoOpcao(titulo, descricao));
                  // no telemóvel, botões de 48 (alvo de toque)
                  final lado = ecraTelemovel(context) ? 48.0 : 40.0;
                  final controlo = ExcludeSemantics(
                    child: DecoratedBox(
                      decoration:
                          BoxDecoration(color: Tokens.fundo, borderRadius: BorderRadius.circular(Tokens.raioCampo)),
                      child: Padding(
                        padding: const EdgeInsets.all(Tokens.e4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          _Botao('−', 'Menos', valor > min ? () => _mudar(-1) : null, lado: lado),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 72),
                            child: Text(_texto(valor),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Tokens.texto)),
                          ),
                          _Botao('+', 'Mais', valor < max ? () => _mudar(1) : null, lado: lado),
                        ]),
                      ),
                    ),
                  );
                  if (c.maxWidth < larguraMinimaLado) {
                    return SizedBox(
                      width: double.infinity,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        texto,
                        const SizedBox(height: Tokens.e8),
                        controlo,
                      ]),
                    );
                  }
                  return Row(children: [
                    Expanded(child: texto),
                    const SizedBox(width: Tokens.e16),
                    controlo,
                  ]);
                }),
              ),
            ),
          ),
      );
}

class _Botao extends StatelessWidget {
  const _Botao(this.simbolo, this.dica, this.aoCarregar, {this.lado = 40});
  final String simbolo;
  final String dica;
  final VoidCallback? aoCarregar;

  /// A largura e a altura do botão.
  final double lado;

  @override
  Widget build(BuildContext context) => Material(
        color: Tokens.superficie3,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          canRequestFocus: false, // só toque/rato: o foco é da linha
          onTap: aoCarregar,
          child: SizedBox(
            width: lado,
            height: lado,
            child: Center(
              child: Text(simbolo,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: aoCarregar == null ? Tokens.texto2.withValues(alpha: .4) : Tokens.texto)),
            ),
          ),
        ),
      );
}
