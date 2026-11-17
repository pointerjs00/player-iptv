import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';
import 'package:player_iptv/ui/player/relogio_direto.dart';
import 'package:player_iptv/ui/player/saltos_direto.dart';

/// Um mpv com um cache: `posicao` é o time-pos; um seek relativo move-o dentro de
/// [inicioCache, fimCache] (como o mpv num direto: não sai do que está no cache).
class _MpvCache implements MotorMpv {
  double posicao = 100;
  double inicioCache = 40;
  double fimCache = 103;
  final comandos = <String>[];

  @override
  Future<void> command(List<String> c) async {
    comandos.add(c.join(' '));
    if (c.first == 'seek') posicao = (posicao + double.parse(c[1])).clamp(inicioCache, fimCache);
  }

  @override
  Future<String> getProperty(String p) async => switch (p) {
        'time-pos' => '$posicao',
        'demuxer-cache-duration' => '${fimCache - posicao}',
        _ => '',
      };

  @override
  Future<void> setProperty(String p, String v) async {}
  @override
  Future<void> setRate(double r) async {}
  @override
  Future<void> setVolume(double v) async {}
}

void main() {
  late _MpvCache mpv;
  late RelogioDireto relogio;
  late SaltosDireto saltos;
  late DateTime t;
  setUp(() {
    t = DateTime(2026, 11, 17, 21);
    mpv = _MpvCache();
    relogio = RelogioDireto(agora: () => t);
    saltos = SaltosDireto(mpv, relogio, esperar: Duration.zero);
  });

  test('recuar 10 s: seek relativo e fica 10 s atrás do direto', () async {
    expect(await saltos.recuar(), isNull);
    expect(mpv.comandos, ['seek -10 relative']);
    expect(relogio.atraso, const Duration(seconds: 10));
    expect(relogio.emDireto, isFalse);
  });

  test('recuar conta só o que o mpv recuou de facto (fim do cache para trás)', () async {
    mpv.inicioCache = 94;
    await saltos.recuar();
    expect(relogio.atraso, const Duration(seconds: 6));
    expect(await saltos.recuar(), 'Não há mais para recuar');
    expect(relogio.atraso, const Duration(seconds: 6));
  });

  test('avançar não passa o direto; em direto avisa e não faz seek', () async {
    expect(await saltos.avancar(), 'Já está em direto');
    expect(mpv.comandos, isEmpty);
    relogio.recuou(const Duration(seconds: 4));
    expect(await saltos.avancar(), isNull);
    expect(mpv.comandos, ['seek 4.000 relative']);
    expect(relogio.emDireto, isTrue);
  });

  test('voltar ao direto: seek pelo atraso todo', () async {
    await saltos.recuar();
    await saltos.recuar();
    mpv.comandos.clear();
    await saltos.voltarAoDireto();
    expect(mpv.comandos, ['seek 20.000 relative']);
    expect(relogio.emDireto, isTrue);
    expect(mpv.posicao, 100);
  });

  test('em direto, "voltar ao direto" não faz nada', () async {
    await saltos.voltarAoDireto();
    expect(mpv.comandos, isEmpty);
  });

  test('o atraso fica limitado ao buffer à frente (ex.: depois de a rede parar)', () async {
    await saltos.recuar();
    mpv.fimCache = mpv.posicao + 3;
    t = t.add(const Duration(seconds: 5));
    await saltos.acertarPeloBuffer();
    expect(relogio.atraso, const Duration(seconds: 3));
  });

  test('logo a seguir a um salto não se acerta pelo buffer (o cache ainda está a mexer)', () async {
    await saltos.recuar();
    mpv.fimCache = mpv.posicao + 1;
    await saltos.acertarPeloBuffer();
    expect(relogio.atraso, const Duration(seconds: 10));
  });

  test('sem time-pos (mpv a abrir): conta o pedido', () async {
    final s = SaltosDireto(_SemPosicao(), relogio, esperar: Duration.zero);
    await s.recuar();
    expect(relogio.atraso, const Duration(seconds: 10));
  });

  test('um mpv que falha não lança', () async {
    final s = SaltosDireto(_SemPosicao(falha: true), relogio, esperar: Duration.zero);
    await s.recuar();
    await s.voltarAoDireto();
  });
}

class _SemPosicao implements MotorMpv {
  _SemPosicao({this.falha = false});
  final bool falha;
  @override
  Future<void> command(List<String> c) async {
    if (falha) throw StateError('fechado');
  }

  @override
  Future<String> getProperty(String p) async => falha ? throw StateError('fechado') : '';
  @override
  Future<void> setProperty(String p, String v) async {}
  @override
  Future<void> setRate(double r) async {}
  @override
  Future<void> setVolume(double v) async {}
}
