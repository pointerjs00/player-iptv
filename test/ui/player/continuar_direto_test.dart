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

  group('reabrir depois de ir até ao fim do buffer: não repete o que já se viu (os PTS)', () {
    // visto no libmpv da app (mag.max-cdn.com, RTP 1 HD): ligação A com demuxer-start-time 10420.003,
    // saltou para o fim do buffer (time-pos 29.497); a ligação B começou em 10430.008, por isso o que
    // A viu por último está em B a 19.492 s — abrir B do início repetia ~19,5 s
    test('a posição no stream novo do que se viu por último', () {
      expect(ContinuarDireto.posicaoNoNovo(inicioAntigo: 10420.003, posicaoAntiga: 29.497, inicioNovo: 10430.008),
          closeTo(19.492, 1e-6));
      expect(ContinuarDireto.posicaoNoNovo(inicioAntigo: null, posicaoAntiga: 29.5, inicioNovo: 10430), isNull);
      expect(ContinuarDireto.posicaoNoNovo(inicioAntigo: 1, posicaoAntiga: null, inicioNovo: 10430), isNull);
      expect(ContinuarDireto.posicaoNoNovo(inicioAntigo: 1, posicaoAntiga: 2, inicioNovo: null), isNull);
    });

    test('com o alvo no cache: salta logo para lá', () {
      final r = ContinuarDireto.saltoAoRetomar(alvo: 19.5, posicao: 0.3, aFrente: 29, ultimaTentativa: false);
      expect(r.salto, closeTo(19.2, 1e-9));
      expect(r.esperar, isFalse);
    });

    test('o alvo ainda não chegou: espera; na última tentativa vai até onde dá (nunca para trás)', () {
      final r = ContinuarDireto.saltoAoRetomar(alvo: 19.5, posicao: 0.3, aFrente: 8, ultimaTentativa: false);
      expect(r.salto, isNull);
      expect(r.esperar, isTrue);
      final u = ContinuarDireto.saltoAoRetomar(alvo: 19.5, posicao: 0.3, aFrente: 8, ultimaTentativa: true);
      expect(u.salto, 8);
      expect(u.esperar, isFalse);
    });

    test('o que se viu está antes do início do stream novo (o caso normal, em direto): não salta', () {
      // visto: A sem saltos acabou 0,9 s antes do início de B
      final r = ContinuarDireto.saltoAoRetomar(alvo: -0.888, posicao: 0.2, aFrente: 20, ultimaTentativa: false);
      expect(r.salto, isNull);
      expect(r.esperar, isFalse);
      expect(ContinuarDireto.saltoAoRetomar(alvo: 0.9, posicao: 0.2, aFrente: 20, ultimaTentativa: false).salto, isNull,
          reason: 'menos de 1 s não vale um seek');
    });

    test('PTS sem sentido (o servidor recomeçou os tempos): não salta', () {
      final r = ContinuarDireto.saltoAoRetomar(alvo: 5000, posicao: 0.2, aFrente: 30, ultimaTentativa: true);
      expect(r.salto, isNull);
    });

    test('sem saber o buffer à frente: espera e, no fim, não salta às cegas', () {
      expect(ContinuarDireto.saltoAoRetomar(alvo: 19, posicao: 0, aFrente: null, ultimaTentativa: false).esperar, isTrue);
      expect(ContinuarDireto.saltoAoRetomar(alvo: 19, posicao: 0, aFrente: null, ultimaTentativa: true).salto, isNull);
    });
  });

  group('ronda 2: o proveito conta só o que cada ligação deu de novo', () {
    test('um VOD que o servidor corta ao fim de ~1 s (reaberto em start: posição) chega ao cartão', () {
      // a ligação abre no ponto do filme (time-pos 600) e corta a 601: deu 1 s, não 601
      final c = ContinuarDireto();
      var desistiu = false;
      var pos = 600.0;
      for (var i = 0; i < 6 && !desistiu; i++) {
        final l = LigacaoDireto()..abriu(pos);
        pos += 1;
        desistiu = !c.permitir(tocou: l.proveito(parede: const Duration(milliseconds: 1200), posicaoNoCorte: pos));
      }
      expect(desistiu, isTrue);
    });

    test('salto automático depois de reabrir + corte 2 s depois, várias vezes seguidas: chega ao cartão', () {
      final c = ContinuarDireto();
      var reaberturas = 0;
      var desistiu = false;
      while (!desistiu && reaberturas < 10) {
        reaberturas++;
        final l = LigacaoDireto()..abriu(0.3);
        l.saltou(20.3); // o salto para onde se estava (não é imagem nova)
        desistiu = !c.permitir(tocou: l.proveito(parede: const Duration(milliseconds: 2800), posicaoNoCorte: 22.3));
      }
      expect(desistiu, isTrue);
      expect(reaberturas, ContinuarDireto.maximoSemProveito + 1);
    });

    test('quem salta à mão para o fim do buffer: a ligação deu tudo o que se andou', () {
      final l = LigacaoDireto()..abriu(0.2);
      expect(l.proveito(parede: const Duration(seconds: 2), posicaoNoCorte: 29.5), const Duration(milliseconds: 29300));
    });

    test('sem posições: a parede', () {
      expect(LigacaoDireto().proveito(parede: const Duration(seconds: 3), posicaoNoCorte: null), const Duration(seconds: 3));
      expect((LigacaoDireto()..abriu(5)).proveito(parede: const Duration(seconds: 3), posicaoNoCorte: 4),
          const Duration(seconds: 3));
    });
  });

  group('ronda 2: o ponto do corte só com os dois PTS', () {
    test('sem demuxer-start-time ou sem time-pos: não se espera pelo salto', () {
      expect(ContinuarDireto.pontoDoCorte(inicio: '', posicao: '29.5'), isNull);
      expect(ContinuarDireto.pontoDoCorte(inicio: '10420.003', posicao: ''), isNull);
      expect(ContinuarDireto.pontoDoCorte(inicio: 'nan', posicao: '1'), isNull);
      expect(ContinuarDireto.pontoDoCorte(inicio: '10420.003', posicao: '29.497'), (inicio: 10420.003, posicao: 29.497));
    });
  });

  group('ronda 2: o som durante o salto depois de reabrir', () {
    test('sem som enquanto se espera; volta só depois do salto e da primeira imagem', () {
      final m = MudoDuranteSalto();
      expect(m.comecar(), 'yes');
      expect(m.acabouSalto(silencio: false, temImagem: false), isNull, reason: 'ainda sem imagem: o som não volta');
      expect(m.primeiraImagem(silencio: false), 'no');
      expect(m.primeiraImagem(silencio: false), isNull, reason: 'uma vez só');
    });

    test('com imagem já à vista, o som volta com o salto (conforme o silêncio da sessão)', () {
      final m = MudoDuranteSalto()..comecar();
      expect(m.primeiraImagem(silencio: false), isNull, reason: 'o salto ainda não acabou');
      expect(m.acabouSalto(silencio: true, temImagem: true), 'yes');
    });

    test('mudar o silêncio durante a espera não liga o som escondido', () {
      final m = MudoDuranteSalto()..comecar();
      expect(m.mudouSilencio(false), isNull);
      expect(m.acabouSalto(silencio: false, temImagem: true), 'no');
      expect(m.mudouSilencio(true), 'yes', reason: 'fora da espera vai logo para o mpv');
    });

    test('canal novo: esquece', () {
      final m = MudoDuranteSalto()..comecar();
      m.reiniciar();
      expect(m.mudouSilencio(false), 'no');
      expect(m.primeiraImagem(silencio: false), isNull);
    });
  });
}
