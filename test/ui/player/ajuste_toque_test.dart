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
  @override
  Future<void> volumeInicial(int percentagem) async {}
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
}
