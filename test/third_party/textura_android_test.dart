import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android: a textura do vídeo tem de respeitar o recorte (crop) que o MediaCodec põe em cada imagem.
///
/// No API 29+ o `createSurfaceProducer()` do Flutter usa um `ImageReader`, e esse caminho não aplica
/// o recorte (`ImageReaderSurfaceProducer.handlesCropAndRotation()` devolve false no embedding do
/// Flutter 3.50): mostrava-se o buffer inteiro do descodificador, com as linhas de alinhamento por
/// escrever (YUV a zeros = verde) no fundo da imagem. Com as texturas GL (`SurfaceTexture`) o recorte
/// vai na matriz da textura. O Flutter só garante esse caminho com o Impeller em OpenGL ES (com Vulkan
/// o comportamento da opção não está definido), por isso as duas coisas andam juntas.
void main() {
  test('o Impeller do Android corre em OpenGL ES', () {
    final manifesto = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final meta = RegExp(r'<meta-data\s+android:name="io\.flutter\.embedding\.android\.ImpellerBackend"\s+'
        r'android:value="opengles"\s*/>');
    expect(meta.hasMatch(manifesto), isTrue);
  });

  test('a MainActivity pede as texturas GL ao SurfaceProducer antes de o motor arrancar', () {
    final atividade = File('android/app/src/main/kotlin/pt/playeriptv/player_iptv/MainActivity.kt').readAsStringSync();
    final onCreate = atividade.indexOf('override fun onCreate(');
    expect(onCreate, greaterThan(-1));
    final flag = atividade.indexOf('FlutterRenderer.debugForceSurfaceProducerGlTextures = true', onCreate);
    final superOnCreate = atividade.indexOf('super.onCreate(', onCreate);
    expect(flag, greaterThan(onCreate));
    expect(flag, lessThan(superOnCreate), reason: 'antes do super.onCreate (o motor e os plugins arrancam lá)');
  });
}
