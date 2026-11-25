/// Listas de um site à escolha (Gestor › Importar › Listas de um site): num blog Blogger ou
/// WordPress lêem-se os posts publicados entre duas datas (pelo feed do próprio site); noutro
/// site, ou num endereço de um post, lê-se só essa página. De cada texto tiram-se as listas
/// (Xtream, M3U e portal + MAC), como no Telegram.
library;

import '../modelo/conta.dart';
import '../rede/http.dart';
import '../idioma/idioma.dart';
import 'stbstalker.dart' show extrairPares;

const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

/// Como se leu o site.
enum TipoSite {
  /// Os posts do Blogger entre as datas (`/feeds/posts/default`).
  blogger,

  /// Os posts do WordPress entre as datas (`/wp-json/wp/v2/posts`).
  wordpress,

  /// Só a página do endereço (sem datas).
  pagina,
}

class ResultadoSite {
  ResultadoSite({this.contas = const [], this.lidas = 0, this.tipo = TipoSite.pagina, this.erro});

  final List<Conta> contas;

  /// Os posts (ou a página) lidos.
  final int lidas;
  final TipoSite tipo;

  /// Uma mensagem para o utilizador (nenhum post no período, nenhuma lista na página).
  final String? erro;
}

/// O endereço escrito, pronto a usar ("site.com" → "https://site.com/"); null se não servir.
String? siteDeTexto(String entrada) {
  var t = entrada.trim();
  if (t.isEmpty) return null;
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(t)) t = 'https://$t';
  final u = Uri.tryParse(t);
  if (u == null || u.host.isEmpty || !u.host.contains('.')) return null;
  return u.path.isEmpty ? '$t/' : t;
}

/// É a página inicial do site (sem caminho)? Aí procuram-se os posts por datas.
bool raizDoSite(String url) {
  final u = Uri.parse(url);
  return (u.path.isEmpty || u.path == '/') && u.query.isEmpty;
}

final _reHref = RegExp(r'''href\s*=\s*["']([^"']+)["']''', caseSensitive: false);
final _reQuebra = RegExp(r'<\s*(br|/p|/div|/li|/h\d|/tr|/pre|p|div|li|tr)\b[^>]*>', caseSensitive: false);
final _reEtiqueta = RegExp(r'<[^>]+>', dotAll: true);
final _reScript = RegExp(r'<(script|style)\b[\s\S]*?</\1>', caseSensitive: false);
final _reEntidade = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos|nbsp);');

String _entidades(String t) => t.replaceAllMapped(_reEntidade, (m) {
      final e = m[1]!;
      switch (e) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
        case 'nbsp':
          return ' ';
      }
      final n = e.startsWith('#x') ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
      return n == null || n <= 0 || n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF) ? '' : String.fromCharCode(n);
    });

/// O texto de uma página (ou do conteúdo de um post): o que se vê, uma linha por parágrafo, e
/// os links (href) no fim, um por linha (um link pode ter a lista que o texto não mostra).
String htmlParaTexto(String html) {
  final semCodigo = html.replaceAll(_reScript, '');
  final hrefs = [for (final m in _reHref.allMatches(semCodigo)) _entidades(m[1]!)];
  final visivel = semCodigo.replaceAll(_reQuebra, '\n').replaceAll(_reEtiqueta, ' ');
  return '${_entidades(visivel)}\n${hrefs.join('\n')}';
}

final _reUrl = RegExp(r'''https?://[^\s"'<>)\]]+''', caseSensitive: false);

/// Um link de uma M3U a sério (num site há muitos outros links: menus, imagens, outros posts).
bool pareceLista(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return false;
  final caminho = u.path.toLowerCase();
  final tipo = (u.queryParameters['type'] ?? u.queryParameters['output'] ?? '').toLowerCase();
  return caminho.endsWith('.m3u') || caminho.endsWith('.m3u8') || caminho.endsWith('get.php') ||
      tipo.contains('m3u');
}

/// As listas de um texto de um site: portal + MAC (como no stbstalker), Xtream (get.php com
/// utilizador e palavra-passe) e M3U (só links que parecem playlists).
List<Conta> contasDoSite(String texto) {
  final contas = <Conta>[];
  final vistos = <String>{};
  void juntar(Conta? c) {
    if (c != null && vistos.add(chave(c))) contas.add(c);
  }

  for (final par in extrairPares(texto)) {
    juntar(contaDeLinha(par));
  }
  for (final m in _reUrl.allMatches(texto)) {
    final url = m[0]!.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
    final c = contaDeLinha(url);
    if (c == null || c.tipo == Tipo.stalker) continue;
    if (c.tipo == Tipo.xtream || pareceLista(url)) juntar(c);
  }
  return contas;
}

DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

