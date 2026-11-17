import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/diagnostico.dart';

AmostraMpv _a({double? buffer = 8, bool pausado = false, int dropsSaida = 0, int dropsDesc = 0,
        double? fps = 25, double? ecra = 50}) =>
    AmostraMpv.deMapa({
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
    test('sem amostras: nada a dizer', () => expect(diagnosticar(const []), isNull));

    test('sem vídeo (canal a abrir ou falhado): nada a dizer, não "fluido"', () {
      expect(diagnosticar([AmostraMpv.deMapa(const {'paused-for-cache': 'no', 'frame-drop-count': '0'})]), isNull);
    });

    test('fluido', () {
      expect(diagnosticar([_a(), _a(), _a()]), Veredicto.fluido);
    });

    test('rede: o leitor parou à espera de dados', () {
      expect(diagnosticar([_a(), _a(buffer: 0, pausado: true)]), Veredicto.rede);
    });

    test('rede: o buffer está a esvaziar', () {
      expect(diagnosticar([_a(buffer: 6), _a(buffer: 3.5), _a(buffer: 1.2)]), Veredicto.rede);
    });

    test('buffer a baixar mas ainda folgado não é rede', () {
      expect(diagnosticar([_a(buffer: 18), _a(buffer: 14)]), Veredicto.fluido);
    });

    test('descodificação: imagens perdidas no descodificador', () {
      expect(diagnosticar([_a(dropsDesc: 2), _a(dropsDesc: 9)]), Veredicto.descodificacao);
    });

    test('ecrã: imagens perdidas na saída', () {
      expect(diagnosticar([_a(dropsSaida: 1), _a(dropsSaida: 4)]), Veredicto.ecra);
    });

    test('ecrã: 50 fps num ecrã a 60 Hz (judder)', () {
      expect(diagnosticar([_a(fps: 50, ecra: 60)]), Veredicto.ecra);
      expect(diagnosticar([_a(fps: 25, ecra: 60)]), Veredicto.ecra);
    });

    test('ritmos compatíveis não são problema (25 em 50, 30 em 60, 29.97 em 59.94)', () {
      expect(diagnosticar([_a(fps: 25, ecra: 50)]), Veredicto.fluido);
      expect(diagnosticar([_a(fps: 50, ecra: 50)]), Veredicto.fluido);
      expect(diagnosticar([_a(fps: 30, ecra: 60)]), Veredicto.fluido);
      expect(diagnosticar([_a(fps: 29.97, ecra: 59.94)]), Veredicto.fluido);
      expect(diagnosticar([_a(fps: 29.97, ecra: 60)]), Veredicto.fluido);
    });

    test('com display-resample o mpv compensa 50 em 60', () {
      expect(diagnosticar([_a(fps: 50, ecra: 60)], reamostra: true), Veredicto.fluido);
    });

    test('ritmo do ecrã desconhecido não acusa o ecrã', () {
      expect(diagnosticar([_a(fps: 50, ecra: null)]), Veredicto.fluido);
    });

    test('prioridade: rede > descodificação > ecrã', () {
      expect(diagnosticar([_a(dropsDesc: 0, dropsSaida: 0), _a(pausado: true, dropsDesc: 5, dropsSaida: 5)]),
          Veredicto.rede);
      expect(
          diagnosticar([_a(dropsDesc: 0, dropsSaida: 0, fps: 50, ecra: 60), _a(dropsDesc: 5, dropsSaida: 5)]),
          Veredicto.descodificacao);
    });

    test('textos', () {
      expect(textoVeredicto(Veredicto.rede), 'rede (buffer a esvaziar)');
      expect(textoVeredicto(Veredicto.descodificacao), 'descodificação (imagens perdidas no descodificador)');
      expect(textoVeredicto(Veredicto.ecra), 'ecrã (imagens perdidas na saída / 50 fps num ecrã a 60 Hz)');
      expect(textoVeredicto(Veredicto.fluido), 'fluido');
    });
  });
}
