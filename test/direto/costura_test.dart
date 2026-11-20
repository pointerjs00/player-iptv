import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/direto/costura.dart';

import 'ts_sintetico.dart';

/// O primeiro pacote em que a costura por PCR deve começar: o primeiro PUSI de vídeo a partir do
/// primeiro pacote com PCR maior do que o do pacote `ultimo`.
int _esperadoPorPcr(int ultimo, int desde) {
  var k = desde;
  while (!(temPcr(k) && pcrSintetico(k) > pcrSintetico(ultimo))) {
    k++;
  }
  while (!inicioPes(k)) {
    k++;
  }
  return k;
}

void main() {
  group('pontoDeCostura (bytes)', () {
    test('encontra a cauda na ligação nova e devolve a posição logo a seguir', () {
      final antes = tsSintetico(0, 4000);
      final cauda = antes.sublist(antes.length - tamanhoCauda);
      final novo = tsSintetico(1500, 6000); // repete 25 s
      expect(pontoDeCostura(cauda, novo), (4000 - 1500) * 188);
    });

    test('a cauda a meio de um pacote (a ligação anterior acabou a meio dele)', () {
      final antes = tsSintetico(0, 4000).sublist(0, 3999 * 188 + 100);
      final cauda = antes.sublist(antes.length - tamanhoCauda);
      final novo = tsSintetico(1500, 6000);
      expect(pontoDeCostura(cauda, novo), (3999 - 1500) * 188 + 100);
    });

    test('sem a cauda, ou só depois do limite: null', () {
      final antes = tsSintetico(0, 4000);
      final cauda = antes.sublist(antes.length - tamanhoCauda);
      expect(pontoDeCostura(cauda, tsSintetico(1500, 6000, variante: 1)), isNull);
      expect(pontoDeCostura(cauda, tsSintetico(1500, 6000), limite: 1000 * 188), isNull);
      expect(pontoDeCostura(const [], tsSintetico(0, 10)), isNull);
    });
  });

  group('costuraPorPcr', () {
    test('salta o que tem PCR até ao último gravado e começa num início de PES do vídeo', () {
      final novo = tsSintetico(1500, 6000, variante: 1);
      const ultimo = 3999; // o último pacote gravado, que leva PCR
      final p = costuraPorPcr(pcrSintetico(ultimo), novo);
      expect(p, (_esperadoPorPcr(ultimo, 1500) - 1500) * 188);
      expect(p! % 188, 0);
    });

    test('sem PID de vídeo conhecido: no primeiro pacote com PCR maior', () {
      // sem PAT/PMT: só pacotes de vídeo (k % 100 > 1)
      final novo = tsSintetico(2, 99);
      final p = costuraPorPcr(pcrSintetico(43), novo);
      expect(p, (47 - 2) * 188, reason: 'o 47 é o primeiro com PCR depois do 43');
    });

    test('a ligação começa à frente: aceita-a inteira (0)', () {
      expect(costuraPorPcr(pcrSintetico(1000), tsSintetico(3000, 3500)), 0);
    });

    test('sem PCR legível: null', () {
      expect(costuraPorPcr(pcrSintetico(1000), tsSintetico(500, 1500, comPcr: false)), isNull);
      expect(costuraPorPcr(pcrSintetico(1000), List<int>.generate(5000, (i) => i % 251)), isNull);
    });

    test('tudo o que veio é velho: a posição a seguir ao fim (nada a gravar)', () {
      final novo = tsSintetico(500, 900);
      expect(costuraPorPcr(pcrSintetico(1000), novo), novo.length);
    });

    test('um PCR muito para trás (o canal recomeçou): não se compara, null', () {
      final novo = tsSintetico(500, 900);
      expect(costuraPorPcr(pcrSintetico(500) + recuoMaximoPcr + relogioPcr, novo), isNull);
    });
  });

  test('diferencaPcr dá a volta aos 33 bits', () {
    const volta = (1 << 33) * 300;
    expect(diferencaPcr(100, volta - 100), 200);
    expect(diferencaPcr(volta - 100, 100), -200);
    expect(diferencaPcr(5, 3), 2);
  });

  group('LeitorTs', () {
    test('acha a PMT, o PID do PCR e do vídeo e o último PCR, mesmo em pedaços tortos', () {
      final l = LeitorTs();
      for (final p in emPedacos(tsSintetico(0, 400).sublist(77), 1000)) {
        l.ler(p);
      }
      expect(l.pidPmt, pidPmtSintetico);
      expect(l.pidPcr, pidVideoSintetico);
      expect(l.pidVideo, pidVideoSintetico);
      expect(l.ultimoPcr, pcrSintetico(399));
    });
  });
}
