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

  test('voltar ao direto: com o atraso todo no buffer à frente, seek pelo atraso todo', () async {
    await saltos.recuar();
    await saltos.recuar();
    mpv.comandos.clear();
    expect(await saltos.voltarAoDireto(), VoltaAoDireto.porSeek);
    expect(mpv.comandos, ['seek 20.000 relative']);
    expect(relogio.emDireto, isTrue);
    expect(mpv.posicao, 100);
  });

  test('em direto, "voltar ao direto" não faz nada', () async {
    expect(await saltos.voltarAoDireto(), VoltaAoDireto.jaEmDireto);
    expect(mpv.comandos, isEmpty);
  });

  test('pausa longa (o buffer à frente encheu e o mpv deixou de ler): reabre o canal, não diz "em direto"',
      () async {
    relogio.pausou();
    t = t.add(const Duration(minutes: 3));
    relogio.retomou();
    mpv.fimCache = mpv.posicao + 67; // 64 MiB a ~8 Mb/s
    expect(await saltos.voltarAoDireto(), VoltaAoDireto.reabrir);
    expect(mpv.comandos, isEmpty, reason: 'o seek só chegava ao fim do cache, ainda ~2 min atrás');
    expect(relogio.emDireto, isFalse);
    expect(relogio.atraso, const Duration(minutes: 3), reason: 'o atraso real não é cortado pelo buffer');
  });

  test('buffer à frente desconhecido: reabre (só assim é certo chegar ao direto)', () async {
    final s = SaltosDireto(_SemPosicao(), relogio, esperar: Duration.zero);
    relogio.recuou(const Duration(seconds: 20));
    expect(await s.voltarAoDireto(), VoltaAoDireto.reabrir);
  });

  test('avançar conta só o que o mpv avançou de facto (fim do cache à frente)', () async {
    relogio.pausou();
    t = t.add(const Duration(seconds: 30));
    relogio.retomou();
    mpv.fimCache = mpv.posicao + 4;
    expect(await saltos.avancar(), isNull);
    expect(relogio.atraso, const Duration(seconds: 26));
    expect(relogio.emDireto, isFalse);
  });

  test('sem time-pos (mpv a abrir): conta o pedido', () async {
    final s = SaltosDireto(_SemPosicao(), relogio, esperar: Duration.zero);
    await s.recuar();
    expect(relogio.atraso, const Duration(seconds: 10));
  });

  test('um mpv que falha não lança', () async {
    final s = SaltosDireto(_SemPosicao(falha: true), relogio, esperar: Duration.zero);
    await s.recuar();
    await s.avancar();
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
