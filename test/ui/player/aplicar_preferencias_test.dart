import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/ui/player/aplicar_preferencias.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';

/// Um mpv de mentira: regista o que lhe pedem. Com `aceitaAuto: false` ignora
/// deinterlace=auto, como a libmpv incluída (0.36).
class MpvFalso implements MotorMpv {
  MpvFalso({this.aceitaAuto = true});
  final bool aceitaAuto;
  final chamadas = <String>[];
  final props = <String, String>{'deinterlace': 'no', 'vf': ''};

  @override
  Future<void> setProperty(String p, String v) async {
    chamadas.add('$p=$v');
    if (p == 'deinterlace' && v == 'auto' && !aceitaAuto) return; // ignorado pelo mpv
    props[p] = v;
  }

  @override
  Future<String> getProperty(String p) async => props[p] ?? '';

  @override
  Future<void> setRate(double r) async => chamadas.add('rate=$r');

  @override
  Future<void> setVolume(double v) async => chamadas.add('volume=$v');

  @override
  Future<void> command(List<String> c) async => chamadas.add(c.join(' '));
}

Future<MpvFalso> _abrir(Preferencias p,
    {PlataformaVideo plataforma = PlataformaVideo.windows,
    ModoDescodificacao modo = ModoDescodificacao.direto,
    SessaoPlayer? sessao,
    bool aceitaAuto = true}) async {
  final mpv = MpvFalso(aceitaAuto: aceitaAuto);
  await aplicarAoAbrir(mpv, p, sessao ?? SessaoPlayer(), plataforma: plataforma, modo: modo);
  return mpv;
}

