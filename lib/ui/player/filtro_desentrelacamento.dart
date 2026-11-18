import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// O shader de desentrelaçamento do Android (`shaders/desentrelacar.frag`), por cima da textura do
/// vídeo (`Video.envolverTextura`). Com o `mediacodec_embed` as imagens nunca passam pelo mpv, por
/// isso é o Flutter que as filtra; serve igual no modo Compatível. Ver `desentrelacamento.dart`.
abstract final class FiltroDesentrelacamento {
  static Future<ui.FragmentProgram?>? _programa;

  /// O programa (carregado uma vez por processo; null se falhar).
  static Future<ui.FragmentProgram?> programa() =>
      _programa ??= ui.FragmentProgram.fromAsset('shaders/desentrelacar.frag').then<ui.FragmentProgram?>(
        (p) => p,
        onError: (Object e) {
          debugPrint('desentrelaçamento: shader do Flutter não carregou ($e)');
          return null;
        },
      );

  /// O Flutter deste aparelho permite um shader como filtro de imagem (só com o Impeller).
  static bool get suportado => ui.ImageFilter.isShaderFilterSupported;
}

/// A textura do vídeo com o shader de desentrelaçamento. Sem shader (Skia), sem programa ou sem o
/// tamanho do vídeo fica a textura sozinha: nunca parte a imagem.
class TexturaDesentrelacada extends StatelessWidget {
  const TexturaDesentrelacada({
    super.key,
    required this.programa,
    required this.colunas,
    required this.linhas,
    required this.child,
    this.suportado,
  });

  final ui.FragmentProgram? programa;

  /// O tamanho da imagem do vídeo (as linhas contam-se nela, não no ecrã).
  final int colunas;
  final int linhas;
  final Widget child;

  /// Só para os testes (por omissão: [FiltroDesentrelacamento.suportado]).
  final bool? suportado;

  @override
  Widget build(BuildContext context) {
    final p = programa;
    if (p == null || colunas <= 0 || linhas <= 0 || !(suportado ?? FiltroDesentrelacamento.suportado)) return child;
    final shader = p.fragmentShader()
      // 0 e 1: o tamanho da entrada (posto pelo motor)
      ..setFloat(2, colunas.toDouble())
      ..setFloat(3, linhas.toDouble());
    return ImageFiltered(imageFilter: ui.ImageFilter.shader(shader), child: child);
  }
}
