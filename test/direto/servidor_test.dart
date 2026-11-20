import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/direto/gravador.dart';
import 'package:player_iptv/direto/servidor.dart';

const _bloco = 64 * 1024; // 65536 mod 188 = 112: os blocos não acabam em fronteiras de pacote
const _reserva = 256 * 1024;
final _origem = Uri.parse('http://exemplo.invalid/live/u/p/1.ts');

/// A origem começa a meio de um pacote: o primeiro pacote inteiro está em 88.
const _base = 88;

/// O byte na posição absoluta `p` do MPEG-TS falso: 0x47 no começo de cada pacote e, no resto, um
/// valor que depende da posição (sem 0x47 e sem período curto), para se saber de onde veio cada byte.
int _byte(int p) {
  if ((p - _base) % 188 == 0) return 0x47;
  final v = (p * 2654435761 >> 7) & 0xff;
  return v == 0x47 ? 0x48 : v;
}

List<int> _bytes(int desde, int n) => List<int>.generate(n, (i) => _byte(desde + i));

/// A primeira fronteira de pacote em `p` ou depois (a ligação única destes testes).
int _alinhado(int p) => p <= _base ? _base : _base + (p - _base + 187) ~/ 188 * 188;

/// Uma resposta a ser lida pelo HttpClient: junta os bytes e deixa esperar por um total ou pelo fim.
class _Leitura {
  _Leitura(this.resposta) {
    resposta.listen((d) {
      bytes.addAll(d);
      _verificar();
    }, onError: (Object _) => _acabar(), onDone: _acabar);
  }

  final HttpClientResponse resposta;
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
}

/// Um pedido numa ligação crua (como um motor que pode parar de ler ou cortar a ligação): separa o
/// cabeçalho do corpo e deixa esperar por uma condição sobre o corpo.
class _Cru {
  _Cru._(this.socket);

  static Future<_Cru> pedir(Uri u, {Map<String, String> cabecalhos = const {}, bool lerJa = true}) async {
    final s = await Socket.connect(u.host, u.port);
    final c = _Cru._(s);
    c._sub = s.listen(c._chegou, onError: (Object _) => c._acabar(), onDone: c._acabar);
    if (!lerJa) c._sub.pause();
    final extra = cabecalhos.entries.map((e) => '${e.key}: ${e.value}\r\n').join();
    s.write('GET ${u.path}?${u.query} HTTP/1.1\r\nHost: ${u.host}:${u.port}\r\n$extra\r\n');
    return c;
  }

  final Socket socket;
  late final StreamSubscription<List<int>> _sub;
  final _bruto = <int>[];
  String? cabecalho;
  final corpo = <int>[];
  final _acabou = Completer<void>();
  final _esperas = <(bool Function(), Completer<void>)>[];

  Future<void> get acabou => _acabou.future;

  void retomar() => _sub.resume();

  void pausar() => _sub.pause();

  Future<void> quando(bool Function() cond) {
    final c = Completer<void>();
    _esperas.add((cond, c));
    _verificar();
    return c.future;
  }

  void _chegou(List<int> d) {
    if (cabecalho == null) {
      _bruto.addAll(d);
      final s = String.fromCharCodes(_bruto);
      final i = s.indexOf('\r\n\r\n');
      if (i >= 0) {
        cabecalho = s.substring(0, i);
        corpo.addAll(_bruto.sublist(i + 4));
      }
    } else {
      corpo.addAll(d);
    }
    _verificar();
  }

  void _verificar() {
    _esperas.removeWhere((e) {
      if (!e.$1()) return false;
      e.$2.complete();
      return true;
    });
  }

  void _acabar() {
    if (!_acabou.isCompleted) _acabou.complete();
    for (final e in _esperas) {
      e.$2.completeError(StateError('a ligação acabou com ${corpo.length} bytes'));
    }
    _esperas.clear();
  }
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

  Future<HttpClientResponse> pedir(Uri u, {String? range}) async {
    final p = await cliente.getUrl(u);
    if (range != null) p.headers.set(HttpHeaders.rangeHeader, range);
    return p.close();
  }

  test('GET com desde envia os bytes certos (num pacote inteiro) e continua a enviar os que chegam',
      () async {
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
    expect(r.headers.chunkedTransferEncoding, isFalse);
    expect(r.headers.value(HttpHeaders.connectionHeader), 'close');
    expect(r.headers.value(HttpHeaders.contentRangeHeader), isNull);
    final ini = _alinhado(1000);
    expect(g.alinhar(1000), ini);
    final l = _Leitura(r);
    await l.ate(100000 - ini);
    expect(l.bytes, _bytes(ini, 100000 - ini));
    expect(l.bytes.first, 0x47);
    // continua: o que chega à origem chega ao cliente, em vários pedaços
    await enviar(g, origem, 300000);
    await l.ate(400000 - ini);
    await enviar(g, origem, 5000);
    await l.ate(405000 - ini);
    expect(l.bytes, _bytes(ini, 405000 - ini));
    await s.fechar();
    await l.acabou;
    await g.parar();
  });

