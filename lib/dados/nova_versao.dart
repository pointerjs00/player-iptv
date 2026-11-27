/// O aviso de nova versão: a release mais recente da edição da app publicada no GitHub
/// (`pointerjs00/player-iptv`), comparada com a versão da app. Cada versão tem duas releases: a
/// completa (`v1.0.26`, com os pacotes das duas edições) e a de partilha (`partilha-v1.0.26`, só
/// com os dela). A edição de partilha só vê as suas: só é avisada delas e só aponta para elas.
/// Avisa-se uma vez por versão; sem rede, sem releases ou em dados móveis não se diz nada.
library;

import 'dart:convert';
import 'dart:io';

import '../rede/http.dart';

/// As releases do repositório, as mais recentes primeiro.
const enderecoReleases = 'https://api.github.com/repos/pointerjs00/player-iptv/releases?per_page=30';

/// A etiqueta das releases de cada edição (seguida da versão).
const prefixoCompleta = 'v', prefixoPartilha = 'partilha-v';

/// O ficheiro com a última versão de que já se avisou.
const ficheiroVersaoAvisada = 'nova_versao_avisada.txt';

/// Um ficheiro da release (um APK ou o zip do Windows).
class Pacote {
  const Pacote(this.nome, this.url, this.tamanho, this.sha256);

  /// «TVIntel-1.0.28-android-arm64.apk».
  final String nome;

  /// O endereço do download (`browser_download_url`).
  final String url;

  /// Em bytes.
  final int tamanho;

  /// O SHA-256 em hexadecimal (o `digest` do GitHub sem o «sha256:»); null se não vier.
  final String? sha256;
}

class NovaVersao {
  const NovaVersao(this.versao, this.pagina, {this.pacotes = const []});

  /// «1.0.26» (a etiqueta da release sem o «v»).
  final String versao;

  /// A página da release no GitHub (onde estão os pacotes).
  final String pagina;

  /// Os ficheiros da release.
  final List<Pacote> pacotes;
}

/// O resultado da procura manual (o botão nas Definições).
sealed class Procura {
  const Procura();
}

/// A app já está na versão mais recente desta edição.
class EmDia extends Procura {
  const EmDia(this.versao);
  final String versao;
}

/// Há uma versão mais recente.
class HaNova extends Procura {
  const HaNova(this.v);
  final NovaVersao v;
}

/// Sem rede, ou o GitHub não respondeu com releases desta edição.
class SemResposta extends Procura {
  const SemResposta();
}

List<Pacote> _pacotes(Object? assets) => [
      if (assets is List)
        for (final a in assets.whereType<Map>())
          if (a['name'] is String && a['browser_download_url'] is String && a['size'] is int)
            Pacote(a['name'] as String, a['browser_download_url'] as String, a['size'] as int,
                a['digest'] is String && (a['digest'] as String).startsWith('sha256:')
                    ? (a['digest'] as String).substring(7)
                    : null),
    ];

/// A release mais recente com a etiqueta `prefixo` + versão em `texto` (a lista da API); rascunhos e
/// pré-versões não contam. null se não houver nenhuma.
NovaVersao? lerUltimaRelease(String texto, {required String prefixo}) {
  try {
    final j = jsonDecode(texto);
    if (j is! List) return null;
    NovaVersao? melhor;
    for (final r in j.whereType<Map>()) {
      if (r['draft'] == true || r['prerelease'] == true) continue;
      final tag = r['tag_name'], pagina = r['html_url'];
      if (tag is! String || pagina is! String || !tag.startsWith(prefixo)) continue;
      final v = tag.substring(prefixo.length);
      // depois do prefixo, só a versão («1.0.26»): outra etiqueta qualquer não conta
      if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(v)) continue;
      if (melhor == null || maisRecente(v, melhor.versao)) melhor = NovaVersao(v, pagina, pacotes: _pacotes(r['assets']));
    }
    return melhor;
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

/// A procura manual: ao contrário do aviso, não olha para a versão já avisada nem para os dados
/// móveis (quem carrega no botão quer saber).
Future<Procura> procurarVersao(
    {required String atual, String prefixo = prefixoCompleta, Future<String> Function(Uri uri) obter = _obterDaRede}) async {
  final NovaVersao? v;
  try {
    v = lerUltimaRelease(await obter(Uri.parse(enderecoReleases)), prefixo: prefixo);
  } catch (_) {
    return const SemResposta();
  }
  if (v == null) return const SemResposta();
  return maisRecente(v.versao, atual) ? HaNova(v) : EmDia(atual);
}

/// A versão nova de que ainda não se avisou (null: nenhuma, sem rede ou em dados móveis). Fica
/// logo marcada como avisada.
Future<NovaVersao?> novaVersaoPorAvisar(Directory pasta,
    {required String atual,
    Future<String> Function(Uri uri) obter = _obterDaRede,
    Future<bool> Function()? emDadosMoveis,
    String prefixo = prefixoCompleta}) async {
  if (emDadosMoveis != null && await emDadosMoveis()) return null;
  final NovaVersao? v;
  try {
    v = lerUltimaRelease(await obter(Uri.parse(enderecoReleases)), prefixo: prefixo);
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
