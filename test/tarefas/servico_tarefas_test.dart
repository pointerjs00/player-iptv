import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/tarefas/segredos.dart';
import 'package:player_iptv/tarefas/servico_tarefas.dart';

void main() {
  test('iniciar devolve logo e o trabalho corre sem await do chamador', () async {
    final s = ServicoTarefas();
    final c = Completer<String>();
    var arrancou = false;
    final t = s.iniciar('Importar', (p) {
      arrancou = true;
      return c.future;
    });
    expect(t.estado, EstadoTarefa.aDecorrer);
    expect(arrancou, isTrue);
    expect(s.emCurso, [t]);
    c.complete('ok');
    await Future<void>.delayed(Duration.zero);
    s.dispose();
  });

  test('o progresso notifica', () async {
    final s = ServicoTarefas();
    var avisos = 0;
    s.addListener(() => avisos++);
    final c = Completer<String>();
    final t = s.iniciar('X', (p) {
      p(0.5, 'metade');
      return c.future;
    });
    final antes = avisos;
    expect(t.progresso, 0.5);
    expect(t.detalhe, 'metade');
    expect(antes, greaterThan(0));
    c.complete('fim');
    await Future<void>.delayed(Duration.zero);
    expect(avisos, greaterThan(antes));
    s.dispose();
  });

  test('ao terminar vai para recentes com resultado e emite em acabadas', () async {
    final s = ServicoTarefas();
    final emitidas = <Tarefa>[];
    s.acabadas.listen(emitidas.add);
    final t = s.iniciar('X', (p) async => '3 canais');
    await Future<void>.delayed(Duration.zero);
    expect(t.estado, EstadoTarefa.terminada);
    expect(t.resultado, '3 canais');
    expect(t.fim, isNotNull);
    expect(s.emCurso, isEmpty);
    expect(s.recentes, [t]);
    expect(emitidas, [t]);
    s.dispose();
  });

  test('excecao leva a falhou com a mensagem', () async {
    final s = ServicoTarefas();
    final t = s.iniciar('X', (p) async => throw Exception('rebentou'));
    await Future<void>.delayed(Duration.zero);
    expect(t.estado, EstadoTarefa.falhou);
    expect(t.resultado, contains('rebentou'));
    expect(s.recentes, [t]);
    s.dispose();
  });

  test('cancelar poe cancelado a true e acaba em cancelada', () async {
    final s = ServicoTarefas();
    late Progresso prog;
    final c = Completer<String>();
    final t = s.iniciar('X', (p) {
      prog = p;
      return c.future;
    });
    expect(prog.cancelado, isFalse);
    s.cancelar(t.id);
    expect(prog.cancelado, isTrue);
    c.complete('tarde');
    await Future<void>.delayed(Duration.zero);
    expect(t.estado, EstadoTarefa.cancelada);
    expect(s.recentes, [t]);
    s.dispose();
  });

  test('12 tarefas terminadas: so 10 em recentes, a mais recente primeiro', () async {
    final s = ServicoTarefas();
    final ts = [for (var i = 0; i < 12; i++) s.iniciar('T$i', (p) async => 'r$i')];
    await Future<void>.delayed(Duration.zero);
    expect(s.recentes.length, 10);
    expect(s.recentes.first, ts.last);
    s.dispose();
  });

  test('o resultado e o detalhe passam por mascararSegredos', () async {
    final s = ServicoTarefas();
    final c = Completer<String>();
    final t = s.iniciar('X', (p) {
      p(null, 'a ler http://h/c?mac=00:1A:79:AA:BB:CC');
      return c.future;
    });
    expect(t.detalhe, isNot(contains('00:1A')));
    c.complete('falhou http://h/c?mac=00:1A:79:AA:BB:CC');
    await Future<void>.delayed(Duration.zero);
    expect(t.resultado, isNot(contains('00:1A')));
    expect(t.resultado, isNot(contains('mac=')));
    expect(t.resultado, contains('http://h'));
    s.dispose();
  });

  test('guarda rotuloAcao, aoAcao e repetir', () async {
    final s = ServicoTarefas();
    var chamou = false;
    Future<void> rep() async {}
    final t = s.iniciar('X', (p) async => 'ok',
        repetir: rep, rotuloAcao: 'Ir para Ver TV', aoAcao: () => chamou = true);
    expect(t.rotuloAcao, 'Ir para Ver TV');
    t.aoAcao!();
    expect(chamou, isTrue);
    expect(t.repetir, rep);
    await Future<void>.delayed(Duration.zero);
    s.dispose();
  });

  group('mascararSegredos', () {
    test('MAC', () {
      expect(mascararSegredos('mac 00:1A:79:AA:BB:CC ok'), 'mac ••:••:••:••:••:•• ok');
    });
    test('URL: tira caminho, query e credenciais', () {
      final r = mascararSegredos('ver http://u:p@h:8080/live/abc/def.ts?token=zz fim');
      expect(r, 'ver http://h:8080/… fim');
    });
    test('URL sem caminho fica igual', () {
      expect(mascararSegredos('http://h'), 'http://h');
    });
    test('pares username/password/token', () {
      final r = mascararSegredos('username=joao&password=segredo token=abc');
      expect(r, 'username=•••&password=••• token=•••');
      expect(r, isNot(contains('segredo')));
    });
    test('JSON', () {
      expect(mascararSegredos('{"password":"xyz"}'), isNot(contains('xyz')));
    });
  });
}
