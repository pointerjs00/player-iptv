import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/guia/armazem.dart';
import 'package:player_iptv/guia/programa.dart';

void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('guia'));
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  GuiaLista guia(int canais, {String desc = ''}) => GuiaLista({
        for (var i = 0; i < canais; i++)
          '$i': [Programa(1000, 2000, 'Programa $i', desc), Programa(2000, 3000, 'Seguinte $i', desc)],
      }, criado: DateTime(2026, 11, 23, 12), etag: '"e"');

  File ficheiro(String chave) => File('${pasta.path}/${ArmazemGuia.nomeFicheiro(chave)}');

  test('grava comprimido, volta a ler igual e grava por cima', () async {
    final a = ArmazemGuia(pasta);
    await a.gravar('lista1', guia(3));
    final lido = await a.ler('lista1');
    expect(lido!.porCanal.length, 3);
    expect(lido.porCanal['2']!.last, const Programa(2000, 3000, 'Seguinte 2'));
    expect(lido.criado, DateTime(2026, 11, 23, 12));
    expect(lido.etag, '"e"');
    await a.gravar('lista1', guia(1));
    expect((await a.ler('lista1'))!.porCanal.length, 1);
    expect(pasta.listSync().whereType<File>().length, 1, reason: 'um só ficheiro por lista, sem restos');
    expect(await a.ler('outra'), isNull);
  });

  test('5000 canais com descrições ficam pequenos (comprimidos)', () async {
    final a = ArmazemGuia(pasta);
    await a.gravar('grande', guia(5000, desc: 'Uma descrição normal de um programa de televisão, com algum texto.'));
    expect(await a.ocupado(), lessThan(2 * 1024 * 1024));
  });

  test('um ficheiro estragado lê-se como "sem guia"', () async {
    final a = ArmazemGuia(pasta);
    ficheiro('x').writeAsStringSync('lixo');
    expect(await a.ler('x'), isNull);
  });

  test('arrumar: apaga os de listas que já não existem e os sem uso há uma semana', () async {
    final a = ArmazemGuia(pasta);
    await a.gravar('fica', guia(1));
    await a.gravar('apagada', guia(1));
    await a.gravar('velha', guia(1));
    ficheiro('velha').setLastModifiedSync(DateTime.now().subtract(const Duration(days: 8)));
    await a.arrumar(manter: {'fica', 'velha'});
    expect(ficheiro('fica').existsSync(), isTrue);
    expect(ficheiro('apagada').existsSync(), isFalse);
    expect(ficheiro('velha').existsSync(), isFalse);
  });

  test('passando do teto, saem os usados há mais tempo (nunca o que se acabou de gravar)', () async {
    final a = ArmazemGuia(pasta, teto: 1);
    await a.gravar('antiga', guia(50));
    ficheiro('antiga').setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 2)));
    await a.gravar('nova', guia(50));
    expect(ficheiro('antiga').existsSync(), isFalse);
    expect(ficheiro('nova').existsSync(), isTrue);
  });
}
