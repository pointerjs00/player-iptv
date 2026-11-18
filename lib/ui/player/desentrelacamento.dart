import 'dart:io';

import 'package:flutter/foundation.dart';

import 'configuracao_mpv.dart';
import 'progresso.dart' show eDiretoMpv;

/// O desentrelaçamento do player (canais 1080i/576i/480i).
///
/// Com um libmpv **completo** (mpv 0.40+ com o ffmpeg com filtros: ver `third_party/libmpv_completo`)
/// desentrelaça-se com o `bwdif` do ffmpeg em modo `send_field`: uma imagem por campo, 25i -> 50
/// imagens/s (30i -> 60), como o "sfvip player", e só nas imagens marcadas como entrelaçadas
/// (`deint=interlaced`). No Windows serve com descodificação por software e `d3d11va-copy` (as
/// imagens d3d11va na GPU levam o `d3d11vpp`). No Android só fora do modo direto
/// (`vo=mediacodec_embed`: as imagens nem passam pelo mpv), por isso um direto entrelaçado reabre-se
/// em Compatível (`mediacodec-copy` + `vo=gpu`). O MediaCodec não marca as imagens entrelaçadas: aí
/// o `idet` do ffmpeg vê as riscas e marca-as antes do bwdif (um progressivo passa sem mexer, a 25).
///
/// Se o filtro não existe (o libmpv mínimo do media_kit, 0.36, `--disable-filters`: o mpv recusa o
/// `vf` com -9) ou não faz efeito (medido: a saída fica nas imagens/s da entrada), volta o shader do
/// player (um campo + deteção de riscas, ver [shaderMpvDesentrelacar]): no Windows no renderizador do
/// mpv (`glsl-shaders`), no Android por cima da textura do vídeo no Flutter
/// (`shaders/desentrelacar.frag`). O shader fica nas 25 imagens/s do vídeo.

/// O texto das definições: as imagens/s por campo dependem do libmpv e do aparelho (sem o filtro, o
/// shader limpa as linhas às imagens/s do canal).
const textoDefinicaoDesentrelacamento = 'Limpa as linhas dos canais entrelaçados (1080i/576i/480i). Por campo, '
    'quando o aparelho o permite: até 50 imagens/s (60 nos 480i); senão às imagens/s do canal.';

/// O rótulo do `idet` no `vf` (Android): o mpv dá o que ele contou em `vf-metadata/<rótulo>`.
const rotuloIdet = 'pidet';

/// O que se lê do mpv para decidir (de uma vez, fora da UI). `core-idle`/`eof-reached`: uma leitura
/// em pausa, a carregar ou no fim do buffer (corte do servidor) não diz nada do filtro; `vf`: se o
/// mpv ainda o tem. No Android `seekable` (um direto ou um filme) e o que o idet contou.
List<String> propriedadesEntrelacamento(PlataformaVideo p) => [
      'mpv-version',
      'video-frame-info/interlaced',
      'height',
      'container-fps',
      'estimated-vf-fps',
      'hwdec-current',
      'core-idle',
      'eof-reached',
      'vf',
      if (p == PlataformaVideo.android) ...['seekable', 'partially-seekable', 'vf-metadata/$rotuloIdet'],
    ];

double? _numero(String? s) => double.tryParse(s?.trim() ?? '');

double? _fps(Map<String, String> m) {
  final c = _numero(m['container-fps']);
  return c != null && c > 0 ? c : _numero(m['estimated-vf-fps']);
}

const _linhasEntrelacadas = [480, 486, 576, 1080, 1088];

/// A imagem é entrelaçada? null: ainda não se sabe (sem altura ou sem fps).
/// - Quando é o mpv a descodificar (software, `d3d11va-copy`…) a marca dele vale
///   (`video-frame-info/interlaced`; visto no Windows: RTP 1 FHD 1920x1080 25 fps -> `yes`).
/// - Com o MediaCodec (`hwdec-current` mediacodec…) o mpv não sabe: 1080/1088, 576 ou 480/486
///   linhas a 30 imagens/s ou menos pode ser entrelaçado (é como a TV transmite; 720p e 50p são
///   sempre progressivos). Serve para o shader do Flutter, que só mexe onde há riscas; para reabrir
///   em Compatível conta a regra mais estreita de [pareceEntrelacadaNoDireto].
bool? imagemEntrelacada(Map<String, String> m) {
  final hwdec = (m['hwdec-current'] ?? '').trim();
  final marca = (m['video-frame-info/interlaced'] ?? '').trim();
  if (!hwdec.startsWith('mediacodec') && (marca == 'yes' || marca == 'no')) return marca == 'yes';
  final altura = _numero(m['height']);
  final fps = _fps(m);
  if (altura == null || altura <= 0 || fps == null || fps <= 0) return null;
  return _linhasEntrelacadas.contains(altura.round()) && fps <= 30.5;
}

