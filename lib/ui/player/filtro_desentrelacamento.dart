import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// O shader de desentrelaçamento do Android (`shaders/desentrelacar.frag`), por cima da textura do
/// vídeo (`Video.envolverTextura`). Com o `mediacodec_embed` as imagens nunca passam pelo mpv, por
/// isso é o Flutter que as filtra; serve igual no modo Compatível. Ver `desentrelacamento.dart`.
///
/// O `ImageFilter.shader` recebe a textura já desenhada à escala do ecrã (uma passagem fora do
/// ecrã, que não se pode evitar: um `FragmentShader` não lê texturas externas). Por isso só serve
/// quando o vídeo ocupa pelo menos tantas linhas do ecrã como tem ([shaderCabe]): reduzido, os dois
/// campos já vêm misturados.
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

/// Quantas linhas (píxeis físicos) do ecrã o vídeo ocupa numa caixa `caixa` (lógica, `dpr`), com o
/// ajuste do `Video` (`fit`, `aspecto` forçado) e o zoom (`escala`). 0 sem tamanho.
double linhasMostradas(
    {required Size caixa,
    required double dpr,
    required int colunas,
    required int linhas,
    required BoxFit fit,
    double? aspecto,
    double escala = 1}) {
  if (caixa.isEmpty || colunas <= 0 || linhas <= 0) return 0;
  final w = aspecto == null ? colunas.toDouble() : linhas * aspecto;
  final h = linhas.toDouble();
  final sx = caixa.width / w, sy = caixa.height / h;
  final double y = switch (fit) {
    BoxFit.fill => sy,
    BoxFit.cover => math.max(sx, sy),
    BoxFit.fitWidth => sx,
    BoxFit.fitHeight => sy,
    BoxFit.none => 1,
    BoxFit.scaleDown => math.min(1, math.min(sx, sy)),
    BoxFit.contain => math.min(sx, sy),
  };
  return (h * y * escala * dpr).roundToDouble();
}

/// O shader só serve se o vídeo não for reduzido no ecrã (1 % de folga para arredondamentos).
bool shaderCabe({required int linhasVideo, required double linhasNoEcra}) =>
    linhasVideo > 0 && linhasNoEcra >= linhasVideo * 0.99;

/// A textura do vídeo com o shader de desentrelaçamento. Sem shader (Skia), sem programa, sem o
/// tamanho do vídeo, ou com o vídeo reduzido no ecrã fica a textura sozinha: nunca parte a imagem.
/// O `FragmentShader` é um só por widget (criado uma vez, largado no fim).
class TexturaDesentrelacada extends StatefulWidget {
  const TexturaDesentrelacada({
    super.key,
    required this.programa,
    required this.colunas,
    required this.linhas,
    required this.child,
    this.linhasNoEcra,
    this.suportado,
    this.filtro,
  });

  final ui.FragmentProgram? programa;

  /// O tamanho da imagem do vídeo (as linhas contam-se nela, não no ecrã).
  final int colunas;
  final int linhas;

  /// As linhas do ecrã que o vídeo ocupa ([linhasMostradas]); null: não se sabe (assume-se que cabe).
  final double? linhasNoEcra;
  final Widget child;

  /// Só para os testes (por omissão: [FiltroDesentrelacamento.suportado]).
  final bool? suportado;

  /// Só para os testes: o filtro feito com o shader (por omissão `ImageFilter.shader`).
  final ui.ImageFilter Function(ui.FragmentShader shader)? filtro;

  @override
  State<TexturaDesentrelacada> createState() => _TexturaDesentrelacadaState();
}

class _TexturaDesentrelacadaState extends State<TexturaDesentrelacada> {
  ui.FragmentShader? _shader;
  ui.FragmentProgram? _de;

  ui.FragmentShader _shaderDe(ui.FragmentProgram p) {
    if (!identical(p, _de)) {
      _shader?.dispose();
      _shader = p.fragmentShader();
      _de = p;
    }
    return _shader!;
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final p = w.programa;
    final noEcra = w.linhasNoEcra;
    if (p == null ||
        w.colunas <= 0 ||
        w.linhas <= 0 ||
        !(w.suportado ?? FiltroDesentrelacamento.suportado) ||
        (noEcra != null && !shaderCabe(linhasVideo: w.linhas, linhasNoEcra: noEcra))) {
      return w.child;
    }
    final shader = _shaderDe(p)
      // 0 e 1: o tamanho da entrada (posto pelo motor)
      ..setFloat(2, w.colunas.toDouble())
      ..setFloat(3, w.linhas.toDouble());
    return ImageFiltered(imageFilter: (w.filtro ?? ui.ImageFilter.shader)(shader), child: w.child);
  }
}

/// Mede as linhas do ecrã que o vídeo ocupa (`medir`, com a caixa e o dpr) e põe-nas em `linhas`
/// depois de cada layout em que mudem: quem as escuta (o [TexturaDesentrelacada] dentro do `Video`)
/// é reconstruído, por isso redimensionar a janela muda a decisão do shader.
class MedidorLinhas extends StatelessWidget {
  const MedidorLinhas({super.key, required this.linhas, required this.medir, required this.child});

  final ValueNotifier<double?> linhas;
  final double Function(Size caixa, double dpr) medir;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? View.of(context).devicePixelRatio;
    return LayoutBuilder(builder: (context, c) {
      final v = medir(c.biggest, dpr);
      if (v != linhas.value) {
        // depois do layout: mudar o valor a meio dele marcava widgets abaixo a meio da construção
        WidgetsBinding.instance.addPostFrameCallback((_) => linhas.value = v);
      }
      return child;
    });
  }
}
