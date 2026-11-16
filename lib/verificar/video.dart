/// Lê o início de um stream e diz se é vídeo (segue playlists HLS). Porta de `motor/video.py`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../rede/http.dart';
import 'estado.dart';

int? syncTs(List<int> b) {
  for (var i = 0; i < 188 && i < b.length; i++) {
    if (b[i] == 0x47 && i + 188 < b.length && b[i + 188] == 0x47) return i;
  }
  return null;
}

List<int> _inicio(List<int> b) {
  var i = 0;
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) i = 3;
  while (i < b.length && i < 4096 && const [32, 9, 13, 10].contains(b[i])) {
    i++;
  }
  return b.sublist(i, b.length < i + 16 ? b.length : i + 16);
}

bool eVideo(List<int> b) {
  if (b.length < 376) return false;
  final ini = _inicio(b);
  if (ini.isNotEmpty && (ini[0] == 0x3C || ini[0] == 0x7B)) return false; // < ou {
  if (syncTs(b) != null) return true;
  if (b.length >= 8) {
    final t = ascii.decode(b.sublist(4, 8), allowInvalid: true);
    return const {'ftyp', 'moof', 'styp'}.contains(t);
  }
  return false;
}

bool _ePlaylist(List<int> b) => ascii.decode(_inicio(b), allowInvalid: true).startsWith('#EXTM3U');

class _Leitura {
  _Leitura(this.corpo, this.urlFinal, this.cortado);
  final List<int> corpo;
  final Uri urlFinal;
  final Object? cortado; // o erro que cortou a leitura a meio (não é prova)
}

/// GET que lê no máximo `segundos` ou `maxBytes` (um stream não acaba).
Future<_Leitura> _ler(Uri url, Map<String, String> headers, Duration timeout, Cancelamento? can,
    {Duration segundos = const Duration(seconds: 3), int maxBytes = 1024 * 1024}) async {
  can?.verificar();
  final cliente = HttpClient()..connectionTimeout = timeout;
  try {
    final p = await cliente.getUrl(url).timeout(timeout);
    headers.forEach((k, v) {
      if (k.toLowerCase() != 'accept-encoding') p.headers.set(k, v, preserveHeaderCase: true);
    });
    final r = await p.close().timeout(timeout);
    if (r.statusCode >= 400) {
      final retryAfter = r.headers.value('retry-after');
      unawaited(r.drain<void>().catchError((_) {}));
      throw ErroHttp(r.statusCode, '$url', retryAfter);
    }
    final corpo = BytesBuilder(copy: false);
    final fim = DateTime.now().add(segundos);
    Object? cortado;
    try {
      await for (final bloco in r.timeout(timeout)) {
        can?.verificar();
        corpo.add(bloco);
        if (corpo.length >= maxBytes || DateTime.now().isAfter(fim)) break;
      }
    } on Cancelado {
      rethrow;
    } catch (e) {
      cortado = e;
    }
    final redir = r.redirects.isEmpty ? url : url.resolveUri(r.redirects.last.location);
    return _Leitura(corpo.takeBytes(), redir, cortado);
  } finally {
    cliente.close(force: true);
  }
}

/// Lê o stream e classifica. `stream401Inc`: num Xtream com a conta ativa, 401/403 no stream
/// costuma ser limite de ligações, não conta morta.
Future<ResultadoVerificacao> lerStream(String url, Map<String, String> headers,
    {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, bool stream401Inc = false}) async {
  var u = Uri.parse(url);
  _Leitura? r;
  try {
    var nivel = 0;
    for (; nivel <= 4; nivel++) {
      final alvo = u;
      final lido = await comRitmo(alvo, cancelamento, () => _ler(alvo, headers, timeout, cancelamento));
      r = lido;
      if (!_ePlaylist(lido.corpo)) break;
      if (lido.cortado != null) return classificarFalha(lido.cortado!);
      final linhas = utf8.decode(lido.corpo, allowMalformed: true).split('\n')
          .map((l) => l.trim().replaceAll('﻿', '')).where((l) => l.isNotEmpty && !l.startsWith('#'));
      if (linhas.isEmpty) return const ResultadoVerificacao(EstadoV.inconclusivo, 'playlist sem entradas');
      u = lido.urlFinal.resolve(linhas.first);
    }
    if (nivel > 4) return const ResultadoVerificacao(EstadoV.inconclusivo, 'playlist HLS com demasiados níveis');
  } on Cancelado {
    rethrow;
  } catch (e) {
    if (stream401Inc && e is ErroHttp && (e.status == 401 || e.status == 403)) {
      return ResultadoVerificacao(EstadoV.inconclusivo,
          'stream recusado apesar de conta ativa (${e.status}) — possível limite de ligações');
    }
    return classificarFalha(e);
  }
  final l = r!;
  if (l.corpo.length < 376) {
    return const ResultadoVerificacao(EstadoV.inconclusivo, 'resposta vazia ou curta demais');
  }
  if (!eVideo(l.corpo)) {
    if (l.cortado != null) return classificarFalha(l.cortado!);
    return const ResultadoVerificacao(EstadoV.naoFunciona, 'resposta não é vídeo');
  }
  return const ResultadoVerificacao(EstadoV.funciona, 'vídeo recebido');
}
