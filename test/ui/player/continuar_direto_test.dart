import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/continuar_direto.dart';
import 'package:player_iptv/ui/player/progresso.dart';

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

  group('ContinuarDireto.eDireto = o classificador da barra de progresso (eDiretoMpv)', () {
    test('o direto TS no corte (visto no emulador: seekable=no) continua a ser direto e reabre-se', () {
      expect(ContinuarDireto.eDireto('no', partiallySeekable: ''), isTrue);
      expect(ContinuarDireto.eDireto('no', partiallySeekable: 'no'), isTrue);
      expect(
          ContinuarDireto.deve(
              fimDoBuffer: true,
              aAbrir: false,
              erro: false,
              aTocar: true,
              direto: ContinuarDireto.eDireto('no', partiallySeekable: 'no')),
          isTrue,
          reason: 'é a reabertura que corrige os saltos para trás');
    });
    test('só dá para andar pelo cache (partially-seekable): direto', () {
      expect(ContinuarDireto.eDireto('yes', partiallySeekable: 'yes'), isTrue);
    });
    test('ficheiro com fim (seekable sem ser só pelo cache): não é direto', () {
      expect(ContinuarDireto.eDireto('yes', partiallySeekable: 'no'), isFalse);
      expect(eDiretoMpv(seekable: 'yes', partiallySeekable: 'no'), isFalse);
    });
    test('o mesmo resultado que a barra de progresso', () {
      for (final s in ['yes', 'no', '']) {
        for (final p in ['yes', 'no', '']) {
          final j = janelaDe({'time-pos': '5', 'duration': '60', 'seekable': s, 'partially-seekable': p})!;
          expect(j.direto, ContinuarDireto.eDireto(s, partiallySeekable: p), reason: 'seekable=$s partially=$p');
        }
      }
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

  group('ContinuarDireto.falhou (o que o player chama em cada erro durante "A carregar…")', () {
    testWidgets('dois erros da mesma tentativa (tcp + "Failed to open") gastam uma só espera; '
        'a sequência 1 -> 2 -> 4 s acontece toda antes do cartão', (t) async {
      final c = ContinuarDireto();
      var pedido = 1;
      final reaberturas = <Duration>[];
      var decorrido = Duration.zero;
      void reabrir() {
        reaberturas.add(decorrido);
        pedido++;
      }

      Future<void> avancar(Duration d) async {
        decorrido += d;
        await t.pump(d);
      }

      for (final espera in ContinuarDireto.esperas) {
        // a ligação falha: o media_kit manda a linha do tcp e a do "Failed to open"
        expect(c.falhou(pedido, reabrir), Retoma.agendada);
        expect(c.falhou(pedido, reabrir), Retoma.jaAgendada, reason: 'o 2.º erro do mesmo pedido não gasta outra');
        await avancar(espera - const Duration(milliseconds: 1));
        expect(reaberturas.length, ContinuarDireto.esperas.indexOf(espera), reason: 'ainda à espera');
        await avancar(const Duration(milliseconds: 1));
      }
      expect(reaberturas, const [Duration(seconds: 1), Duration(seconds: 3), Duration(seconds: 7)]);
      expect(c.falhou(pedido, reabrir), Retoma.desistir, reason: 'só agora o cartão (~7 s depois do corte)');
      expect(c.falhou(pedido, reabrir), Retoma.desistir);
    });

    testWidgets('voltar a haver imagem esquece as falhas; canal novo cancela a reabertura marcada', (t) async {
      final c = ContinuarDireto();
      var reabriu = 0;
      expect(c.falhou(1, () => reabriu++), Retoma.agendada);
      c.reiniciar(); // o utilizador mudou de canal
      await t.pump(const Duration(seconds: 2));
      expect(reabriu, 0);
      expect(c.falhou(2, () => reabriu++), Retoma.agendada);
      await t.pump(const Duration(seconds: 1));
      expect(reabriu, 1);
      c.abriu();
      expect(c.falhou(3, () => reabriu++), Retoma.agendada);
      await t.pump(const Duration(seconds: 1));
      expect(reabriu, 2, reason: 'depois de abrir, a próxima falha volta a esperar 1 s');
    });
  });

  group('ContinuarDireto.cortadoAntesDoFim (um ficheiro com fim que parou cedo)', () {
    test('parou mais de 10 s antes da duração: foi um corte', () {
      expect(ContinuarDireto.cortadoAntesDoFim(posicao: const Duration(minutes: 20), duracao: const Duration(minutes: 90)),
          isTrue);
    });
    test('chegou (quase) ao fim: acabou', () {
      expect(ContinuarDireto.cortadoAntesDoFim(posicao: const Duration(seconds: 5395), duracao: const Duration(minutes: 90)),
          isFalse);
    });
    test('duração desconhecida: não se sabe, não é corte', () {
      expect(ContinuarDireto.cortadoAntesDoFim(posicao: const Duration(minutes: 1), duracao: Duration.zero), isFalse);
    });
  });
}
