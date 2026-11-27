/// A hora de Lisboa (as grelhas da MEO vêm sem fuso). Portugal continental: UTC no inverno e
/// UTC+1 no verão, do último domingo de março às 01:00 UTC ao último domingo de outubro às
/// 01:00 UTC.
library;

DateTime _ultimoDomingo(int ano, int mes) {
  final ultimo = DateTime.utc(ano, mes + 1, 0); // o último dia do mês
  return DateTime.utc(ano, mes, ultimo.day - ultimo.weekday % 7, 1);
}

/// Em hora de verão neste instante (UTC).
bool horaDeVerao(DateTime utc) {
  final u = utc.toUtc();
  return !u.isBefore(_ultimoDomingo(u.year, 3)) && u.isBefore(_ultimoDomingo(u.year, 10));
}

/// A hora de Lisboa `local` (os campos são a hora do relógio, seja qual for o fuso do objeto)
/// em UTC.
DateTime lisboaParaUtc(DateTime local) {
  final relogio = DateTime.utc(local.year, local.month, local.day, local.hour, local.minute, local.second);
  final verao = relogio.subtract(const Duration(hours: 1));
  return horaDeVerao(verao) ? verao : relogio;
}

/// O instante `utc` na hora do relógio de Lisboa (num DateTime UTC com os campos de Lisboa).
DateTime utcParaLisboa(DateTime utc) {
  final u = utc.toUtc();
  return horaDeVerao(u) ? u.add(const Duration(hours: 1)) : u;
}

/// "AAAA-MM-DDTHH:MM:SS" (sem fuso) como hora de Lisboa → UTC; null se não for uma data.
DateTime? lerHoraLisboa(Object? texto) {
  if (texto is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?').firstMatch(texto);
  if (m == null) return null;
  int n(int i) => int.parse(m[i] ?? '0');
  return lisboaParaUtc(DateTime.utc(n(1), n(2), n(3), n(4), n(5), n(6)));
}
