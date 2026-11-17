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
    test('por omissão: 1×, volume, sem silêncio, sem atraso do áudio, desentrelaçamento ligado', () async {
      final mpv = await _abrir(Preferencias.omissao());
      expect(mpv.chamadas,
          containsAll(['rate=1.0', 'volume=100.0', 'mute=no', 'audio-delay=0.000', 'deinterlace=auto']));
      expect(mpv.props['deinterlace'], 'auto');
    });

    test('as preferências guardadas são as aplicadas', () async {
      final p = Preferencias.omissao()
        ..volume = 40
        ..desentrelacar = false
        ..hardware = false;
      final mpv = await _abrir(p);
      expect(mpv.chamadas, containsAll(['volume=40.0', 'deinterlace=no', 'vf=', 'hwdec=no']));
      expect(mpv.chamadas, isNot(contains('deinterlace=auto')));
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

  group('desentrelaçamento', () {
    test('Android direto: não se toca no mpv (o descodificador do aparelho trata disso)', () async {
      final mpv = await _abrir(Preferencias.omissao(), plataforma: PlataformaVideo.android);
      expect(mpv.chamadas.where((c) => c.startsWith('deinterlace') || c.startsWith('vf')), isEmpty);
    });

    test('Android Compatível com libmpv sem "auto": filtro bwdif só nas imagens entrelaçadas', () async {
      final mpv = await _abrir(Preferencias.omissao(),
          plataforma: PlataformaVideo.android, modo: ModoDescodificacao.compativel, aceitaAuto: false);
      expect(mpv.props['vf'], 'lavfi=[bwdif=deint=interlaced]');
      expect(mpv.props['deinterlace'], 'no');
    });

    test('Windows com hardware e libmpv sem "auto": deinterlace=yes (o mpv escolhe o desentrelaçador '
        'das imagens da GPU; um filtro lavfi nelas partia o vídeo)', () async {
      final mpv = await _abrir(Preferencias.omissao(), aceitaAuto: false);
      expect(mpv.props['deinterlace'], 'yes');
      expect(mpv.props['vf'], '');
      expect(mpv.chamadas.where((c) => c.startsWith('vf=lavfi')), isEmpty);
    });

    test('Windows em software e libmpv sem "auto": o filtro (imagens na memória)', () async {
      final mpv = await _abrir(Preferencias.omissao()..hardware = false, aceitaAuto: false);
      expect(mpv.props['vf'], 'lavfi=[bwdif=deint=interlaced]');
    });

    test('desligar depois do filtro tira-o', () async {
      final mpv = MpvFalso(aceitaAuto: false);
      expect(await aplicarDesentrelacamento(mpv, ligado: true, temEfeito: true, imagensNaGpu: false), isTrue);
      expect(mpv.props['vf'], isNot(''));
      expect(await aplicarDesentrelacamento(mpv, ligado: false, temEfeito: true, imagensNaGpu: false), isFalse);
      expect(mpv.props['vf'], '');
      expect(mpv.props['deinterlace'], 'no');
    });

    test('sem efeito: devolve falso e não mexe', () async {
      final mpv = MpvFalso();
      expect(await aplicarDesentrelacamento(mpv, ligado: true, temEfeito: false, imagensNaGpu: true), isFalse);
      expect(mpv.chamadas, isEmpty);
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
