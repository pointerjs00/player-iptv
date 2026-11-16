/// Pedidos HTTP com tempo limite, limite de tamanho e cancelamento.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ErroHttp implements Exception {
  ErroHttp(this.status, [this.url = '', this.retryAfter]);
  final int status;
  final String url;
  final String? retryAfter;
  @override
  String toString() => 'o servidor respondeu $status';
}

class Cancelado implements Exception {
  @override
  String toString() => 'cancelado';
}

/// Permite parar pedidos em curso (p.ex. ao sair do ecrã de uma lista).
class Cancelamento {
  bool _cancelado = false;
  final _ouvintes = <void Function()>[];
  bool get cancelado => _cancelado;

  void cancelar() {
    if (_cancelado) return;
    _cancelado = true;
    for (final f in List.of(_ouvintes)) {
      f();
    }
  }

  void verificar() {
    if (_cancelado) throw Cancelado();
  }

  /// Um cancelamento que é cancelado com este (e que se pode cancelar sozinho).
  Cancelamento filho() {
    final f = Cancelamento();
    if (_cancelado) {
      f.cancelar();
    } else {
      _ouvir(f.cancelar);
    }
    return f;
  }

  void Function() _ouvir(void Function() f) {
    _ouvintes.add(f);
    return () => _ouvintes.remove(f);
  }
}

const uaVlc = 'VLC/3.0.20 LibVLC/3.0.20';

/// Um pedido de cada vez por servidor, com um intervalo mínimo entre pedidos (porta de
/// `RitmoHost` em motor/rede.py). Só a verificação o usa: põe-no na zona com [ritmoZona].
class RitmoHost {
  RitmoHost({this.intervalo = const Duration(milliseconds: 350), this.tentativas429 = 2,
      this.espera429Max = const Duration(seconds: 60)});
  final Duration intervalo;
  final int tentativas429;
  final Duration espera429Max;

  final _vez = <String, Future<void>>{};
  final _ultimo = <String, DateTime>{};

  Future<T> vez<T>(String host, Future<T> Function() f) async {
    final anterior = _vez[host] ?? Future<void>.value();
    final minha = Completer<void>();
    _vez[host] = minha.future;
    // o relógio da conta pára enquanto espera a vez do servidor (I4 do Python)
    final relogio = Zone.current[relogioZona] as RelogioConta?;
    relogio?.pausar();
    try {
      await anterior;
      final ultimo = _ultimo[host];
      if (ultimo != null) {
        final falta = ultimo.add(intervalo).difference(DateTime.now());
        if (falta > Duration.zero) await Future<void>.delayed(falta);
      }
    } finally {
      relogio?.retomar();
    }
    try {
      return await f();
    } finally {
      _ultimo[host] = DateTime.now();
      if (identical(_vez[host], minha.future)) _vez.remove(host);
      minha.complete();
    }
  }
}

/// Chave da zona com o [RitmoHost] partilhado pelas verificações.
const ritmoZona = #ritmoHost;

/// Chave da zona com o [RelogioConta] da conta em verificação.
const relogioZona = #relogioConta;

/// Limite de tempo por conta que pára enquanto a conta espera a vez de um servidor.
class RelogioConta {
  RelogioConta(this.limite, this._aoEsgotar);
  final Duration limite;
  final void Function() _aoEsgotar;
  final _cronometro = Stopwatch();
  int _pausas = 0;
  Timer? _vigia;

  void iniciar() {
    _cronometro.start();
    _vigia = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (_cronometro.elapsed >= limite) {
        t.cancel();
        _aoEsgotar();
      }
    });
  }

  void pausar() {
    if (_pausas++ == 0) _cronometro.stop();
  }

  void retomar() {
    if (--_pausas == 0) _cronometro.start();
  }

  void parar() => _vigia?.cancel();
}

/// Espera `d`, mas sai com [Cancelado] logo que `cancelamento` for cancelado.
Future<void> esperarCancelavel(Duration d, Cancelamento? cancelamento) async {
  cancelamento?.verificar();
  if (cancelamento == null) return Future<void>.delayed(d);
  final acordar = Completer<void>();
  final parar = cancelamento._ouvir(() {
    if (!acordar.isCompleted) acordar.complete();
  });
  final t = Timer(d, () {
    if (!acordar.isCompleted) acordar.complete();
  });
  try {
    await acordar.future;
  } finally {
    t.cancel();
    parar();
  }
  cancelamento.verificar();
}

Duration _espera429(String? valor, int tentativa, Duration maximo) {
  final s = double.tryParse((valor ?? '').trim());
  final espera = s == null || s < 0
      ? Duration(seconds: 5 * (1 << tentativa))
      : Duration(milliseconds: (s * 1000).round());
  return espera > maximo ? maximo : espera;
}

/// Corre `f` (um pedido a `uri`) na vez do servidor, se a zona tiver um [RitmoHost]; um 429
/// é repetido (com o Retry-After) fora da vez, para não bloquear os outros pedidos.
Future<T> comRitmo<T>(Uri uri, Cancelamento? cancelamento, Future<T> Function() f) async {
  final ritmo = Zone.current[ritmoZona] as RitmoHost?;
  if (ritmo == null || uri.scheme == 'file') return f();
  final host = '${uri.host.toLowerCase()}:${uri.port}';
  for (var tentativa = 0;; tentativa++) {
    try {
      return await ritmo.vez(host, () {
        cancelamento?.verificar(); // cancelado enquanto esperava a vez
        return f();
      });
    } on ErroHttp catch (e) {
      if (e.status != 429 || tentativa >= ritmo.tentativas429) rethrow;
      await esperarCancelavel(_espera429(e.retryAfter, tentativa, ritmo.espera429Max), cancelamento);
    }
  }
}

