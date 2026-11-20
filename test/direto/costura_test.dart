import 'dart:math' as math;

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
      expect(l.ultimoDts, tempoSintetico(395));
    });

    test('o PCR num PID diferente do vídeo (pela PMT)', () {
      final l = LeitorTs();
      for (final p in emPedacos(tsSintetico(0, 400, pcrNoutroPid: true), 999)) {
        l.ler(p);
      }
      expect(l.pidPcr, pidPcrSintetico);
      expect(l.pidVideo, pidVideoSintetico);
      expect(l.ultimoPcr, pcrSintetico(399));
    });

    test('pedaços de 1 byte dão o mesmo que um pedaço só', () {
      final ts = tsSintetico(0, 300).sublist(50);
      final a = <int>[], b = <int>[];
      final la = LeitorTs(), lb = LeitorTs();
      la.ler(ts, (p) {
        a.add(p.posicao);
        return false;
      });
      for (var i = 0; i < ts.length; i++) {
        lb.ler([ts[i]], (p) {
          b.add(p.posicao);
          return false;
        });
      }
      expect(b, a);
      expect(a.first, 138);
      expect(a, hasLength(299));
    });
  });

  group('ProcuraCostura (ronda 1)', () {
    test('o PCR num PID diferente do vídeo: começa no PES do vídeo', () {
      final novo = tsSintetico(1500, 6000, variante: 1, pcrNoutroPid: true);
      expect(costuraPorPcr(pcrSintetico(3999), novo), (4005 - 1500) * 188);
    });

    test('a volta dos 33 bits do PCR e do DTS', () {
      // o tempo dá a volta no pacote 1500: o último gravado (1503) tem um PCR pequeno
      const d = (1 << 33) - 1500 * 900;
      final novo = tsSintetico(1000, 2500, variante: 1, deslocamento: d);
      final ultimo = pcrSintetico(1503, deslocamento: d);
      expect(ultimo, lessThan(pcrSintetico(1003, deslocamento: d)), reason: 'sem a volta, pareceria salto');
      expect(costuraPorPcr(ultimo, novo), (1510 - 1000) * 188);
      expect(costuraPorPcr(ultimo, novo, ultimoDts: tempoSintetico(1500 + 5, deslocamento: d)), (1510 - 1000) * 188);
    });

    test('pelo DTS não se perde a imagem que começa antes do PCR seguinte', () {
      final novo = tsSintetico(1500, 6000, variante: 1);
      // último gravado: PES 4020, PCR 4023; o PES 4025 vem antes do PCR 4027
      expect(costuraPorPcr(pcrSintetico(4023), novo, ultimoDts: tempoSintetico(4020)), (4025 - 1500) * 188);
      expect(costuraPorPcr(pcrSintetico(4023), novo), (4030 - 1500) * 188, reason: 'sem o DTS: depois do PCR');
    });

    test('uma cauda ambígua (nulos) só vale com o PCR seguinte maior do que o último', () {
      final novo = [
        ...tsSintetico(1500, 2000), ...nulos(25), //
        ...tsSintetico(2000, 4000), ...nulos(20), ...tsSintetico(4000, 6000),
      ];
      final p = ProcuraCostura(cauda: nulos(20), ultimoPcr: pcrSintetico(3999));
      DecisaoCostura? d;
      for (final c in emPedacos(novo, 65536)) {
        d ??= p.receber(c);
      }
      expect(d?.modo, ModoCostura.bytes);
      expect(d?.desde, (4000 - 1500 + 25) * 188 + 20 * 188);
    });

    test('a cauda a 21 MB: continua a procurar sem guardar (custo medido em comparações)', () {
      final todo = tsSintetico(0, 125000, passo: 24); // ~3750 pacotes/s (~5,6 Mb/s)
      final cauda = todo.sublist(120000 * 188 - tamanhoCauda, 120000 * 188);
      final p = ProcuraCostura(
          cauda: cauda,
          ultimoPcr: pcrSintetico(119999, passo: 24),
          ultimoDts: tempoSintetico(119995, passo: 24),
          limite: limiteProcura);
      DecisaoCostura? d;
      var guardadoMax = 0;
      for (final c in emPedacos(todo.sublist(8000 * 188), 65536)) {
        d = p.receber(c);
        guardadoMax = math.max(guardadoMax, p.recebidos - p.descartavelAte);
        if (d != null) break;
      }
      expect(d?.modo, ModoCostura.bytes);
      expect(d?.desde, 112000 * 188);
      // com PCR, só fica guardado o pedaço atual (a procura não precisa dos bytes já vistos)
      expect(guardadoMax, lessThanOrEqualTo(65536));
      // KMP: no máximo 2 comparações por byte procurado
      expect(p.comparacoes, lessThanOrEqualTo(2 * p.recebidos));
      printOnFailure('comparações: ${p.comparacoes} em ${p.recebidos} bytes');
    });

    test('o pior caso do KMP (só 0xFF) continua linear', () {
      final cauda = [...List<int>.filled(tamanhoCauda - 1, 0xFF), 0x00];
      final p = ProcuraCostura(cauda: cauda, ultimoPcr: 0, limite: 1 << 30);
      p.receber(List<int>.filled(4 << 20, 0xFF));
      expect(p.comparacoes, lessThanOrEqualTo(2 * p.recebidos));
    });
  });
}
