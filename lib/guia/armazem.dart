/// O guia guardado no aparelho: um ficheiro pequeno e comprimido por lista, na pasta de cache
/// da app (o Android pode limpá-la; não entra na cópia de segurança). Há um teto para todos os
/// guias juntos e os que não se usam há uma semana desaparecem.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'programa.dart';

class ArmazemGuia {
  ArmazemGuia(this._pasta, {this.teto = 20 * 1024 * 1024, this.validade = const Duration(days: 7)});

  /// O armazém na pasta de cache da app (null se não houver: em testes, por exemplo).
  static Future<ArmazemGuia?> doAparelho() async {
    try {
      final cache = await getApplicationCacheDirectory();
      return ArmazemGuia(Directory('${cache.path}${Platform.pathSeparator}guia'));
    } catch (_) {
      return null;
    }
  }

  final Directory _pasta;

  /// O tamanho máximo de todos os guias juntos (bytes).
  final int teto;

  /// Um guia sem uso há mais do que isto é apagado.
  final Duration validade;

  /// O nome do ficheiro de uma lista (a chave junta o id da lista e a conta: editar a conta
  /// começa um guia novo).
  static String nomeFicheiro(String chave) => '${sha1.convert(utf8.encode(chave))}.json.gz';

  File _ficheiro(String chave) => File('${_pasta.path}${Platform.pathSeparator}${nomeFicheiro(chave)}');

  /// O guia guardado de uma lista (null = nenhum ou ilegível). Marca-o como usado.
  Future<GuiaLista?> ler(String chave) async {
    final f = _ficheiro(chave);
    try {
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      // marcado como usado: a limpeza apaga primeiro os que não se usam
      await f.setLastModified(DateTime.now());
      return bytes.length < 256 * 1024 ? _descodificar(bytes) : await Isolate.run(() => _descodificar(bytes));
    } catch (_) {
      return null;
    }
  }

  static GuiaLista? _descodificar(List<int> bytes) {
    try {
      return GuiaLista.deJson(jsonDecode(utf8.decode(gzip.decode(bytes))));
    } catch (_) {
      return null;
    }
  }

  /// Grava o guia de uma lista (por cima do anterior) e arruma os outros.
  Future<void> gravar(String chave, GuiaLista guia) async {
    try {
      await _pasta.create(recursive: true);
      final dados = guia.paraJson();
      final bytes = await Isolate.run(() => gzip.encode(utf8.encode(jsonEncode(dados))));
      final f = _ficheiro(chave);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
      await arrumar(proteger: {nomeFicheiro(chave)});
    } catch (_) {
      // sem espaço ou sem pasta: o guia fica só na memória
    }
  }

  Future<void> apagar(String chave) async {
    try {
      await _ficheiro(chave).delete();
    } catch (_) {}
  }

  /// Apaga os guias sem uso há mais de [validade], os que não são de nenhuma lista de
  /// `manter` (as chaves das listas que existem; null = não se sabe) e, passando do [teto],
  /// os usados há mais tempo. Os de `proteger` (nomes de ficheiro) ficam sempre.
  Future<void> arrumar({Set<String>? manter, Set<String> proteger = const {}}) async {
    final List<File> ficheiros;
    try {
      if (!await _pasta.exists()) return;
      ficheiros = [await for (final e in _pasta.list()) if (e is File) e];
    } catch (_) {
      return;
    }
    final nomesManter = manter == null ? null : {for (final k in manter) nomeFicheiro(k)};
    final agora = DateTime.now();
    final vivos = <(File, DateTime, int)>[];
    for (final f in ficheiros) {
      final nome = f.uri.pathSegments.last;
      try {
        final st = await f.stat();
        final velho = agora.difference(st.modified) > validade;
        final semLista = nomesManter != null && !nomesManter.contains(nome);
        final restos = nome.endsWith('.tmp') && agora.difference(st.modified) > const Duration(minutes: 10);
        if (!proteger.contains(nome) && (velho || semLista || restos)) {
          await f.delete();
        } else {
          vivos.add((f, st.modified, st.size));
        }
      } catch (_) {}
    }
    var total = vivos.fold<int>(0, (s, v) => s + v.$3);
    if (total <= teto) return;
    vivos.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (f, _, tamanho) in vivos) {
      if (total <= teto) break;
      if (proteger.contains(f.uri.pathSegments.last)) continue;
      try {
        await f.delete();
        total -= tamanho;
      } catch (_) {}
    }
  }

  /// O espaço ocupado por todos os guias (bytes).
  Future<int> ocupado() async {
    try {
      if (!await _pasta.exists()) return 0;
      var n = 0;
      await for (final e in _pasta.list()) {
        if (e is File) n += await e.length();
      }
      return n;
    } catch (_) {
      return 0;
    }
  }
}
