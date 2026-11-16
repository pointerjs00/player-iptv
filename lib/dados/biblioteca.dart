/// As listas guardadas na app, com a última verificação, os favoritos e a cache de canais.
/// Um ficheiro JSON na pasta de dados da app, escrito de forma atómica.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../importar/importar.dart';
import '../modelo/canal.dart';
import '../modelo/conta.dart';

class Lista {
  Lista({required this.id, required this.ordem, required this.conta, this.ultima,
      Set<String>? favoritos})
      : favoritos = favoritos ?? <String>{};

  final String id;

  /// Nº de ordem (não muda quando se apagam outras): dá o nome NNNHOST.
  final int ordem;
  final Conta conta;
  UltimaVerificacao? ultima;

  /// Ids dos canais favoritos.
  final Set<String> favoritos;

  String get nome => nomeLista(ordem, conta, ultima?.validade ?? '');

  /// Com INC à frente se a última verificação foi inconclusiva.
  String get nomeMostrado => ultima?.estado == 'inconclusivo' ? '$marcaInc$nome' : nome;

  Map<String, dynamic> paraJson() => {
        'id': id, 'ordem': ordem, 'conta': conta.paraJson(),
        if (ultima != null) 'ultima': ultima!.paraJson(),
        'favoritos': favoritos.toList(),
      };

  static Lista? deJson(Object? j) {
    if (j is! Map) return null;
    try {
      return Lista(
        id: '${j['id']}', ordem: (j['ordem'] as num).toInt(),
        conta: Conta.deJson(Map<String, dynamic>.from(j['conta'] as Map)),
        ultima: UltimaVerificacao.deJson(j['ultima']),
        favoritos: {for (final f in (j['favoritos'] as List? ?? const [])) '$f'},
      );
    } catch (_) {
      return null; // entrada estragada: ignora-se, as outras ficam
    }
  }
}

class Biblioteca extends ChangeNotifier {
  Biblioteca._(this._pasta, this._listas);

  final Directory _pasta;
  final List<Lista> _listas;

  List<Lista> get listas => List.unmodifiable(_listas);

  File get _ficheiro => File('${_pasta.path}${Platform.pathSeparator}biblioteca.json');
  Directory get _pastaCanais => Directory('${_pasta.path}${Platform.pathSeparator}canais');

  /// Abre (ou cria) a biblioteca em `pasta`. Um ficheiro estragado fica guardado como
  /// biblioteca.json.bak e a app começa vazia.
  static Future<Biblioteca> abrir(Directory pasta) async {
    await pasta.create(recursive: true);
    final b = Biblioteca._(pasta, []);
    if (await b._ficheiro.exists()) {
      try {
        final dados = jsonDecode(await b._ficheiro.readAsString());
        for (final j in (dados['listas'] as List)) {
          final l = Lista.deJson(j);
          if (l != null) b._listas.add(l);
        }
      } catch (_) {
        await b._ficheiro.copy('${b._ficheiro.path}.bak');
      }
    }
    return b;
  }

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
      final l = Lista(id: _novoId(), ordem: proxima++, conta: i.conta, ultima: i.ultima);
      _listas.add(l);
      porChave[chave(i.conta)] = l;
      novas++;
    }
    await guardar();
    return novas;
  }

  Future<void> remover(String id) async {
    _listas.removeWhere((l) => l.id == id);
    final f = _ficheiroCanais(id);
    if (await f.exists()) await f.delete();
    await guardar();
  }

  Future<void> registarVerificacao(String id, UltimaVerificacao v) async {
    final l = porId(id);
    if (l == null) return;
    l.ultima = v;
    await guardar();
  }

  Future<void> alternarFavorito(String id, String canalId) async {
    final l = porId(id);
    if (l == null) return;
    if (!l.favoritos.remove(canalId)) l.favoritos.add(canalId);
    await guardar();
  }

  File _ficheiroCanais(String id) => File('${_pastaCanais.path}${Platform.pathSeparator}$id.json');

  Future<ConteudoLista?> canaisEmCache(String id) async {
    final f = _ficheiroCanais(id);
    if (!await f.exists()) return null;
    try {
      return ConteudoLista.deJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> guardarCanais(String id, ConteudoLista c) async {
    await _pastaCanais.create(recursive: true);
    await _escreverAtomico(_ficheiroCanais(id), jsonEncode(c.paraJson()));
  }

  Future<void> guardar() async {
    await _escreverAtomico(_ficheiro,
        const JsonEncoder.withIndent(' ').convert({'versao': 1, 'listas': [for (final l in _listas) l.paraJson()]}));
    notifyListeners();
  }

  static Future<void> _escreverAtomico(File f, String texto) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(texto, flush: true);
    await tmp.rename(f.path);
  }

  static final _rnd = Random.secure();
  static String _novoId() =>
      List.generate(6, (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
