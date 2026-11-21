import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/pasta_dados.dart';

void main() {
  late Directory raiz;
  setUp(() => raiz = Directory.systemTemp.createTempSync('pasta-dados'));
  tearDown(() => raiz.deleteSync(recursive: true));

  Directory sub(String n) => Directory('${raiz.path}${Platform.pathSeparator}$n');

  test('a pasta do nome antigo passa para a nova (vazia)', () async {
    File('${(sub('Velha')..createSync()).path}/biblioteca.json').writeAsStringSync('{}');
    final nova = sub('Nova')..createSync();
    await migrarPastaAntiga(nova, antigo: 'Velha');
    expect(File('${nova.path}/biblioteca.json').existsSync(), isTrue);
    expect(sub('Velha').existsSync(), isFalse);
  });

  test('a nova com dados fica como está', () async {
    File('${(sub('Velha')..createSync()).path}/biblioteca.json').writeAsStringSync('velha');
    final nova = sub('Nova')..createSync();
    File('${nova.path}/biblioteca.json').writeAsStringSync('nova');
    await migrarPastaAntiga(nova, antigo: 'Velha');
    expect(File('${nova.path}/biblioteca.json').readAsStringSync(), 'nova');
    expect(sub('Velha').existsSync(), isTrue);
  });

  test('sem pasta antiga não faz nada', () async {
    final nova = sub('Nova')..createSync();
    await migrarPastaAntiga(nova, antigo: 'Velha');
    expect(nova.existsSync(), isTrue);
  });
}
