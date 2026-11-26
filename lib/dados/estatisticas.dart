/// O tempo de visualização: quanto se viu de cada canal, por dia e por hora do dia. Fica só no
/// aparelho (um ficheiro na pasta da app, fora da cópia de segurança) e conta só a reprodução a
/// sério (o player avisa enquanto o vídeo está a tocar: sem pausas, sem o tempo a carregar).
///
/// No Windows o player é outra janela (outro processo): é ela que escreve; a janela principal
/// relê o ficheiro ([recarregar]) quando o Início volta a estar à vista.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../modelo/canal.dart';
import 'biblioteca.dart' show escreverAtomico;

/// O tempo visto de um canal (num período), com o que é preciso para o mostrar.
class CanalVisto {
  const CanalVisto({required this.chave, required this.nome, required this.logo, required this.listaId,
      required this.lista, required this.canalId, required this.tempo});

  /// O id da lista e o id do canal, separados por `|`.
  final String chave;
  final String nome;
  final String logo;
  final String listaId;

  /// O nome da lista (o de quando se viu).
  final String lista;
  final String canalId;
  final Duration tempo;
}

/// O resumo da semana: o total, o da semana anterior, os 7 dias (o mais antigo primeiro, hoje o
/// último) e os canais mais vistos.
class ResumoSemana {
  const ResumoSemana({required this.total, required this.anterior, required this.porDia, required this.maisVistos});

  final Duration total;
  final Duration anterior;
  final List<Duration> porDia;
  final List<CanalVisto> maisVistos;

  bool get vazia => total == Duration.zero && anterior == Duration.zero;
}

