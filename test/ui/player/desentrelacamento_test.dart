import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';
import 'package:player_iptv/ui/player/desentrelacamento.dart';

class _Mpv implements MotorMpv {
  final chamadas = <String>[];
  @override
  Future<int?> setProperty(String p, String v) async {
    chamadas.add('$p=$v');
    return 0;
  }
  @override
  Future<String> getProperty(String p) async => '';
  @override
  Future<void> setRate(double r) async {}
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> command(List<String> c) async {}
}

class _MpvQueRecusa extends _Mpv {
  @override
  Future<int?> setProperty(String p, String v) async {
    await super.setProperty(p, v);
    return p == 'vf' && v.isNotEmpty ? -9 : 0;
  }
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

  group('filtro real do mpv (bwdif por campo)', () {
    test('só há filtros nos builds completos do libmpv (0.40 ou mais; o minimo do media_kit é 0.36)', () {
      expect(filtrosDoMpv('mpv v0.42.0-38-gbcde6b93c'), isTrue);
      expect(filtrosDoMpv('mpv v0.40.0'), isTrue);
      expect(filtrosDoMpv('mpv v0.36.0-549-g78d43740f5-dirty'), isFalse);
      expect(filtrosDoMpv('mpv v0.9.0'), isFalse);
      expect(filtrosDoMpv('mpv v1.0.0'), isTrue);
      expect(filtrosDoMpv(''), isFalse);
      expect(filtrosDoMpv(null), isFalse);
      expect(filtrosDoMpv('mpv-git-qualquer'), isFalse);
    });

    MeioDesentrelacamento meio(PlataformaVideo p,
            {bool ligado = true, bool? entrelacada = true, String hwdec = 'd3d11va-copy', bool filtros = true,
            bool direto = false, bool shaderFlutter = true}) =>
        meioDesentrelacamento(p,
            ligado: ligado, entrelacada: entrelacada, hwdec: hwdec, shaderFlutter: shaderFlutter, filtros: filtros, direto: direto);

    test('Windows com filtros: o bwdif do mpv (software ou d3d11va-copy); sem filtros o shader', () {
      expect(meio(PlataformaVideo.windows), MeioDesentrelacamento.filtroMpv);
      expect(meio(PlataformaVideo.windows, hwdec: 'no'), MeioDesentrelacamento.filtroMpv);
      expect(meio(PlataformaVideo.windows, filtros: false), MeioDesentrelacamento.shaderMpv);
      expect(meio(PlataformaVideo.windows, hwdec: 'd3d11va'), MeioDesentrelacamento.d3d11vpp,
          reason: 'imagens na GPU: o bwdif (software) não as apanha');
    });

    test('Android com filtros fora do modo direto: o bwdif; no direto (sem filtros possíveis) o shader', () {
      expect(meio(PlataformaVideo.android, hwdec: 'mediacodec-copy'), MeioDesentrelacamento.filtroMpv);
      expect(meio(PlataformaVideo.android, hwdec: 'no'), MeioDesentrelacamento.filtroMpv);
      expect(meio(PlataformaVideo.android, hwdec: 'mediacodec', direto: true), MeioDesentrelacamento.shaderFlutter);
      expect(meio(PlataformaVideo.android, hwdec: 'mediacodec', direto: true, shaderFlutter: false), MeioDesentrelacamento.nenhum);
      expect(meio(PlataformaVideo.android, hwdec: 'mediacodec-copy', filtros: false), MeioDesentrelacamento.shaderFlutter);
    });

    test('desligado ou progressivo: nada, mesmo com filtros', () {
      expect(meio(PlataformaVideo.windows, ligado: false), MeioDesentrelacamento.nenhum);
      expect(meio(PlataformaVideo.android, entrelacada: false, hwdec: 'mediacodec-copy'), MeioDesentrelacamento.nenhum);
    });

    test('Android direto: só um direto com as linhas e a cadência da TV entrelaçada pede o Compatível', () {
      bool parece(String h, String fps, {String seekable = 'no'}) => pareceEntrelacadaNoDireto(
          {'height': h, 'container-fps': fps, 'hwdec-current': 'mediacodec', 'seekable': seekable});
      expect(parece('1080', '25.000000'), isTrue);
      expect(parece('576', '25'), isTrue);
      expect(parece('480', '29.970030'), isTrue);
      expect(parece('1080', '23.976024'), isFalse, reason: 'filme: progressivo');
      expect(parece('1080', '24'), isFalse);
      expect(parece('1080', '25', seekable: 'yes'), isFalse, reason: 'um filme (VOD)');
      expect(parece('720', '25'), isFalse);
      expect(parece('1080', '50'), isFalse);
      expect(parece('', '25'), isFalse);
    });

    test('o filtro: só as imagens marcadas; sem marcas (MediaCodec) o idet marca-as antes', () {
      expect(filtroDesentrelacamento('d3d11va-copy'), 'bwdif=mode=send_field:deint=interlaced');
      expect(filtroDesentrelacamento('no'), 'bwdif=mode=send_field:deint=interlaced');
      expect(filtroDesentrelacamento('mediacodec-copy'), '@$rotuloIdet:idet,bwdif=mode=send_field:deint=interlaced');
    });

    test('o efeito do filtro mede-se pelas imagens/s; as leituras sem resposta, em pausa ou no fim não contam', () {
      Map<String, String> m({String v = 'mpv v0.42.0', String vf = 'bwdif=x', String h = '1080', String c = '25',
              String e = '50', String idle = 'no', String eof = 'no'}) =>
          {'mpv-version': v, 'vf': vf, 'height': h, 'container-fps': c, 'estimated-vf-fps': e, 'core-idle': idle,
            'eof-reached': eof};
      const f = MeioDesentrelacamento.filtroMpv;
      expect(efeitoFiltro(f, m()), EfeitoFiltro.dobra);
      expect(efeitoFiltro(f, m(e: '25')), EfeitoFiltro.igual);
      expect(efeitoFiltro(f, m(e: '35')), EfeitoFiltro.porSaber);
      expect(efeitoFiltro(f, m(vf: '')), EfeitoFiltro.removido);
      expect(efeitoFiltro(f, m(h: '')), EfeitoFiltro.semImagem);
      expect(efeitoFiltro(f, m(v: '', vf: '', h: '')), EfeitoFiltro.porSaber, reason: 'pedido sem resposta');
      expect(efeitoFiltro(f, m(eof: 'yes', h: '')), EfeitoFiltro.porSaber, reason: 'fim do buffer (corte)');
      expect(efeitoFiltro(f, m(idle: 'yes', e: '25')), EfeitoFiltro.porSaber, reason: 'pausa ou a carregar');
      expect(efeitoFiltro(f, m(c: '')), EfeitoFiltro.porSaber);
      expect(efeitoFiltro(MeioDesentrelacamento.d3d11vpp, m(vf: '')), EfeitoFiltro.dobra,
          reason: 'o d3d11vpp não está no vf do utilizador');
    });

    test('o que o idet contou (vf-metadata do mpv, visto no libmpv 0.42)', () {
      // o que o mpv deu com um 1080i sem marcas e com um 1080p25 (fontes sintéticas)
      const entrelacado = '{"lavfi.idet.multiple.current_frame":"tff","lavfi.idet.multiple.tff":"75.00",'
          '"lavfi.idet.multiple.bff":"0.00","lavfi.idet.multiple.progressive":"0.00","lavfi.idet.multiple.undetermined":"0.00"}';
      const progressivo = '{"lavfi.idet.multiple.current_frame":"progressive","lavfi.idet.multiple.tff":"0.00",'
          '"lavfi.idet.multiple.bff":"0.00","lavfi.idet.multiple.progressive":"77.00","lavfi.idet.multiple.undetermined":"0.00"}';
      expect(idetEntrelacado(entrelacado), isTrue);
      expect(idetEntrelacado(progressivo), isFalse);
      expect(idetEntrelacado(''), isNull);
      expect(idetEntrelacado(null), isNull);
      expect(idetEntrelacado(progressivo.replaceAll('77.00', '10.00')), isNull, reason: 'poucas imagens');
    });

    test('aplica o vf no mpv e tira o shader; os outros meios tiram o vf', () async {
      final mpv = _Mpv();
      await aplicarMeioMpv(mpv, MeioDesentrelacamento.filtroMpv, caminhoShader: 'x', hwdec: 'd3d11va-copy');
      expect(mpv.chamadas, ['glsl-shaders=', 'deinterlace=no', 'vf=bwdif=mode=send_field:deint=interlaced']);
      final mpv2 = _Mpv();
      await aplicarMeioMpv(mpv2, MeioDesentrelacamento.filtroMpv, caminhoShader: 'x', hwdec: 'mediacodec-copy');
      expect(mpv2.chamadas.last, 'vf=@$rotuloIdet:idet,bwdif=mode=send_field:deint=interlaced');
      final mpv3 = _Mpv();
      await aplicarMeioMpv(mpv3, MeioDesentrelacamento.nenhum, caminhoShader: 'x');
      expect(mpv3.chamadas, ['vf=', 'deinterlace=no', 'glsl-shaders=']);
    });

    test('aplicar devolve o código do mpv para o filtro (recusado: -9)', () async {
      expect(await aplicarMeioMpv(_MpvQueRecusa(), MeioDesentrelacamento.filtroMpv, caminhoShader: 'x'), -9);
      expect(await aplicarMeioMpv(_Mpv(), MeioDesentrelacamento.filtroMpv, caminhoShader: 'x'), 0);
    });

    test('texto das estatísticas', () {
      expect(textoDesentrelacamento(MeioDesentrelacamento.filtroMpv, ligado: true, entrelacada: true),
          'ligado (bwdif, por campo)');
    });
  });

