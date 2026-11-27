/// O aviso de nova versão: a última release publicada no GitHub (`pointerjs00/player-iptv`),
/// comparada com a versão da app. Avisa-se uma vez por versão; sem rede, sem releases ou em dados
/// móveis não se diz nada. Só na edição completa (o `main` decide).
library;

import 'dart:convert';
import 'dart:io';

import '../rede/http.dart';

/// A última release do repositório (a API devolve 404 enquanto não houver nenhuma).
const enderecoUltimaRelease = 'https://api.github.com/repos/pointerjs00/player-iptv/releases/latest';

/// O ficheiro com a última versão de que já se avisou.
const ficheiroVersaoAvisada = 'nova_versao_avisada.txt';

class NovaVersao {
  const NovaVersao(this.versao, this.pagina);

  /// «1.0.26» (a etiqueta da release sem o «v»).
  final String versao;

  /// A página da release no GitHub (onde estão os pacotes).
  final String pagina;
}

/// A release de `texto` (a resposta da API), ou null se não servir (rascunho, pré-versão, erro).
NovaVersao? lerUltimaRelease(String texto) {
  try {
    final j = jsonDecode(texto);
    if (j is! Map || j['draft'] == true || j['prerelease'] == true) return null;
    final tag = j['tag_name'], pagina = j['html_url'];
    if (tag is! String || pagina is! String || tag.trim().isEmpty) return null;
    final v = tag.trim();
    return NovaVersao(v.startsWith('v') || v.startsWith('V') ? v.substring(1) : v, pagina);
  } on FormatException {
    return null;
  }
}

/// `nova` é mais recente do que `atual` («1.0.10» > «1.0.9»); uma versão que não é só números
/// nunca é mais recente.
bool maisRecente(String nova, String atual) {
  List<int>? partes(String v) {
    final ps = v.split('.').map(int.tryParse).toList();
    return ps.any((p) => p == null) ? null : [for (final p in ps) p!];
  }

  final a = partes(nova), b = partes(atual);
  if (a == null || b == null) return false;
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

Future<String> _obterDaRede(Uri uri) async => utf8.decode(await obterBytes(uri.toString(),
    headers: const {'User-Agent': 'TVIntel', 'Accept': 'application/vnd.github+json'}, maxBytes: 1024 * 1024));

/// A versão nova de que ainda não se avisou (null: nenhuma, sem rede ou em dados móveis). Fica
/// logo marcada como avisada.
Future<NovaVersao?> novaVersaoPorAvisar(Directory pasta,
    {required String atual,
    Future<String> Function(Uri uri) obter = _obterDaRede,
    Future<bool> Function()? emDadosMoveis}) async {
  if (emDadosMoveis != null && await emDadosMoveis()) return null;
  final NovaVersao? v;
  try {
    v = lerUltimaRelease(await obter(Uri.parse(enderecoUltimaRelease)));
  } catch (_) {
    return null; // sem rede, ou o GitHub sem releases (404): não se diz nada
  }
  if (v == null || !maisRecente(v.versao, atual)) return null;
  final f = File('${pasta.path}${Platform.pathSeparator}$ficheiroVersaoAvisada');
  try {
    if (await f.exists() && (await f.readAsString()).trim() == v.versao) return null;
    await f.writeAsString(v.versao, flush: true);
  } on FileSystemException {
    // sem gravar, avisa-se na mesma (na próxima abertura volta a avisar)
  }
  return v;
}