void main() {
  group('ao abrir cada canal', () {
    test('por omissão: 1×, volume, sem silêncio, sem atraso do áudio', () async {
      final mpv = await _abrir(Preferencias.omissao());
      expect(mpv.chamadas, containsAll(['rate=1.0', 'volume=100.0', 'mute=no', 'audio-delay=0.000']));
    });

    test('as preferências guardadas são as aplicadas', () async {
      final p = Preferencias.omissao()
        ..volume = 40
        ..desentrelacar = false
        ..hardware = false;
      final mpv = await _abrir(p);
      expect(mpv.chamadas, containsAll(['volume=40.0', 'hwdec=no']));
    });

    test('Windows: a descodificação por hardware muda-se sem recriar o player (hwdec)', () async {
      expect((await _abrir(Preferencias.omissao())).chamadas, contains('hwdec=auto-safe'));
    });

    test('Android: o hwdec vem da configuração do player (não se mexe ao abrir)', () async {
      final mpv = await _abrir(Preferencias.omissao(), plataforma: PlataformaVideo.android);
      expect(mpv.chamadas.where((c) => c.startsWith('hwdec')), isEmpty);
    });

    test('silêncio e atraso do áudio da sessão passam para o canal seguinte', () async {
      final s = SessaoPlayer()
        ..silencio = true
        ..atrasoAudio = const Duration(milliseconds: -250);
      final mpv = await _abrir(Preferencias.omissao(), sessao: s);
      expect(mpv.chamadas, containsAll(['mute=yes', 'audio-delay=-0.250']));
    });

    test('a velocidade volta sempre a 1× (não é preferência)', () async {
      final mpv = await _abrir(Preferencias.omissao(), sessao: SessaoPlayer());
      expect(mpv.chamadas.where((c) => c.startsWith('rate')), ['rate=1.0']);
    });
  });

  group('desentrelaçamento ao abrir (o meio decide-se com a imagem: desentrelacamento.dart)', () {
    test('Windows: deinterlace=no (o yadif que o deinterlace=yes pedia não existe no ffmpeg incluído)', () async {
      // visto no libmpv da app: "filter 'yadif' not found or failed to allocate"
      final mpv = await _abrir(Preferencias.omissao());
      expect(mpv.props['deinterlace'], 'no');
      expect(mpv.chamadas.where((c) => c.startsWith('deinterlace=yes') || c.startsWith('deinterlace=auto')), isEmpty);
      expect(mpv.chamadas.where((c) => c.startsWith('vf=lavfi')), isEmpty);
    });

    test('Android (direto ou Compatível): não se toca no deinterlace nem no vf do mpv', () async {
      for (final modo in ModoDescodificacao.values) {
        final mpv = await _abrir(Preferencias.omissao(), plataforma: PlataformaVideo.android, modo: modo);
        expect(mpv.chamadas.where((c) => c.startsWith('deinterlace') || c.startsWith('vf')), isEmpty);
      }
    });

    test('com o filtro do canal anterior no vf: tira-se ao abrir (senão o bwdif levava canais progressivos)', () async {
      for (final p in [PlataformaVideo.windows, PlataformaVideo.android]) {
        final mpv = MpvFalso();
        await aplicarAoAbrir(mpv, Preferencias.omissao(), SessaoPlayer(),
            plataforma: p, modo: ModoDescodificacao.compativel, limparFiltro: true);
        expect(mpv.chamadas, contains('vf='), reason: '$p');
      }
      final mpv = MpvFalso();
      await aplicarAoAbrir(mpv, Preferencias.omissao(), SessaoPlayer(),
          plataforma: PlataformaVideo.windows, modo: ModoDescodificacao.direto);
      expect(mpv.chamadas.where((c) => c.startsWith('vf')), isEmpty);
    });

    test('um mpv que falha nunca impede o canal de abrir', () async {
      await aplicarAoAbrir(_MpvQueFalha(), Preferencias.omissao(), SessaoPlayer(),
          plataforma: PlataformaVideo.windows, modo: ModoDescodificacao.direto);
    });
  });

  test('cada formato de imagem dá o ajuste do vídeo', () {
    expect(ajusteVideo(FormatoImagem.ajustar), (fit: BoxFit.contain, aspecto: null, escala: 1.0));
    expect(ajusteVideo(FormatoImagem.preencher), (fit: BoxFit.cover, aspecto: null, escala: 1.0));
    expect(ajusteVideo(FormatoImagem.esticar), (fit: BoxFit.fill, aspecto: null, escala: 1.0));
    expect(ajusteVideo(FormatoImagem.r16x9), (fit: BoxFit.contain, aspecto: 16 / 9, escala: 1.0));
    expect(ajusteVideo(FormatoImagem.r4x3), (fit: BoxFit.contain, aspecto: 4 / 3, escala: 1.0));
    expect(ajusteVideo(FormatoImagem.zoom), (fit: BoxFit.contain, aspecto: null, escala: 1.25));
  });

  test('velocidades e textos', () {
    expect(velocidades, [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]);
    expect(velocidades.map(textoVelocidade), ['0,5×', '0,75×', '1×', '1,25×', '1,5×', '2×']);
    expect(textoAtrasoAudio(Duration.zero), '0 ms');
    expect(textoAtrasoAudio(const Duration(milliseconds: 150)), '+150 ms');
    expect(textoAtrasoAudio(const Duration(milliseconds: -1000)), '−1000 ms');
  });

  test('atraso do áudio: passos de 50 ms entre −1 s e +1 s', () {
    expect(passoAtrasoAudio(Duration.zero, 1), const Duration(milliseconds: 50));
    expect(passoAtrasoAudio(const Duration(milliseconds: 950), 1), const Duration(seconds: 1));
    expect(passoAtrasoAudio(const Duration(seconds: 1), 1), const Duration(seconds: 1));
    expect(passoAtrasoAudio(const Duration(seconds: -1), -1), const Duration(seconds: -1));
  });
}

class _MpvQueFalha implements MotorMpv {
  @override
  Future<String> getProperty(String p) => Future.error(StateError('fechado'));
  @override
  Future<void> setProperty(String p, String v) => Future.error(StateError('fechado'));
  @override
  Future<void> setRate(double r) => Future.error(StateError('fechado'));
  @override
  Future<void> setVolume(double v) => Future.error(StateError('fechado'));
  @override
  Future<void> command(List<String> c) => Future.error(StateError('fechado'));
}
