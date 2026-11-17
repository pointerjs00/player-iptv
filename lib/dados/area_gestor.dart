/// A área de trabalho do Gestor: listas para verificar, selecionar, exportar e enviar para o
/// Player, separadas das listas do Player. Um ficheiro próprio (gestor.json), escrito de forma
/// atómica e uma gravação de cada vez.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../importar/importar.dart';
import '../modelo/conta.dart';
import 'biblioteca.dart';

class AreaGestor extends ChangeNotifier implements ColecaoListas {
  AreaGestor._(this._pasta);

  final Directory _pasta;
  final List<Lista> _listas = [];

  @override
  List<Lista> get listas => List.unmodifiable(_listas);

  File get _ficheiro => File('${_pasta.path}${Platform.pathSeparator}gestor.json');

  /// Abre (ou cria) o Gestor em `pasta`. Um ficheiro estragado fica guardado como
  /// gestor.json.bak e o Gestor começa vazio. Um erro ao ler é lançado (nunca se começa vazio
  /// por cima de um ficheiro bom).
  static Future<AreaGestor> abrir(Directory pasta) async {
    await pasta.create(recursive: true);
    final g = AreaGestor._(pasta);
    if (await g._ficheiro.exists()) {
      final texto = await g._ficheiro.readAsString();
      try {
        for (final j in (jsonDecode(texto)['listas'] as List)) {
          final l = Lista.deJson(j);
          if (l != null) g._listas.add(l);
        }
      } catch (_) {
        g._listas.clear();
        await g._ficheiro.copy('${g._ficheiro.path}.bak');
      }
    }
    return g;
  }

  @override
  Lista? porId(String id) {
    for (final l in _listas) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// Junta as listas novas (as repetidas, pela chave, só atualizam o resultado se este for
  /// mais recente). Devolve quantas eram novas.
  Future<int> adicionar(Iterable<Importada> importadas) async {
    final porChave = {for (final l in _listas) chave(l.conta): l};
    var novas = 0;
    var proxima = _listas.fold<int>(0, (m, l) => max(m, l.ordem)) + 1;
    for (final i in importadas) {
      final existente = porChave[chave(i.conta)];
      if (existente != null) {
        final u = i.ultima;
        if (u != null && (existente.ultima == null || u.data.isAfter(existente.ultima!.data))) {
          existente.ultima = u;
        }
        continue;
      }
      final l = Lista(id: novoIdLista(), ordem: proxima++, conta: i.conta, ultima: i.ultima);
      _listas.add(l);
      porChave[chave(i.conta)] = l;
      novas++;
    }
    await _guardar();
    return novas;
  }

  /// Copia as listas atuais do Player, com o último resultado, sem duplicar.
  Future<int> importarDoPlayer(Biblioteca player) =>
      adicionar([for (final l in player.listas) Importada(l.conta, l.ultima)]);

  Future<void> remover(Iterable<String> ids) async {
    final s = ids.toSet();
    _listas.removeWhere((l) => s.contains(l.id));
    await _guardar();
  }

  Future<void> limpar() async {
    _listas.clear();
    await _guardar();
  }

  @override
  Future<void> registarVerificacao(String id, UltimaVerificacao v) async {
    final l = porId(id);
    if (l == null) return;
    l.ultima = v;
    await _guardar();
  }

  Future<void> _gravacoes = Future.value();

  Future<void> _guardar() {
    // o texto é tirado agora; a escrita espera pela anterior
    final texto = const JsonEncoder.withIndent(' ').convert({
      'versao': 1,
      'listas': [for (final l in _listas) l.paraJson()],
    });
    notifyListeners();
    final r = _gravacoes.then((_) => escreverAtomico(_ficheiro, texto));
    _gravacoes = r.catchError((_) {});
    return r;
  }
}
