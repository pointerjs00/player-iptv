import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:media_kit_video/src/video_controller/android_video_controller/real.dart';

void main() {
  const superficie = Rect.fromLTWH(0, 0, 1920, 1080);
  const video43 = Rect.fromLTWH(0, 0, 720, 576);

  test('mediacodec_embed: a superfície recriada (1920x1080) não estica um vídeo 4:3', () {
    // o VideoOutput.Resize depois de segundo plano -> primeiro plano manda o tamanho da
    // superfície; o videoParams não volta a chegar (os mesmos parâmetros)
    expect(AndroidVideoController.rectDepoisDeResize(vo: 'mediacodec_embed', superficie: superficie, video: video43),
        video43);
  });

  test('mediacodec_embed antes do primeiro vídeo: fica a superfície (até o videoParams chegar)', () {
    expect(AndroidVideoController.rectDepoisDeResize(vo: 'mediacodec_embed', superficie: superficie, video: null),
        superficie);
  });

  test('vo=gpu: a superfície tem o tamanho do vídeo, fica o que o Resize diz (como antes)', () {
    expect(AndroidVideoController.rectDepoisDeResize(vo: 'gpu', superficie: superficie, video: video43), superficie);
  });
}
