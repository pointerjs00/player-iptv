import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/direto/gravador.dart';
import 'package:player_iptv/direto/servidor.dart';

const _bloco = 64 * 1024;
const _reserva = 256 * 1024;
final _origem = Uri.parse('http://exemplo.invalid/live/u/p/1.ts');

/// O byte na posição absoluta `p` do stream falso: dá para conferir o que se recebe.
List<int> _bytes(int desde, int n) => List<int>.generate(n, (i) => (desde + i) % 251);

/// Uma resposta a ser lida: junta os bytes e deixa esperar por um total ou pelo fim.
class _Leitura {
  _Leitura(this.resposta) {
    _sub = resposta.listen((d) {
      bytes.addAll(d);
      _verificar();
    }, onError: (Object _) => _acabar(), onDone: _acabar);
  }

  final HttpClientResponse resposta;
  late final StreamSubscription<List<int>> _sub;
  final bytes = <int>[];
  final _acabou = Completer<void>();
  final _esperas = <(int, Completer<void>)>[];

  Future<void> get acabou => _acabou.future;

  /// Espera até ter recebido pelo menos `n` bytes.
  Future<void> ate(int n) {
    final c = Completer<void>();
    _esperas.add((n, c));
    _verificar();
    return c.future;
  }

  void _verificar() {
    _esperas.removeWhere((e) {
      if (bytes.length < e.$1) return false;
      e.$2.complete();
      return true;
    });
  }

  void _acabar() {
    if (!_acabou.isCompleted) _acabou.complete();
    for (final e in _esperas) {
      e.$2.completeError(StateError('a resposta acabou com ${bytes.length} bytes'));
    }
    _esperas.clear();
  }

  Future<void> cancelar() => _sub.cancel();
}

