import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:material_ui/material_ui.dart';

/// A última imagem do vídeo, para ficar por cima (com "A carregar…") enquanto o canal reabre
/// depois de um corte do servidor ([ContinuarDireto]).
///
/// Sem ela o ecrã ficava preto: o `stop()` do media_kit (no zap e dentro do `open()`) põe a largura
/// do vídeo a null e o `Video` esconde a textura até à primeira imagem do canal reaberto. A cópia é
/// do Flutter (`RepaintBoundary.toImage`, na thread de rasterização): nenhuma chamada ao libmpv,
/// serve igual no Android direto (`mediacodec_embed`) e no Windows, e já vem desentrelaçada.
class UltimaImagem {
  UltimaImagem({Future<ui.Image> Function(RenderRepaintBoundary b, double pixelRatio)? copiar, this.limite = limitePadrao})
      : _copiar = copiar ?? ((b, r) => b.toImage(pixelRatio: r));

  /// Quanto se espera pela cópia: a reabertura espera por ela, por isso nunca pode ficar presa
  /// (rasterização parada, app em segundo plano). Depois disto segue-se com a rodinha.
  static const limitePadrao = Duration(milliseconds: 500);

  /// A largura máxima da cópia (fica por baixo de uma rodinha: num 4K seriam ~33 MB).
  static const larguraMaxima = 1280.0;

  final Future<ui.Image> Function(RenderRepaintBoundary b, double pixelRatio) _copiar;
  final Duration limite;
  final _chave = GlobalKey();
  ui.Image? _imagem;

  ui.Image? get imagem => _imagem;

  /// O vídeo (o que se copia).
  Widget envolver(Widget video) => RepaintBoundary(key: _chave, child: video);

  /// Copia o que está no ecrã (`pixelRatio`: o do ecrã; a cópia fica com [larguraMaxima] no
  /// máximo). Falso se não deu (sem vídeo no ecrã, ou sem resposta em [limite]: a que chegar tarde é
  /// largada); nunca lança.
  Future<bool> guardar(double pixelRatio) async {
    final b = _chave.currentContext?.findRenderObject();
    if (b is! RenderRepaintBoundary || !b.hasSize || b.size.width <= 0) return false;
    final r = math.min(pixelRatio, larguraMaxima / b.size.width);
    try {
      final copia = _copiar(b, r);
      var desistiu = false;
      final img = await copia.timeout(limite, onTimeout: () {
        desistiu = true;
        copia.then((i) => i.dispose(), onError: (_) {});
        throw TimeoutException('cópia da imagem', limite);
      });
      if (desistiu) {
        img.dispose();
        return false;
      }
      largar();
      _imagem = img;
      return true;
    } catch (e) {
      debugPrint('player: a última imagem não foi guardada ($e)');
      return false;
    }
  }

  /// Esquece a imagem (a primeira imagem do canal reaberto chegou, erro, outro canal).
  void largar() {
    final i = _imagem;
    _imagem = null;
    i?.dispose();
  }

  /// O que vai por cima do vídeo (null sem imagem): nunca apanha toques nem o foco.
  Widget? sobreposicao() {
    final i = _imagem;
    if (i == null) return null;
    return Positioned.fill(child: IgnorePointer(child: ExcludeFocus(child: RawImage(image: i, fit: BoxFit.fill))));
  }
}
