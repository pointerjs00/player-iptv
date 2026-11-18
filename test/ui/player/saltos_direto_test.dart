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
  double excessoDuracao = 1.6;
  bool semCacheState = false;
  final comandos = <String>[];

  @override
  Future<void> command(List<String> c) async {
    comandos.add(c.join(' '));
    if (c.first == 'seek') posicao = (posicao + double.parse(c[1])).clamp(inicioCache, fimCache);
  }

  @override
  Future<String> getProperty(String p) async => switch (p) {
        'time-pos' => '$posicao',
        // como o mpv: a duração à frente pode passar o fim procurável (até ~1,6 s, visto num
        // portal); o fim procurável é o do intervalo em seekable-ranges
        'demuxer-cache-duration' => '${fimCache + excessoDuracao - posicao}',
        'demuxer-cache-state' => semCacheState
            ? ''
            : '{"seekable-ranges":[{"start":$inicioCache,"end":$fimCache}],"cache-end":${fimCache + 0.4}}',
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

  test('avançar vai até ao fim do buffer (o mais recente recebido), mesmo já "em direto"', () async {
    // em direto pelo relógio, mas com 3 s já recebidos à frente
    expect(await saltos.avancar(), isNull);
    expect(mpv.comandos, ['seek 2.500 relative'],
        reason: 'o fim procurável menos ${SaltosDireto.margemFim.inMilliseconds} ms (não a duração à frente, que passa o fim)');
    expect(mpv.posicao, 102.5);
    expect(relogio.emDireto, isTrue);
    expect(relogio.atraso, Duration.zero);
  });

  test('a margem antes do fim: o tempo entre ler o fim e o seek (a imagem anda) não o faz passar', () async {
    // visto no emulador: sem margem, o 3.º → deu "Cannot seek in this stream" (o seek relativo
    // conta da posição de quando chega ao mpv, uns ms depois da leitura)
    expect(SaltosDireto.margemFim, greaterThan(Duration.zero));
    expect(SaltosDireto.margemFim, lessThanOrEqualTo(const Duration(seconds: 1)));
  });

  test('no fim do buffer: avisa e não faz seek', () async {
    mpv.fimCache = 100.3;
    expect(await saltos.avancar(), 'Já está no fim do buffer');
    expect(mpv.comandos, isEmpty);
  });

  test('avançar 10 s com mais buffer à frente: anda os 10 s', () async {
    mpv.fimCache = 130;
    relogio.recuou(const Duration(seconds: 4));
    expect(await saltos.avancar(), isNull);
    expect(mpv.comandos, ['seek 10.000 relative'], reason: 'o relógio já não limita: o buffer à frente é que manda');
    expect(relogio.atraso, Duration.zero);
  });

  test('sem demuxer-cache-state: pela duração à frente, com 1 s de margem', () async {
    mpv.semCacheState = true;
    mpv.excessoDuracao = 0;
    expect(await saltos.avancar(), isNull);
    expect(mpv.comandos, ['seek 2.000 relative']);
  });

  test('voltar ao direto: com o atraso todo no buffer à frente, vai até ao fim do buffer', () async {
    await saltos.recuar();
    await saltos.recuar();
    mpv.comandos.clear();
    expect(await saltos.voltarAoDireto(), VoltaAoDireto.porSeek);
    expect(mpv.comandos, ['seek 22.500 relative'], reason: 'os 20 s de atraso e os 3 s já recebidos à frente');
    expect(relogio.emDireto, isTrue);
    expect(mpv.posicao, 102.5);
  });

  test('em direto mas com buffer à frente: "voltar ao direto" vai até ao fim do buffer', () async {
    expect(await saltos.voltarAoDireto(), VoltaAoDireto.porSeek);
    expect(mpv.comandos, ['seek 2.500 relative']);
  });

  test('em direto e no fim do buffer: "voltar ao direto" não faz nada', () async {
    mpv.fimCache = 100.2;
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
    expect(relogio.atraso, const Duration(milliseconds: 26500));
    expect(relogio.emDireto, isFalse);
  });

  group('irPara (barra de progresso: arrastar/setas)', () {
    test('1 s para trás no cache: faz o seek e não avisa', () async {
      expect(await saltos.irPara(99), isNull);
      expect(mpv.comandos, ['seek -1.000 relative']);
      expect(relogio.atraso, const Duration(seconds: 1));
    });

    test('para trás no cache: seek relativo pela diferença e o atraso cresce o que recuou', () async {
      expect(await saltos.irPara(70), isNull);
      expect(mpv.comandos, ['seek -30.000 relative']);
      expect(mpv.posicao, 70);
      expect(relogio.atraso, const Duration(seconds: 30));
    });

    test('nunca sai do cache para trás: conta só o que o mpv recuou', () async {
      await saltos.irPara(10);
      expect(mpv.posicao, 40);
      expect(relogio.atraso, const Duration(seconds: 60));
    });

    test('para a frente: até ao fim do buffer, nunca para lá dele', () async {
      await saltos.irPara(70);
      mpv.comandos.clear();
      expect(await saltos.irPara(85), isNull);
      expect(mpv.comandos, ['seek 15.000 relative']);
      expect(relogio.atraso, const Duration(seconds: 15));
      // pedir para lá do fim do buffer: só até ao fim (o mais recente recebido)
      mpv.comandos.clear();
      await saltos.irPara(500);
      expect(mpv.comandos, ['seek 17.500 relative']);
      expect(mpv.posicao, 102.5);
      expect(relogio.atraso, Duration.zero);
    });

    test('já no fim do buffer, para a frente: avisa e não faz seek', () async {
      mpv.fimCache = 100.4;
      expect(await saltos.irPara(103), 'Já está no fim do buffer');
      expect(mpv.comandos, isEmpty);
    });

    test('em direto pelo relógio, arrastar para o fim do buffer: vai lá', () async {
      expect(await saltos.irPara(103), isNull);
      expect(mpv.comandos, ['seek 2.500 relative']);
    });

    test('menos de 1 s: não faz nada (nem diz "Não há mais para recuar"); sem time-pos: não faz nada', () async {
      expect(await saltos.irPara(100.3), isNull);
      expect(await saltos.irPara(99.3), isNull, reason: 'o _recuar diria "Não há mais para recuar" abaixo de 1 s');
      expect(await saltos.irPara(100.8), isNull);
      expect(mpv.comandos, isEmpty);
      final s = SaltosDireto(_SemPosicao(), relogio, esperar: Duration.zero);
      expect(await s.irPara(50), isNull);
      expect(relogio.atraso, Duration.zero);
    });
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

  test('zapping a meio de "voltar ao direto": não faz seek no canal novo nem pede reabrir', () async {
    await saltos.recuar();
    mpv.comandos.clear();
    expect(await saltos.voltarAoDireto(aindaValido: () => false), VoltaAoDireto.cancelado);
    expect(mpv.comandos, isEmpty);
    relogio.pausou();
    t = t.add(const Duration(minutes: 3));
    expect(await saltos.voltarAoDireto(aindaValido: () => false), VoltaAoDireto.cancelado);
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
