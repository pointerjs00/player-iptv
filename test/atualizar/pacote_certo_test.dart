import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/atualizar/pacote_certo.dart';
import 'package:player_iptv/dados/nova_versao.dart';

/// O pacote da release para este aparelho: a edição e o processador (Android) ou o zip (Windows).
void main() {
  final pacotes = [
    for (final n in [
      'TVIntel-1.0.28-android-arm64.apk',
      'TVIntel-1.0.28-android-armv7.apk',
      'TVIntel-1.0.28-windows.zip',
      'TVIntel-1.0.28-partilha-android-arm64.apk',
      'TVIntel-1.0.28-partilha-android-armv7.apk',
      'TVIntel-1.0.28-partilha-windows.zip',
    ])
      Pacote(n, 'https://x/$n', 1, null),
  ];

  String? nome(Plataforma p, {List<String> abis = const [], bool partilha = false}) =>
      pacoteDaApp(pacotes, plataforma: p, abis: abis, partilha: partilha)?.nome;

  test('Android: o processador preferido do aparelho, da edição certa', () {
    expect(nome(Plataforma.android, abis: ['arm64-v8a', 'armeabi-v7a', 'armeabi']), 'TVIntel-1.0.28-android-arm64.apk');
    expect(nome(Plataforma.android, abis: ['arm64-v8a', 'armeabi-v7a'], partilha: true),
        'TVIntel-1.0.28-partilha-android-arm64.apk');
    expect(nome(Plataforma.android, abis: ['armeabi-v7a', 'armeabi']), 'TVIntel-1.0.28-android-armv7.apk');
    expect(nome(Plataforma.android, abis: ['armeabi-v7a'], partilha: true), 'TVIntel-1.0.28-partilha-android-armv7.apk');
  });

  test('Android sem processador suportado (x86_64) ou sem o ficheiro: nenhum', () {
    expect(nome(Plataforma.android, abis: ['x86_64']), isNull);
    expect(nome(Plataforma.android), isNull);
    expect(
        pacoteDaApp([pacotes[0]], plataforma: Plataforma.android, abis: ['armeabi-v7a'], partilha: false), isNull);
  });

  test('Windows: o zip da edição (a completa nunca leva o da partilha, nem o contrário)', () {
    expect(nome(Plataforma.windows), 'TVIntel-1.0.28-windows.zip');
    expect(nome(Plataforma.windows, partilha: true), 'TVIntel-1.0.28-partilha-windows.zip');
    expect(pacoteDaApp([pacotes[5]], plataforma: Plataforma.windows, partilha: false), isNull);
    expect(pacoteDaApp([pacotes[2]], plataforma: Plataforma.windows, partilha: true), isNull);
  });

  test('outras plataformas: nenhum', () {
    expect(nome(Plataforma.outra, abis: ['arm64-v8a']), isNull);
  });
}
