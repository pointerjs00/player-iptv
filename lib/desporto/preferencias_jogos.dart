/// As preferências dos «Jogos» (`<dados>/desporto/preferencias.json`): as competições seguidas,
/// as equipas favoritas, a qualidade preferida, a última fonte que funcionou em cada canal e as
/// associações manuais de canais. Num ficheiro à parte das Preferências (não existe na edição de
/// partilha).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../dados/biblioteca.dart' show escreverAtomico;
import '../modelo/canal.dart';
import 'catalogo.dart';
import 'modelo.dart';

class UltimaFonte {
  const UltimaFonte(this.listaId, this.canalId, this.data);
  final String listaId, canalId;
  final DateTime data;
}

/// Uma associação manual: o canal da lista é `canalTv` (null = «não é este canal»).
class Associacao {
  const Associacao(this.canal, this.canalTv);
  final Canal canal;
  final String? canalTv;
}

class PreferenciasJogos extends ChangeNotifier {
  PreferenciasJogos._(this._ficheiro);
  final File _ficheiro;

  Set<String> _competicoes = {for (final c in catalogoCompeticoes) if (c.seguidaPorOmissao) c.id};
  List<String> _equipas = [];
  Qualidade _qualidade = Qualidade.fhd;
  /// Por omissão vêem-se todos os jogos (os que ainda não têm canal também).
  bool _mostrarSemCanal = true;
  final _ultimas = <String, UltimaFonte>{};

  /// listaId → canalId → associação.
  final _associacoes = <String, Map<String, Associacao>>{};

  static Future<PreferenciasJogos> abrir(Directory pasta) async {
    final p = PreferenciasJogos._(File('${pasta.path}${Platform.pathSeparator}preferencias.json'));
    try {
      p._ler(jsonDecode(await p._ficheiro.readAsString()));
    } catch (_) {/* sem ficheiro ou estragado: as omissões */}
    return p;
  }

  void _ler(Object? j) {
    if (j is! Map) return;
    final comp = j['competicoes'];
    if (comp is List) _competicoes = {for (final c in comp) if (c is String && competicaoPorId(c) != null) c};
    final eq = j['equipas'];
    if (eq is List) _equipas = [for (final e in eq) if (e is String && e.trim().isNotEmpty) e];
    final q = j['qualidade'];
    if (q is String) _qualidade = Qualidade.values.firstWhere((x) => x.name == q, orElse: () => _qualidade);
    if (j['mostrarSemCanal'] is bool) _mostrarSemCanal = j['mostrarSemCanal'] as bool;
    final u = j['ultimas'];
    if (u is Map) {
      for (final e in u.entries) {
        final v = e.value;
        final d = v is Map ? DateTime.tryParse('${v['data']}') : null;
        if (d != null) _ultimas['${e.key}'] = UltimaFonte('${v['lista']}', '${v['canal']}', d);
      }
    }
    final a = j['associacoes'];
    if (a is Map) {
      for (final l in a.entries) {
        if (l.value is! Map) continue;
        for (final c in (l.value as Map).entries) {
          final v = c.value;
          if (v is! Map || v['canal'] is! Map) continue;
          _associacoes.putIfAbsent('${l.key}', () => {})['${c.key}'] =
              Associacao(Canal.deJson(Map<String, dynamic>.from(v['canal'] as Map)), v['tv'] as String?);
        }
      }
    }
  }

  Map<String, Object?> _mapa() => {
        'competicoes': _competicoes.toList(),
        'equipas': _equipas,
        'qualidade': _qualidade.name,
        'mostrarSemCanal': _mostrarSemCanal,
        'ultimas': {
          for (final e in _ultimas.entries)
            e.key: {'lista': e.value.listaId, 'canal': e.value.canalId, 'data': e.value.data.toIso8601String()},
        },
        'associacoes': {
          for (final l in _associacoes.entries)
            l.key: {for (final c in l.value.entries) c.key: {'canal': c.value.canal.paraJson(), 'tv': c.value.canalTv}},
        },
      };

  Future<void> _fila = Future.value();

  Future<void> guardar() {
    final texto = jsonEncode(_mapa());
    return _fila = _fila.then((_) async {
      await _ficheiro.parent.create(recursive: true);
      await escreverAtomico(_ficheiro, texto);
    }).catchError((Object _) {});
  }

  void _mudou() {
    notifyListeners();
    unawaited(guardar());
  }

  Set<String> get competicoes => Set.unmodifiable(_competicoes);
  set competicoes(Set<String> v) {
    _competicoes = {...v};
    _mudou();
  }

  void alternarCompeticao(String id) {
    _competicoes.contains(id) ? _competicoes.remove(id) : _competicoes.add(id);
    _mudou();
  }

  List<String> get equipasFavoritas => List.unmodifiable(_equipas);
  set equipasFavoritas(List<String> v) {
    _equipas = [for (final e in v) if (e.trim().isNotEmpty) e.trim()];
    _mudou();
  }

  Qualidade get qualidade => _qualidade;
  set qualidade(Qualidade v) {
    _qualidade = v;
    _mudou();
  }

  bool get mostrarSemCanal => _mostrarSemCanal;
  set mostrarSemCanal(bool v) {
    _mostrarSemCanal = v;
    _mudou();
  }

  UltimaFonte? ultimaFonte(String canalTv) => _ultimas[canalTv];

  void registarFuncionou(String canalTv, String listaId, String canalId, DateTime data) {
    _ultimas[canalTv] = UltimaFonte(listaId, canalId, data);
    _mudou();
  }

  /// O canal `canal` da lista é `canalTv` (null = «não é este canal»).
  void associar(String listaId, Canal canal, String? canalTv) {
    _associacoes.putIfAbsent(listaId, () => {})[canal.id] = Associacao(canal, canalTv);
    _mudou();
  }

  Associacao? associacao(String listaId, String canalId) => _associacoes[listaId]?[canalId];

  /// As associações a `canalTv`, por lista.
  Iterable<(String, Canal)> associadosA(String canalTv) sync* {
    for (final l in _associacoes.entries) {
      for (final a in l.value.values) {
        if (a.canalTv == canalTv) yield (l.key, a.canal);
      }
    }
  }

  bool get temAssociacoes => _associacoes.values.any((m) => m.isNotEmpty);

  void limparAssociacoes() {
    _associacoes.clear();
    _mudou();
  }
}