  test('o cabeçalho sai logo, mesmo sem nada para enviar (desde = fim, ou nada gravado)', () async {
    final (:g, :origem) = gravador();
    await g.iniciar();
    final s = await ServidorDireto.iniciar(g);
    final vazio = await pedir(s.urlDesde(0)); // nada gravado ainda
    expect(vazio.statusCode, 200);
    await enviar(g, origem, 1000);
    final r = await pedir(s.urlDesde(g.fim)); // o fim (1000) está a meio de um pacote
    expect(r.statusCode, 200);
    final l = _Leitura(r), lv = _Leitura(vazio);
    await enviar(g, origem, 10000);
    // espera pelo pacote seguinte e começa nele
    final ini = _alinhado(1000);
    await l.ate(11000 - ini);
    expect(l.bytes, _bytes(ini, 11000 - ini));
    await lv.ate(1000);
    expect(lv.bytes.sublist(0, 1000), _bytes(_base, 1000));
    await s.fechar();
    await g.parar();
  });

  test('desde para além do fim começa no fim (alinhado)', () async {
    final (:g, :origem) = gravador();
    await g.iniciar();
    await enviar(g, origem, 1000);
    final s = await ServidorDireto.iniciar(g);
    final l = _Leitura(await pedir(s.urlDesde(10000000)));
    await enviar(g, origem, 1000);
    final ini = _alinhado(1000);
    await l.ate(2000 - ini);
    expect(l.bytes, _bytes(ini, 2000 - ini));
    await s.fechar();
    await g.parar();
  });

  test('HEAD dá só o cabeçalho; outro método → 405; desde em falta ou inválido → 400', () async {
    final (:g, :origem) = gravador();
    await g.iniciar();
    await enviar(g, origem, 1000);
    final s = await ServidorDireto.iniciar(g);
    final u = s.urlDesde(0);
    final head = await (await cliente.headUrl(u)).close();
    expect(head.statusCode, 200);
    expect(head.headers.contentType?.mimeType, 'video/mp2t');
    expect(await head.fold<int>(0, (n, d) => n + d.length), 0);
    final post = await (await cliente.postUrl(u)).close();
    expect(post.statusCode, 405);
    await post.drain<void>();
    for (final q in [<String, String>{}, {'desde': 'x'}, {'desde': '-1'}]) {
      final r = await pedir(u.replace(queryParameters: q));
      expect(r.statusCode, 400, reason: '$q');
      await r.drain<void>();
    }
    await s.fechar();
    await g.parar();
  });

  test('Range: bytes=N- → 206 a partir de desde + N alinhado; bytes=0- e sem Range → 200', () async {
    final (:g, :origem) = gravador(reserva: 1 << 20);
    await g.iniciar();
    await enviar(g, origem, 100000);
    final s = await ServidorDireto.iniciar(g);
    final desde = _alinhado(1000);
    final u = s.urlDesde(desde);

    final parcial = await pedir(u, range: 'bytes=5000-');
    expect(parcial.statusCode, 206);
    final ini = _alinhado(desde + 5000);
    expect(parcial.headers.value(HttpHeaders.contentRangeHeader), 'bytes ${ini - desde}-*/*');
    expect(parcial.headers.contentType?.mimeType, 'video/mp2t');
    expect(parcial.headers.contentLength, -1);
    final lp = _Leitura(parcial);
    await lp.ate(100000 - ini);
    expect(lp.bytes, _bytes(ini, 100000 - ini));

    // a forma bytes=N-M também conta como N- (o direto não tem fim)
    final fechado = await pedir(u, range: 'bytes=376-999');
    expect(fechado.statusCode, 206);
    expect(fechado.headers.value(HttpHeaders.contentRangeHeader), 'bytes 376-*/*');
    final lf = _Leitura(fechado);
    await lf.ate(10);
    expect(lf.bytes.sublist(0, 10), _bytes(desde + 376, 10));

    for (final range in ['bytes=0-', null, 'bytes=-500', 'linhas=3-']) {
      final r = await pedir(u, range: range);
      expect(r.statusCode, 200, reason: range);
      expect(r.headers.value(HttpHeaders.contentRangeHeader), isNull, reason: range);
      final l = _Leitura(r);
      await l.ate(10);
      expect(l.bytes.sublist(0, 10), _bytes(desde, 10), reason: range);
    }
    await s.fechar();
    await g.parar();
  });

