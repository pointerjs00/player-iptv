import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// «Ver TV» é o nome do antigo «Player»: nenhum texto entre aspas em lib/ o diz. Ficam «Player IPTV»
/// (a app) e «Stalker Portal Player» (produto externo).
void main() {
  test('nenhuma string de lib/ fala do «Player» antigo', () {
    final resto = RegExp(r'(?<!Stalker Portal )(?<![A-Za-z])Player(?![A-Za-z])(?! IPTV)');
    final aspas = RegExp(r'''('[^'\n]*'|"[^"\n]*")''');
    final maus = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final (i, linha) in f.readAsLinesSync().indexed) {
        if (linha.trimLeft().startsWith('//')) continue;
        for (final m in aspas.allMatches(linha)) {
          if (resto.hasMatch(m[0]!)) maus.add('${f.path}:${i + 1}: ${m[0]}');
        }
      }
    }
    expect(maus, isEmpty);
  });
}
