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
  final _chave = GlobalKey();
  ui.Image? _imagem;

  ui.Image? get imagem => _imagem;

  /// O vídeo (o que se copia).
  Widget envolver(Widget video) => RepaintBoundary(key: _chave, child: video);

  /// Copia o que está no ecrã (`pixelRatio`: o do ecrã). Falso se não deu (sem vídeo no ecrã); nunca
  /// lança.
  Future<bool> guardar(double pixelRatio) async {
    final b = _chave.currentContext?.findRenderObject();
    if (b is! RenderRepaintBoundary || !b.hasSize) return false;
    try {
      final img = await b.toImage(pixelRatio: pixelRatio);
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
