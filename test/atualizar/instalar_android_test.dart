import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/atualizar/instalar_android.dart';

/// O lado Dart do canal «player_iptv/atualizar» (o Kotlin está em MainActivity.kt).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('player_iptv/atualizar');
  final chamadas = <MethodCall>[];
  final respostas = <String, Object?>{};

  setUp(() {
    chamadas.clear();
    respostas.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (c) async {
      chamadas.add(c);
      return respostas[c.method];
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, null));

  const i = InstaladorAndroid();

  test('abis: as do aparelho, pela ordem', () async {
    respostas['abis'] = ['arm64-v8a', 'armeabi-v7a'];
    expect(await i.abis(), ['arm64-v8a', 'armeabi-v7a']);
    respostas['abis'] = null;
    expect(await i.abis(), isEmpty);
  });

  test('podeInstalar e pedirAutorizacao (false: o ecrã do Android não existe nesta TV)', () async {
    respostas['podeInstalar'] = false;
    expect(await i.podeInstalar(), isFalse);
    respostas['pedirAutorizacao'] = false;
    expect(await i.pedirAutorizacao(), isFalse);
    respostas['pedirAutorizacao'] = true;
    expect(await i.pedirAutorizacao(), isTrue);
  });

  test('abrirPagina passa o endereço; false quando não há browser (TV)', () async {
    respostas['abrirPagina'] = false;
    expect(await i.abrirPagina('https://github.com/x'), isFalse);
    expect(chamadas.last.arguments, {'url': 'https://github.com/x'});
    respostas['abrirPagina'] = true;
    expect(await i.abrirPagina('https://github.com/x'), isTrue);
  });

  test('instalar passa o caminho do APK', () async {
    await i.instalar(File('/data/cache/atualizar/TVIntel-1.0.28-android-arm64.apk'));
    expect(chamadas.single.method, 'instalar');
    expect(chamadas.single.arguments, {'caminho': '/data/cache/atualizar/TVIntel-1.0.28-android-arm64.apk'});
  });
}
