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
        expect(c.propriedades, containsPair('cache-secs', '20'));
        expect(c.propriedades, containsPair('demuxer-max-bytes', _mib64));
        expect(c.propriedades, containsPair('demuxer-max-back-bytes', _mib64));
        expect(c.propriedades, containsPair('cache-pause-initial', 'yes'));
        expect(c.propriedades, containsPair('cache-pause-wait', '2'));
        expect(c.propriedades, containsPair('network-timeout', '15'));
        expect(c.propriedades,
            containsPair('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5'));
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

    test('emulador: software (o mediacodec_embed não mostra imagens descodificadas no CPU)', () {
      final c = ConfiguracaoMpv.para(PlataformaVideo.android, emulador: true);
      expect(c.vo, 'gpu');
      expect(c.hwdec, 'no');
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

  group('desentrelaçamento inteligente', () {
    test('ligado: deinterlace=auto (só imagens entrelaçadas)', () {
      final c = ConfiguracaoMpv.para(PlataformaVideo.windows, desentrelacar: true);
      expect(c.propriedades, containsPair('deinterlace', 'auto'));
      expect(c.desentrelacamentoAtivo, isTrue);
    });

    test('desligado: deinterlace=no', () {
      final c = ConfiguracaoMpv.para(PlataformaVideo.android, modo: ModoDescodificacao.compativel);
      expect(c.propriedades, containsPair('deinterlace', 'no'));
      expect(c.desentrelacamentoAtivo, isFalse);
    });

    test('Android Compatível: o filtro do mpv aplica-se', () {
      final c = ConfiguracaoMpv.para(PlataformaVideo.android,
          modo: ModoDescodificacao.compativel, desentrelacar: true);
      expect(c.propriedades, containsPair('deinterlace', 'auto'));
      expect(c.desentrelacamentoAtivo, isTrue);
    });

    test('Android direto: o descodificador de hardware trata disso; a opção não aparece como ativa', () {
      final c = ConfiguracaoMpv.para(PlataformaVideo.android, desentrelacar: true);
      expect(c.propriedades.containsKey('deinterlace'), isFalse);
      expect(c.desentrelacamentoAtivo, isFalse);
      expect(ConfiguracaoMpv.desentrelacamentoTemEfeito(PlataformaVideo.android, ModoDescodificacao.direto),
          isFalse);
      expect(
          ConfiguracaoMpv.desentrelacamentoTemEfeito(PlataformaVideo.android, ModoDescodificacao.compativel),
          isTrue);
      expect(
          ConfiguracaoMpv.desentrelacamentoTemEfeito(PlataformaVideo.android, ModoDescodificacao.direto,
              emulador: true),
          isTrue);
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
