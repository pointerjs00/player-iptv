/// Importação de listas publicadas num canal público do Telegram (a página `t.me/s/<canal>`,
/// sem conta nem chave). Lê o texto das mensagens entre duas datas e reaproveita a leitura de
/// linhas (Xtream, M3U) e de pares "portal MAC" já usada no resto da app.
library;

import '../modelo/conta.dart';
import '../rede/http.dart';
import '../idioma/idioma.dart';
import 'stbstalker.dart' show extrairPares;

/// O canal sugerido por omissão (o campo fica aberto a outros canais públicos).
const telegramCanalOmissao = 'michelstv4';

/// O prefixo da página pública de um canal: `$telegramBase<canal>`. Um teste aponta-o a um
/// servidor local.
const telegramBase = 'https://t.me/s/';

const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

/// Nomes de utilizador do Telegram: 5–32 letras/dígitos/_, começados por letra.
final _reCanal = RegExp(r'^[A-Za-z][A-Za-z0-9_]{4,31}$');
final _reNaUrl = RegExp(r'(?:t|telegram)\.me/(?:s/)?@?([A-Za-z0-9_]+)', caseSensitive: false);
/// Cada mensagem começa num `tgme_widget_message_wrap`: divide-se a página aí.
final _reInicioMensagem = RegExp(r'<div class="tgme_widget_message_wrap', caseSensitive: false);
final _reId = RegExp(r'data-post="[^"/]+/(\d+)"', caseSensitive: false);
final _reData = RegExp(r'datetime="([^"]+)"');
final _reTexto = RegExp(
    r'tgme_widget_message_text[^>]*>([\s\S]*?)</div>',
    caseSensitive: false);
final _reHref = RegExp(r'href="([^"]*)"', caseSensitive: false);

typedef MensagemTelegram = ({int id, DateTime data, String texto});

class ResultadoTelegram {
  ResultadoTelegram({this.contas = const [], this.mensagens = 0, this.erro});
  final List<Conta> contas;
  final int mensagens;
  final String? erro;
}

/// O nome do canal a partir do que o utilizador escreveu (`@nome`, `t.me/nome`, `t.me/s/nome`,
/// um link completo ou só `nome`); null se não parecer um nome de canal.
String? canalDeTexto(String entrada) {
  var t = entrada.trim();
  if (t.isEmpty) return null;
  final naUrl = _reNaUrl.firstMatch(t);
  if (naUrl != null) t = naUrl[1]!;
  t = t.replaceFirst(RegExp(r'^@'), '');
  return _reCanal.hasMatch(t) ? t : null;
}

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

/// O texto de uma mensagem: o conteúdo visível mais os links (href), um por linha. Os links
/// entram porque o Telegram corta o texto visível dos muito compridos.
String _textoDaMensagem(String htmlMensagem) {
  final bloco = _reTexto.firstMatch(htmlMensagem);
  if (bloco == null) return '';
  final interno = bloco[1]!;
  final hrefs = [for (final m in _reHref.allMatches(interno)) _desescapar(m[1]!)];
  var visivel = interno.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  visivel = visivel.replaceAll(RegExp(r'<[^>]+>', dotAll: true), '');
  return _desescapar('$visivel\n${hrefs.join('\n')}');
}

/// As contas (Xtream, M3U, portal MAC) do texto de uma mensagem. Ignora os links para o próprio
/// Telegram e as listas repetidas dentro da mensagem.
List<Conta> contasDaMensagem(String texto) {
  final contas = <Conta>[];
  final vistos = <String>{};
  void juntar(Conta? c) {
    if (c == null) return;
    final h = hostDe(c.endereco).toLowerCase();
    if (h.isEmpty || h == 't.me' || h.endsWith('telegram.me') || h.endsWith('telegram.org')) return;
    if (vistos.add(chave(c))) contas.add(c);
  }

  // "portal MAC" em linhas separadas (como no stbstalker)
  for (final par in extrairPares(texto)) {
    juntar(contaDeLinha(par));
  }
  // Xtream e M3U, uma lista por linha (o portal já foi tratado acima)
  for (final linha in texto.split(RegExp(r'\r\n|\r|\n'))) {
    final c = contaDeLinha(linha);
    if (c != null && c.tipo != Tipo.stalker) juntar(c);
  }
  return contas;
}

