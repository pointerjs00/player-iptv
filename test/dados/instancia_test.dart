import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';

void main() {
  late Directory pasta;
  setUp(() async => pasta = await Directory.systemTemp.createTemp('inst'));
  tearDown(() async {
    try {
      await pasta.delete(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Future<File> comUmaLista() async {
    final b = await Biblioteca.abrir(pasta);
    await b.adicionar([Importada(contaDeLinha('http://a.com/c/ 00:1A:79:00:00:01')!)]);
    return File('${pasta.path}${Platform.pathSeparator}biblioteca.json');
  }

  test('I7: um erro ao ler (ficheiro bloqueado) não começa vazio nem estraga a biblioteca', () async {
    final f = await comUmaLista();
    final antes = await f.readAsString();
    Future<String> bloqueado(File _) async => throw const FileSystemException('partilha violada');
    await expectLater(Biblioteca.abrir(pasta, ler: bloqueado), throwsA(isA<FileSystemException>()));
    expect(await f.readAsString(), antes);
    expect(File('${f.path}.bak').existsSync(), isFalse);
  });

  test('I7: um erro de leitura passageiro é repetido', () async {
    await comUmaLista();
    var vezes = 0;
    Future<String> umaFalha(File f) async {
      if (vezes++ == 0) throw const FileSystemException('o antivírus tem o ficheiro aberto');
      return f.readAsString();
    }

    final b = await Biblioteca.abrir(pasta, ler: umaFalha);
    expect(b.listas, hasLength(1));
  });

  test('I7: só um ficheiro estragado (JSON inválido) vai para .bak', () async {
    final f = await comUmaLista();
    await f.writeAsString('{ isto não é json');
    final b = await Biblioteca.abrir(pasta);
    expect(b.listas, isEmpty);
    expect(File('${f.path}.bak').existsSync(), isTrue);
  });

  test('I7: o ficheiro temporário leva o pid e bytes aleatórios', () {
    final f = File('${pasta.path}/biblioteca.json');
    final a = Biblioteca.nomeTemporario(f), b = Biblioteca.nomeTemporario(f);
    expect(a, contains('.$pid.'));
    expect(a, isNot(b));
    expect(a, endsWith('.tmp'));
  });

  test('I7: uma 2.ª instância da app não consegue o bloqueio da pasta de dados', () async {
    final primeira = await Biblioteca.bloquearInstancia(pasta);
    expect(primeira, isNotNull);
    expect(await Biblioteca.bloquearInstancia(pasta), isNull);
    await primeira!.close();
    final depois = await Biblioteca.bloquearInstancia(pasta);
    expect(depois, isNotNull);
    await depois!.close();
  }, skip: Platform.isWindows ? false : 'os bloqueios POSIX (fcntl) são por processo: só se vê no Windows');
}
