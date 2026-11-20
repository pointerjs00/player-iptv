import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/diagnostico.dart';
import 'package:player_iptv/ui/player/motor_reproducao.dart';

AmostraMpv _a({double? buffer = 8, bool pausado = false, int dropsSaida = 0, int dropsDesc = 0,
        double? fps = 25, double? ecra = 50, String sync = 'audio'}) =>
    AmostraMpv.deMapa({
      'video-sync': sync,
      'demuxer-cache-duration': buffer?.toString() ?? '',
      'paused-for-cache': pausado ? 'yes' : 'no',
      'frame-drop-count': '$dropsSaida',
      'decoder-frame-drop-count': '$dropsDesc',
      'container-fps': fps?.toString() ?? '',
      'display-fps': ecra?.toString() ?? '',
    });

void main() {
  test('lê as propriedades do mpv (texto) e tolera as que faltam', () {
    final a = AmostraMpv.deMapa({
      'hwdec-current': 'mediacodec',
      'video-codec': 'h264 (H.264 / AVC)',
      'width': '1920',
      'height': '1080',
      'container-fps': '50.000000',
      'estimated-vf-fps': '49.97',
      'display-fps': '60.000000',
      'frame-drop-count': '3',
      'decoder-frame-drop-count': '1',
      'demuxer-cache-duration': '7.52',
      'cache-buffering-state': '100',
      'video-bitrate': '5400000',
      'paused-for-cache': 'no',
    });
    expect(a.hwdec, 'mediacodec');
    expect(a.largura, 1920);
    expect(a.altura, 1080);
    expect(a.fpsContentor, 50);
    expect(a.fpsEstimado, closeTo(49.97, 1e-9));
    expect(a.fpsEcra, 60);
    expect(a.dropsSaida, 3);
    expect(a.dropsDescodificador, 1);
    expect(a.bufferSegundos, closeTo(7.52, 1e-9));
    expect(a.estadoBuffer, 100);
    expect(a.bitrate, 5400000);
    expect(a.pausadoParaCache, isFalse);

    final vazia = AmostraMpv.deMapa(const {});
    expect(vazia.hwdec, '');
    expect(vazia.largura, 0);
    expect(vazia.fpsContentor, isNull);
    expect(vazia.dropsSaida, 0);
    expect(vazia.bufferSegundos, isNull);
  });

  test('as linhas mostram o essencial em português', () {
    final a = AmostraMpv.deMapa({
      'hwdec-current': 'no',
      'video-codec': 'h264',
      'width': '1280',
      'height': '720',
      'container-fps': '50',
      'display-fps': '60',
      'demuxer-cache-duration': '4.25',
      'video-bitrate': '3500000',
      'paused-for-cache': 'yes',
    });
    final texto = linhasEstatisticas(a).map((l) => '${l.$1}: ${l.$2}').join('\n');
    expect(texto, contains('1280×720'));
    expect(texto, contains('software'));
    expect(texto, contains('4.3 s'));
    expect(texto, contains('3.5 Mb/s'));
    expect(texto, contains('50.00'));
    expect(texto, contains('60.00'));
  });

  group('veredicto', () {
    // 3 amostras (3 s) iguais
    List<AmostraMpv> x3(AmostraMpv a) => [a, a, a];

    test('sem amostras: nada a dizer', () => expect(diagnosticar(const []), isNull));

    test('sem vídeo (canal a abrir ou falhado): nada a dizer, não "fluido"', () {
      final v = AmostraMpv.deMapa(const {'paused-for-cache': 'no', 'frame-drop-count': '0'});
      expect(diagnosticar([v, v, v]), isNull);
    });

    test('menos de 3 amostras (logo a seguir a abrir/zapping): ainda a medir', () {
      expect(diagnosticar([_a(), _a()]), isNull);
      expect(diagnosticar([_a(buffer: 20), _a(buffer: 1, pausado: true)]), isNull);
    });

    test('fluido', () => expect(diagnosticar(x3(_a())), Veredicto.fluido));

    test('rede: o leitor parou à espera de dados (2 amostras seguidas)', () {
      expect(diagnosticar([_a(), _a(buffer: 0, pausado: true), _a(buffer: 0, pausado: true)]), Veredicto.rede);
    });

    test('uma só amostra parada não chega (engasgo de 1 s)', () {
      expect(diagnosticar([_a(buffer: 2), _a(buffer: 2), _a(buffer: 1.6, pausado: true)]), Veredicto.fluido);
    });

    test('rede: o buffer está a esvaziar (cai ≥ 1 s e fica abaixo de 1,5 s)', () {
      expect(diagnosticar([_a(buffer: 6), _a(buffer: 3.5), _a(buffer: 1.2)]), Veredicto.rede);
    });

    test('buffer pequeno a oscilar (HLS/TS com rajadas) não é rede', () {
      expect(diagnosticar([_a(buffer: 2.4), _a(buffer: 2.9), _a(buffer: 2.1)]), Veredicto.fluido);
      expect(diagnosticar([_a(buffer: 18), _a(buffer: 16), _a(buffer: 14)]), Veredicto.fluido);
    });

    test('descodificação: ≥ 2 imagens perdidas no descodificador na janela', () {
      expect(diagnosticar([_a(dropsDesc: 2), _a(dropsDesc: 5), _a(dropsDesc: 9)]), Veredicto.descodificacao);
      expect(diagnosticar([_a(dropsDesc: 2), _a(dropsDesc: 2), _a(dropsDesc: 3)]), Veredicto.fluido,
          reason: 'uma perda isolada não conta');
    });

    test('ecrã: ≥ 2 imagens perdidas na saída', () {
      expect(diagnosticar([_a(dropsSaida: 1), _a(dropsSaida: 2), _a(dropsSaida: 4)]), Veredicto.ecra);
      expect(diagnosticar([_a(dropsSaida: 1), _a(dropsSaida: 1), _a(dropsSaida: 2)]), Veredicto.fluido);
    });

    test('ecrã: 50 fps num ecrã a 60 Hz (judder)', () {
      expect(diagnosticar(x3(_a(fps: 50, ecra: 60))), Veredicto.ecra);
      expect(diagnosticar(x3(_a(fps: 25, ecra: 60))), Veredicto.ecra);
    });

    test('ritmos compatíveis não são problema (25 em 50, 30 em 60, 29.97 em 59.94)', () {
      expect(diagnosticar(x3(_a(fps: 25, ecra: 50))), Veredicto.fluido);
      expect(diagnosticar(x3(_a(fps: 50, ecra: 50))), Veredicto.fluido);
      expect(diagnosticar(x3(_a(fps: 30, ecra: 60))), Veredicto.fluido);
      expect(diagnosticar(x3(_a(fps: 29.97, ecra: 59.94))), Veredicto.fluido);
      expect(diagnosticar(x3(_a(fps: 29.97, ecra: 60))), Veredicto.fluido);
    });

    test('Android direto: o mpv não sabe os Hz; usa os do sistema (canal nativo)', () {
      expect(diagnosticar(x3(_a(fps: 50, ecra: null))), Veredicto.fluido, reason: 'desconhecido não acusa');
      expect(diagnosticar(x3(_a(fps: 50, ecra: null)), hzEcra: 60), Veredicto.ecra);
      expect(diagnosticar(x3(_a(fps: 50, ecra: null)), hzEcra: 50), Veredicto.fluido);
    });

    test('display-resample só conta quando está mesmo ativo (o mpv sabe os Hz do ecrã)', () {
      expect(diagnosticar(x3(_a(fps: 50, ecra: 60, sync: 'display-resample'))), Veredicto.fluido);
      // Windows com vo=libmpv: pedido mas sem Hz do ecrã -> o mpv volta ao áudio; não se sabe
      expect(diagnosticar(x3(_a(fps: 50, ecra: null, sync: 'display-resample'))), Veredicto.fluido);
      expect(diagnosticar(x3(_a(fps: 50, ecra: null, sync: 'display-resample')), hzEcra: 60), Veredicto.ecra,
          reason: 'Hz do sistema conhecidos mas o mpv não reamostra');
      expect(diagnosticar(x3(_a(fps: 50, ecra: 60, sync: 'audio'))), Veredicto.ecra);
    });

    test('prioridade: rede > descodificação > ecrã', () {
      expect(
          diagnosticar([
            _a(),
            _a(pausado: true, buffer: 0, dropsDesc: 5, dropsSaida: 5),
            _a(pausado: true, buffer: 0, dropsDesc: 9, dropsSaida: 9),
          ]),
          Veredicto.rede);
      expect(
          diagnosticar([_a(fps: 50, ecra: 60), _a(dropsDesc: 3, dropsSaida: 3), _a(dropsDesc: 5, dropsSaida: 5)]),
          Veredicto.descodificacao);
    });

    test('textos', () {
      expect(textoVeredicto(Veredicto.rede), 'rede (buffer a esvaziar)');
      expect(textoVeredicto(Veredicto.descodificacao), 'descodificação (imagens perdidas no descodificador)');
      expect(textoVeredicto(Veredicto.ecra), 'ecrã (imagens perdidas na saída / 50 fps num ecrã a 60 Hz)');
      expect(textoVeredicto(Veredicto.fluido), 'fluido');
    });
  });

  test('as linhas mostram os Hz do sistema quando o mpv não os sabe', () {
    final a = AmostraMpv.deMapa(const {'width': '1280', 'height': '720', 'container-fps': '50'});
    final texto = linhasEstatisticas(a, hzEcra: 60).map((l) => '${l.$1}: ${l.$2}').join('\n');
    expect(texto, contains('60.00 (sistema)'));
  });

  group('semImagemDireta (descodificação direta sem imagem)', () {
    Map<String, String> m({String codec = 'h264', String hw = 'mediacodec', String vo = 'yes'}) =>
        {'video-codec': codec, 'hwdec-current': hw, 'vo-configured': vo};

    test('a tocar com o descodificador de hardware: tem imagem', () {
      expect(semImagemDireta(larguraVista: 1920, propriedades: m()), isFalse);
    });
    test('o mpv passou para software: o mediacodec_embed não mostra nada', () {
      expect(semImagemDireta(larguraVista: 1920, propriedades: m(hw: 'no')), isTrue);
    });
    test('a saída de vídeo falhou com o vídeo a ser descodificado', () {
      expect(semImagemDireta(larguraVista: 1920, propriedades: m(vo: 'no')), isTrue);
    });
    test('o MediaCodec não abriu e o mpv largou o vídeo ("Video: no video"): o mpv respondeu "no"', () {
      expect(semImagemDireta(larguraVista: 1920, propriedades: m(codec: '', hw: '', vo: 'no')), isTrue);
    });
    test('propriedades vazias não são prova: o mpv não respondeu ou o vídeo ainda está a arrancar', () {
      // visto no emulador: com o mpv preso, as três leituras voltam vazias (o pedido passou o
      // limite) e o canal passava para "Compatível" sem razão
      expect(semImagemDireta(larguraVista: 1920, propriedades: m(codec: '', hw: '', vo: '')), isFalse);
      expect(semImagemDireta(larguraVista: 1920, propriedades: m(hw: '')), isFalse);
      expect(semImagemDireta(larguraVista: 1920, propriedades: m(codec: '', hw: 'no', vo: '')), isFalse,
          reason: 'sem codec nem vo, "no" no hwdec não diz que havia vídeo');
    });
    test('canal só de som (rádio): nunca houve vídeo, não é falha', () {
      expect(semImagemDireta(larguraVista: 0, propriedades: m(codec: '', hw: '', vo: 'no')), isFalse);
    });
  });

  group('M1: linhasEstatisticasMotor (ExoPlayer)', () {
    Map<String, String> l(EstatisticasMotor e) => {for (final (r, v) in linhasEstatisticasMotor(e)) r: v};

    test('o descodificador de vídeo, com hardware ou software', () {
      expect(l(const EstatisticasMotor(descodificador: 'OMX.amlogic.avc.decoder.awesome', hardware: true))['Descodificador'],
          'OMX.amlogic.avc.decoder.awesome (hardware)');
      expect(l(const EstatisticasMotor(descodificador: 'c2.android.avc.decoder', hardware: false))['Descodificador'],
          'c2.android.avc.decoder (software)');
      expect(l(const EstatisticasMotor())['Descodificador'], '—');
    });

    test('o modo túnel: se ficou mesmo ativo, e a nota das perdidas', () {
      expect(l(const EstatisticasMotor(tunelPedido: false, tunelAtivo: false))['Modo túnel'], 'desligado');
      expect(l(const EstatisticasMotor(tunelPedido: true, tunelAtivo: false))['Modo túnel'], 'pedido, mas não ficou ativo');
      final ativo = l(const EstatisticasMotor(tunelPedido: true, tunelAtivo: true, perdidas: 0, renderizadas: 900));
      expect(ativo['Modo túnel'], 'ativo');
      expect(ativo['Imagens (perdidas · mostradas)'], '0 · 900 (em túnel as perdidas não são contadas)');
      final semTunel = l(const EstatisticasMotor(tunelPedido: false, tunelAtivo: false, perdidas: 2, renderizadas: 900));
      expect(semTunel['Imagens (perdidas · mostradas)'], '2 · 900');
      expect(l(const EstatisticasMotor()).containsKey('Modo túnel'), isFalse, reason: 'o motor não disse nada');
    });
  });
}
