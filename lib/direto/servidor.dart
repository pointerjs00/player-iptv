/// Servir o direto gravado pelo [GravadorDireto] ao motor do player, em `127.0.0.1`.
///
/// `GET /<código>/direto?desde=<posição>` envia os bytes gravados a partir dessa posição e continua a
/// enviar o que vai chegando (stream sem fim, `video/mp2t`, sem `Content-Length` nem chunked, até a
/// ligação fechar). O código é aleatório (128 bits) e só é conhecido pelo player: as outras apps do
/// aparelho não conseguem ler. Se a posição pedida já foi apagada, continua no bloco mais antigo
/// ([GravadorDireto.inicio]). Começa-se sempre numa fronteira de pacote TS ([GravadorDireto.alinhar]).
///
/// `Range: bytes=N-` (o motor a tentar de novo no mesmo URL) responde 206 a partir de `desde + N`
/// alinhado, com `Content-Range: bytes <início>-*/*` (tamanho desconhecido).
///
/// Cada pedido tem o seu ciclo de leitura: lê um pedaço, envia-o e só lê o seguinte quando o cliente
/// o recebeu, por isso um leitor lento atrasa-se a ele próprio e nunca ao gravador.
///
/// O código nunca é registado nem vai nas respostas de erro.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import 'gravador.dart';

class ServidorDireto {
  ServidorDireto._(this._gravador, this._http, this._codigo)
      : endereco = _http.address,
        _porta = _http.port;

  /// Quanto atrás do fim começa o [urlDireto]: dá ao motor algum avanço sem se notar.
  static const atrasoDireto = Duration(seconds: 2);

  /// O tamanho de cada leitura do gravador (e de cada envio ao cliente).
  static const pedaco = 256 * 1024;

  final GravadorDireto _gravador;
  final HttpServer _http;
  final String _codigo;

  /// O endereço em que o servidor escuta (sempre loopback); fica conhecido depois de [fechar].
  final InternetAddress endereco;
  final int _porta;

  /// Os pedidos em curso, para os acordar e esperar por eles no [fechar].
  final _pedidos = <_Pedido>{};
  final _abertos = StreamController<int>.broadcast();
  bool _fechado = false;
  Future<void>? _fecho;

