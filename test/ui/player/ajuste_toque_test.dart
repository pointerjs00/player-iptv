import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/ajuste_toque.dart';

class _Falso implements SistemaAudioBrilho {
  int volumeAtual = 5;
  final pedidosVolume = <int>[];
  final pedidosBrilho = <double?>[];

  @override
  Future<(int, int)?> volume() async => (volumeAtual, 10);
  @override
  Future<void> definirVolume(int indice) async => pedidosVolume.add(indice);
  @override
  Future<double?> brilho() async => 0.5;
  @override
  Future<void> definirBrilho(double? v) async => pedidosBrilho.add(v);
  final mudancas = StreamController<(int, int)>.broadcast();
  @override
  Stream<(int, int)> mudancasVolume() => mudancas.stream;
}

void main() {
  test('o meio do ecrã não é um ajuste (fica para mudar de canal)', () async {
    final a = AjusteToque(sistema: _Falso());
    await pumpEventQueue();
    expect(a.comecar(0.5), isFalse);
    expect(a.terminar(), isFalse);
    expect(a.visivel, isNull);
    a.dispose();
  });

  test('à direita: o volume do sistema sobe aos degraus e a barra aparece', () async {
    final s = _Falso();
    final a = AjusteToque(sistema: s);
    await pumpEventQueue();
    expect(a.comecar(0.9), isTrue);
    await pumpEventQueue();
    expect(a.visivel, ZonaAjuste.volume);
    a.mover(0.12); // 0.12 / 0.6 = +20 %: de 5 para 7
    expect(s.pedidosVolume.last, 7);
    expect(a.nivelVolume, closeTo(0.7, 1e-9));
    expect(a.terminar(), isTrue);
    a.dispose();
  });

  test('à esquerda: o brilho da app nunca chega a zero e volta ao do sistema ao sair', () async {
    final s = _Falso();
    final a = AjusteToque(sistema: s);
    await pumpEventQueue();
    expect(a.comecar(0.1), isTrue);
    expect(a.visivel, ZonaAjuste.brilho);
    a.mover(-5);
    expect(s.pedidosBrilho.last, 0.01);
    a.terminar();
    a.dispose();
    expect(s.pedidosBrilho.last, isNull);
  });

  group('o volume do sistema é o das barras (telemóvel)', () {
    test('as teclas do aparelho (aviso do sistema) mudam o nível e avisam quem ouve', () async {
      final s = _Falso();
      final a = AjusteToque(sistema: s);
      await pumpEventQueue();
      var avisos = 0;
      a.addListener(() => avisos++);
      s.mudancas.add((8, 10));
      await pumpEventQueue();
      expect(a.nivelVolume, closeTo(0.8, 1e-9));
      expect(avisos, 1);
      // o eco do que já se sabe não volta a avisar
      s.mudancas.add((8, 10));
      await pumpEventQueue();
      expect(avisos, 1);
      a.dispose();
    });

    test('durante um deslize, um aviso atrasado não desfaz o dedo', () async {
      final s = _Falso();
      final a = AjusteToque(sistema: s);
      await pumpEventQueue();
      a.comecar(0.9);
      await pumpEventQueue();
      a.mover(0.12); // 5 -> 7
      s.mudancas.add((5, 10));
      await pumpEventQueue();
      expect(a.nivelVolume, closeTo(0.7, 1e-9));
      a.dispose();
    });

    test('a barra do player muda o volume do sistema ao degrau, e um passo é um degrau', () async {
      final s = _Falso();
      final a = AjusteToque(sistema: s);
      await pumpEventQueue();
      expect(a.maxVolume, 10);
      a.definirVolume(0.32);
      expect(s.pedidosVolume.last, 3);
      expect(a.nivelVolume, closeTo(0.3, 1e-9));
      a.passoVolume(1);
      expect(s.pedidosVolume.last, 4);
      a.passoVolume(-1);
      expect(s.pedidosVolume.last, 3);
      a.dispose();
    });

    test('o silêncio põe o sistema a zero e ligar o som repõe o de antes', () async {
      final s = _Falso();
      final a = AjusteToque(sistema: s);
      await pumpEventQueue();
      expect(a.silencio, isFalse);
      a.silenciar(true);
      expect(s.pedidosVolume.last, 0);
      expect(a.silencio, isTrue);
      a.silenciar(false);
      expect(s.pedidosVolume.last, 5);
      expect(a.silencio, isFalse);
      a.dispose();
    });

    test('mexer na barra com o som desligado não repõe o volume de antes por cima', () async {
      final s = _Falso();
      final a = AjusteToque(sistema: s);
      await pumpEventQueue();
      a.silenciar(true);
      a.definirVolume(0.2); // como a barra faz: muda primeiro…
      a.silenciar(false); // …e depois tira o silêncio
      expect(s.pedidosVolume.last, 2);
      a.dispose();
    });
  });
}
