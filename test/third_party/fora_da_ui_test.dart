import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:media_kit/src/player/native/utils/fora_da_ui.dart';

/// Uma chamada nativa que demora (ou não volta) nunca pode correr na thread da UI (ANR).
int _demorado(String lib, int ctx, List<String> args) {
  sleep(Duration(milliseconds: int.parse(args.first)));
  return ctx + 1;
}

/// As chamadas síncronas ao libmpv (set/get/command/hook/criar/destruir) só podem estar em
/// funções de topo `ffi…` (que correm num isolate com [foraDaUi]) ou nas que o media_kit já corria
/// em isolates (`_screenshot`, `_getPlaylist`).
final _chamadaSincrona = RegExp(
    r'mpv\.mpv_(set_property|set_property_string|get_property|get_property_string|command|command_ret|'
    r'command_string|terminate_destroy|hook_continue|initialize|create)\(');
final _topo = RegExp(r'^(?:[A-Za-z_][\w<>?, ]*\s+)?([A-Za-z_]\w*)\s*(?:<[^>]*>)?\(');

List<String> _sincronasForaDeIsolates(String caminho) {
  final linhas = File(caminho).readAsLinesSync();
  final erros = <String>[];
  String? funcao;
  for (var i = 0; i < linhas.length; i++) {
    final l = linhas[i];
    if (l.startsWith('class ') || l.startsWith('abstract ') || l.startsWith('extension ')) {
      funcao = l.split(' ')[1];
    } else if (l.isNotEmpty && !l.startsWith(' ') && !l.startsWith('}') && !l.startsWith('/')) {
      funcao = _topo.firstMatch(l)?.group(1) ?? funcao;
    }
    if (_chamadaSincrona.hasMatch(l)) {
      final f = funcao ?? '';
      if (!(f.startsWith('ffi') || f == '_screenshot' || f == '_getPlaylist')) {
        erros.add('$caminho:${i + 1} ($f): ${l.trim()}');
      }
    }
  }
  return erros;
}

void main() {
  test('foraDaUi: uma chamada que bloqueia não prende quem chama', () async {
    var tiques = 0;
    final t = Timer.periodic(const Duration(milliseconds: 50), (_) => tiques++);
    final r = await foraDaUi(_demorado, 'lib', 41, const ['600']);
    t.cancel();
    expect(r, 42);
    expect(tiques, greaterThanOrEqualTo(5), reason: 'a UI continuou a correr durante a chamada');
  });

  test('nenhuma chamada síncrona ao libmpv na thread da UI (media_kit e media_kit_video locais)', () {
    final erros = [
      for (final f in [
        'third_party/media_kit/lib/src/player/native/player/real.dart',
        'third_party/media_kit/lib/src/player/native/core/initializer_native_callable.dart',
        'third_party/media_kit_video/lib/src/utils/query_decoders.dart',
        'third_party/media_kit_video/lib/src/video_controller/android_video_controller/real.dart',
      ])
        ..._sincronasForaDeIsolates(f),
    ];
    expect(erros, isEmpty, reason: erros.join('\n'));
  });

  test('o media_kit_video resolvido é o local', () {
    final config = File('.dart_tool/package_config.json').readAsStringSync();
    expect(RegExp(r'"name":\s*"media_kit_video",\s*"rootUri":\s*"[^"]*third_party/media_kit_video"').hasMatch(config),
        isTrue);
    expect(File('third_party/media_kit_video/LICENSE').existsSync(), isTrue);
    expect(File('third_party/media_kit_video/README.player-iptv.md').existsSync(), isTrue);
  });
}
