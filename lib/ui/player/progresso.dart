import 'dart:convert';

/// O que a barra de progresso lê do mpv (de uma vez, fora da UI: ver [janelaDe]).
const propriedadesProgresso = ['time-pos', 'duration', 'seekable', 'partially-seekable', 'demuxer-cache-state'];

/// A parte do vídeo por onde se pode andar, em segundos do mpv (os do `time-pos`).
/// - Filme (seekable, duração conhecida): de 0 à duração.
/// - Direto (ou duração desconhecida): o que o mpv tem no cache — do mais antigo guardado para
///   trás (`demuxer-max-back-bytes`) ao mais recente recebido (o direto mais o readahead).
class JanelaProgresso {
  const JanelaProgresso({
    required this.inicio,
    required this.fim,
    required this.posicao,
    required this.direto,
    this.bufferAte,
  });

  final double inicio;
  final double fim;

  /// O `time-pos` (dentro de [inicio, fim]).
  final double posicao;

  /// Direto: os seeks ficam no cache (pelo [SaltosDireto]); filme: seek absoluto.
  final bool direto;

  /// Até onde há dados à frente (o `cache-end`), se se sabe.
  final double? bufferAte;

  double get comprimento => fim - inicio;

  /// O tempo à esquerda: a posição contada do início da janela.
  Duration get decorrido => decorridoEm(posicao);

  /// O tempo à direita: a duração (filme) ou o comprimento da janela (direto).
  Duration get total => _duracao(comprimento);

  Duration decorridoEm(double segundos) => _duracao(_limitar(segundos) - inicio);

  /// Onde fica `segundos` na barra (0–1).
  double fracao(double segundos) => comprimento <= 0 ? 0 : (_limitar(segundos) - inicio) / comprimento;

  /// Até onde vai a parte "já recebida" da barra (0–1; sem cache-end, a posição).
  double get fracaoBuffer => fracao(bufferAte ?? posicao);

  /// O alvo de um seek de `d` a partir da posição (ou de `de`: um alvo ainda a caminho).
  double deslocado(Duration d, {double? de}) => _limitar((de ?? posicao) + d.inMicroseconds / 1e6);

  /// O alvo num ponto da barra (arrasto/toque).
  double alvoPorFracao(double f) => inicio + comprimento * f.clamp(0.0, 1.0);

  double _limitar(double s) => s.clamp(inicio, fim < inicio ? inicio : fim);

  static Duration _duracao(double s) => Duration(microseconds: (s < 0 ? 0 : s * 1e6).round());
}

double? _numero(String? v) {
  final n = double.tryParse(v?.trim() ?? '');
  return n != null && n.isFinite ? n : null;
}

/// A janela a partir das [propriedadesProgresso] (texto; "" quando o mpv não sabe). null sem
/// posição (o canal a abrir).
JanelaProgresso? janelaDe(Map<String, String> m) {
  final pos = _numero(m['time-pos']);
  if (pos == null) return null;
  final duracao = _numero(m['duration']);
  // com o cache ligado o mpv diz `seekable` num direto, mas também `partially-seekable` (só pelo
  // cache); um filme tem duração
  final filme = m['seekable']?.trim() == 'yes' && m['partially-seekable']?.trim() != 'yes' &&
      duracao != null && duracao > 0;

  double? fimCache;
  final intervalos = <(double, double)>[];
  try {
    final estado = jsonDecode(m['demuxer-cache-state'] ?? '');
    if (estado is Map) {
      final f = estado['cache-end'];
      if (f is num) fimCache = f.toDouble();
      final r = estado['seekable-ranges'];
      if (r is List) {
        for (final i in r) {
          if (i is Map && i['start'] is num && i['end'] is num) {
            intervalos.add(((i['start'] as num).toDouble(), (i['end'] as num).toDouble()));
          }
        }
      }
    }
  } on FormatException {
    // sem cache-state (ou ilegível): só o que se sabe
  }

  if (filme) {
    final p = pos.clamp(0.0, duracao);
    return JanelaProgresso(
      inicio: 0,
      fim: duracao,
      posicao: p,
      direto: false,
      bufferAte: fimCache?.clamp(p, duracao),
    );
  }

  // direto: o intervalo do cache que tem a posição (1 s de folga: o cache-state e o time-pos não
  // são lidos no mesmo instante); senão o mais recente
  const folga = 1.0;
  final i = intervalos.indexWhere((r) => pos >= r.$1 - folga && pos <= r.$2 + folga);
  final escolhido = i >= 0 ? i : intervalos.length - 1;
  final (a, b) = escolhido >= 0 ? intervalos[escolhido] : (pos, pos);
  final inicio = a < pos ? a : pos;
  var fim = b > pos ? b : pos;
  // o cache-end é do intervalo que está a ser lido (o mais recente): só esse cresce com ele
  final aLer = escolhido == intervalos.length - 1;
  if (aLer && fimCache != null && fimCache > fim) fim = fimCache;
  return JanelaProgresso(
    inicio: inicio,
    fim: fim,
    posicao: pos,
    direto: true,
    bufferAte: fimCache?.clamp(pos, fim),
  );
}

/// "00:00:02", "01:01:01" (as frações cortam-se); desconhecido: "--:--:--".
String textoTempo(Duration? d) {
  if (d == null) return '--:--:--';
  if (d.isNegative) d = Duration.zero;
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.inHours)}:${dois(d.inMinutes % 60)}:${dois(d.inSeconds % 60)}';
}
