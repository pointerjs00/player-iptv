/// A cache em disco das fontes dos «Jogos» (`<dados>/desporto/`): a resposta de cada pedido, em
/// texto, com a data em que chegou. Os adaptadores leem-na como se viesse da rede.
library;

import 'dart:convert';
import 'dart:io';

import '../dados/biblioteca.dart' show escreverAtomico;

class Guardado {
  const Guardado(this.texto, this.data);
  final String texto;

  /// Quando chegou (UTC).
  final DateTime data;
}

class ArmazemDesporto {
  ArmazemDesporto._(this.pasta);
  final Directory pasta;

  /// O que tem mais do que isto apaga-se em [arrumar].
  static const idadeMaxima = Duration(days: 8);

  static Future<ArmazemDesporto> abrir(Directory pasta) async {
    await pasta.create(recursive: true);
    return ArmazemDesporto._(pasta);
  }

  File _ficheiro(String chave) {
    final nome = chave.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${pasta.path}${Platform.pathSeparator}$nome.json');
  }

  Future<Guardado?> ler(String chave) async {
    try {
      final j = jsonDecode(await _ficheiro(chave).readAsString()) as Map<String, dynamic>;
      return Guardado(j['texto'] as String, DateTime.parse(j['data'] as String));
    } catch (_) {
      return null; // sem ficheiro ou estragado: como se não houvesse
    }
  }

  Future<void> gravar(String chave, String texto, DateTime data) =>
      escreverAtomico(_ficheiro(chave), jsonEncode({'data': data.toUtc().toIso8601String(), 'texto': texto}));

  /// Apaga o que chegou há mais de [idadeMaxima].
  Future<void> arrumar({required DateTime agora}) async {
    await for (final f in pasta.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        if (agora.difference(DateTime.parse(j['data'] as String)) > idadeMaxima) await f.delete();
      } catch (_) {
        try {
          await f.delete();
        } on FileSystemException {/* em uso */}
      }
    }
  }
}
