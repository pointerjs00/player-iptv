import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/desporto/hora_lisboa.dart';

/// A hora de Lisboa (o horário de verão português), para as grelhas em hora local.
void main() {
  group('hora de Lisboa', () {
    test('inverno: a hora de Lisboa é UTC', () {
      expect(lisboaParaUtc(DateTime.utc(2026, 1, 15, 20)), DateTime.utc(2026, 1, 15, 20));
      expect(lisboaParaUtc(DateTime.utc(2026, 11, 27, 20, 1)), DateTime.utc(2026, 11, 27, 20, 1));
    });
    test('verão: UTC + 1', () {
      expect(lisboaParaUtc(DateTime.utc(2026, 7, 15, 20)), DateTime.utc(2026, 7, 15, 19));
    });
    test('as mudanças no último domingo de março e de outubro (01:00 UTC)', () {
      // 2026: 29 de março e 25 de outubro
      expect(lisboaParaUtc(DateTime.utc(2026, 3, 29, 0, 30)), DateTime.utc(2026, 3, 29, 0, 30));
      expect(lisboaParaUtc(DateTime.utc(2026, 3, 29, 3)), DateTime.utc(2026, 3, 29, 2));
      expect(lisboaParaUtc(DateTime.utc(2026, 10, 25, 3)), DateTime.utc(2026, 10, 25, 3));
      expect(lisboaParaUtc(DateTime.utc(2026, 10, 24, 20)), DateTime.utc(2026, 10, 24, 19));
    });
  });
}
