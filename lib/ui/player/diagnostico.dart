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
  'video-sync',
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
    this.sincronizacao = '',
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
      sincronizacao: m['video-sync']?.trim() ?? '',
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

  /// `video-sync` do mpv (ex.: `audio`, `display-resample`).
  final String sincronizacao;

  /// O mpv está mesmo a acertar o ritmo ao ecrã: pediu-se `display-*` e ele sabe os Hz do ecrã
  /// (no Windows com `vo=libmpv` não sabe, e volta a sincronizar pelo áudio).
  bool get reamostraAtiva => sincronizacao.startsWith('display-') && (fpsEcra ?? 0) > 0;
}

/// Onde está o problema de fluidez.
enum Veredicto { rede, descodificacao, ecra, fluido }

String textoVeredicto(Veredicto v) => switch (v) {
      Veredicto.rede => 'rede (buffer a esvaziar)',
      Veredicto.descodificacao => 'descodificação (imagens perdidas no descodificador)',
      Veredicto.ecra => 'ecrã (imagens perdidas na saída / 50 fps num ecrã a 60 Hz)',
      Veredicto.fluido => 'fluido',
    };

/// Amostras precisas para um veredicto (~3 s): logo a seguir a abrir/zapping ainda se mede.
const amostrasMinimas = 3;

/// Perdas na janela abaixo disto são ruído (uma imagem perdida de vez em quando).
const _perdasMinimas = 2;

/// O veredicto a partir das últimas amostras (a mais antiga primeiro; ~5 s), só com condições
/// que se mantêm: parado à espera da rede em 2 amostras seguidas, ou o buffer a cair ≥ 1 s até
/// menos de 1,5 s; ≥ 2 perdas na janela. Prioridade: rede > descodificação > ecrã (um buffer
/// vazio também faz perder imagens). `hzEcra`: os Hz do ecrã segundo o sistema, para quando o mpv
/// não os sabe (`mediacodec_embed` no Android). Sem vídeo ou poucas amostras: null.
Veredicto? diagnosticar(List<AmostraMpv> amostras, {double? hzEcra}) {
  if (amostras.isEmpty) return null;
  final primeira = amostras.first;
  final ultima = amostras.last;
  // ainda sem vídeo (a abrir, ou o canal falhou): não há fluidez a julgar
  if (ultima.largura <= 0 && ultima.fpsContentor == null && ultima.fpsEstimado == null) return null;
  if (amostras.length < amostrasMinimas) return null;
  final penultima = amostras[amostras.length - 2];
  final b0 = primeira.bufferSegundos;
  final b1 = ultima.bufferSegundos;
  if ((ultima.pausadoParaCache && penultima.pausadoParaCache) ||
      (b0 != null && b1 != null && b0 - b1 >= 1 && b1 < 1.5)) {
    return Veredicto.rede;
  }
  if (ultima.dropsDescodificador - primeira.dropsDescodificador >= _perdasMinimas) return Veredicto.descodificacao;
  if (ultima.dropsSaida - primeira.dropsSaida >= _perdasMinimas) return Veredicto.ecra;
  if (!ultima.reamostraAtiva && ritmoDesfasado(ultima.fpsContentor, ultima.fpsEcra ?? hzEcra)) return Veredicto.ecra;
  return Veredicto.fluido;
}

/// Descodificação direta (`mediacodec_embed`) sem imagem: o vídeo está a ser descodificado
/// (`video-codec` conhecido, `larguraVista` > 0) mas o mpv passou para software (`hwdec-current`
/// = "no": o `mediacodec_embed` só mostra imagens do MediaCodec) ou a saída de vídeo falhou
/// (`vo-configured` = "no"). Ouve-se o som com o ecrã preto. Canais só de som não contam.
///
/// Só com prova: uma propriedade vazia quer dizer que o mpv não respondeu a tempo (pedido sem
/// resposta) ou que o vídeo ainda está a arrancar, não que não há imagem.
bool semImagemDireta({required int larguraVista, required Map<String, String> propriedades}) {
  if (larguraVista <= 0) return false;
  final hw = propriedades['hwdec-current']?.trim() ?? '';
  final codec = propriedades['video-codec']?.trim() ?? '';
  final vo = propriedades['vo-configured']?.trim() ?? '';
  if (codec.isEmpty) return false;
  return hw == 'no' || vo == 'no';
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
List<(String, String)> linhasEstatisticas(AmostraMpv a, {double? hzEcra}) {
  String fps(double? v) => v == null || v <= 0 ? '—' : v.toStringAsFixed(2);
  final hw = a.hwdec.isEmpty ? '—' : (a.hwdec == 'no' ? 'software (CPU)' : 'hardware (${a.hwdec})');
  final br = a.bitrate;
  final buffer = a.bufferSegundos;
  return [
    ('Descodificação', hw),
    ('Codec', a.codec.isEmpty ? '—' : a.codec),
    ('Resolução', a.largura > 0 ? '${a.largura}×${a.altura}' : '—'),
    ('Imagens/s (canal · medido)', '${fps(a.fpsContentor)} · ${fps(a.fpsEstimado)}'),
    ('Ecrã (Hz)', a.fpsEcra != null || hzEcra == null ? fps(a.fpsEcra) : '${fps(hzEcra)} (sistema)'),
    ('Perdidas (saída · descodificador)', '${a.dropsSaida} · ${a.dropsDescodificador}'),
    ('Buffer', buffer == null ? '—' : '${buffer.toStringAsFixed(1)} s'),
    ('Estado do buffer', a.estadoBuffer == null ? '—' : '${a.estadoBuffer}%'),
    ('Débito do vídeo', br == null || br <= 0 ? '—' : '${(br / 1e6).toStringAsFixed(1)} Mb/s'),
    ('À espera da rede', a.pausadoParaCache ? 'sim' : 'não'),
  ];
}
