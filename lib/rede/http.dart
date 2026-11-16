/// Pedidos HTTP com tempo limite, limite de tamanho e cancelamento.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ErroHttp implements Exception {
  ErroHttp(this.status, [this.url = '']);
  final int status;
  final String url;
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

  void Function() _ouvir(void Function() f) {
    _ouvintes.add(f);
    return () => _ouvintes.remove(f);
  }
}

const uaVlc = 'VLC/3.0.20 LibVLC/3.0.20';

/// GET que devolve o corpo em bytes (no máximo `maxBytes`). Lança [ErroHttp] para status
/// >= 400, [TimeoutException], [SocketException] ou [Cancelado].
Future<List<int>> obterBytes(String url, {Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15), int maxBytes = 64 * 1024 * 1024,
    Cancelamento? cancelamento}) async {
  cancelamento?.verificar();
  final uri = Uri.parse(url);
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
      await resp.drain<void>().catchError((_) {});
      throw ErroHttp(resp.statusCode, url);
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

/// Mensagem legível para um erro de rede.
String descreverErro(Object e) {
  if (e is ErroHttp) {
    return switch (e.status) {
      401 || 403 => 'acesso recusado (${e.status})',
      404 => 'não encontrado (404)',
      456 => 'o painel recusa a ligação (456) — MAC em uso noutro aparelho?',
      _ => 'erro do servidor (${e.status})',
    };
  }
  if (e is TimeoutException) return 'o servidor não respondeu a tempo';
  if (e is SocketException) return 'não foi possível ligar ao servidor';
  if (e is Cancelado) return 'cancelado';
  return '$e';
}