  group('no mpv', () {
    test('shader do mpv: sem deinterlace (pedia o yadif, que não existe) e com o glsl-shaders', () async {
      final mpv = _Mpv();
      await aplicarMeioMpv(mpv, MeioDesentrelacamento.shaderMpv, caminhoShader: r'C:\x\desentrelacar.glsl');
      expect(mpv.chamadas, ['vf=', 'deinterlace=no', r'glsl-shaders=C:\x\desentrelacar.glsl']);
    });

    test('d3d11vpp: deinterlace=yes sem shader', () async {
      final mpv = _Mpv();
      await aplicarMeioMpv(mpv, MeioDesentrelacamento.d3d11vpp, caminhoShader: 'x');
      expect(mpv.chamadas, ['vf=', 'glsl-shaders=', 'deinterlace=yes']);
    });

    test('nada ou shader do Flutter: o mpv sem nada', () async {
      for (final m in [MeioDesentrelacamento.nenhum, MeioDesentrelacamento.shaderFlutter]) {
        final mpv = _Mpv();
        await aplicarMeioMpv(mpv, m, caminhoShader: 'x');
        expect(mpv.chamadas, ['vf=', 'deinterlace=no', 'glsl-shaders=']);
      }
    });

    test('sem o ficheiro do shader: fica sem nada (não lança)', () async {
      final mpv = _Mpv();
      await aplicarMeioMpv(mpv, MeioDesentrelacamento.shaderMpv, caminhoShader: null);
      expect(mpv.chamadas, ['vf=', 'deinterlace=no', 'glsl-shaders=']);
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

  test('o texto das definições não promete as 50 imagens/s sem condição (e o 480i é 60)', () {
    expect(textoDefinicaoDesentrelacamento, contains('quando o aparelho o permite'));
    expect(textoDefinicaoDesentrelacamento, contains('60 nos 480i'));
    expect(textoDefinicaoDesentrelacamento, isNot(contains('por campo (50 imagens/s)')));
  });
}
