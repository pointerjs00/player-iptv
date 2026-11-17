/// Diagnóstico da fluidez a partir das propriedades do mpv (para justificar o "lag").
library;

/// As propriedades lidas a cada segundo para as estatísticas.
const propriedadesDiagnostico = [
  'hwdec-current',
  'video-codec',
  'width',
  'height',
  'container-fps',
  'estimated-vf-fps',
  'display-fps',
  'frame-drop-count',
  'decoder-frame-drop-count',
  'demuxer-cache-duration',
  'cache-buffering-state',
  'video-bitrate',
  'paused-for-cache',
];

/// Um retrato do mpv num instante (os valores chegam como texto; os que faltam ficam nulos/0).
class AmostraMpv {
  const AmostraMpv({
    this.hwdec = '',
    this.codec = '',
    this.largura = 0,
    this.altura = 0,
    this.fpsContentor,
    this.fpsEstimado,
    this.fpsEcra,
    this.dropsSaida = 0,
    this.dropsDescodificador = 0,
    this.bufferSegundos,
    this.estadoBuffer,
    this.bitrate,
    this.pausadoParaCache = false,
  });

  factory AmostraMpv.deMapa(Map<String, String> m) {
    double? d(String k) {
      final v = double.tryParse(m[k]?.trim() ?? '');
      return v == null || v.isNaN ? null : v;
    }

    int i(String k) => d(k)?.round() ?? 0;
    return AmostraMpv(
      hwdec: m['hwdec-current']?.trim() ?? '',
      codec: m['video-codec']?.trim() ?? '',
      largura: i('width'),
      altura: i('height'),
      fpsContentor: d('container-fps'),
      fpsEstimado: d('estimated-vf-fps'),
      fpsEcra: d('display-fps'),
      dropsSaida: i('frame-drop-count'),
      dropsDescodificador: i('decoder-frame-drop-count'),
      bufferSegundos: d('demuxer-cache-duration'),
      estadoBuffer: d('cache-buffering-state')?.round(),
      bitrate: d('video-bitrate'),
      pausadoParaCache: m['paused-for-cache']?.trim() == 'yes',
    );
  }

  final String hwdec;
  final String codec;
  final int largura;
  final int altura;
  final double? fpsContentor;
  final double? fpsEstimado;
  final double? fpsEcra;

  /// Imagens perdidas na saída (o ecrã não as mostrou a tempo).
  final int dropsSaida;

  /// Imagens que o descodificador não conseguiu descodificar a tempo.
  final int dropsDescodificador;

  /// Segundos de vídeo já recebidos e à espera.
  final double? bufferSegundos;

  /// % do buffer inicial/de recuperação (100 = pronto).
  final int? estadoBuffer;

  /// bits por segundo do vídeo.
  final double? bitrate;

  /// O leitor parou à espera de dados da rede.
  final bool pausadoParaCache;
}

/// Onde está o problema de fluidez.
enum Veredicto { rede, descodificacao, ecra, fluido }

String textoVeredicto(Veredicto v) => switch (v) {
      Veredicto.rede => 'rede (buffer a esvaziar)',
      Veredicto.descodificacao => 'descodificação (imagens perdidas no descodificador)',
      Veredicto.ecra => 'ecrã (imagens perdidas na saída / 50 fps num ecrã a 60 Hz)',
      Veredicto.fluido => 'fluido',
    };

/// Abaixo disto (segundos) e a cair, o buffer está a esvaziar.
const _bufferBaixo = 3.0;

/// O veredicto a partir das últimas amostras (a mais antiga primeiro; uns 5 s chegam).
/// Prioridade: rede > descodificação > ecrã (um buffer vazio também faz perder imagens).
/// `reamostra`: o mpv acerta o ritmo ao do ecrã (`video-sync=display-resample`).
Veredicto? diagnosticar(List<AmostraMpv> amostras, {bool reamostra = false}) {
  if (amostras.isEmpty) return null;
  final primeira = amostras.first;
  final ultima = amostras.last;
  // ainda sem vídeo (a abrir, ou o canal falhou): não há fluidez a julgar
  if (ultima.largura <= 0 && ultima.fpsContentor == null && ultima.fpsEstimado == null) return null;
  final b0 = primeira.bufferSegundos;
  final b1 = ultima.bufferSegundos;
  if (ultima.pausadoParaCache || (b0 != null && b1 != null && b1 < b0 && b1 < _bufferBaixo)) {
    return Veredicto.rede;
  }
  if (ultima.dropsDescodificador > primeira.dropsDescodificador) return Veredicto.descodificacao;
  if (ultima.dropsSaida > primeira.dropsSaida) return Veredicto.ecra;
  if (!reamostra && ritmoDesfasado(ultima.fpsContentor, ultima.fpsEcra)) return Veredicto.ecra;
  return Veredicto.fluido;
}

/// O ecrã não mostra cada imagem o mesmo número de vezes (ex.: 50 fps a 60 Hz: 1 ou 2
/// refrescamentos alternadamente = judder). Desconhecido = não acusa.
bool ritmoDesfasado(double? fps, double? ecra) {
  if (fps == null || ecra == null || fps <= 0 || ecra <= 0) return false;
  final k = (ecra / fps).round();
  if (k < 1) return true;
  return (ecra - k * fps).abs() / ecra > 0.01;
}

/// As linhas da sobreposição "Estatísticas" (rótulo, valor).
List<(String, String)> linhasEstatisticas(AmostraMpv a) {
  String fps(double? v) => v == null || v <= 0 ? '—' : v.toStringAsFixed(2);
  final hw = a.hwdec.isEmpty ? '—' : (a.hwdec == 'no' ? 'software (CPU)' : 'hardware (${a.hwdec})');
  final br = a.bitrate;
  final buffer = a.bufferSegundos;
  return [
    ('Descodificação', hw),
    ('Codec', a.codec.isEmpty ? '—' : a.codec),
    ('Resolução', a.largura > 0 ? '${a.largura}×${a.altura}' : '—'),
    ('Imagens/s (canal · medido)', '${fps(a.fpsContentor)} · ${fps(a.fpsEstimado)}'),
    ('Ecrã (Hz)', fps(a.fpsEcra)),
    ('Perdidas (saída · descodificador)', '${a.dropsSaida} · ${a.dropsDescodificador}'),
    ('Buffer', buffer == null ? '—' : '${buffer.toStringAsFixed(1)} s'),
    ('Estado do buffer', a.estadoBuffer == null ? '—' : '${a.estadoBuffer}%'),
    ('Débito do vídeo', br == null || br <= 0 ? '—' : '${(br / 1e6).toStringAsFixed(1)} Mb/s'),
    ('À espera da rede', a.pausadoParaCache ? 'sim' : 'não'),
  ];
}
