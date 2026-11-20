import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// O ExoPlayer lê a rajada inteira de cada ligação nova (o servidor manda logo ~20–30 s, às vezes
/// 40–50 s, e fecha ao fim de poucos segundos): com o máximo a 30 s, o resto ficava no socket e
/// perdia-se no fecho. O `DefaultLoadControl` do Media3 1.5.1 continua a ler abaixo do mínimo
/// mesmo com o limite de bytes atingido, se `prioritizeTimeOverSizeThresholds`; entre o mínimo e o
/// máximo pára só no máximo ou no limite de bytes (por omissão ~144 MB com vídeo e áudio).
void main() {
  test('o LoadControl do ExoPlayer: mínimo 30 s, máximo 60 s, início 1,5 s, retoma 2,5 s, tempo antes dos bytes',
      () {
    final fonte = File('android/app/src/main/kotlin/pt/playeriptv/player_iptv/ReprodutorExo.kt').readAsStringSync();
    final carga = RegExp(r'DefaultLoadControl\.Builder\(\)([\s\S]*?)\.build\(\)').firstMatch(fonte);
    expect(carga, isNotNull);
    final corpo = carga!.group(1)!;
    expect(corpo, contains('.setBufferDurationsMs(30_000, 60_000, 1_500, 2_500)'));
    expect(corpo, contains('.setPrioritizeTimeOverSizeThresholds(true)'));
    expect(corpo, isNot(contains('setTargetBufferBytes')), reason: 'o limite de bytes fica o do Media3 (~144 MB)');
    expect(RegExp(r'DefaultLoadControl\.Builder\(\)').allMatches(fonte), hasLength(1));
  });
}