  test('vários pedidos ao mesmo tempo são servidos cada um por si; o cliente que fecha sai logo',
      () async {
    final (:g, :origem) = gravador(reserva: 4 << 20);
    await g.iniciar();
    await enviar(g, origem, 50000);
    final s = await ServidorDireto.iniciar(g);
    final a = _Leitura(await pedir(s.urlDesde(0)));
    // o segundo é uma ligação crua, para a poder cortar como um motor que fecha
    final b = await _Cru.pedir(s.urlDesde(30000));
    final ib = _alinhado(30000);
    await a.ate(50000 - _base);
    await b.quando(() => b.corpo.length >= 50000 - ib);
    expect(b.cabecalho, startsWith('HTTP/1.1 200 OK\r\n'));
    expect(b.cabecalho!.toLowerCase(), isNot(contains('transfer-encoding')));
    expect(b.cabecalho!.toLowerCase(), isNot(contains('content-length')));
    expect(b.corpo, _bytes(ib, 50000 - ib));
    final abertos = <int>[];
    final umSo = s.pedidosAbertos.firstWhere((n) => n == 1);
    s.pedidosAbertos.listen(abertos.add);
    // o cliente fecha em repouso (o gravador não recebe nada): o ciclo dele termina logo
    b.socket.destroy();
    await umSo;
    await enviar(g, origem, 10000);
    await a.ate(60000 - _base);
    expect(a.bytes, _bytes(_base, 60000 - _base));
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

  test('leitor atrasado: o bloco pedido já foi apagado, continua do início (alinhado)', () async {
    final (:g, :origem) = gravador();
    await g.iniciar();
    for (var k = 0; k < 10; k++) {
      await enviar(g, origem, _bloco);
    }
    expect(g.inicio, greaterThan(0));
    expect(g.inicio % 188, isNot(_base)); // o início do bloco não é uma fronteira de pacote
    final s = await ServidorDireto.iniciar(g);
    final ini = _alinhado(g.inicio);
    expect(g.alinhar(g.inicio), ini);
    final l = _Leitura(await pedir(s.urlDesde(1000)));
    final total = g.fim - ini;
    await l.ate(total);
    expect(l.bytes, _bytes(ini, total));
    expect(l.bytes.first, 0x47);
    await s.fechar();
    await g.parar();
  });

  test('leitor a meio que pára, perde o bloco e retoma: salta para o início alinhado, sem atrasar o '
      'gravador', () async {
    final (:g, :origem) = gravador();
    await g.iniciar();
    await enviar(g, origem, 1000);
    final s = await ServidorDireto.iniciar(g);
    final c = await _Cru.pedir(s.urlDesde(0));
    await c.quando(() => c.corpo.length >= 1000 - _base);
    // o motor pára de ler (pausa): o gravador continua muito para além da reserva e dos buffers
    c.pausar();
    const muito = 24 << 20;
    while (g.fim < muito) {
      await enviar(g, origem, 64 * 1024);
    }
    expect(g.fim, greaterThanOrEqualTo(muito)); // o gravador nunca esperou pelo leitor
    final j = _alinhado(g.inicio);
    expect(g.alinhar(g.inicio), j);
    final fim = g.fim;
    c.retomar();
    final cauda = _bytes(fim - 188, 188);
    bool acabaNoFim() {
      final n = c.corpo.length;
      if (n < 188) return false;
      for (var i = 0; i < 188; i++) {
        if (c.corpo[n - 188 + i] != cauda[i]) return false;
      }
      return true;
    }

    await c.quando(acabaNoFim);
    // o corpo é _bytes(_base, k) seguido de _bytes(j, fim - j)
    final recebido = c.corpo;
    var k = 0;
    while (k < recebido.length && recebido[k] == _byte(_base + k)) {
      k++;
    }
    expect(k, greaterThan(1000 - _base));
    expect(_base + k, lessThan(j));
    expect(recebido.length - k, fim - j);
    expect(recebido.sublist(k), _bytes(j, fim - j));
    expect(recebido[k], 0x47);
    // e continua com o que chega
    await enviar(g, origem, 5000);
    await c.quando(() => c.corpo.length >= k + g.fim - j);
    expect(c.corpo.sublist(k), _bytes(j, g.fim - j));
    await s.fechar();
    await c.acabou;
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
    expect(s.urlDireto.queryParameters['desde'], '$_base'); // janela menor do que 2 s: o início
    for (var k = 0; k < 6; k++) {
      relogio = relogio.add(const Duration(seconds: 1));
      await enviar(g, c, 10000);
    }
    final desde = int.parse(s.urlDireto.queryParameters['desde']!);
    expect(desde, g.posicaoHa(ServidorDireto.atrasoDireto));
    expect(desde, greaterThan(_base));
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
    await a.ate(1000 - _base);
    await b.ate(1000 - _alinhado(500));
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
    final aberto = s.pedidosAbertos.firstWhere((n) => n == 1);
    final parado = await _Cru.pedir(s.urlDesde(0), lerJa: false); // nunca lê
    await aberto;
    // muito mais do que cabe nos buffers da ligação: o gravador nunca espera pelo leitor
    for (var k = 0; k < 64; k++) {
      await enviar(g, origem, 64 * 1024);
    }
    expect(g.fim, 1000 + 64 * 64 * 1024);
    final fechados = s.pedidosAbertos.firstWhere((n) => n == 0);
    await s.fechar();
    await fechados;
    parado.socket.destroy();
    await g.parar();
  });

  test('o gravador parar termina as respostas abertas', () async {
    final (:g, :origem) = gravador();
    await g.iniciar();
    await enviar(g, origem, 1000);
    final s = await ServidorDireto.iniciar(g);
    final a = _Leitura(await pedir(s.urlDesde(0)));
    await a.ate(1000 - _base);
    final nenhum = s.pedidosAbertos.firstWhere((n) => n == 0);
    await g.parar();
    await a.acabou;
    await nenhum;
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
