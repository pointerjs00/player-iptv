import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// «Ver TV» é o nome do antigo «Player»: nada em lib/ o diz. Ficam «Player IPTV» (a app) e
/// «Stalker Portal Player» (produto externo).
final _palavra = RegExp(r'(?<![A-Za-z0-9_])Player(?![A-Za-z0-9_])');
final _permitidos = RegExp(r'Player IPTV|Stalker Portal Player');

/// Usos do tipo `Player` do media_kit (código, não texto). Cada ficheiro traz o motivo.
const _excecoes = <String, String>{
  // `Player(configuration: ...)` e `final Player player`: o tipo do media_kit
  'lib/ui/player/motor_mpv.dart': 'tipo Player do media_kit',
  // `MotorForaDaUi.doPlayer(Player player)`: o mesmo tipo
  'lib/ui/player/mpv_fora_da_ui.dart': 'tipo Player do media_kit',
};

/// Tira os comentários (`//` até ao fim da linha e blocos `/* */`) sem olhar para os literais:
/// um `//` dentro de um texto («http://») não é tratado como comentário se vier depois de `:`.
String _semComentarios(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), ' ');

/// As ocorrências de «Player» que não são «Player IPTV» nem «Stalker Portal Player».
List<String> _restos(String codigo) {
  final r = <String>[];
  for (final linha in _semComentarios(codigo).split('\n')) {
    if (_palavra.hasMatch(linha.replaceAll(_permitidos, ''))) r.add(linha.trim());
  }
  return r;
}

void main() {
  test('o verificador apanha texto interpolado, ignora comentários e deixa «Player IPTV»', () {
    expect(_restos(r"final t = '${x ? 'Player' : 'y'}';"), isNotEmpty);
    expect(_restos(r"final t = 'A lista \'do Player\'';"), isNotEmpty);
    expect(_restos("// o Player muda\n/* Player */\nfinal a = 1;"), isEmpty);
    expect(_restos("final t = 'Player IPTV e Stalker Portal Player';"), isEmpty);
    expect(_restos("final t = 'MotorPlayer e player';"), isEmpty);
  });

  test('nada em lib/ fala do «Player» antigo', () {
    final maus = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final caminho = f.path.replaceAll(r'\', '/');
      if (!caminho.endsWith('.dart') || _excecoes.keys.any(caminho.endsWith)) continue;
      for (final l in _restos(f.readAsStringSync())) {
        maus.add('$caminho: $l');
      }
    }
    expect(maus, isEmpty);
  });
}
