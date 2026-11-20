/// Servir o direto gravado pelo [GravadorDireto] ao motor do player, em `127.0.0.1`.
///
/// `GET /<código>/direto?desde=<posição>` envia os bytes gravados a partir dessa posição e continua a
/// enviar o que vai chegando (stream sem fim, `video/mp2t`, sem `Content-Length`). O código é
/// aleatório (128 bits) e só é conhecido pelo player: as outras apps do aparelho não conseguem ler.
/// Se a posição pedida já foi apagada, continua no bloco mais antigo ([GravadorDireto.inicio]).
///
/// Cada pedido tem o seu ciclo de leitura: lê um pedaço, envia-o e só lê o seguinte quando o cliente
/// o recebeu, por isso um leitor lento atrasa-se a ele próprio e nunca ao gravador.
///
/// O código nunca é registado nem vai nas respostas de erro.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;

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
    for (final p in _pedidos) {
      p.acordar();
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
      resposta
        ..statusCode = HttpStatus.ok
        ..bufferOutput = false
        ..headers.contentType = ContentType('video', 'mp2t')
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (pedido.method == 'HEAD') {
        await resposta.close();
        return;
      }
      await _servir(resposta, desde);
    } catch (_) {
      // o cliente foi-se ou o servidor fechou: não há a quem responder
      try {
        await resposta.close();
      } catch (_) {}
    }
  }

  Future<void> _recusar(HttpResponse r, int estado) async {
    r
      ..statusCode = estado
      ..headers.contentType = ContentType.text;
    await r.close();
  }

  /// O ciclo de um pedido: lê, envia, espera pelo cliente; no fim do gravado espera por crescimento.
  Future<void> _servir(HttpResponse resposta, int desde) async {
    final p = _Pedido();
    _pedidos.add(p);
    _mudou();
    final crescer = _gravador.crescimento.listen((_) => p.acordar(), onDone: () {
      p.gravadorParou = true;
      p.acordar();
    });
    var clienteFoi = false;
    unawaited(resposta.done.then((_) {}, onError: (Object _) {}).whenComplete(() {
      clienteFoi = true;
      p.acordar();
    }));
    try {
      // uma posição para além do gravado ficaria à espera para sempre: começa no fim
      var pos = math.min(desde, _gravador.fim);
      while (!_fechado && !clienteFoi) {
        p.cresceu = false;
        final dados = await _gravador.ler(pos, pedaco);
        if (_fechado || clienteFoi) break;
        if (dados == null) {
          // o leitor atrasou-se e o bloco foi apagado: continua no mais antigo
          final inicio = _gravador.inicio;
          if (inicio <= pos) break; // o gravador parou e apagou tudo
          pos = inicio;
          continue;
        }
        if (dados.isEmpty) {
          if (p.gravadorParou) break;
          if (!p.cresceu) await p.esperar();
          continue;
        }
        resposta.add(dados);
        await resposta.flush(); // só continua quando o cliente recebeu: um leitor lento fica para trás
        // o HttpServer engole o erro de escrita quando o cliente fecha (o flush acaba bem e o resto
        // é ignorado), mas destrói a ligação: sem ela, o ciclo termina
        if (resposta.connectionInfo == null) break;
        pos += dados.length;
      }
    } catch (_) {
      // o cliente fechou a ligação (ou o servidor a meio do envio)
    } finally {
      await crescer.cancel();
      try {
        await resposta.close();
      } catch (_) {}
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
  Completer<void>? _espera;
  final _feito = Completer<void>();

  Future<void> get feito => _feito.future;

  Future<void> esperar() => (_espera ??= Completer<void>()).future;

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
