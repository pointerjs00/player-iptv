import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/desporto/modelo.dart';
import 'package:player_iptv/desporto/nomes.dart';

/// Reconhecer canais portugueses nos nomes das listas, as equipas pelo nome e ler os títulos das
/// grelhas (com nomes e títulos reais vistos a 27/11/2026).
void main() {
  group('canais', () {
    test('o Sport TV 1 com prefixos e qualidades das listas', () {
      final r = reconhecerCanal('|PT| SPORT TV 1 FHD')!;
      expect(r.canal.id, 'sporttv1');
      expect(r.qualidade, Qualidade.fhd);
      expect(r.portugues, isTrue);
      expect(reconhecerCanal('PT: SPORTTV1 ᴴᴰ')?.canal.id, 'sporttv1');
      expect(reconhecerCanal('PT: SPORTTV1 ᴴᴰ')?.qualidade, Qualidade.hd);
      expect(reconhecerCanal('[PT] Sport TV 1 HEVC (backup)')?.canal.id, 'sporttv1');
      expect(reconhecerCanal('SPORT TV+ 4K')?.canal.id, 'sporttvmais');
      expect(reconhecerCanal('SPORT TV+ 4K')?.qualidade, Qualidade.uhd);
      expect(reconhecerCanal('BENFICA TV')?.canal.id, 'btv');
      expect(reconhecerCanal('|PT| DAZN 2 FHD')?.canal.id, 'dazn2');
    });

    test('o nome antigo da DAZN (Eleven) conta, com confiança mais baixa', () {
      final r = reconhecerCanal('ELEVEN SPORTS 1')!;
      expect(r.canal.id, 'dazn1');
      expect(r.confianca, lessThan(1));
      expect(reconhecerCanal('DAZN 1')!.confianca, 1);
    });

    test('outros países e outros canais não se confundem', () {
      expect(reconhecerCanal('|BR| SPORTV 1'), isNull, reason: 'o SporTV é brasileiro');
      expect(reconhecerCanal('|PT| SPORT TV 1 PREMIUM'), isNull);
      expect(reconhecerCanal('SIC NOTÍCIAS'), isNull);
      expect(reconhecerCanal('DAZN 1 ES')?.portugues, isFalse);
      expect(reconhecerCanal('|DE| DAZN 1')?.portugues, isFalse);
      expect(reconhecerCanal('DAZN 1', grupo: 'ESPAÑA DEPORTES')?.portugues, isFalse);
      expect(reconhecerCanal('DAZN 1', grupo: '|PT| DESPORTO')?.portugues, isTrue);
      expect(reconhecerCanal('DAZN 1')?.portugues, isTrue, reason: 'sem outro país à vista');
    });
  });

  group('equipas', () {
    test('a mesma equipa com nomes diferentes', () {
      expect(mesmaEquipa('FC Porto', 'Porto'), isTrue);
      expect(mesmaEquipa('Sporting CP', 'Sporting'), isTrue);
      expect(mesmaEquipa('SL Benfica', 'Benfica'), isTrue);
      expect(mesmaEquipa('Man United', 'Manchester United'), isTrue);
      expect(mesmaEquipa('Brighton & Hove A.', 'Brighton'), isTrue);
      expect(mesmaEquipa('Bayern München', 'Bayern Munique'), isTrue);
      expect(mesmaEquipa('Nottm Forest', 'Nottingham Forest'), isTrue);
      expect(mesmaEquipa('Vitória de Guimarães', 'Vitória SC'), isTrue);
      expect(mesmaEquipa('MARÍTIMO', 'Marítimo'), isTrue);
      expect(mesmaEquipa('CD NACIONAL', 'Nacional'), isTrue);
    });

    test('as equipas B, sub-23 e femininas não são a principal', () {
      expect(mesmaEquipa('Sporting CP B', 'Sporting CP'), isFalse);
      expect(mesmaEquipa('Benfica B', 'Benfica'), isFalse);
      expect(mesmaEquipa('Porto Sub-23', 'FC Porto'), isFalse);
      expect(mesmaEquipa('Benfica (W)', 'Benfica'), isFalse);
      expect(mesmaEquipa('Real Madrid', 'Real Betis'), isFalse);
    });
  });

  group('títulos das grelhas', () {
    test('MEO: casa x fora - competição', () {
      final t = lerTitulo('Brighton & Hove A. x Universitatea Craiova - UEFA Conference League')!;
      expect(t.casa, 'Brighton & Hove A.');
      expect(t.fora, 'Universitatea Craiova');
      expect(t.competicao, 'UEFA Conference League');
      expect(t.direto, isFalse);
      expect(t.feminino, isFalse);
    });

    test('modalidade, feminino e direto', () {
      final b = lerTitulo('Basquetebol Fem.: Benfica x Uzkk Student Nis - Eurocup Women')!;
      expect(b.modalidade, 'basquetebol');
      expect(b.feminino, isTrue);
      expect(b.casa, 'Benfica');
      final r = lerTitulo('Rugby: Itália x Fiji - Nations Championship (Direto)')!;
      expect(r.direto, isTrue);
      expect(r.fora, 'Fiji');
      expect(r.competicao, 'Nations Championship');
      final t = lerTitulo('Ténis: ATP Finals (Direto)')!;
      expect(t.modalidade, 'tenis');
      expect(t.casa, isNull);
      expect(t.competicao, 'ATP Finals');
    });

    test('Sport TV: maiúsculas com X', () {
      final t = lerTitulo('MARÍTIMO X CD NACIONAL')!;
      expect(t.casa, 'MARÍTIMO');
      expect(t.fora, 'CD NACIONAL');
    });

    test('títulos de enchimento e programas que não são o jogo', () {
      for (final x in [
        'DAZN 3',
        'Fora de Horas: Sem Transmissão',
        'ANTEVISÃO MARÍTIMO X CD NACIONAL',
        'Liga Europa: Resumo do Dia',
        'Highlights WTA Finals Riyhad - WTA Tournament Highlights',
        'Jornada 13 - LaLiga Resumos',
        'Liga Francesa: Ligue 1 Show',
      ]) {
        expect(lerTitulo(x), isNull, reason: x);
      }
    });
  });
}
