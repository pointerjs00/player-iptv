import 'dart:convert';

/// O que a barra de progresso lê do mpv (de uma vez, fora da UI: ver [janelaDe]).
const propriedadesProgresso = ['time-pos', 'duration', 'seekable', 'partially-seekable', 'demuxer-cache-state'];

/// Direto ou ficheiro com fim, pelas propriedades do mpv (o mesmo para a barra de progresso e
/// para o [ContinuarDireto]). Um ficheiro deixa andar (`seekable=yes`) e não só pelo cache
/// (`partially-seekable` não é `yes`). Um direto TS no corte diz `seekable=no` (visto no
/// emulador); com o cache ligado pode dizer `seekable=yes` e `partially-seekable=yes`. Sem
/// resposta (vazio): direto.
bool eDiretoMpv({required String seekable, String partiallySeekable = ''}) =>
    seekable.trim() != 'yes' || partiallySeekable.trim() == 'yes';

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

  /// Num direto, os seeks ficam este tanto para dentro do mais antigo no cache: com o buffer para
  /// trás cheio, o mais antigo sai a cada segundo, e o seek vai à imagem-chave antes do alvo — no
  /// início exato cairia fora do cache.
  static const margemInicio = Duration(seconds: 3);

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
  double deslocado(Duration d, {double? de}) {
    final origem = _limitar(de ?? posicao);
    return _limitarAlvo(origem + d.inMicroseconds / 1e6, origem);
  }

  /// O alvo num ponto da barra (arrasto/toque).
  double alvoPorFracao(double f) => _limitarAlvo(inicio + comprimento * f.clamp(0.0, 1.0), _limitar(posicao));

  /// Dentro da janela e, num direto, a [margemInicio] para dentro do início — mas recuar nunca
  /// empurra para a frente de `origem` (já dentro da margem, fica onde está).
  double _limitarAlvo(double s, double origem) {
    final alto = fim < inicio ? inicio : fim;
    var baixo = inicio;
    if (direto) {
      final m = inicio + margemInicio.inMicroseconds / 1e6;
      baixo = m < origem ? m : origem;
    }
    return s.clamp(baixo, alto);
  }

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
  final direto = eDiretoMpv(seekable: m['seekable'] ?? '', partiallySeekable: m['partially-seekable'] ?? '');
  // um ficheiro com duração vai de 0 ao fim; sem ela (ou num direto), a janela do cache
  final filme = !direto && duracao != null && duracao > 0;

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

  // direto (ou ficheiro sem duração): o intervalo do cache que tem a posição (1 s de folga: o cache-state e o time-pos não
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
    direto: direto,
    bufferAte: fimCache?.clamp(pos, fim),
  );
}

/// O fim do intervalo procurável do cache (`seekable-ranges` do `demuxer-cache-state`) que tem
/// `pos` (1 s de folga, como em [janelaDe]): até onde um seek fica no cache. null sem intervalo.
double? fimProcuravel(String cacheState, double pos) {
  try {
    final estado = jsonDecode(cacheState);
    final r = estado is Map ? estado['seekable-ranges'] : null;
    if (r is! List) return null;
    for (final i in r) {
      if (i is Map && i['start'] is num && i['end'] is num) {
        final a = (i['start'] as num).toDouble(), b = (i['end'] as num).toDouble();
        if (pos >= a - 1 && pos <= b + 1) return b;
      }
    }
  } on FormatException {
    // sem cache-state
  }
  return null;
}

/// "00:00:02", "01:01:01" (as frações cortam-se); desconhecido: "--:--:--".
String textoTempo(Duration? d) {
  if (d == null) return '--:--:--';
  if (d.isNegative) d = Duration.zero;
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.inHours)}:${dois(d.inMinutes % 60)}:${dois(d.inSeconds % 60)}';
}
