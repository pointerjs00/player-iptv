import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// O media_kit vem de third_party/media_kit com o lock por player (ver o README.md de lá e o
/// relatório da tarefa 5): com o lock estático de origem, um player cujo mpv deixa de responder
/// a um seek/stop prendia a criação de todos os players seguintes (spinner até reiniciar a app).
/// Não se testa com players verdadeiros (precisam do libmpv nativo): a verificação é no
/// aparelho; aqui garante-se que a alteração não se perde numa atualização.
void main() {
  final fonte = File('third_party/media_kit/lib/src/player/native/player/real.dart');

  test('o lock do NativePlayer é de cada player, não estático', () {
    final s = fonte.readAsStringSync();
    expect(s, isNot(contains('static final Lock lock')));
    expect(RegExp(r'^\s*final Lock lock = Lock\(\);', multiLine: true).hasMatch(s), isTrue);
  });

  test('o pubspec usa a cópia local do media_kit', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('dependency_overrides:'));
    expect(RegExp(r'media_kit:\s*\n\s*path:\s*third_party/media_kit').hasMatch(pubspec), isTrue);
    expect(File('third_party/media_kit/LICENSE').existsSync(), isTrue);
    expect(File('third_party/media_kit/README.player-iptv.md').readAsStringSync(), contains('tarefa 5'));
  });

  test('o media_kit resolvido é o local', () {
    final config = File('.dart_tool/package_config.json').readAsStringSync();
    expect(RegExp(r'"name":\s*"media_kit",\s*"rootUri":\s*"[^"]*third_party/media_kit"').hasMatch(config), isTrue);
  });
}