/// "2026-11-26" (o dia local).
String chaveDia(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _inicioDoDia(DateTime d) => DateTime(d.year, d.month, d.day);

class Estatisticas extends ChangeNotifier {
  Estatisticas._(this._pasta);

  /// Sem ficheiro (testes, ou antes de [abrir]).
  Estatisticas.emMemoria() : this._(null);

  /// As da app (abertas no arranque, em `main`).
  static Estatisticas atual = Estatisticas.emMemoria();

  static const nomeFicheiro = 'estatisticas.json';

  /// Os dias mais antigos do que isto saem ao gravar (o ficheiro nunca cresce sem limite).
  static const diasGuardados = 120;

  final Directory? _pasta;

  /// dia → chave do canal → segundos.
  final _segundos = <String, Map<String, int>>{};

  /// dia → segundos por hora do dia (24).
  final _horas = <String, List<int>>{};

  /// chave do canal → (nome, logo, nome da lista): o mais recente.
  final _canais = <String, (String, String, String)>{};

  bool _sujo = false;

  File? get _ficheiro => _pasta == null ? null : File('${_pasta.path}${Platform.pathSeparator}$nomeFicheiro');

  static Future<Estatisticas> abrir(Directory pasta) async {
    final e = Estatisticas._(pasta);
    await e.recarregar();
    return e;
  }

  /// Lê o ficheiro outra vez (o que a janela do player escreveu, no Windows). Um ficheiro
  /// estragado conta como vazio.
  Future<void> recarregar() async {
    final f = _ficheiro;
    if (f == null) return;
    try {
      if (!await f.exists()) return;
      _ler(jsonDecode(await f.readAsString()));
      notifyListeners();
    } catch (_) {/* estragado: fica o que havia */}
  }

  void _ler(Object? j) {
    if (j is! Map || j['v'] != 1) return;
    _segundos.clear();
    _horas.clear();
    _canais.clear();
    final dias = j['dias'];
    if (dias is Map) {
      for (final e in dias.entries) {
        final v = e.value;
        if (v is! Map) continue;
        _segundos['${e.key}'] = {
          for (final c in v.entries)
            if (c.value is num) '${c.key}': (c.value as num).toInt(),
        };
      }
    }
    final horas = j['horas'];
    if (horas is Map) {
      for (final e in horas.entries) {
        final v = e.value;
        if (v is List && v.length == 24) _horas['${e.key}'] = [for (final x in v) x is num ? x.toInt() : 0];
      }
    }
    final canais = j['canais'];
    if (canais is Map) {
      for (final e in canais.entries) {
        final v = e.value;
        if (v is List && v.length >= 3) _canais['${e.key}'] = ('${v[0]}', '${v[1]}', '${v[2]}');
      }
    }
  }

  Map<String, Object> _paraJson() => {
        'v': 1,
        'dias': _segundos,
        'horas': _horas,
        'canais': {for (final e in _canais.entries) e.key: [e.value.$1, e.value.$2, e.value.$3]},
      };

  /// Soma `tempo` visto do `canal` da lista (`listaId`, `listaNome`) no instante `quando`.
  void somar(String listaId, String listaNome, Canal canal, Duration tempo, {DateTime? quando}) {
    if (tempo <= Duration.zero) return;
    final q = quando ?? DateTime.now();
    final dia = chaveDia(q);
    final chave = '$listaId|${canal.id}';
    final s = tempo.inSeconds;
    final porCanal = _segundos.putIfAbsent(dia, () => {});
    porCanal[chave] = (porCanal[chave] ?? 0) + s;
    final horas = _horas.putIfAbsent(dia, () => List.filled(24, 0));
    horas[q.hour] += s;
    _canais[chave] = (canal.nome, canal.logo, listaNome);
    _sujo = true;
    notifyListeners();
  }

  /// Grava (só se mudou), sem os dias mais antigos do que [diasGuardados].
  Future<void> guardar({DateTime? agora}) async {
    final f = _ficheiro;
    if (f == null || !_sujo) return;
    _podar(agora ?? DateTime.now());
    _sujo = false;
    try {
      await escreverAtomico(f, jsonEncode(_paraJson()));
    } catch (_) {
      _sujo = true; // tenta-se outra vez na próxima
    }
  }

  void _podar(DateTime agora) {
    final limite = chaveDia(_inicioDoDia(agora).subtract(const Duration(days: diasGuardados)));
    _segundos.removeWhere((dia, _) => dia.compareTo(limite) < 0);
    _horas.removeWhere((dia, _) => dia.compareTo(limite) < 0);
    final usados = {for (final m in _segundos.values) ...m.keys};
    _canais.removeWhere((c, _) => !usados.contains(c));
  }

  /// Apaga tudo (memória e ficheiro).
  Future<void> apagar() async {
    _segundos.clear();
    _horas.clear();
    _canais.clear();
    _sujo = false;
    notifyListeners();
    try {
      await _ficheiro?.delete();
    } catch (_) {}
  }

  bool get vazio => _segundos.values.every((m) => m.isEmpty);

  // ------------------------------------------------------------------ os resumos

  /// Os dias (chaves) dos últimos `n` dias até `agora`, o mais antigo primeiro.
  static List<String> _dias(DateTime agora, int n) {
    final hoje = _inicioDoDia(agora);
    return [for (var i = n - 1; i >= 0; i--) chaveDia(DateTime(hoje.year, hoje.month, hoje.day - i))];
  }

  Duration _doDia(String dia) => Duration(seconds: (_segundos[dia]?.values ?? const <int>[]).fold(0, (a, b) => a + b));

  /// Os canais mais vistos nos últimos `dias` (até `n`).
  List<CanalVisto> maisVistos(DateTime agora, {int dias = 30, int n = 10}) {
    final soma = <String, int>{};
    for (final d in _dias(agora, dias)) {
      for (final e in (_segundos[d] ?? const <String, int>{}).entries) {
        soma[e.key] = (soma[e.key] ?? 0) + e.value;
      }
    }
    final ordem = soma.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in ordem.take(n))
        () {
          final (nome, logo, lista) = _canais[e.key] ?? ('', '', '');
          final i = e.key.indexOf('|');
          return CanalVisto(chave: e.key, nome: nome, logo: logo, listaId: e.key.substring(0, i), lista: lista,
              canalId: e.key.substring(i + 1), tempo: Duration(seconds: e.value));
        }(),
    ];
  }

  ResumoSemana semana(DateTime agora) {
    final esta = _dias(agora, 7);
    final antes = _dias(agora.subtract(const Duration(days: 7)), 7);
    final porDia = [for (final d in esta) _doDia(d)];
    return ResumoSemana(
      total: porDia.fold(Duration.zero, (a, b) => a + b),
      anterior: antes.fold(Duration.zero, (a, d) => a + _doDia(d)),
      porDia: porDia,
      maisVistos: maisVistos(agora, dias: 7, n: 3),
    );
  }

  /// As listas mais usadas nos últimos `dias`: (nome da lista, tempo), por ordem.
  List<(String, Duration)> listasMaisUsadas(DateTime agora, {int dias = 30}) {
    final soma = <String, int>{};
    for (final d in _dias(agora, dias)) {
      for (final e in (_segundos[d] ?? const <String, int>{}).entries) {
        final nome = _canais[e.key]?.$3 ?? '';
        soma[nome] = (soma[nome] ?? 0) + e.value;
      }
    }
    final ordem = soma.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in ordem) (e.key, Duration(seconds: e.value))];
  }

  /// O tempo por dia da semana nos últimos `dias` (segunda primeiro).
  List<Duration> porDiaDaSemana(DateTime agora, {int dias = 30}) {
    final r = List.filled(7, 0);
    final hoje = _inicioDoDia(agora);
    for (var i = 0; i < dias; i++) {
      final d = DateTime(hoje.year, hoje.month, hoje.day - i);
      r[d.weekday - 1] += _doDia(chaveDia(d)).inSeconds;
    }
    return [for (final s in r) Duration(seconds: s)];
  }

  /// O tempo por hora do dia nos últimos `dias` (0 h primeiro).
  List<Duration> porHora(DateTime agora, {int dias = 30}) {
    final r = List.filled(24, 0);
    for (final d in _dias(agora, dias)) {
      final h = _horas[d];
      if (h == null) continue;
      for (var i = 0; i < 24; i++) {
        r[i] += h[i];
      }
    }
    return [for (final s in r) Duration(seconds: s)];
  }

  /// Quantos dias seguidos, até hoje (ou até ontem, se hoje ainda não se viu nada), com pelo
  /// menos [minimoDia] visto.
  int diasSeguidos(DateTime agora) {
    final hoje = _inicioDoDia(agora);
    var i = _doDia(chaveDia(hoje)) >= minimoDia ? 0 : 1;
    var n = 0;
    while (_doDia(chaveDia(DateTime(hoje.year, hoje.month, hoje.day - i))) >= minimoDia) {
      n++;
      i++;
    }
    return n;
  }

  /// O mínimo para um dia contar na sequência.
  static const minimoDia = Duration(minutes: 5);
}

/// "12 h 40", "45 min", "0 min".
String textoDuracao(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '$m min';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h h' : '$h h ${r.toString().padLeft(2, '0')}';
}
