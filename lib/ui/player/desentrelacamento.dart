import 'dart:io';

import 'package:flutter/foundation.dart';

import 'configuracao_mpv.dart';

/// O desentrelaçamento do player (canais 1080i/576i).
///
/// Com um libmpv **completo** (mpv 0.40+ com o ffmpeg com filtros: ver `third_party/libmpv_completo`)
/// desentrelaça-se com o `bwdif` do ffmpeg em modo `send_field`: uma imagem por campo, 25i -> 50
/// imagens/s (o que o "sfvip player" faz), só nas imagens marcadas como entrelaçadas
/// (`deint=interlaced`). No Windows serve com descodificação por software e `d3d11va-copy`; no
/// Android só fora do modo direto (`vo=mediacodec_embed`: as imagens nem passam pelo mpv), por isso
/// um canal entrelaçado no direto reabre-se em Compatível (`mediacodec-copy` + `vo=gpu`; o MediaCodec
/// não marca o entrelaçado, aí o filtro leva `deint=all`, e só se chega lá com a regra das linhas).
///
/// O libmpv mínimo do media_kit (0.36, `--disable-filters`) não tem nenhum: `deinterlace=yes` pede o
/// `yadif`, que não existe (`filter 'yadif' not found`). Aí fica o shader do player (um campo +
/// deteção de riscas, ver [shaderMpvDesentrelacar]): no Windows no renderizador do mpv
/// (`glsl-shaders`), no Android por cima da textura do vídeo no Flutter (`shaders/desentrelacar.frag`).
/// O shader fica nas 25 imagens/s do vídeo. O `d3d11vpp` (imagens d3d11 na GPU, por campo) só entra
/// se o hwdec for mesmo `d3d11va`: com o ANGLE da app o mpv dá `d3d11va-copy`.

/// O que se lê do mpv para decidir (de uma vez, fora da UI). No Android sem o
/// `video-frame-info`: o MediaCodec não passa a marca de entrelaçado ao mpv.
List<String> propriedadesEntrelacamento(PlataformaVideo p) => [
      'mpv-version',
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

/// O libmpv tem os filtros do ffmpeg (`bwdif`)? Os builds completos são mpv 0.40+; o mínimo do
/// media_kit é 0.36 (`mpv-version` = "mpv v0.42.0-38-g…").
bool filtrosDoMpv(String? versao) {
  final m = RegExp(r'v?(\d+)\.(\d+)').firstMatch(versao ?? '');
  if (m == null) return false;
  final maior = int.parse(m[1]!), menor = int.parse(m[2]!);
  return maior > 0 || menor >= 40;
}

/// O `vf` do desentrelaçamento: o bwdif por campo (`send_field`: 25i -> 50 imagens/s). Só nas imagens
/// que o mpv marca como entrelaçadas; o MediaCodec não as marca, aí vão todas (só se chega cá com a
/// regra das linhas de [imagemEntrelacada]).
String filtroDesentrelacamento(String hwdec) =>
    'bwdif=mode=send_field:deint=${hwdec.trim().startsWith('mediacodec') ? 'all' : 'interlaced'}';

/// O Android no modo direto com imagem entrelaçada e filtros no libmpv: o filtro não se aplica no
/// direto, o canal tem de reabrir em Compatível (uma vez por canal, ver `CompativelNaSessao`).
bool precisaModoComFiltro(PlataformaVideo p,
        {required bool ligado, required bool? entrelacada, required bool filtros, required bool direto}) =>
    p == PlataformaVideo.android && ligado && entrelacada == true && filtros && direto;

/// Com o filtro no `vf` a imagem que sai do mpv já é progressiva (`video-frame-info/interlaced` passa a
/// `no`): não se reavalia a partir dela, senão o filtro ligava e desligava a cada verificação.
bool? entrelacadaDepois(MeioDesentrelacamento atual, bool? anterior, bool? lida) =>
    atual == MeioDesentrelacamento.filtroMpv ? (anterior ?? lida) : (lida ?? anterior);

/// Com o filtro posto o mpv deixou de ter imagem (altura vazia): o filtro não funcionou aqui; volta-se
/// ao shader.
bool filtroFalhou(MeioDesentrelacamento atual, Map<String, String> m) =>
    atual == MeioDesentrelacamento.filtroMpv && (_numero(m['height']) ?? 0) <= 0;

enum MeioDesentrelacamento {
  /// Desligado, imagem progressiva ou sem meio neste aparelho.
  nenhum,

  /// O `bwdif` do ffmpeg por campo (`vf`), 50 imagens/s: libmpv completo, Windows ou Android
  /// fora do modo direto.
  filtroMpv,

  /// Windows com imagens d3d11va na GPU: `deinterlace=yes` (o mpv põe o `d3d11vpp`, por campo).
  d3d11vpp,

  /// Windows: o shader no renderizador do mpv (`glsl-shaders`).
  shaderMpv,

  /// Android: o shader do Flutter por cima da textura do vídeo.
  shaderFlutter,
}

/// Como desentrelaçar. `shaderFlutter`: o Flutter permite o shader (Impeller).
MeioDesentrelacamento meioDesentrelacamento(PlataformaVideo p,
    {required bool ligado,
    required bool? entrelacada,
    required String hwdec,
    required bool shaderFlutter,
    bool filtros = false,
    bool direto = false}) {
  if (!ligado || entrelacada != true) return MeioDesentrelacamento.nenhum;
  if (p == PlataformaVideo.android) {
    if (filtros && !direto) return MeioDesentrelacamento.filtroMpv;
    return shaderFlutter ? MeioDesentrelacamento.shaderFlutter : MeioDesentrelacamento.nenhum;
  }
  if (hwdec.trim() == 'd3d11va') return MeioDesentrelacamento.d3d11vpp;
  return filtros ? MeioDesentrelacamento.filtroMpv : MeioDesentrelacamento.shaderMpv;
}

/// Põe o meio no mpv (o shader e os filtros só correm no mpv; o do Flutter deixa-o sem nada).
/// Nunca lança. `hwdec`: o `hwdec-current` (decide o `deint` do filtro).
Future<void> aplicarMeioMpv(MotorMpv mpv, MeioDesentrelacamento m,
    {required String? caminhoShader, String hwdec = ''}) async {
  try {
    if (m == MeioDesentrelacamento.filtroMpv) {
      await mpv.setProperty('glsl-shaders', '');
      await mpv.setProperty('deinterlace', 'no');
      await mpv.setProperty('vf', filtroDesentrelacamento(hwdec));
      return;
    }
    await mpv.setProperty('vf', '');
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
      MeioDesentrelacamento.filtroMpv => 'ligado (bwdif, por campo)',
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
