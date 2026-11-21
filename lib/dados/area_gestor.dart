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

  /// O ficheiro existia mas não se conseguiu ler: a 1.ª gravação guarda-o primeiro em .bak.
  bool _porLer = false;

  /// Abre (ou cria) o Gestor em `pasta`; nunca lança (o Gestor não impede a app de abrir).
  /// - um bloqueio passageiro ao ler (antivírus, cópia de segurança) é repetido, como na biblioteca;
  /// - bloqueado de vez: começa vazio e a 1.ª gravação muda o ficheiro antigo para .bak (nada se perde);
  /// - estragado: fica guardado como gestor.json.bak e o Gestor começa vazio.
  static Future<AreaGestor> abrir(Directory pasta,
      {@visibleForTesting Future<String> Function(File f) ler = _lerTexto}) async {
    await pasta.create(recursive: true);
    final g = AreaGestor._(pasta);
    if (await g._ficheiro.exists()) {
      String? texto;
      for (var tentativa = 1; texto == null; tentativa++) {
        try {
          texto = await ler(g._ficheiro);
        } on FileSystemException {
          if (tentativa >= 5) {
            g._porLer = true;
            return g;
          }
          await Future<void>.delayed(Duration(milliseconds: 200 * tentativa));
        }
      }
      try {
        for (final j in (jsonDecode(texto)['listas'] as List)) {
          final l = Lista.deJson(j);
          if (l != null) g._listas.add(l);
        }
      } catch (_) {
        g._listas.clear();
        try {
          await g._ficheiro.copy('${g._ficheiro.path}.bak');
        } on FileSystemException {
          g._porLer = true; // não se copiou: a 1.ª gravação tenta outra vez
        }
      }
    }
    return g;
  }

  static Future<String> _lerTexto(File f) => f.readAsString();

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

  /// Aplica as listas do Gestor de uma cópia de segurança (ver [planearRestauro]). Se a gravação
  /// falhar, tudo volta a como estava; o resultado traz como desfazer.
  Future<ResultadoRestauro> restaurar(List<Lista> doFicheiro, {required bool substituir}) async {
    final plano = planearRestauro(_listas, doFicheiro, substituir: substituir);
    final antes = List.of(_listas);
    Future<void> desfazer() async {
      _listas
        ..clear()
        ..addAll(antes);
      await _guardar();
    }

    _listas
      ..clear()
      ..addAll(plano.listas);
    try {
      await _guardar();
    } catch (_) {
      _listas
        ..clear()
        ..addAll(antes);
      notifyListeners();
      rethrow;
    }
    return ResultadoRestauro(plano, desfazer);
  }

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
    final r = _gravacoes.then((_) async {
      if (_porLer) {
        // o ficheiro que não se leu não é reescrito por cima: vai para .bak
        await _ficheiro.rename('${_ficheiro.path}.bak');
        _porLer = false;
      }
      await escreverAtomico(_ficheiro, texto);
    });
    _gravacoes = r.catchError((_) {});
    return r;
  }
}