void main() {
  late Directory tmp;
  late HttpClient cliente;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('servidor_test');
    cliente = HttpClient();
  });
  tearDown(() {
    cliente.close(force: true);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Um gravador cuja origem é um StreamController que o teste alimenta.
  ({GravadorDireto g, StreamController<List<int>> origem}) gravador({int reserva = _reserva}) {
    final c = StreamController<List<int>>();
    final g = GravadorDireto(
        origem: _origem, cabecalhos: const {}, pasta: Directory('${tmp.path}${Platform.pathSeparator}s'),
        reservaBytes: reserva, tamanhoBloco: _bloco, esperar: (_) async {}, abrir: (_, _) async => c.stream);
    return (g: g, origem: c);
  }

  Future<void> enviar(GravadorDireto g, StreamController<List<int>> c, int n) async {
    final alvo = g.fim + n;
    final chegou = g.crescimento.firstWhere((f) => f >= alvo);
    c.add(_bytes(g.fim, n));
    await chegou;
  }

  Future<HttpClientResponse> pedir(Uri u) async => (await cliente.getUrl(u)).close();

  test('GET com desde envia os bytes certos e continua a enviar os que chegam', () async {
    final (:g, :origem) = gravador(reserva: 1 << 20); // nada roda: tudo continua no disco
    await g.iniciar();
    await enviar(g, origem, 100000);
    final s = await ServidorDireto.iniciar(g);
    final u = s.urlDesde(1000);
    expect(u.host, '127.0.0.1');
    final r = await pedir(u);
    expect(r.statusCode, 200);
    expect(r.headers.contentType?.mimeType, 'video/mp2t');
    expect(r.headers.contentLength, -1);
    final l = _Leitura(r);
    await l.ate(99000);
    expect(l.bytes, _bytes(1000, 99000));
    // continua: o que chega à origem chega ao cliente, em vários pedaços
    await enviar(g, origem, 300000);
    await l.ate(399000);
    await enviar(g, origem, 5000);
    await l.ate(404000);
    expect(l.bytes, _bytes(1000, 404000));
    await s.fechar();
    await l.acabou;
    await g.parar();
  });

  test('vários pedidos ao mesmo tempo são servidos cada um por si; o cliente que fecha sai', () async {
    final (:g, :origem) = gravador(reserva: 4 << 20);
    await g.iniciar();
    await enviar(g, origem, 50000);
    final s = await ServidorDireto.iniciar(g);
    final a = _Leitura(await pedir(s.urlDesde(0)));
    // o segundo é uma ligação crua, para a poder cortar como um motor que fecha
    final u = s.urlDesde(30000);
    final b = await Socket.connect(u.host, u.port);
    final recebidoB = <int>[];
    final chegouB = Completer<void>();
    b.listen((d) {
      recebidoB.addAll(d);
      if (recebidoB.length >= 20000 && !chegouB.isCompleted) chegouB.complete();
    }, onError: (Object _) {});
    b.write('GET ${u.path}?${u.query} HTTP/1.1\r\nHost: ${u.host}:${u.port}\r\n\r\n');
    await a.ate(50000);
    await chegouB.future;
    expect(String.fromCharCodes(recebidoB.take(15)), 'HTTP/1.1 200 OK');
    final abertos = <int>[];
    var umSo = false;
    s.pedidosAbertos.listen((n) {
      abertos.add(n);
      if (n == 1) umSo = true;
    });
    b.destroy(); // o cliente fecha: o ciclo dele termina no envio seguinte, o outro continua
    var enviados = 0;
    while (!umSo) {
      await enviar(g, origem, 10000);
      enviados += 10000;
      await a.ate(50000 + enviados);
    }
    expect(enviados, lessThan(1 << 20));
    await enviar(g, origem, 10000);
    await a.ate(60000 + enviados);
    expect(a.bytes, _bytes(0, 60000 + enviados));
    await s.fechar();
    await a.acabou;
    expect(abertos, [1, 0]);
    await g.parar();
  });

  test('código errado ou caminho errado → 404, sem o código na resposta', () async {
    final (:g, :origem) = gravador();
    await g.iniciar();
    await enviar(g, origem, 1000);
    final s = await ServidorDireto.iniciar(g);
    final certo = s.urlDesde(0);
    final codigo = certo.pathSegments.first;
    expect(codigo, matches(RegExp(r'^[0-9a-f]{32}$')));
    final outro = codigo.replaceRange(0, 1, codigo[0] == '0' ? '1' : '0');
    for (final caminho in ['/$outro/direto', '/direto', '/$codigo', '/$codigo/outro', '/', '/$codigo/direto/x']) {
      final r = await pedir(certo.replace(path: caminho));
      expect(r.statusCode, 404, reason: caminho);
      final corpo = await r.fold<List<int>>([], (a, d) => a..addAll(d));
      expect(String.fromCharCodes(corpo), isNot(contains(codigo)));
    }
    // dois servidores têm códigos diferentes
    final s2 = await ServidorDireto.iniciar(g);
    expect(s2.urlDesde(0).pathSegments.first, isNot(codigo));
    await s2.fechar();
    await s.fechar();
    await g.parar();
  });

  test('leitor atrasado: o bloco pedido já foi apagado, continua do início', () async {
    final (:g, :origem) = gravador();
    await g.iniciar();
    for (var k = 0; k < 10; k++) {
      await enviar(g, origem, _bloco);
    }
    expect(g.inicio, greaterThan(0));
    final s = await ServidorDireto.iniciar(g);
    final inicio = g.inicio;
    final l = _Leitura(await pedir(s.urlDesde(1000)));
    final total = g.fim - inicio;
    await l.ate(total);
    expect(l.bytes, _bytes(inicio, total));
    await s.fechar();
    await g.parar();
  });

  test('urlDireto pede perto do fim (ou o início, se a janela for pequena)', () async {
    var relogio = DateTime(2026, 11, 20, 20);
    final c = StreamController<List<int>>();
    final g = GravadorDireto(
        origem: _origem, cabecalhos: const {}, pasta: Directory('${tmp.path}${Platform.pathSeparator}s'),
        reservaBytes: 1 << 20, tamanhoBloco: _bloco, agora: () => relogio, esperar: (_) async {},
        abrir: (_, _) async => c.stream);
    await g.iniciar();
    final s = await ServidorDireto.iniciar(g);
    await enviar(g, c, 1000);
    expect(s.urlDireto.queryParameters['desde'], '${g.posicaoHa(const Duration(seconds: 2))}');
    expect(s.urlDireto.queryParameters['desde'], '0'); // janela menor do que 2 s: o início
    for (var k = 0; k < 6; k++) {
      relogio = relogio.add(const Duration(seconds: 1));
      await enviar(g, c, 10000);
    }
    final desde = int.parse(s.urlDireto.queryParameters['desde']!);
    expect(desde, g.posicaoHa(ServidorDireto.atrasoDireto));
    expect(desde, greaterThan(0));
    expect(desde, lessThan(g.fim));
    await s.fechar();
    await g.parar();
  });

  test('fechar o servidor termina as respostas abertas e deixa de aceitar pedidos', () async {
    final (:g, :origem) = gravador();
    await g.iniciar();
    await enviar(g, origem, 1000);
    final s = await ServidorDireto.iniciar(g);
    final a = _Leitura(await pedir(s.urlDesde(0)));
    final b = _Leitura(await pedir(s.urlDesde(500)));
    await a.ate(1000);
    await b.ate(500);
    await s.fechar(); // os dois estão à espera de crescimento
    await a.acabou;
    await b.acabou;
    await expectLater(pedir(s.urlDesde(0)), throwsA(isA<SocketException>()));
    await s.fechar(); // duas vezes não faz mal
    await g.parar();
  });

  test('um leitor que não lê não atrasa o gravador; fechar termina-o mesmo a meio de um envio', () async {
    final (:g, :origem) = gravador(reserva: 1 << 20);
    await g.iniciar();
    await enviar(g, origem, 1000);
    final s = await ServidorDireto.iniciar(g);
    final u = s.urlDesde(0);
    final parado = await Socket.connect(u.host, u.port);
    final sub = parado.listen(null)..pause(); // nunca lê
    final aberto = s.pedidosAbertos.firstWhere((n) => n == 1);
    parado.write('GET ${u.path}?${u.query} HTTP/1.1\r\nHost: ${u.host}:${u.port}\r\n\r\n');
    await aberto;
    // muito mais do que cabe nos buffers da ligação: o gravador nunca espera pelo leitor
    for (var k = 0; k < 64; k++) {
      await enviar(g, origem, 64 * 1024);
    }
    expect(g.fim, 1000 + 64 * 64 * 1024);
    final fechados = s.pedidosAbertos.firstWhere((n) => n == 0);
    await s.fechar();
    await fechados;
    await sub.cancel();
    parado.destroy();
    await g.parar();
  });

  test('o gravador parar termina as respostas abertas', () async {
    final (:g, :origem) = gravador();
    await g.iniciar();
    await enviar(g, origem, 1000);
    final s = await ServidorDireto.iniciar(g);
    final a = _Leitura(await pedir(s.urlDesde(0)));
    await a.ate(1000);
    await g.parar();
    await a.acabou;
    await s.pedidosAbertos.firstWhere((n) => n == 0);
    await s.fechar();
  });

  test('só escuta em loopback', () async {
    final (:g, :origem) = gravador();
    await g.iniciar();
    final s = await ServidorDireto.iniciar(g);
    final u = s.urlDesde(0);
    expect(u.host, InternetAddress.loopbackIPv4.address);
    expect(s.endereco, InternetAddress.loopbackIPv4);
    // por um endereço da rede do aparelho a porta não responde
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    final fora = [
      for (final i in interfaces)
        for (final e in i.addresses)
          if (!e.isLoopback) e
    ];
    for (final e in fora.take(1)) {
      await expectLater(Socket.connect(e, u.port, timeout: const Duration(seconds: 10)),
          throwsA(isA<SocketException>()));
    }
    await s.fechar();
    await g.parar();
  });
}