/// GET que devolve o corpo em bytes (no máximo `maxBytes`). Lança [ErroHttp] para status
/// >= 400, [TimeoutException], [SocketException] ou [Cancelado].
Future<List<int>> obterBytes(String url, {Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15), int maxBytes = 64 * 1024 * 1024,
    Cancelamento? cancelamento}) async {
  cancelamento?.verificar();
  final uri = Uri.parse(url);
  return comRitmo(uri, cancelamento, () => _obterBytes(uri, url, headers, timeout, maxBytes, cancelamento));
}

Future<List<int>> _obterBytes(Uri uri, String url, Map<String, String> headers, Duration timeout, int maxBytes,
    Cancelamento? cancelamento) async {
  if (uri.scheme == 'file') {
    final f = File.fromUri(uri);
    if (await f.length() > maxBytes) throw ErroHttp(413, url);
    return f.readAsBytes();
  }
  final cliente = HttpClient()
    ..connectionTimeout = timeout
    ..autoUncompress = true
    ..userAgent = null;
  final parar = cancelamento?._ouvir(() => cliente.close(force: true));
  try {
    final pedido = await cliente.getUrl(uri).timeout(timeout);
    pedido.followRedirects = true;
    pedido.maxRedirects = 5;
    headers.forEach((k, v) {
      // o HttpClient trata da compressão; um Accept-Encoding manual estraga o autoUncompress
      if (k.toLowerCase() != 'accept-encoding') pedido.headers.set(k, v, preserveHeaderCase: true);
    });
    if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      pedido.headers.set('User-Agent', uaVlc);
    }
    final resp = await pedido.close().timeout(timeout);
    if (resp.statusCode >= 400) {
      final retryAfter = resp.headers.value('retry-after');
      await resp.drain<void>().catchError((_) {});
      throw ErroHttp(resp.statusCode, url, retryAfter);
    }
    final corpo = <int>[];
    await for (final bloco in resp.timeout(timeout)) {
      cancelamento?.verificar();
      corpo.addAll(bloco);
      if (corpo.length > maxBytes) break;
    }
    return corpo;
  } on HttpException {
    cancelamento?.verificar();
    rethrow;
  } on SocketException {
    cancelamento?.verificar();
    rethrow;
  } finally {
    parar?.call();
    cliente.close(force: true);
  }
}

Future<String> obterTexto(String url, {Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15), int maxBytes = 64 * 1024 * 1024,
    Cancelamento? cancelamento}) async {
  final b = await obterBytes(url, headers: headers, timeout: timeout, maxBytes: maxBytes,
      cancelamento: cancelamento);
  var t = utf8.decode(b, allowMalformed: true);
  if (t.startsWith('﻿')) t = t.substring(1);
  return t;
}

/// JSON (ou null se o corpo não for JSON).
Future<Object?> obterJson(String url, {Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15), int maxBytes = 96 * 1024 * 1024,
    Cancelamento? cancelamento}) async {
  final t = await obterTexto(url, headers: headers, timeout: timeout, maxBytes: maxBytes,
      cancelamento: cancelamento);
  try {
    return jsonDecode(t.trim());
  } on FormatException {
    return null;
  }
}

/// Um erro cuja mensagem já é para o utilizador (p.ex. `ErroLista`).
abstract interface class ErroLegivel {
  String get mensagem;
}

final _reLink = RegExp(r'\S+://\S+');
final _reMac = RegExp(r'(?:[0-9A-Fa-f]{2}(?::|-|%3A|%3a)){5}[0-9A-Fa-f]{2}');
final _reUri = RegExp(r',?\s*uri\s*=\s*');

/// Tira de um texto os links (nas contas Xtream levam o utilizador e a password) e os MACs.
String semSegredos(String t) => t
    .replaceAll(_reLink, '')
    .replaceAll(_reMac, '')
    .replaceAll(_reUri, ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Mensagem legível (em português, sem links nem MACs) para qualquer erro: é o que se mostra
/// e o que se guarda.
String descreverErro(Object e) {
  if (e is ErroLegivel) return semSegredos(e.mensagem);
  if (e is ErroHttp) {
    return switch (e.status) {
      401 || 403 => 'acesso recusado (${e.status})',
      404 => 'não encontrado (404)',
      456 => 'o painel recusa a ligação (456) — MAC em uso noutro aparelho?',
      _ => 'erro do servidor (${e.status})',
    };
  }
  if (e is TimeoutException) return 'o servidor não respondeu a tempo';
  if (e is TlsException) return 'falha na ligação segura (certificado ou TLS)';
  if (e is SocketException) return 'não foi possível ligar ao servidor';
  if (e is HttpException) return 'a ligação foi cortada pelo servidor';
  if (e is FormatException) return 'endereço ou resposta inválidos';
  if (e is FileSystemException) return 'não foi possível ler o ficheiro';
  if (e is Cancelado) return 'cancelado';
  return 'falha inesperada';
}
