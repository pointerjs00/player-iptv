import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/estatisticas.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/ui/player/tempo_visto.dart';

const sport = Canal(id: '1', nome: 'Sport TV 1', grupo: 'Desporto', logo: 'http://l/s.png');
const rtp = Canal(id: '2', nome: 'RTP 1', grupo: 'Portugal');
const cnn = Canal(id: '3', nome: 'CNN', grupo: 'Notícias');

/// Quinta, 26 de novembro de 2026, 21:00.
final agora = DateTime(2026, 11, 26, 21);
DateTime diasAtras(int n, [int hora = 21]) => DateTime(2026, 11, 26 - n, hora);

void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('estatisticas'));
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Estatisticas comDados() => Estatisticas.emMemoria()
    ..somar('l1', 'Lista A', sport, const Duration(hours: 2), quando: agora)
    ..somar('l1', 'Lista A', rtp, const Duration(minutes: 30), quando: diasAtras(1, 20))
    ..somar('l2', 'Lista B', cnn, const Duration(hours: 1), quando: diasAtras(3, 9))
    ..somar('l1', 'Lista A', sport, const Duration(minutes: 45), quando: diasAtras(9));

  test('a semana: o total, a anterior, os 7 dias (hoje no fim) e os 3 mais vistos', () {
    final s = comDados().semana(agora);
    expect(s.total, const Duration(hours: 3, minutes: 30));
    expect(s.anterior, const Duration(minutes: 45));
    expect(s.porDia, hasLength(7));
    expect(s.porDia.last, const Duration(hours: 2));
    expect(s.porDia[5], const Duration(minutes: 30));
    expect(s.porDia[3], const Duration(hours: 1));
    expect(s.maisVistos.map((c) => (c.nome, c.lista, c.tempo)), [
      ('Sport TV 1', 'Lista A', const Duration(hours: 2)),
      ('CNN', 'Lista B', const Duration(hours: 1)),
      ('RTP 1', 'Lista A', const Duration(minutes: 30)),
    ]);
    expect(s.maisVistos.first.logo, 'http://l/s.png');
    expect((s.maisVistos.first.listaId, s.maisVistos.first.canalId), ('l1', '1'));
  });

  test('os mais vistos em 30 dias somam os dias; as listas mais usadas; por hora e por dia da semana', () {
    final e = comDados();
    expect(e.maisVistos(agora).first.tempo, const Duration(hours: 2, minutes: 45));
    expect(e.listasMaisUsadas(agora), [('Lista A', const Duration(hours: 3, minutes: 15)), ('Lista B', const Duration(hours: 1))]);
    final horas = e.porHora(agora);
    expect(horas[21], const Duration(hours: 2, minutes: 45));
    expect(horas[9], const Duration(hours: 1));
    final semana = e.porDiaDaSemana(agora);
    expect(semana[DateTime.thursday - 1], const Duration(hours: 2));
    expect(semana[DateTime.wednesday - 1], const Duration(minutes: 30));
  });

  test('dias seguidos: conta até hoje (ou até ontem, se hoje ainda não se viu nada)', () {
    final e = Estatisticas.emMemoria();
    for (var i = 0; i < 4; i++) {
      e.somar('l', 'L', rtp, const Duration(minutes: 20), quando: diasAtras(i + 1));
    }
    expect(e.diasSeguidos(agora), 4, reason: 'hoje ainda sem nada: conta-se até ontem');
    e.somar('l', 'L', rtp, const Duration(minutes: 2), quando: agora);
    expect(e.diasSeguidos(agora), 4, reason: '2 min hoje ainda não contam');
    e.somar('l', 'L', rtp, const Duration(minutes: 10), quando: agora);
    expect(e.diasSeguidos(agora), 5);
  });

  test('grava e volta a ler; os dias com mais de 120 dias saem; apagar tira o ficheiro', () async {
    final e = await Estatisticas.abrir(pasta);
    e
      ..somar('l1', 'Lista A', sport, const Duration(hours: 1), quando: agora)
      ..somar('l1', 'Lista A', rtp, const Duration(hours: 1), quando: diasAtras(130));
    await e.guardar(agora: agora);
    final f = File('${pasta.path}/${Estatisticas.nomeFicheiro}');
    expect(f.existsSync(), isTrue);
    final lida = await Estatisticas.abrir(pasta);
    expect(lida.semana(agora).total, const Duration(hours: 1));
    expect(lida.maisVistos(agora, dias: 365).map((c) => c.nome), ['Sport TV 1'], reason: 'o de há 130 dias saiu');
    await lida.apagar();
    expect(f.existsSync(), isFalse);
    expect(lida.vazio, isTrue);
  });

  test('um ficheiro estragado conta como vazio', () async {
    File('${pasta.path}/${Estatisticas.nomeFicheiro}').writeAsStringSync('{lixo');
    expect((await Estatisticas.abrir(pasta)).vazio, isTrue);
  });

  test('o contador do player: soma ao canal da lista e grava no máximo uma vez por minuto', () async {
    final e = await Estatisticas.abrir(pasta);
    final prefs = Preferencias.omissao();
    var t = agora;
    final contar = contadorDeTempo('l1', 'Lista A', estatisticas: e, preferencias: prefs, agora: () => t);
    contar(sport, const Duration(seconds: 15));
    await Future<void>.delayed(const Duration(milliseconds: 300)); // a gravação é em disco
    final f = File('${pasta.path}/${Estatisticas.nomeFicheiro}');
    expect(f.existsSync(), isTrue, reason: 'a 1.ª vez grava logo');
    f.deleteSync();
    t = t.add(const Duration(seconds: 15));
    contar(sport, const Duration(seconds: 15));
    await Future<void>.delayed(const Duration(milliseconds: 300)); // a gravação é em disco
    expect(f.existsSync(), isFalse, reason: 'menos de um minuto depois não grava');
    t = t.add(const Duration(minutes: 1));
    contar(sport, const Duration(seconds: 15));
    await Future<void>.delayed(const Duration(milliseconds: 300)); // a gravação é em disco
    expect(f.existsSync(), isTrue);
    expect(e.semana(agora).total, const Duration(seconds: 45));
  });

  test('com «Contar o tempo de visualização» desligado, o contador não soma nada', () {
    final e = Estatisticas.emMemoria();
    final prefs = Preferencias.omissao()..contarTempo = false;
    contadorDeTempo('l1', 'Lista A', estatisticas: e, preferencias: prefs, agora: () => agora)(sport, const Duration(minutes: 5));
    expect(e.vazio, isTrue);
  });

  test('textoDuracao', () {
    expect(textoDuracao(const Duration(minutes: 45)), '45 min');
    expect(textoDuracao(const Duration(hours: 12, minutes: 40)), '12 h 40');
    expect(textoDuracao(const Duration(hours: 3)), '3 h');
    expect(textoDuracao(const Duration(minutes: 65)), '1 h 05');
  });
}
