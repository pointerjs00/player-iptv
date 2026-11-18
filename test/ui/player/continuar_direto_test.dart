import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/continuar_direto.dart';

void main() {
  group('ContinuarDireto.deve (o buffer acabou: pedir o canal de novo)', () {
    bool deve({bool fim = true, bool aAbrir = false, bool erro = false, bool aTocar = true, bool direto = true}) =>
        ContinuarDireto.deve(fimDoBuffer: fim, aAbrir: aAbrir, erro: erro, aTocar: aTocar, direto: direto);

    test('um direto a tocar, aberto e sem erro: continua', () => expect(deve(), isTrue));
    test('não é o fim do buffer: nada', () => expect(deve(fim: false), isFalse));
    test('a abrir (o vigia trata), com erro ou em pausa: nada', () {
      expect(deve(aAbrir: true), isFalse);
      expect(deve(erro: true), isFalse);
      expect(deve(aTocar: false), isFalse);
    });
    test('um ficheiro (VOD, filme de uma lista M3U) que chegou ao fim acaba: não recomeça', () {
      expect(deve(direto: false), isFalse);
    });
  });

  group('ContinuarDireto.eDireto (pela propriedade "seekable" do mpv)', () {
    test('não dá para andar no ficheiro: direto', () => expect(ContinuarDireto.eDireto('no'), isTrue));
    test('o mpv não respondeu: trata-se como direto', () => expect(ContinuarDireto.eDireto(''), isTrue));
    test('dá para andar (ficheiro com fim): não é direto', () => expect(ContinuarDireto.eDireto('yes'), isFalse));
  });

  group('ContinuarDireto.permitir (nunca em ciclo)', () {
    test('um portal que corta a cada 6 s mas deixa ver continua sempre', () {
      final c = ContinuarDireto();
      for (var i = 0; i < 30; i++) {
        expect(c.permitir(tocou: const Duration(seconds: 6)), isTrue, reason: 'corte $i');
      }
    });
    test('um canal que reabre sem tocar quase nada pára ao fim de ${ContinuarDireto.maximoSemProveito}', () {
      final c = ContinuarDireto();
      for (var i = 0; i < ContinuarDireto.maximoSemProveito; i++) {
        expect(c.permitir(tocou: const Duration(seconds: 1)), isTrue);
      }
      expect(c.permitir(tocou: const Duration(seconds: 1)), isFalse);
    });
    test('uma reabertura com proveito volta a contar do zero', () {
      final c = ContinuarDireto();
      for (var i = 0; i < ContinuarDireto.maximoSemProveito; i++) {
        c.permitir(tocou: Duration.zero);
      }
      expect(c.permitir(tocou: ContinuarDireto.proveito), isTrue);
      expect(c.permitir(tocou: Duration.zero), isTrue);
    });
    test('canal novo recomeça a contagem', () {
      final c = ContinuarDireto();
      for (var i = 0; i < ContinuarDireto.maximoSemProveito; i++) {
        c.permitir(tocou: Duration.zero);
      }
      c.reiniciar();
      expect(c.permitir(tocou: Duration.zero), isTrue);
    });
  });

  group('ContinuarDireto.esperaAntesDeTentar (uma reabertura que falha)', () {
    test('tenta de novo com espera crescente e depois desiste (cartão de erro)', () {
      final c = ContinuarDireto();
      expect(c.esperaAntesDeTentar(), const Duration(seconds: 1));
      expect(c.esperaAntesDeTentar(), const Duration(seconds: 2));
      expect(c.esperaAntesDeTentar(), const Duration(seconds: 4));
      expect(c.esperaAntesDeTentar(), isNull);
    });
    test('quando volta a haver imagem, as falhas esquecem-se', () {
      final c = ContinuarDireto();
      c.esperaAntesDeTentar();
      c.esperaAntesDeTentar();
      c.abriu();
      expect(c.esperaAntesDeTentar(), const Duration(seconds: 1));
    });
  });
}