/// As mensagens de uma página (id, data e texto), da mais recente para a mais antiga.
List<MensagemTelegram> mensagensDaPagina(String html) {
  final out = <MensagemTelegram>[];
  final inicios = [for (final m in _reInicioMensagem.allMatches(html)) m.start, html.length];
  for (var i = 0; i < inicios.length - 1; i++) {
    final bloco = html.substring(inicios[i], inicios[i + 1]);
    final idM = _reId.firstMatch(bloco), dM = _reData.firstMatch(bloco);
    final id = idM == null ? null : int.tryParse(idM[1]!);
    final data = dM == null ? null : DateTime.tryParse(dM[1]!);
    if (id == null || data == null) continue;
    out.add((id: id, data: data.toLocal(), texto: _textoDaMensagem(bloco)));
  }
  out.sort((a, b) => b.id.compareTo(a.id));
  return out;
}

Future<String> _ler(String url, Duration timeout) =>
    obterTexto(url, headers: {'User-Agent': _ua}, timeout: timeout, maxBytes: 8 * 1024 * 1024);

DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

String _legivel(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

void _verSeParou(bool Function()? cancelado) {
  if (cancelado?.call() ?? false) throw Cancelado();
}

/// Junta ao Gestor as listas das mensagens do canal publicadas entre as duas datas (inclusive).
///
/// `aoProgresso(mensagens lidas, listas encontradas)` diz como vai a leitura. Com `cancelado` a
/// devolver true, pára com [Cancelado] antes da página seguinte.
Future<ResultadoTelegram> importarTelegram(String canal, DateTime inicio, DateTime fim,
    {String base = telegramBase,
    Duration timeout = const Duration(seconds: 15),
    int maxPaginas = 40,
    void Function(int lidas, int encontradas)? aoProgresso,
    bool Function()? cancelado}) async {
  inicio = _dia(inicio);
  fim = _dia(fim);
  if (fim.isBefore(inicio)) throw ArgumentError('a data de fim é anterior à data de início');
  final contas = <Conta>[];
  final vistos = <String>{};
  var lidas = 0;
  int? antesDe;
  for (var pagina = 0; pagina < maxPaginas; pagina++) {
    _verSeParou(cancelado);
    final url = '$base$canal${antesDe == null ? '' : '?before=$antesDe'}';
    final List<MensagemTelegram> mensagens;
    try {
      mensagens = mensagensDaPagina(await _ler(url, timeout));
    } catch (e) {
      if (pagina == 0) rethrow; // canal inexistente ou sem rede
      break; // uma página antiga que não abre não apaga o que já se leu
    }
    if (mensagens.isEmpty) break;
    for (final m in mensagens) {
      final d = _dia(m.data);
      if (d.isAfter(fim) || d.isBefore(inicio)) continue;
      lidas++;
      for (final c in contasDaMensagem(m.texto)) {
        if (vistos.add(chave(c))) contas.add(c);
      }
    }
    aoProgresso?.call(lidas, contas.length);
    // a página mais antiga já passou o início, ou o `before` não avança: pára de recuar
    final maisAntiga = mensagens.last;
    if (_dia(maisAntiga.data).isBefore(inicio) || antesDe == maisAntiga.id) break;
    antesDe = maisAntiga.id;
  }
  if (lidas == 0) {
    final periodo = inicio == fim ? tr('em {0}', [_legivel(inicio)]) : tr('entre {0} e {1}', [_legivel(inicio), _legivel(fim)]);
    return ResultadoTelegram(erro: tr('Nenhuma mensagem publicada {0}.', [periodo]));
  }
  _verSeParou(cancelado);
  return ResultadoTelegram(contas: contas, mensagens: lidas);
}
