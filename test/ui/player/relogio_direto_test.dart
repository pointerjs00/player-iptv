import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/relogio_direto.dart';

void main() {
  late DateTime t;
  late RelogioDireto r;
  void passar(int ms) => t = t.add(Duration(milliseconds: ms));
  setUp(() {
    t = DateTime(2026, 11, 17, 20);
    r = RelogioDireto(agora: () => t);
  });

  test('a tocar a 1× fica em direto', () {
    passar(60000);
    expect(r.atraso, Duration.zero);
    expect(r.emDireto, isTrue);
  });

  test('recuar 10 s deixa 10 s atrás do direto; avançar volta', () {
    r.recuou(const Duration(seconds: 10));
    passar(5000);
    expect(r.atraso, const Duration(seconds: 10));
    expect(r.emDireto, isFalse);
    r.avancou(const Duration(seconds: 10));
    expect(r.emDireto, isTrue);
  });

  test('avançar para lá do direto (o buffer à frente) deixa o atraso em zero, nunca negativo', () {
    r.recuou(const Duration(seconds: 4));
    r.avancou(const Duration(seconds: 10));
    expect(r.atraso, Duration.zero);
    expect(r.emDireto, isTrue);
  });

  test('a pausa conta como atraso (o direto continua)', () {
    r.pausou();
    passar(7000);
    expect(r.atraso, const Duration(seconds: 7));
    r.retomou();
    passar(30000);
    expect(r.atraso, const Duration(seconds: 7));
  });

  test('velocidades diferentes de 1× mudam o atraso ao longo do tempo', () {
    r.mudouVelocidade(0.5);
    passar(10000);
    expect(r.atraso, const Duration(seconds: 5));
    r.mudouVelocidade(2);
    passar(2000);
    expect(r.atraso, const Duration(seconds: 3));
    passar(10000);
    expect(r.atraso, Duration.zero, reason: 'nunca à frente do direto');
    expect(r.emDireto, isTrue);
  });

  test('pausar e retomar duas vezes seguidas não conta a dobrar', () {
    r.pausou();
    r.pausou();
    passar(1000);
    r.retomou();
    r.retomou();
    passar(1000);
    expect(r.atraso, const Duration(seconds: 1));
  });

  test('pausa de minutos: o atraso é o real (o direto não espera pelo buffer)', () {
    r.pausou();
    passar(4 * 60 * 1000);
    r.retomou();
    expect(r.atraso, const Duration(minutes: 4));
    expect(r.emDireto, isFalse);
  });

  test('voltar ao direto e trocar de canal recomeçam em direto', () {
    r.recuou(const Duration(seconds: 20));
    r.voltouAoDireto();
    expect(r.emDireto, isTrue);
    r.pausou();
    passar(3000);
    r.reiniciar();
    passar(3000);
    expect(r.atraso, Duration.zero);
    expect(r.velocidade, 1);
  });

  test('menos de 2 s atrás ainda é "em direto"', () {
    r.recuou(const Duration(milliseconds: 1500));
    expect(r.emDireto, isTrue);
    r.recuou(const Duration(seconds: 1));
    expect(r.emDireto, isFalse);
  });

  test('texto do atraso', () {
    expect(textoAtraso(const Duration(seconds: 7)), '−0:07');
    expect(textoAtraso(const Duration(seconds: 75)), '−1:15');
    expect(textoAtraso(const Duration(minutes: 61, seconds: 2)), '−1:01:02');
  });
}
