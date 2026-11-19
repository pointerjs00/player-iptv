/// Importação de pares "portal MAC" publicados no blog stbstalker.
/// Porta de `tv-management/motor/stbstalker.py`.
library;

import '../modelo/conta.dart';
import '../rede/http.dart';

const stbBase = 'https://stbstalker.alaaeldinee.com/';

final _reMac = RegExp(r'\b([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})\b');
final _reUrl = RegExp(r'''https?://[^\s"'<>)\]]+''', caseSensitive: false);
final _rePost = RegExp(r'(?:href=")?((?:https?://[^"\s]*?)?/\d{4}/\d{2}/[^"\s>]*?\.html)',
    caseSensitive: false);
final _reDataSlug = RegExp(r'(\d{1,2})-(\d{1,2})-(\d{4})\.html', caseSensitive: false);
final _reMaisAntigos = RegExp(r'href="([^"]*updated-max=[^"]*)"');

const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

typedef PostStb = ({String url, DateTime data});

class ResultadoStb {
  ResultadoStb({this.linhas = const [], this.total = 0, this.posts = const [], this.erro});
  final List<String> linhas;
  final int total;
  final List<PostStb> posts;
  final String? erro;
}

Future<String> _ler(String url, Duration timeout) =>
    obterTexto(url, headers: {'User-Agent': _ua}, timeout: timeout, maxBytes: 16 * 1024 * 1024);

String _codigo(int? n) => n == null || n < 0 || n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF)
    ? '�'
    : String.fromCharCode(n);

String _desescapar(String t) => t
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => _codigo(int.tryParse(m[1]!)))
    .replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);'), (m) => _codigo(int.tryParse(m[1]!, radix: 16)))
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

String _htmlParaTexto(String html) {
  var t = html.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  t = t.replaceAll(RegExp(r'</(p|div|li|h\d)>', caseSensitive: false), '\n');
  t = t.replaceAll(RegExp(r'<[^>]+>', dotAll: true), '');
  return _desescapar(t);
}

String _chavePar(String par) {
  final c = contaDeLinha(par);
  return c == null ? par : chave(c);
}

/// Pares "portal MAC" do texto, cada MAC associado ao portal acima dele.
List<String> extrairPares(String texto) {
  final pares = <String>[];
  final vistos = <String>{};
  String? portal;
  for (final linha in texto.split(RegExp(r'\r\n|\r|\n'))) {
    final url = _reUrl.firstMatch(linha);
    if (url != null) {
      final u = url[0]!.replaceAll(RegExp(r'[.,);\]]+$'), '');
      if (!u.contains('stbstalker') && !u.contains('blogger') && !u.contains('gstatic')) portal = u;
    }
    for (final m in _reMac.allMatches(linha)) {
      if (portal == null) continue;
      final par = '$portal ${m[1]!.toUpperCase()}';
      if (vistos.add(_chavePar(par))) pares.add(par);
    }
  }
  return pares;
}

/// A data do slug do post, ex.: smart-stb-emu-pro-11-11-2026.html.
DateTime? dataDoPost(String url) {
  final m = _reDataSlug.firstMatch(url);
  if (m == null) return null;
  final d = int.parse(m[1]!), mes = int.parse(m[2]!), ano = int.parse(m[3]!);
  final data = DateTime(ano, mes, d);
  return data.year == ano && data.month == mes && data.day == d ? data : null;
}

String _legivel(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

/// Os posts com inicio <= data <= fim (mais recentes primeiro). Recua pelas páginas
/// antigas até passar `inicio`.
Future<List<PostStb>> postsEntre(DateTime inicio, DateTime fim,
    {String base = stbBase, Duration timeout = const Duration(seconds: 15), int maxPaginas = 20}) async {
  inicio = _dia(inicio);
  fim = _dia(fim);
  final raiz = Uri.parse(base);
  final vistos = <String, DateTime>{};
  var url = base;
  for (var i = 0; i < maxPaginas; i++) {
    final pagina = await _ler(url, timeout);
    DateTime? maisAntigo;
    for (final m in _rePost.allMatches(pagina)) {
      final u = raiz.resolve(m[1]!).toString();
      final d = dataDoPost(u);
      if (d == null) continue;
      if (maisAntigo == null || d.isBefore(maisAntigo)) maisAntigo = d;
      vistos.putIfAbsent(u, () => d);
    }
    if (maisAntigo != null && maisAntigo.isBefore(inicio)) break;
    final m = _reMaisAntigos.firstMatch(pagina);
    if (m == null) break;
    url = raiz.resolve(_desescapar(m[1]!)).toString();
  }
  final posts = [
    for (final e in vistos.entries)
      if (!e.value.isBefore(inicio) && !e.value.isAfter(fim)) (url: e.key, data: e.value)
  ]..sort((a, b) => b.data.compareTo(a.data));
  return posts;
}

/// Junta os pares de todos os posts publicados entre as duas datas (inclusive).
///
/// `aoProgresso(posts lidos, posts, listas encontradas até agora)` diz como vai a leitura dos posts.
Future<ResultadoStb> importarEntre(DateTime inicio, DateTime fim,
    {String base = stbBase,
    Duration timeout = const Duration(seconds: 15),
    void Function(int lidos, int posts, int encontradas)? aoProgresso}) async {
  inicio = _dia(inicio);
  fim = _dia(fim);
  if (fim.isBefore(inicio)) throw ArgumentError('a data de fim é anterior à data de início');
  final posts = await postsEntre(inicio, fim, base: base, timeout: timeout);
  if (posts.isEmpty) {
    final periodo = inicio == fim ? 'em ${_legivel(inicio)}' : 'entre ${_legivel(inicio)} e ${_legivel(fim)}';
    return ResultadoStb(erro: 'Nenhum post publicado $periodo.');
  }
  final linhas = <String>[];
  final vistos = <String>{};
  for (final (i, p) in posts.indexed) {
    String? texto;
    try {
      texto = _htmlParaTexto(await _ler(p.url, timeout));
    } on Exception {
      texto = null; // um post que não abre não impede os outros
    }
    if (texto != null) {
      for (final par in extrairPares(texto)) {
        if (vistos.add(_chavePar(par))) linhas.add(par);
      }
    }
    aoProgresso?.call(i + 1, posts.length, linhas.length);
  }
  return ResultadoStb(linhas: linhas, total: linhas.length, posts: posts);
}
