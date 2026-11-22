/// Pedidos HTTP com tempo limite, limite de tamanho e cancelamento.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import '../idioma/idioma.dart';

class ErroHttp implements Exception {
  ErroHttp(this.status, [this.url = '', this.retryAfter]);
  final int status;
  final String url;
  final String? retryAfter;
  @override
  String toString() => 'o servidor respondeu $status';
}

/// A resposta passou do tamanho máximo: não se devolve um corpo cortado como se estivesse
/// completo (uma lista de canais cortada faria um canal "não existir").
class ErroTamanho implements Exception {
  ErroTamanho(this.maxBytes);
  final int maxBytes;
  @override
  String toString() => 'resposta grande demais';
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
Future<Uint8List> obterBytes(String url, {Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15), int maxBytes = 64 * 1024 * 1024,
    Cancelamento? cancelamento}) async {
  cancelamento?.verificar();
  final uri = Uri.parse(url);
  return comRitmo(uri, cancelamento, () => _obterBytes(uri, url, headers, timeout, maxBytes, cancelamento));
}

/// Um cliente partilhado: as ligações ficam abertas uns segundos e são reutilizadas
/// (keep-alive), em vez de uma ligação TCP/TLS nova por pedido. O tempo de espera fica abaixo
/// dos 5 s de keep-alive comuns nos servidores, para não se reutilizar uma ligação já fechada.
final _cliente = HttpClient()
  ..autoUncompress = true
  ..userAgent = null
  ..connectionTimeout = const Duration(seconds: 30)
  ..idleTimeout = const Duration(seconds: 4);

/// O prazo total de um pedido: `timeout` é só o tempo máximo sem receber nada.
const _prazoPorTimeout = 8;

Future<Uint8List> _obterBytes(Uri uri, String url, Map<String, String> headers, Duration timeout, int maxBytes,
    Cancelamento? cancelamento) async {
  if (uri.scheme == 'file') {
    final f = File.fromUri(uri);
    if (await f.length() > maxBytes) throw ErroTamanho(maxBytes);
    return f.readAsBytes();
  }
  HttpClientRequest? pedido;
  StreamSubscription<List<int>>? leitura;
  Object? motivo; // porque é que o pedido foi abortado (cancelamento ou prazo total)
  final abortado = Completer<HttpClientRequest>();
  void abortar(Object e) {
    if (motivo != null) return;
    motivo = e;
    pedido?.abort(e);
    abortado.completeError(e);
  }

  final parar = cancelamento?._ouvir(() => abortar(Cancelado()));
  final prazo = Timer(timeout * _prazoPorTimeout,
      () => abortar(TimeoutException('o servidor não acabou de responder a tempo', timeout * _prazoPorTimeout)));
  try {
    final aLigar = _cliente.getUrl(uri);
    try {
      pedido = await Future.any([aLigar, abortado.future]).timeout(timeout);
    } catch (_) {
      // a ligação pode ainda acabar de se fazer: não fica presa no cliente
      unawaited(aLigar.then((p) => p.abort(), onError: (_) {}));
      rethrow;
    }
    final p = pedido;
    p.followRedirects = true;
    p.maxRedirects = 5;
    headers.forEach((k, v) {
      // o HttpClient trata da compressão; um Accept-Encoding manual estraga o autoUncompress
      if (k.toLowerCase() != 'accept-encoding') p.headers.set(k, v, preserveHeaderCase: true);
    });
    if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      p.headers.set('User-Agent', uaVlc);
    }
    final resp = await p.close().timeout(timeout);
    if (resp.statusCode >= 400) {
      final retryAfter = resp.headers.value('retry-after');
      await resp.drain<void>().catchError((_) {});
      throw ErroHttp(resp.statusCode, url, retryAfter);
    }
    // BytesBuilder: 1 byte por byte (uma List<int> gasta 8)
    final corpo = BytesBuilder(copy: false);
    final lido = Completer<void>();
    leitura = resp.timeout(timeout).listen((bloco) {
      corpo.add(bloco);
      if (corpo.length > maxBytes && !lido.isCompleted) lido.completeError(ErroTamanho(maxBytes));
    }, onError: (Object e) {
      if (!lido.isCompleted) lido.completeError(e);
    }, onDone: () {
      if (!lido.isCompleted) lido.complete();
    }, cancelOnError: true);
    // o abort não fecha a resposta já recebida: espera-se pelo fim da leitura ou pelo abortar
    await Future.any([lido.future, abortado.future]);
    return corpo.takeBytes();
  } catch (e) {
    if (cancelamento?.cancelado ?? false) throw Cancelado();
    final m = motivo;
    if (m != null && e is! ErroHttp && e is! ErroTamanho) throw m;
    rethrow;
  } finally {
    prazo.cancel();
    parar?.call();
    // cancelar a leitura a meio fecha a ligação (não volta ao cliente partilhado)
    unawaited(leitura?.cancel());
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
  final b = await obterBytes(url, headers: headers, timeout: timeout, maxBytes: maxBytes,
      cancelamento: cancelamento);
  // uma lista de canais pode ter dezenas de MB: descodifica-se fora da thread da interface
  if (b.length < limiteIsolate) return _json(b);
  return Isolate.run(() => _json(b));
}

/// A partir deste tamanho (bytes), o JSON é tratado num isolate.
const limiteIsolate = 256 * 1024;

Object? _json(Uint8List b) {
  var t = utf8.decode(b, allowMalformed: true);
  if (t.startsWith('﻿')) t = t.substring(1);
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
      401 || 403 => tr('acesso recusado ({0})', [e.status]),
      404 => tr('não encontrado (404)'),
      456 => tr('o painel recusa a ligação (456) — MAC em uso noutro aparelho?'),
      _ => tr('erro do servidor ({0})', [e.status]),
    };
  }
  if (e is TimeoutException) return tr('o servidor não respondeu a tempo');
  if (e is ErroTamanho) return tr('a resposta do servidor é grande demais');
  if (e is TlsException) return tr('falha na ligação segura (certificado ou TLS)');
  if (e is SocketException) return tr('não foi possível ligar ao servidor');
  if (e is HttpException) return tr('a ligação foi cortada pelo servidor');
  if (e is FormatException) return tr('endereço ou resposta inválidos');
  if (e is FileSystemException) return tr('não foi possível ler o ficheiro');
  if (e is Cancelado) return 'cancelado';
  return tr('falha inesperada');
}