/// Android no modo direto (o mpv não vê as imagens): vale a pena reabrir em Compatível para o filtro?
/// Só um direto (`seekable` não; os filmes VOD são quase sempre progressivos) com as linhas da TV
/// entrelaçada (1080/576/480) a 25 ou 30 (29,97) imagens/s, as cadências das emissões 50i/60i. Um
/// filme a 24/23,976 fica no direto. O que não se sabe aqui (um 1080p25 progressivo) decide-o o idet
/// já em Compatível, e o canal volta ao direto da próxima vez (`CompativelNaSessao.progressivo`).
bool pareceEntrelacadaNoDireto(Map<String, String> m) {
  // como a barra de progresso: um direto com o cache ligado pode dizer seekable=yes e
  // partially-seekable=yes (ver eDiretoMpv)
  if (!eDiretoMpv(seekable: m['seekable'] ?? '', partiallySeekable: m['partially-seekable'] ?? '')) return false;
  final altura = _numero(m['height']);
  final fps = _fps(m);
  if (altura == null || fps == null || !_linhasEntrelacadas.contains(altura.round())) return false;
  return (fps >= 24.5 && fps <= 25.5) || (fps >= 29.5 && fps <= 30.5);
}

/// O libmpv tem os filtros do ffmpeg (`bwdif`)? Os builds completos são mpv 0.40+; o mínimo do
/// media_kit é 0.36 (`mpv-version` = "mpv v0.42.0-38-g…"). É só a primeira condição: o `vf` tem de
/// ser aceite pelo mpv e medido a dobrar as imagens (ver `FiltrosNaSessao`).
bool filtrosDoMpv(String? versao) {
  final m = RegExp(r'v?(\d+)\.(\d+)').firstMatch(versao ?? '');
  if (m == null) return false;
  final maior = int.parse(m[1]!), menor = int.parse(m[2]!);
  return maior > 0 || menor >= 40;
}

/// O `vf` do desentrelaçamento: o bwdif por campo (`send_field`: 25i -> 50 imagens/s), só nas imagens
/// marcadas como entrelaçadas. O MediaCodec não as marca: aí o `idet` (deteção de riscas do ffmpeg)
/// marca-as antes; um progressivo passa sem mexer. Medido com o libmpv 0.42 (imagens sem marca):
/// entrelaçado 25 -> 50, progressivo 25 -> 25 (com `deint=all` o progressivo ia a 50, a perder detalhe).
String filtroDesentrelacamento(String hwdec) => hwdec.trim().startsWith('mediacodec')
    ? '@$rotuloIdet:idet,bwdif=mode=send_field:deint=interlaced'
    : 'bwdif=mode=send_field:deint=interlaced';

/// O que se mediu do filtro (ou do d3d11vpp) posto no mpv.
enum EfeitoFiltro {
  /// A leitura não diz nada: sem resposta, em pausa, a carregar, no fim do buffer, sem fps.
  porSaber,

  /// A saída tem o dobro das imagens da entrada: desentrelaça por campo.
  dobra,

  /// A saída tem as imagens da entrada: não fez nada (ou a imagem é progressiva).
  igual,

  /// A tocar, sem imagem.
  semImagem,

  /// O mpv já não tem o filtro no `vf`.
  removido,
}

