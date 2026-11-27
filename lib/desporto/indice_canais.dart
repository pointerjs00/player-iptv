/// O índice dos canais portugueses das listas (spec §8): para cada canal do catálogo, os canais
/// das listas que o têm. Lê-se a cache de canais de cada lista só quando muda (pela data) e o
/// reconhecimento dos nomes faz-se num isolate (listas de 100 mil canais). Fica guardado em
/// `<dados>/desporto/indice.json`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../dados/biblioteca.dart';
import '../modelo/canal.dart';
import 'modelo.dart';
import 'nomes.dart';
import 'onde_ver.dart';
import 'preferencias_jogos.dart';

/// Um canal reconhecido numa lista.
typedef _Entrada = ({Map<String, dynamic> canal, int qualidade, double confianca});

class _IndiceLista {
  _IndiceLista(this.data, this.porCanal);

  /// A data da cache de canais (ISO) quando se indexou.
  final String data;

  /// canal do catálogo → canais da lista.
  final Map<String, List<_Entrada>> porCanal;
}

/// Só os nomes e grupos chegam ao isolate; o resto do canal só para os reconhecidos.
Map<String, List<(int, int, double)>> _reconhecer(List<(String, String)> nomes) {
  final r = <String, List<(int, int, double)>>{};
  for (final (i, (nome, grupo)) in nomes.indexed) {
    final rec = reconhecerCanal(nome, grupo: grupo);
    if (rec == null || !rec.portugues) continue;
    r.putIfAbsent(rec.canal.id, () => []).add((i, rec.qualidade.index, rec.confianca));
  }
  return r;
}

class IndiceCanais extends ChangeNotifier {
  IndiceCanais(this.biblioteca, Directory pasta, this.preferencias)
      : _ficheiro = File('${pasta.path}${Platform.pathSeparator}indice.json');

  final Biblioteca biblioteca;
  final PreferenciasJogos preferencias;
  final File _ficheiro;
  Map<String, _IndiceLista>? _porLista;

  /// Listas que ainda não têm canais em cache (não entram no «Onde ver»).
  int get listasSemCache => _semCache;
  int _semCache = 0;

  Future<void>? _aAtualizar;

  /// Relê as listas cuja cache de canais mudou (só uma atualização de cada vez).
  Future<void> atualizar() => _aAtualizar ??= _atualizar().whenComplete(() => _aAtualizar = null);

  Future<void> _atualizar() async {
    final indice = _porLista ??= await _lerDoDisco();
    var mudou = false;
    var semCache = 0;
    final ids = <String>{};
    for (final l in List.of(biblioteca.listas)) {
      ids.add(l.id);
      final data = await biblioteca.dataCache(l.id);
      if (data == null) {
        semCache++;
        mudou |= indice.remove(l.id) != null;
        continue;
      }
      final d = data.toUtc().toIso8601String();
      if (indice[l.id]?.data == d) continue;
      final c = await biblioteca.canaisEmCache(l.id);
      if (c == null) continue;
      final nomes = [for (final x in c.canais) (x.nome, x.grupo)];
      final reconhecidos = nomes.length > 2000 ? await Isolate.run(() => _reconhecer(nomes)) : _reconhecer(nomes);
      indice[l.id] = _IndiceLista(d, {
        for (final e in reconhecidos.entries)
          e.key: [for (final (i, q, conf) in e.value) (canal: c.canais[i].paraJson(), qualidade: q, confianca: conf)],
      });
      mudou = true;
    }
    final antes = indice.length;
    indice.removeWhere((id, _) => !ids.contains(id));
    mudou |= indice.length != antes;
    _semCache = semCache;
    if (mudou) await _gravar(indice);
    notifyListeners();
  }

  Future<Map<String, _IndiceLista>> _lerDoDisco() async {
    try {
      final j = jsonDecode(await _ficheiro.readAsString()) as Map<String, dynamic>;
      return {
        for (final e in j.entries)
          e.key: _IndiceLista('${(e.value as Map)['data']}', {
            for (final c in ((e.value as Map)['canais'] as Map).entries)
              '${c.key}': [
                for (final x in c.value as List)
                  (
                    canal: Map<String, dynamic>.from((x as List)[0] as Map),
                    qualidade: x[1] as int,
                    confianca: (x[2] as num).toDouble(),
                  ),
              ],
          }),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _gravar(Map<String, _IndiceLista> indice) async {
    await _ficheiro.parent.create(recursive: true);
    await escreverAtomico(
        _ficheiro,
        jsonEncode({
          for (final e in indice.entries)
            e.key: {
              'data': e.value.data,
              'canais': {
                for (final c in e.value.porCanal.entries)
                  c.key: [for (final x in c.value) [x.canal, x.qualidade, x.confianca]],
              },
            },
        }));
  }

  /// As fontes do canal `canalTv` em todas as listas (sem ordem; ver [ordenarFontes]), com as
  /// associações manuais aplicadas.
  List<FonteCanal> fontes(String canalTv) {
    final indice = _porLista ?? const {};
    final r = <FonteCanal>[];
    final vistos = <(String, String)>{};
    for (final l in biblioteca.listas) {
      for (final e in indice[l.id]?.porCanal[canalTv] ?? const <_Entrada>[]) {
        final canal = Canal.deJson(e.canal);
        final a = preferencias.associacao(l.id, canal.id);
        if (a != null && a.canalTv != canalTv) continue; // «não é este» ou associado a outro
        vistos.add((l.id, canal.id));
        r.add(FonteCanal(l, canal, qualidade: Qualidade.values[e.qualidade], confianca: e.confianca, canalTv: canalTv));
      }
    }
    for (final (listaId, canal) in preferencias.associadosA(canalTv)) {
      final l = biblioteca.porId(listaId);
      if (l == null || !vistos.add((listaId, canal.id))) continue;
      r.add(FonteCanal(l, canal, canalTv: canalTv));
    }
    return r;
  }
}