String _legivel(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T00:00:00';

void _verSeParou(bool Function()? cancelado) {
  if (cancelado?.call() ?? false) throw Cancelado();
}

/// Um post lido de um feed: a data e o conteúdo (HTML).
typedef PostSite = ({DateTime data, String html});

/// Os posts de um blog Blogger entre as datas; null se o site não for um Blogger.
Future<List<PostSite>?> postsBlogger(String raiz, DateTime inicio, DateTime fim,
    {Duration timeout = const Duration(seconds: 15), int maxPosts = 200, bool Function()? cancelado}) async {
  final origem = Uri.parse(raiz).origin;
  final posts = <PostSite>[];
  for (var inicioIndice = 1; posts.length < maxPosts; inicioIndice += 50) {
    _verSeParou(cancelado);
    final q = Uri(queryParameters: {
      'alt': 'json',
      'max-results': '50',
      'start-index': '$inicioIndice',
      'published-min': '${_iso(inicio)}Z',
      'published-max': '${_iso(fim.add(const Duration(days: 1)))}Z',
    }).query;
    Object? r;
    try {
      r = await obterJson('$origem/feeds/posts/default?$q', headers: {'User-Agent': _ua}, timeout: timeout);
    } on Cancelado {
      rethrow;
    } catch (_) {
      if (inicioIndice == 1) return null; // não é um Blogger (ou o feed está fechado)
      break;
    }
    final feed = r is Map ? r['feed'] : null;
    if (feed is! Map) return inicioIndice == 1 ? null : posts;
    final entradas = feed['entry'];
    if (entradas is! List || entradas.isEmpty) break;
    for (final e in entradas) {
      if (e is! Map) continue;
      final data = DateTime.tryParse('${(e['published'] as Map?)?[r'$t'] ?? ''}');
      final html = '${(e['content'] as Map?)?[r'$t'] ?? (e['summary'] as Map?)?[r'$t'] ?? ''}';
      if (data != null) posts.add((data: data.toLocal(), html: html));
    }
    if (entradas.length < 50) break;
  }
  return posts;
}

/// Os posts de um site WordPress entre as datas; null se o site não for um WordPress (ou não
/// tiver a API aberta).
Future<List<PostSite>?> postsWordpress(String raiz, DateTime inicio, DateTime fim,
    {Duration timeout = const Duration(seconds: 15), int maxPosts = 200, bool Function()? cancelado}) async {
  final origem = Uri.parse(raiz).origin;
  final posts = <PostSite>[];
  for (var pagina = 1; posts.length < maxPosts; pagina++) {
    _verSeParou(cancelado);
    final q = Uri(queryParameters: {
      'after': _iso(inicio.subtract(const Duration(seconds: 1))),
      'before': _iso(fim.add(const Duration(days: 1))),
      'per_page': '50',
      'page': '$pagina',
      '_fields': 'date,content',
    }).query;
    Object? r;
    try {
      r = await obterJson('$origem/wp-json/wp/v2/posts?$q', headers: {'User-Agent': _ua}, timeout: timeout);
    } on Cancelado {
      rethrow;
    } catch (_) {
      if (pagina == 1) return null;
      break; // passou a última página (400)
    }
    if (r is! List) return pagina == 1 ? null : posts;
    if (r.isEmpty) break;
    for (final p in r) {
      if (p is! Map) continue;
      final data = DateTime.tryParse('${p['date'] ?? ''}');
      final html = '${(p['content'] as Map?)?['rendered'] ?? ''}';
      if (data != null) posts.add((data: data, html: html));
    }
    if (r.length < 50) break;
  }
  return posts;
}

/// As listas de um site: na página inicial de um Blogger ou WordPress, as dos posts publicados
/// entre as duas datas (inclusive); senão, as da página do endereço.
Future<ResultadoSite> importarSite(String url, DateTime inicio, DateTime fim,
    {Duration timeout = const Duration(seconds: 15),
    void Function(int lidas, int encontradas)? aoProgresso,
    bool Function()? cancelado}) async {
  inicio = _dia(inicio);
  fim = _dia(fim);
  if (fim.isBefore(inicio)) throw ArgumentError('a data de fim é anterior à data de início');
  final contas = <Conta>[];
  final vistos = <String>{};
  void juntar(String html) {
    for (final c in contasDoSite(htmlParaTexto(html))) {
      if (vistos.add(chave(c))) contas.add(c);
    }
  }

  if (raizDoSite(url)) {
    for (final (tipo, ler) in [(TipoSite.blogger, postsBlogger), (TipoSite.wordpress, postsWordpress)]) {
      final posts = await ler(url, inicio, fim, timeout: timeout, cancelado: cancelado);
      if (posts == null) continue;
      // só os do período (o servidor pode ignorar o filtro)
      final noPeriodo = [
        for (final p in posts)
          if (!_dia(p.data).isBefore(inicio) && !_dia(p.data).isAfter(fim)) p,
      ];
      if (noPeriodo.isEmpty) {
        final periodo = inicio == fim ? tr('em {0}', [_legivel(inicio)]) : tr('entre {0} e {1}', [_legivel(inicio), _legivel(fim)]);
        return ResultadoSite(tipo: tipo, erro: tr('Nenhum post publicado {0}.', [periodo]));
      }
      for (final (i, p) in noPeriodo.indexed) {
        _verSeParou(cancelado);
        juntar(p.html);
        aoProgresso?.call(i + 1, contas.length);
      }
      return _resultado(contas, noPeriodo.length, tipo);
    }
  }
  _verSeParou(cancelado);
  juntar(await obterTexto(url, headers: {'User-Agent': _ua}, timeout: timeout, maxBytes: 8 * 1024 * 1024));
  aoProgresso?.call(1, contas.length);
  return _resultado(contas, 1, TipoSite.pagina);
}

ResultadoSite _resultado(List<Conta> contas, int lidas, TipoSite tipo) => ResultadoSite(
      contas: contas,
      lidas: lidas,
      tipo: tipo,
      erro: contas.isEmpty
          ? (tipo == TipoSite.pagina
              ? tr('A página não tem listas (Xtream, M3U ou portal MAC) no texto.')
              : tr('Os posts do período não têm listas (Xtream, M3U ou portal MAC) no texto.'))
          : null,
    );
