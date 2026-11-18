import 'dart:io';

import 'package:flutter/foundation.dart';

import 'configuracao_mpv.dart';

/// O desentrelaçamento do player (canais 1080i/576i).
///
/// O libmpv incluído (0.36, ffmpeg 6.0 com `--disable-filters`) não tem nenhum desentrelaçador de
/// software: `deinterlace=yes` pede o `yadif`, que não existe (`filter 'yadif' not found`), e o
/// vídeo segue entrelaçado. Só o `d3d11vpp` (Windows) existe, e só para imagens d3d11 na GPU — e com
/// o ANGLE da app o mpv não carrega o `d3d11-egl`, por isso o `auto-safe` dá `d3d11va-copy` (imagens
/// na memória). No Android direto (`mediacodec_embed`) as imagens nem passam pelo mpv, e o
/// MediaCodec do aparelho pode não desentrelaçar (o do emulador não: riscas nas capturas).
///
/// Por isso o player desentrelaça com um shader dele (um campo + deteção de riscas, ver
/// [shaderMpvDesentrelacar]): no Windows no renderizador do mpv (`glsl-shaders`, à resolução da
/// imagem), no Android por cima da textura do vídeo no Flutter (`shaders/desentrelacar.frag`, que
/// serve nos dois modos). Fica-se nas 25 imagens/s do vídeo (o d3d11vpp dá 50, por campo).

/// O que se lê do mpv para decidir (de uma vez, fora da UI). No Android sem o
/// `video-frame-info`: o MediaCodec não passa a marca de entrelaçado ao mpv.
List<String> propriedadesEntrelacamento(PlataformaVideo p) => [
      if (p != PlataformaVideo.android) 'video-frame-info/interlaced',
      'height',
      'container-fps',
      'estimated-vf-fps',
      'hwdec-current',
    ];

double? _numero(String? s) => double.tryParse(s?.trim() ?? '');

/// A imagem é entrelaçada? null: ainda não se sabe (sem altura ou sem fps).
/// - Quando é o mpv a descodificar (software, `d3d11va-copy`…) a marca dele vale
///   (`video-frame-info/interlaced`; visto no Windows: RTP 1 FHD 1920x1080 25 fps -> `yes`).
/// - Com o MediaCodec (`hwdec-current` mediacodec…) o mpv não sabe: 1080/1088, 576 ou 480/486
///   linhas a 30 imagens/s ou menos é entrelaçado (é como a TV transmite; 720p e 50p são sempre
///   progressivos). Um 1080p25 progressivo também leva o shader, que só mexe onde há riscas.
bool? imagemEntrelacada(Map<String, String> m) {
  final hwdec = (m['hwdec-current'] ?? '').trim();
  final marca = (m['video-frame-info/interlaced'] ?? '').trim();
  if (!hwdec.startsWith('mediacodec') && (marca == 'yes' || marca == 'no')) return marca == 'yes';
  final altura = _numero(m['height']);
  var fps = _numero(m['container-fps']);
  if (fps == null || fps <= 0) fps = _numero(m['estimated-vf-fps']);
  if (altura == null || altura <= 0 || fps == null || fps <= 0) return null;
  const linhas = [480, 486, 576, 1080, 1088];
  return linhas.contains(altura.round()) && fps <= 30.5;
}

enum MeioDesentrelacamento {
  /// Desligado, imagem progressiva ou sem meio neste aparelho.
  nenhum,

  /// Windows com imagens d3d11va na GPU: `deinterlace=yes` (o mpv põe o `d3d11vpp`, por campo).
  d3d11vpp,

  /// Windows: o shader no renderizador do mpv (`glsl-shaders`).
  shaderMpv,

  /// Android: o shader do Flutter por cima da textura do vídeo.
  shaderFlutter,
}

/// Como desentrelaçar. `shaderFlutter`: o Flutter permite o shader (Impeller).
MeioDesentrelacamento meioDesentrelacamento(PlataformaVideo p,
    {required bool ligado, required bool? entrelacada, required String hwdec, required bool shaderFlutter}) {
  if (!ligado || entrelacada != true) return MeioDesentrelacamento.nenhum;
  if (p == PlataformaVideo.android) return shaderFlutter ? MeioDesentrelacamento.shaderFlutter : MeioDesentrelacamento.nenhum;
  return hwdec.trim() == 'd3d11va' ? MeioDesentrelacamento.d3d11vpp : MeioDesentrelacamento.shaderMpv;
}