  /// Começa a servir o gravado de `g` numa porta livre de `127.0.0.1`.
  static Future<ServidorDireto> iniciar(GravadorDireto g) async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http
      ..serverHeader = null
      ..autoCompress = false;
    final s = ServidorDireto._(g, http, _codigoAleatorio());
    http.listen(s._atender, onError: (Object _) {});
    return s;
  }

  static String _codigoAleatorio() {
    final r = math.Random.secure();
    return List<String>.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// O URL que o motor abre para ver a partir de `posicao` (bytes desde o início da sessão).
  Uri urlDesde(int posicao) => Uri(
      scheme: 'http',
      host: endereco.address,
      port: _porta,
      pathSegments: [_codigo, 'direto'],
      queryParameters: {'desde': '$posicao'});

  /// O URL do direto: [atrasoDireto] antes do fim, ou o início se a janela ainda for menor.
  Uri get urlDireto => urlDesde(_gravador.posicaoHa(atrasoDireto));

  /// Quantos pedidos estão a ser servidos, a cada mudança.
  @visibleForTesting
  Stream<int> get pedidosAbertos => _abertos.stream;

  /// Deixa de aceitar pedidos e termina as respostas abertas.
  Future<void> fechar() => _fecho ??= _fechar();

  Future<void> _fechar() async {
    _fechado = true;
    // as ligações dos pedidos já não são do HttpServer: destroem-se aqui (também solta um envio
    // preso num cliente que não lê)
    for (final p in _pedidos) {
      p.acordar();
      p.socket?.destroy();
    }
    try {
      await _http.close(force: true);
    } catch (_) {}
    await Future.wait([for (final p in _pedidos.toList()) p.feito]);
    await _abertos.close();
  }

  bool _codigoCerto(String c) {
    if (c.length != _codigo.length) return false;
    var dif = 0;
    for (var i = 0; i < c.length; i++) {
      dif |= c.codeUnitAt(i) ^ _codigo.codeUnitAt(i);
    }
    return dif == 0;
  }

  Future<void> _atender(HttpRequest pedido) async {
    final resposta = pedido.response;
    try {
      final seg = pedido.uri.pathSegments;
      if (_fechado || seg.length != 2 || seg[1] != 'direto' || !_codigoCerto(seg[0])) {
        await _recusar(resposta, HttpStatus.notFound);
        return;
      }
      if (pedido.method != 'GET' && pedido.method != 'HEAD') {
        resposta.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        await _recusar(resposta, HttpStatus.methodNotAllowed);
        return;
      }
      final desde = int.tryParse(pedido.uri.queryParameters['desde'] ?? '');
      if (desde == null || desde < 0) {
        await _recusar(resposta, HttpStatus.badRequest);
        return;
      }
      if (pedido.method == 'HEAD') {
        resposta
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('video', 'mp2t')
          ..headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        await resposta.close();
        return;
      }
      await _servir(resposta, desde, _inicioRange(pedido.headers.value(HttpHeaders.rangeHeader)));
    } catch (e) {
      _registar(e);
      try {
        await resposta.close();
      } catch (_) {}
    }
  }

  /// O `N` de um `Range: bytes=N-` (o fim de `bytes=N-M` ignora-se: o direto não tem fim); null sem
  /// `Range`, com `bytes=0-` (é o pedido todo) ou com outra forma (ignorada, como a RFC permite).
  static int? _inicioRange(String? range) {
    if (range == null) return null;
    final m = RegExp(r'^\s*bytes\s*=\s*(\d+)\s*-\s*\d*\s*$').firstMatch(range);
    final n = m == null ? null : int.tryParse(m.group(1)!);
    return n == null || n == 0 ? null : n;
  }

  /// Um erro que não é só o cliente a ir-se (um problema a ler o disco, por exemplo): o player vê o
  /// fim da resposta, por isso fica o rasto, sem URL nem código.
  static void _registar(Object e) {
    if (e is SocketException || e is HttpException) return;
    final codigo = e is FileSystemException ? ' (código ${e.osError?.errorCode ?? '?'})' : '';
    debugPrint('servidor do direto: a resposta parou com ${e.runtimeType}$codigo');
  }

  Future<void> _recusar(HttpResponse r, int estado) async {
    r
      ..statusCode = estado
      ..headers.contentType = ContentType.text;
    await r.close();
  }

  /// O ciclo de um pedido: escreve o cabeçalho, depois lê, envia, espera pelo cliente; no fim do
  /// gravado espera por crescimento.
  ///
  /// A ligação é tirada ao [HttpServer] (`detachSocket`): o corpo vai sem chunked e acaba quando a
  /// ligação fecha (`Connection: close`), os erros de escrita chegam (o HttpServer engole-os) e o
  /// fecho do cliente vê-se logo, mesmo à espera de crescimento.
  Future<void> _servir(HttpResponse resposta, int desde, int? range) async {
    final p = _Pedido();
    _pedidos.add(p);
    _mudou();
    StreamSubscription<int>? crescer;
    try {
      // uma posição para além do gravado ficaria à espera para sempre: começa no fim; e começa
      // sempre numa fronteira de pacote TS
      var pos = math.min(desde + (range ?? 0), _gravador.fim);
      var porAlinhar = true;
      final alinhado = _gravador.alinhar(pos);
      if (alinhado < _gravador.fim) pos = alinhado;
      final sock = await resposta.detachSocket(writeHeaders: false);
      p.socket = sock;
      if (_fechado) return;
      sock.listen((_) {}, onDone: p.clienteFoi, onError: (Object _) => p.clienteFoi(), cancelOnError: true);
      crescer = _gravador.crescimento.listen((_) => p.acordar(), onDone: () {
        p.gravadorParou = true;
        p.acordar();
      });
      final cab = StringBuffer(range == null ? 'HTTP/1.1 200 OK\r\n' : 'HTTP/1.1 206 Partial Content\r\n')
        ..write('Content-Type: video/mp2t\r\n')
        ..write('Cache-Control: no-store\r\n')
        ..write('Connection: close\r\n');
      // tamanho desconhecido: o ExoPlayer ignora esta forma (fica sem comprimento) e o ffmpeg lê o
      // início e marca o tamanho como desconhecido
      if (range != null) cab.write('Content-Range: bytes ${math.max(0, pos - desde)}-*/*\r\n');
      cab.write('\r\n');
      sock.add(cab.toString().codeUnits);
      await sock.flush(); // o cabeçalho sai já, mesmo sem nada para enviar
      while (!_fechado && !p.foi) {
        p.cresceu = false;
        if (porAlinhar) {
          // a fronteira seguinte pode ainda não ter chegado (o alinhar não passa do fim): espera
          final a = _gravador.alinhar(pos);
          if (a >= _gravador.fim) {
            if (p.gravadorParou) break;
            if (!p.cresceu) await p.esperar();
            continue;
          }
          pos = a;
          porAlinhar = false;
        }
        final dados = await _gravador.ler(pos, pedaco);
        if (_fechado || p.foi) break;
        if (dados == null) {
          // o leitor atrasou-se e o bloco foi apagado: continua no mais antigo, num pacote inteiro
          final inicio = _gravador.inicio;
          if (inicio <= pos) break; // o gravador parou e apagou tudo
          pos = inicio;
          porAlinhar = true;
          continue;
        }
        if (dados.isEmpty) {
          if (p.gravadorParou) break;
          if (!p.cresceu) await p.esperar();
          continue;
        }
        sock.add(dados);
        await sock.flush(); // só continua quando o cliente recebeu: um leitor lento fica para trás
        pos += dados.length;
      }
    } catch (e) {
      _registar(e);
    } finally {
      await crescer?.cancel();
      p.socket?.destroy();
      _pedidos.remove(p);
      p.terminar();
      _mudou();
    }
  }

  void _mudou() {
    if (!_abertos.isClosed) _abertos.add(_pedidos.length);
  }
}

/// O estado do ciclo de um pedido.
class _Pedido {
  /// Houve crescimento (ou outra razão para olhar de novo) desde a última leitura.
  bool cresceu = false;
  bool gravadorParou = false;

  /// O cliente fechou a ligação.
  bool foi = false;

  /// A ligação, depois de tirada ao HttpServer: o [ServidorDireto.fechar] destrói-a.
  Socket? socket;
  Completer<void>? _espera;
  final _feito = Completer<void>();

  Future<void> get feito => _feito.future;

  Future<void> esperar() => (_espera ??= Completer<void>()).future;

  void clienteFoi() {
    foi = true;
    acordar();
  }

  void acordar() {
    cresceu = true;
    final e = _espera;
    _espera = null;
    if (e != null && !e.isCompleted) e.complete();
  }

  void terminar() {
    if (!_feito.isCompleted) _feito.complete();
  }
}
