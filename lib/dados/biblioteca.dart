/// As listas guardadas na app, com a última verificação, os favoritos e a cache de canais.
/// Um ficheiro JSON na pasta de dados da app, escrito de forma atómica.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../importar/importar.dart';
import '../modelo/canal.dart';
import '../modelo/conta.dart';
import '../rede/http.dart' show limiteIsolate;

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

  /// Os canais que a verificação testa ("rtp1", "sporttv1", "dazn1").
  List<String> canaisTeste = const ['rtp1'];

  List<Lista> get listas => List.unmodifiable(_listas);

  File get _ficheiro => File('${_pasta.path}${Platform.pathSeparator}biblioteca.json');
  Directory get _pastaCanais => Directory('${_pasta.path}${Platform.pathSeparator}canais');

  /// Abre (ou cria) a biblioteca em `pasta`. Um ficheiro estragado fica guardado como
  /// biblioteca.json.bak e a app começa vazia.
  /// Um erro ao *ler* (ficheiro bloqueado por outro processo ou pelo antivírus) é repetido e,
  /// se continuar, lançado: nunca se começa vazio por cima de uma biblioteca boa.
  static Future<Biblioteca> abrir(Directory pasta,
      {@visibleForTesting Future<String> Function(File f) ler = _lerTexto}) async {
    await pasta.create(recursive: true);
    final b = Biblioteca._(pasta, []);
    if (await b._ficheiro.exists()) {
      String? texto;
      for (var tentativa = 1; texto == null; tentativa++) {
        try {
          texto = await ler(b._ficheiro);
        } on FileSystemException {
          if (tentativa >= 5) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 200 * tentativa));
        }
      }
      try {
        final dados = jsonDecode(texto);
        for (final j in (dados['listas'] as List)) {
          final l = Lista.deJson(j);
          if (l != null) b._listas.add(l);
        }
        final ct = dados['canais_teste'];
        if (ct is List && ct.isNotEmpty) b.canaisTeste = [for (final c in ct) '$c'];
      } catch (_) {
        // o texto leu-se bem mas não é uma biblioteca (JSON inválido ou outra forma): estragado
        await b._ficheiro.copy('${b._ficheiro.path}.bak');
      }
    }
    return b;
  }

  static Future<String> _lerTexto(File f) => f.readAsString();

  /// O nome do ficheiro temporário de uma gravação: com o pid e bytes aleatórios, para duas
  /// gravações (mesmo de dois processos) nunca escreverem no mesmo ficheiro.
  @visibleForTesting
  static String nomeTemporario(File f) => '${f.path}.$pid.${_novoId()}.tmp';

  /// Bloqueia a pasta de dados para esta instância da app (fica bloqueada enquanto o
  /// ficheiro devolvido estiver aberto). null = outra instância já a tem.
  static Future<RandomAccessFile?> bloquearInstancia(Directory pasta) async {
    await pasta.create(recursive: true);
    final raf = await File('${pasta.path}${Platform.pathSeparator}instancia.lock').open(mode: FileMode.append);
    try {
      await raf.lock(FileLock.exclusive);
      return raf;
    } on FileSystemException {
      await raf.close();
      return null;
    }
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

  Future<void> definirCanaisTeste(List<String> ids) async {
    if (ids.isEmpty) return;
    canaisTeste = List.unmodifiable(ids);
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
      // uma lista grande (100 mil canais) lê-se fora da thread da interface
      if (await f.length() < limiteIsolate) return _lerCanais(await f.readAsString());
      return await _lerCanaisNumIsolate(f.path);
    } catch (_) {
      return null;
    }
  }


  Future<void> guardarCanais(String id, ConteudoLista c) async {
    await _pastaCanais.create(recursive: true);
    // o JSON de uma lista grande faz-se num isolate (só se mandam os mapas, já simples)
    final texto = c.canais.length < 2000
        ? jsonEncode(c.paraJson())
        : await _codificarNumIsolate(c);
    await _emFila(() => _escreverAtomico(_ficheiroCanais(id), texto));
  }

  /// As gravações fazem-se uma de cada vez (várias verificações podem acabar juntas).
  Future<void> _gravacoes = Future.value();

  Future<void> guardar() {
    // o texto é tirado agora (o estado deste momento); a escrita espera pela anterior
    final texto = const JsonEncoder.withIndent(' ').convert({
      'versao': 1, 'canais_teste': canaisTeste, 'listas': [for (final l in _listas) l.paraJson()],
    });
    notifyListeners();
    return _emFila(() => _escreverAtomico(_ficheiro, texto));
  }

  Future<void> _emFila(Future<void> Function() f) {
    final r = _gravacoes.then((_) => f());
    _gravacoes = r.catchError((_) {});
    return r;
  }

  static Future<void> _escreverAtomico(File f, String texto) async {
    final tmp = File(nomeTemporario(f));
    await tmp.writeAsString(texto, flush: true);
    await tmp.rename(f.path);
  }

  static final _rnd = Random.secure();
  static String _novoId() =>
      List.generate(6, (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

ConteudoLista _lerCanais(String texto) => ConteudoLista.deJson(jsonDecode(texto) as Map<String, dynamic>);

// funções de topo: a closure mandada para o isolate não pode levar o `this` da Biblioteca
Future<ConteudoLista> _lerCanaisNumIsolate(String caminho) =>
    Isolate.run(() => _lerCanais(File(caminho).readAsStringSync()));

Future<String> _codificarNumIsolate(ConteudoLista c) => Isolate.run(() => jsonEncode(c.paraJson()));
