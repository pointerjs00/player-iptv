import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/atualizar/descarregar.dart';
import 'package:player_iptv/dados/nova_versao.dart';
import 'package:player_iptv/rede/http.dart';

/// Descarregar o pacote para ficheiro: o tamanho e o SHA-256 confirmados; nada fica para trás
/// quando falha ou se cancela.
void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('descarregar'));
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  final corpo = utf8.encode('o conteúdo do pacote, em três pedaços');
  final pedacos = [corpo.sublist(0, 10), corpo.sublist(10, 20), corpo.sublist(20)];
  final hash = sha256.convert(corpo).toString();

  Pacote pacote({int? tamanho, String? sha = ''}) =>
      Pacote('TVIntel-1.0.28-android-arm64.apk', 'https://x/p.apk', tamanho ?? corpo.length, sha == '' ? hash : sha);

  AbrirDownload abrirCom(Stream<List<int>> s, [int? total]) => (_, _) async => (s, total ?? corpo.length);

  List<String> naPasta() => pasta.listSync().map((e) => e.uri.pathSegments.last).toList();

  test('descarrega, confirma e fica com o nome do pacote; o progresso chega ao total', () async {
    final progresso = <(int, int)>[];
    final f = await descarregarPacote(pacote(), pasta,
        abrir: abrirCom(Stream.fromIterable(pedacos)), progresso: (r, t) => progresso.add((r, t)));
    expect(f.path, endsWith('TVIntel-1.0.28-android-arm64.apk'));
    expect(f.readAsBytesSync(), corpo);
    expect(progresso.last, (corpo.length, corpo.length));
    expect(naPasta(), ['TVIntel-1.0.28-android-arm64.apk'], reason: 'sem o .parcial');
  });

  test('o tamanho errado: ErroPacote e nada na pasta', () async {
    await expectLater(descarregarPacote(pacote(tamanho: corpo.length + 1), pasta, abrir: abrirCom(Stream.fromIterable(pedacos))),
        throwsA(isA<ErroPacote>()));
    expect(naPasta(), isEmpty);
  });

  test('o SHA-256 errado: ErroPacote e nada na pasta', () async {
    await expectLater(descarregarPacote(pacote(sha: 'ab' * 32), pasta, abrir: abrirCom(Stream.fromIterable(pedacos))),
        throwsA(isA<ErroPacote>()));
    expect(naPasta(), isEmpty);
  });

  test('sem SHA-256 na release só o tamanho conta', () async {
    final f = await descarregarPacote(pacote(sha: null), pasta, abrir: abrirCom(Stream.fromIterable(pedacos)));
    expect(f.existsSync(), isTrue);
  });

  test('cancelar a meio: Cancelado e o parcial apagado', () async {
    final c = Cancelamento();
    final s = StreamController<List<int>>();
    final a = descarregarPacote(pacote(), pasta, abrir: abrirCom(s.stream), cancelamento: c);
    s.add(pedacos[0]);
    await Future<void>.delayed(Duration.zero);
    c.cancelar();
    s.add(pedacos[1]);
    await expectLater(a, throwsA(isA<Cancelado>()));
    unawaited(s.close());
    expect(naPasta(), isEmpty);
  });

  test('a ligação cai a meio: relança e o parcial apagado', () async {
    final s = Stream<List<int>>.fromIterable(pedacos.take(2)).followedBy(const SocketException('caiu'));
    await expectLater(descarregarPacote(pacote(), pasta, abrir: abrirCom(s)), throwsA(isA<SocketException>()));
    expect(naPasta(), isEmpty);
  });
}

extension<T> on Stream<T> {
  Stream<T> followedBy(Object erro) async* {
    yield* this;
    throw erro;
  }
}