EfeitoFiltro efeitoFiltro(MeioDesentrelacamento meio, Map<String, String> m) {
  if ((m['mpv-version'] ?? '').trim().isEmpty) return EfeitoFiltro.porSaber;
  if ((m['eof-reached'] ?? '').trim() == 'yes' || (m['core-idle'] ?? '').trim() == 'yes') {
    return EfeitoFiltro.porSaber;
  }
  if (meio == MeioDesentrelacamento.filtroMpv && m.containsKey('vf') && !(m['vf'] ?? '').contains('bwdif')) {
    return EfeitoFiltro.removido;
  }
  if ((_numero(m['height']) ?? 0) <= 0) return EfeitoFiltro.semImagem;
  final entrada = _numero(m['container-fps']), saida = _numero(m['estimated-vf-fps']);
  if (entrada == null || entrada <= 0 || saida == null || saida <= 0) return EfeitoFiltro.porSaber;
  final r = saida / entrada;
  if (r >= 1.6) return EfeitoFiltro.dobra;
  if (r <= 1.25) return EfeitoFiltro.igual;
  return EfeitoFiltro.porSaber;
}

/// O que o idet contou (`vf-metadata/<rotuloIdet>`, JSON do mpv): true entrelaçado, false progressivo,
/// null ainda poucas imagens ou sem leitura. `minimo`: imagens contadas para decidir.
bool? idetEntrelacado(String? metadados, {int minimo = 25}) {
  final t = (metadados ?? '').trim();
  if (t.isEmpty) return null;
  double n(String chave) =>
      double.tryParse(RegExp('"lavfi\\.idet\\.multiple\\.$chave":"([0-9.]+)"').firstMatch(t)?[1] ?? '') ?? 0;
  final entrelacadas = n('tff') + n('bff'), progressivas = n('progressive');
  if (entrelacadas + progressivas < minimo) return null;
  if (entrelacadas > progressivas) return true;
  return progressivas > 4 * entrelacadas ? false : null;
}

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
    bool direto = false,
    bool d3d11vpp = true}) {
  if (!ligado || entrelacada != true) return MeioDesentrelacamento.nenhum;
  if (p == PlataformaVideo.android) {
    if (filtros && !direto) return MeioDesentrelacamento.filtroMpv;
    return shaderFlutter ? MeioDesentrelacamento.shaderFlutter : MeioDesentrelacamento.nenhum;
  }
  // `d3d11vpp`: false quando falhou ou foi recusado neste canal (aí fica o shader do mpv, que corre
  // nas imagens d3d11; o bwdif não as apanha)
  if (hwdec.trim() == 'd3d11va') return d3d11vpp ? MeioDesentrelacamento.d3d11vpp : MeioDesentrelacamento.shaderMpv;
  return filtros ? MeioDesentrelacamento.filtroMpv : MeioDesentrelacamento.shaderMpv;
}

/// Põe o meio no mpv (o shader e os filtros só correm no mpv; o do Flutter deixa-o sem nada).
/// Nunca lança. `hwdec`: o `hwdec-current` (decide o `vf`). Devolve o código do mpv para o que
/// decide o meio (o `vf` do filtro, o `deinterlace` do d3d11vpp; 0 nos outros), null sem resposta.
Future<int?> aplicarMeioMpv(MotorMpv mpv, MeioDesentrelacamento m,
    {required String? caminhoShader, String hwdec = ''}) async {
  try {
    if (m == MeioDesentrelacamento.filtroMpv) {
      await mpv.setProperty('glsl-shaders', '');
      await mpv.setProperty('deinterlace', 'no');
      return await mpv.setProperty('vf', filtroDesentrelacamento(hwdec));
    }
    await mpv.setProperty('vf', '');
    if (m == MeioDesentrelacamento.d3d11vpp) {
      await mpv.setProperty('glsl-shaders', '');
      return await mpv.setProperty('deinterlace', 'yes');
    }
    await mpv.setProperty('deinterlace', 'no');
    await mpv.setProperty(
        'glsl-shaders', m == MeioDesentrelacamento.shaderMpv && caminhoShader != null ? caminhoShader : '');
    return 0;
  } catch (e) {
    debugPrint('mpv: desentrelaçamento não aplicado ($e)');
    return null;
  }
}

/// O que as estatísticas mostram. `confirmado`: o filtro já foi medido a dobrar as imagens.
String textoDesentrelacamento(MeioDesentrelacamento m,
        {required bool ligado, required bool? entrelacada, bool confirmado = true}) =>
    switch (m) {
      MeioDesentrelacamento.filtroMpv when !confirmado => 'ligado (bwdif, a medir)',
      MeioDesentrelacamento.filtroMpv => 'ligado (bwdif, por campo)',
      MeioDesentrelacamento.d3d11vpp when !confirmado => 'ligado (d3d11vpp, a medir)',
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
