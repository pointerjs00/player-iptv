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

  test('download a sério que pára a meio: «Cancelar» interrompe logo e dá Cancelado (não um erro)', () async {
    final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => servidor.close(force: true));
    servidor.listen((r) async {
      r.response.bufferOutput = false;
      r.response.contentLength = 1000;
      r.response.add(List.filled(100, 1));
      await r.response.flush(); // e depois não manda mais nada
    });
    final c = Cancelamento();
    final p = Pacote('TVIntel-1.0.28-windows.zip', 'http://127.0.0.1:${servidor.port}/p.zip', 1000, null);
    final a = descarregarPacote(p, pasta, cancelamento: c);
    Timer(const Duration(milliseconds: 500), c.cancelar); // parado a meio: o utilizador cancela
    await expectLater(a.timeout(const Duration(seconds: 5)), throwsA(isA<Cancelado>()));
    expect(naPasta(), isEmpty);
  });

  test('cancelar antes de a ligação abrir também dá Cancelado', () async {
    final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => servidor.close(force: true));
    servidor.listen((_) {}); // nunca responde
    final c = Cancelamento();
    final p = Pacote('x.zip', 'http://127.0.0.1:${servidor.port}/p.zip', 10, null);
    final a = descarregarPacote(p, pasta, cancelamento: c);
    Timer(const Duration(milliseconds: 200), c.cancelar);
    await expectLater(a.timeout(const Duration(seconds: 5)), throwsA(isA<Cancelado>()));
  });

  test('limparPasta apaga os pacotes antigos (e não falha sem a pasta)', () async {
    File('${pasta.path}${Platform.pathSeparator}TVIntel-1.0.27-android-arm64.apk').writeAsStringSync('velho');
    Directory('${pasta.path}${Platform.pathSeparator}sub').createSync();
    await limparPasta(pasta);
    expect(pasta.existsSync(), isTrue);
    expect(naPasta(), isEmpty);
    await limparPasta(Directory('${pasta.path}${Platform.pathSeparator}nao-existe'));
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
