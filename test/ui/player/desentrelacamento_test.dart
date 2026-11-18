import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';
import 'package:player_iptv/ui/player/desentrelacamento.dart';

class _Mpv implements MotorMpv {
  final chamadas = <String>[];
  @override
  Future<void> setProperty(String p, String v) async => chamadas.add('$p=$v');
  @override
  Future<String> getProperty(String p) async => '';
  @override
  Future<void> setRate(double r) async {}
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> command(List<String> c) async {}
}

void main() {
  group('a imagem é entrelaçada?', () {
    test('o mpv diz (descodificou ele: software, d3d11va-copy): fia-se nisso', () {
      // visto no libmpv da app no Windows: RTP 1 FHD 1920x1080 25 fps -> interlaced=yes
      expect(
          imagemEntrelacada({'video-frame-info/interlaced': 'yes', 'height': '1080', 'container-fps': '25', 'hwdec-current': 'd3d11va-copy'}),
          isTrue);
      expect(imagemEntrelacada({'video-frame-info/interlaced': 'no', 'height': '1080', 'container-fps': '25', 'hwdec-current': 'no'}),
          isFalse, reason: 'um 1080p25 que o mpv diz progressivo');
    });

    test('com o MediaCodec o mpv não sabe: 1080/576/480 linhas a ≤ 30 imagens/s é entrelaçado', () {
      Map<String, String> m(String h, String fps) =>
          {'height': h, 'container-fps': fps, 'hwdec-current': 'mediacodec'};
      expect(imagemEntrelacada(m('1080', '25.000000')), isTrue);
      expect(imagemEntrelacada(m('576', '25')), isTrue);
      expect(imagemEntrelacada(m('480', '29.970')), isTrue);
      expect(imagemEntrelacada(m('1088', '25')), isTrue);
      expect(imagemEntrelacada(m('720', '50')), isFalse, reason: '720p é sempre progressivo');
      expect(imagemEntrelacada(m('720', '25')), isFalse);
      expect(imagemEntrelacada(m('1080', '50')), isFalse, reason: '1080p50');
      expect(imagemEntrelacada(m('2160', '25')), isFalse);
      expect(imagemEntrelacada(m('432', '25')), isFalse);
    });

    test('com o MediaCodec, mesmo que o mpv diga "no" (o MediaCodec não passa a marca), vale a regra', () {
      expect(
          imagemEntrelacada({'video-frame-info/interlaced': 'no', 'height': '1080', 'container-fps': '25', 'hwdec-current': 'mediacodec-copy'}),
          isTrue);
    });

    test('sem fps do contentor usa o medido; sem altura ainda não se sabe', () {
      expect(imagemEntrelacada({'height': '576', 'container-fps': '', 'estimated-vf-fps': '25.0', 'hwdec-current': 'mediacodec'}), isTrue);
      expect(imagemEntrelacada({'height': '', 'container-fps': '25', 'hwdec-current': 'mediacodec'}), isNull);
      expect(imagemEntrelacada({'height': '1080', 'container-fps': '', 'hwdec-current': 'mediacodec'}), isNull);
    });
  });

  group('como se desentrelaça', () {
    MeioDesentrelacamento meio(PlataformaVideo p,
            {bool ligado = true, bool? entrelacada = true, String hwdec = 'd3d11va-copy', bool shaderFlutter = true}) =>
        meioDesentrelacamento(p, ligado: ligado, entrelacada: entrelacada, hwdec: hwdec, shaderFlutter: shaderFlutter);

    test('desligado ou imagem progressiva (ou ainda por saber): nada', () {
      expect(meio(PlataformaVideo.windows, ligado: false), MeioDesentrelacamento.nenhum);
      expect(meio(PlataformaVideo.windows, entrelacada: false), MeioDesentrelacamento.nenhum);
      expect(meio(PlataformaVideo.android, entrelacada: null), MeioDesentrelacamento.nenhum);
    });

    test('Windows: as imagens voltam à memória (d3d11va-copy, software): o shader do mpv', () {
      // o ffmpeg incluído não tem yadif/bwdif ("filter 'yadif' not found") e com o ANGLE da app o
      // mpv não carrega o d3d11-egl, por isso o d3d11va fica -copy e o d3d11vpp não serve
      expect(meio(PlataformaVideo.windows), MeioDesentrelacamento.shaderMpv);
      expect(meio(PlataformaVideo.windows, hwdec: 'no'), MeioDesentrelacamento.shaderMpv);
    });

    test('Windows com imagens d3d11va na GPU: o d3d11vpp do mpv (por campo, 50 imagens/s)', () {
      expect(meio(PlataformaVideo.windows, hwdec: 'd3d11va'), MeioDesentrelacamento.d3d11vpp);
    });

    test('Android (direto ou Compatível): o shader do Flutter por cima da imagem; sem ele, nada', () {
      expect(meio(PlataformaVideo.android, hwdec: 'mediacodec'), MeioDesentrelacamento.shaderFlutter);
      expect(meio(PlataformaVideo.android, hwdec: 'mediacodec-copy'), MeioDesentrelacamento.shaderFlutter);
      expect(meio(PlataformaVideo.android, shaderFlutter: false), MeioDesentrelacamento.nenhum);
    });
  });

  group('no mpv', () {
    test('shader do mpv: sem deinterlace (pedia o yadif, que não existe) e com o glsl-shaders', () async {
      final mpv = _Mpv();
      await aplicarMeioMpv(mpv, MeioDesentrelacamento.shaderMpv, caminhoShader: r'C:\x\desentrelacar.glsl');
      expect(mpv.chamadas, ['deinterlace=no', r'glsl-shaders=C:\x\desentrelacar.glsl']);
    });

    test('d3d11vpp: deinterlace=yes sem shader', () async {
      final mpv = _Mpv();
      await aplicarMeioMpv(mpv, MeioDesentrelacamento.d3d11vpp, caminhoShader: 'x');
      expect(mpv.chamadas, ['glsl-shaders=', 'deinterlace=yes']);
    });

    test('nada ou shader do Flutter: o mpv sem nada', () async {
      for (final m in [MeioDesentrelacamento.nenhum, MeioDesentrelacamento.shaderFlutter]) {
        final mpv = _Mpv();
        await aplicarMeioMpv(mpv, m, caminhoShader: 'x');
        expect(mpv.chamadas, ['deinterlace=no', 'glsl-shaders=']);
      }
    });

    test('sem o ficheiro do shader: fica sem nada (não lança)', () async {
      final mpv = _Mpv();
      await aplicarMeioMpv(mpv, MeioDesentrelacamento.shaderMpv, caminhoShader: null);
      expect(mpv.chamadas, ['deinterlace=no', 'glsl-shaders=']);
    });
  });

  test('o ficheiro do shader do mpv: escreve-se na pasta e devolve o caminho', () async {
    final pasta = await Directory.systemTemp.createTemp('desentrelacar');
    addTearDown(() => pasta.delete(recursive: true));
    final caminho = await escreverShaderMpv(pasta);
    expect(caminho, isNotNull);
    final texto = File(caminho!).readAsStringSync();
    expect(texto, startsWith('//!HOOK MAIN'));
    expect(texto, contains('vec4 hook()'));
    expect(caminho.contains(';'), isFalse, reason: 'o glsl-shaders separa caminhos com ";" no Windows');
  });

  test('texto das estatísticas', () {
    expect(textoDesentrelacamento(MeioDesentrelacamento.nenhum, ligado: true, entrelacada: false),
        'desligado (imagem progressiva)');
    expect(textoDesentrelacamento(MeioDesentrelacamento.nenhum, ligado: false, entrelacada: true), 'desligado');
    expect(textoDesentrelacamento(MeioDesentrelacamento.nenhum, ligado: true, entrelacada: null), 'à espera da imagem');
    expect(textoDesentrelacamento(MeioDesentrelacamento.shaderMpv, ligado: true, entrelacada: true),
        'ligado (shader do player)');
    expect(textoDesentrelacamento(MeioDesentrelacamento.shaderFlutter, ligado: true, entrelacada: true),
        'ligado (shader do player)');
    expect(textoDesentrelacamento(MeioDesentrelacamento.d3d11vpp, ligado: true, entrelacada: true),
        'ligado (d3d11vpp, por campo)');
    expect(textoDesentrelacamento(MeioDesentrelacamento.nenhum, ligado: true, entrelacada: true),
        'indisponível neste aparelho');
  });
}
