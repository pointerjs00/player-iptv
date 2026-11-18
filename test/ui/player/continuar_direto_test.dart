import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/continuar_direto.dart';

void main() {
  final t0 = DateTime(2026, 11, 18, 12);

  group('ContinuarDireto.deve (o buffer acabou: pedir o canal de novo)', () {
    test('a tocar, aberto e sem erro: continua', () {
      expect(ContinuarDireto.deve(fimDoBuffer: true, aAbrir: false, erro: false, aTocar: true), isTrue);
    });
    test('não é o fim do buffer: nada', () {
      expect(ContinuarDireto.deve(fimDoBuffer: false, aAbrir: false, erro: false, aTocar: true), isFalse);
    });
    test('a abrir (o vigia trata), com erro ou em pausa: nada', () {
      expect(ContinuarDireto.deve(fimDoBuffer: true, aAbrir: true, erro: false, aTocar: true), isFalse);
      expect(ContinuarDireto.deve(fimDoBuffer: true, aAbrir: false, erro: true, aTocar: true), isFalse);
      expect(ContinuarDireto.deve(fimDoBuffer: true, aAbrir: false, erro: false, aTocar: false), isFalse);
    });
  });

  group('ContinuarDireto.permitir (nunca em ciclo)', () {
    test('cortes espaçados continuam sempre', () {
      final c = ContinuarDireto();
      for (var i = 0; i < 20; i++) {
        expect(c.permitir(t0.add(Duration(minutes: i))), isTrue, reason: 'corte $i');
      }
    });
    test('mais de ${ContinuarDireto.maximo} cortes em ${ContinuarDireto.janela.inSeconds} s: pára (erro)', () {
      final c = ContinuarDireto();
      for (var i = 0; i < ContinuarDireto.maximo; i++) {
        expect(c.permitir(t0.add(Duration(seconds: i * 5))), isTrue);
      }
      expect(c.permitir(t0.add(const Duration(seconds: 30))), isFalse);
    });
    test('canal novo recomeça a contagem', () {
      final c = ContinuarDireto();
      for (var i = 0; i < ContinuarDireto.maximo; i++) {
        c.permitir(t0.add(Duration(seconds: i)));
      }
      c.reiniciar();
      expect(c.permitir(t0.add(const Duration(seconds: 10))), isTrue);
    });
    test('os cortes antigos saem da janela', () {
      final c = ContinuarDireto();
      for (var i = 0; i < ContinuarDireto.maximo; i++) {
        c.permitir(t0.add(Duration(seconds: i)));
      }
      expect(c.permitir(t0.add(ContinuarDireto.janela + const Duration(seconds: 10))), isTrue);
    });
  });
}
