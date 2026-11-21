/// Parser de listas M3U/M3U8 (#EXTINF com group-title, tvg-logo, user-agent, referer).
library;

import 'dart:isolate';

import '../modelo/canal.dart';

const semGrupo = 'Sem grupo';

final _reAtributo = RegExp(r'([\w-]+)="([^"]*)"');

ConteudoLista lerM3u(String texto) {
  final canais = <Canal>[];
  final grupos = <String>[];
  final vistos = <String>{};
  String? extinf;
  String? grupoExtgrp;
  var opcoes = <String>[];
  for (var linha in texto.split('\n')) {
    linha = linha.trim();
    if (linha.isEmpty) continue;
    final maius = linha.toUpperCase();
    if (maius.startsWith('#EXTM3U')) continue;
    if (maius.startsWith('#EXTINF')) {
      extinf = linha;
      opcoes = [];
      grupoExtgrp = null;
    } else if (maius.startsWith('#EXTGRP:')) {
      grupoExtgrp = linha.substring(8).trim();
    } else if (linha.startsWith('#')) {
      if (extinf != null) opcoes.add(linha);
    } else if (extinf != null) {
      final attrs = {for (final m in _reAtributo.allMatches(extinf)) m[1]!.toLowerCase(): m[2]!};
      // o nome é o texto depois da última vírgula que esteja fora de aspas
      final nome = _nomeDoExtinf(extinf);
      var grupo = (attrs['group-title'] ?? grupoExtgrp ?? '').trim();
      if (grupo.isEmpty) grupo = semGrupo;
      String? ua = attrs['http-user-agent'];
      String? referer = attrs['http-referrer'] ?? attrs['http-referer'];
      for (final o in opcoes) {
        final l = o.toLowerCase();
        if (l.startsWith('#extvlcopt:http-user-agent=')) {
          ua = o.substring(o.indexOf('=') + 1);
        } else if (l.startsWith('#extvlcopt:http-referrer=') || l.startsWith('#extvlcopt:http-referer=')) {
          referer = o.substring(o.indexOf('=') + 1);
        }
      }
      if (vistos.add(grupo)) grupos.add(grupo);
      canais.add(Canal(
        id: linha, nome: nome.isEmpty ? (attrs['tvg-name'] ?? linha) : nome, grupo: grupo,
        url: linha, logo: attrs['tvg-logo'] ?? '', userAgent: ua, referer: referer,
        numero: numeroCanal(attrs['tvg-chno']),
      ));
      extinf = null;
      opcoes = [];
    }
  }
  return ConteudoLista(grupos, canais);
}

String _nomeDoExtinf(String extinf) {
  var dentro = false;
  var ultima = -1;
  for (var i = 0; i < extinf.length; i++) {
    final ch = extinf[i];
    if (ch == '"') dentro = !dentro;
    if (ch == ',' && !dentro) ultima = i;
  }
  return ultima >= 0 ? extinf.substring(ultima + 1).trim() : '';
}

/// Como [lerM3u], mas fora da thread da interface quando a lista é grande.
Future<ConteudoLista> lerM3uAsync(String texto) async {
  if (texto.length < 200000) return lerM3u(texto);
  return Isolate.run(() => lerM3u(texto));
}

bool pareceM3u(String texto) {
  final t = texto.trimLeft();
  return t.toUpperCase().startsWith('#EXTM3U') || t.toUpperCase().contains('#EXTINF');
}
