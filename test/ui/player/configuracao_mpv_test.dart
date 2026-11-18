import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';

const _mib64 = '67108864';

void main() {
  group('comuns (buffer para direto)', () {
    for (final p in PlataformaVideo.values) {
      test('$p', () {
        final c = ConfiguracaoMpv.para(p);
        expect(c.propriedades, containsPair('cache', 'yes'));
        expect(c.propriedades, containsPair('demuxer-readahead-secs', '10'));
        expect(c.propriedades, containsPair('cache-secs', '300'));
        expect(c.propriedades, containsPair('demuxer-max-bytes', _mib64));
        expect(c.propriedades, containsPair('demuxer-max-back-bytes', _mib64));
        expect(c.propriedades, containsPair('cache-pause-initial', 'yes'));
        expect(c.propriedades, containsPair('cache-pause-wait', '2'));
        expect(c.propriedades, containsPair('network-timeout', '15'));
        // sem reconexão dentro do mesmo stream: os servidores IPTV respondem a uma ligação nova
        // com um bloco de segundos já vistos (o mpv voltava atrás dezenas de segundos); o player
        // toca o buffer até ao fim e só então pede o canal de novo (ContinuarDireto)
        expect(c.propriedades, containsPair('stream-lavf-o', 'reconnect=0,reconnect_streamed=0'));
        expect(c.propriedades, containsPair('framedrop', 'vo'));
        expect(ConfiguracaoMpv.bufferBytes, 64 * 1024 * 1024);
        expect(c.configuracaoPlayer.bufferSize, 64 * 1024 * 1024);
      });
    }
  });

  group('Android', () {
    test('por omissão: descodificação direta (sem cópias)', () {
      final c = ConfiguracaoMpv.para(PlataformaVideo.android);
      expect(c.vo, 'mediacodec_embed');
      expect(c.hwdec, 'mediacodec');
      expect(c.configuracaoVideo.vo, 'mediacodec_embed');
      expect(c.configuracaoVideo.hwdec, 'mediacodec');
      expect(c.propriedades, containsPair('ao', 'audiotrack,opensles'));
      expect(c.propriedades.containsKey('video-sync'), isFalse);
      expect(c.reamostraRitmo, isFalse);
    });

    test('modo Compatível: gpu + mediacodec-copy', () {
      final c = ConfiguracaoMpv.para(PlataformaVideo.android, modo: ModoDescodificacao.compativel);
      expect(c.vo, 'gpu');
      expect(c.hwdec, 'mediacodec-copy');
      expect(c.propriedades, containsPair('ao', 'audiotrack,opensles'));
    });

  });

  group('Windows', () {
    test('libmpv (a única saída que desenha dentro da janela Flutter) + auto-safe + display-resample', () {
      final c = ConfiguracaoMpv.para(PlataformaVideo.windows);
      expect(c.vo, 'libmpv');
      expect(c.hwdec, 'auto-safe');
      expect(c.propriedades, containsPair('video-sync', 'display-resample'));
      expect(c.propriedades.containsKey('ao'), isFalse);
      expect(c.reamostraRitmo, isTrue);
    });
  });

  group('descodificação por hardware desligada (software)', () {
    test('Android: gpu sem hwdec, seja qual for o modo', () {
      for (final m in ModoDescodificacao.values) {
        final c = ConfiguracaoMpv.para(PlataformaVideo.android, modo: m, hardware: false);
        expect(c.vo, 'gpu');
        expect(c.hwdec, 'no');
      }
    });

    test('Windows: libmpv sem hwdec', () {
      final c = ConfiguracaoMpv.para(PlataformaVideo.windows, hardware: false);
      expect(c.vo, 'libmpv');
      expect(c.hwdec, 'no');
    });
  });

  group('desentrelaçamento', () {
    test('não vai na configuração do player (aplica-se a cada canal, conforme a preferência)', () {
      for (final p in PlataformaVideo.values) {
        expect(ConfiguracaoMpv.para(p).propriedades.containsKey('deinterlace'), isFalse);
      }
    });
  });

  test('nomes guardados do modo', () {
    expect(ModoDescodificacao.deNome('compativel'), ModoDescodificacao.compativel);
    expect(ModoDescodificacao.deNome('direto'), ModoDescodificacao.direto);
    expect(ModoDescodificacao.deNome(null), ModoDescodificacao.direto);
    expect(ModoDescodificacao.deNome('lixo'), ModoDescodificacao.direto);
    expect(ModoDescodificacao.compativel.rotulo, 'Compatível');
    expect(ModoDescodificacao.direto.rotulo, 'Direta (recomendada)');
  });
}