/// Põe o meio no mpv (só o Windows usa o mpv; no Android garante que fica sem nada). Nunca lança.
Future<void> aplicarMeioMpv(MotorMpv mpv, MeioDesentrelacamento m, {required String? caminhoShader}) async {
  try {
    if (m == MeioDesentrelacamento.d3d11vpp) {
      await mpv.setProperty('glsl-shaders', '');
      await mpv.setProperty('deinterlace', 'yes');
      return;
    }
    await mpv.setProperty('deinterlace', 'no');
    await mpv.setProperty(
        'glsl-shaders', m == MeioDesentrelacamento.shaderMpv && caminhoShader != null ? caminhoShader : '');
  } catch (e) {
    debugPrint('mpv: desentrelaçamento não aplicado ($e)');
  }
}

/// O que as estatísticas mostram.
String textoDesentrelacamento(MeioDesentrelacamento m, {required bool ligado, required bool? entrelacada}) =>
    switch (m) {
      MeioDesentrelacamento.d3d11vpp => 'ligado (d3d11vpp, por campo)',
      MeioDesentrelacamento.shaderMpv || MeioDesentrelacamento.shaderFlutter => 'ligado (shader do player)',
      MeioDesentrelacamento.nenhum when !ligado => 'desligado',
      MeioDesentrelacamento.nenhum when entrelacada == null => 'à espera da imagem',
      MeioDesentrelacamento.nenhum when entrelacada == false => 'desligado (imagem progressiva)',
      MeioDesentrelacamento.nenhum => 'indisponível neste aparelho',
    };

/// Escreve o [shaderMpvDesentrelacar] em `pasta` e devolve o caminho (null se falhar).
Future<String?> escreverShaderMpv(Directory pasta) async {
  try {
    final f = File('${pasta.path}${Platform.pathSeparator}desentrelacar.glsl');
    await f.writeAsString(shaderMpvDesentrelacar, flush: true);
    return f.path.contains(';') ? null : f.path;
  } catch (e) {
    debugPrint('desentrelaçamento: shader não escrito ($e)');
    return null;
  }
}

/// O shader do mpv (hook MAIN: a imagem à resolução dela, antes de ser escalada). Testado no libmpv
/// da app no Windows (render API sobre o ANGLE): as riscas de um canal 1080i desaparecem e as
/// zonas paradas ficam como estavam.
const shaderMpvDesentrelacar = r"""//!HOOK MAIN
//!BIND HOOKED
//!DESC desentrelacamento (campo + deteccao de riscas)

// Imagem entrelaçada: as linhas pares são de um campo, as ímpares do outro (outro instante). Onde
// uma linha ímpar não bate com as pares à volta mas bate com as ímpares (riscas de movimento), é
// trocada por uma interpolação das pares (seguindo a direção da aresta); onde não há riscas
// (imagem parada) fica a linha original, com a resolução toda.
float luz(vec4 c) { return dot(c.rgb, vec3(0.299, 0.587, 0.114)); }

vec4 hook() {
    float linha = floor(HOOKED_pos.y * HOOKED_size.y);
    vec4 c = HOOKED_texOff(vec2(0.0, 0.0));
    if (mod(linha, 2.0) < 0.5) return c;
    vec4 a = HOOKED_texOff(vec2(0.0, -1.0));
    vec4 b = HOOKED_texOff(vec2(0.0, 1.0));
    float lc = luz(c), la = luz(a), lb = luz(b);
    float la2 = luz(HOOKED_texOff(vec2(0.0, -2.0)));
    float lb2 = luz(HOOKED_texOff(vec2(0.0, 2.0)));
    // quanto a linha sai das vizinhas do outro campo, menos quanto sai das do seu campo
    float fora = abs(lc - 0.5 * (la + lb)) - 0.5 * abs(la - lb);
    float proprio = abs(lc - 0.5 * (la2 + lb2));
    float riscas = smoothstep(0.012, 0.04, fora - 0.5 * proprio);
    if (riscas <= 0.0) return c;
    // interpolação na direção da aresta (-1, 0, +1)
    vec4 al = HOOKED_texOff(vec2(-1.0, -1.0)), ar = HOOKED_texOff(vec2(1.0, -1.0));
    vec4 bl = HOOKED_texOff(vec2(-1.0, 1.0)), br = HOOKED_texOff(vec2(1.0, 1.0));
    float d0 = abs(la - lb), d1 = abs(luz(al) - luz(br)), d2 = abs(luz(ar) - luz(bl));
    vec4 m = 0.5 * (a + b);
    if (d1 < d0 && d1 <= d2) m = 0.5 * (al + br);
    else if (d2 < d0) m = 0.5 * (ar + bl);
    m = clamp(m, min(a, b), max(a, b));
    return mix(c, m, riscas);
}
""";
