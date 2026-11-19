import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/design/tokens.dart';
import 'package:player_iptv/ui/gestor/calendario_intervalo.dart';

import 'ajuda_dpad.dart';

void main() {
  final hoje = DateTime(2026, 11, 19);

  /// Abre o calendário como rota; `resultado` guarda o que `escolherIntervalo` devolveu.
  Future<void> abrir(WidgetTester t, {DateTime? inicio, DateTime? fim, void Function(DateTimeRange?)? aoFechar}) async {
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(appTeste(Builder(
      builder: (c) => TextButton(
        onPressed: () async {
          final r = await escolherIntervalo(c, inicio: inicio ?? DateTime(2026, 11, 10), fim: fim ?? hoje, hoje: hoje);
          aoFechar?.call(r);
        },
        child: const Text('abrir'),
      ),
    )));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
  }

  Future<void> tecla(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k);
    await t.pump();
  }

  bool procurarLigado(WidgetTester t) =>
      (t.widget(find.widgetWithText(FilledButton, 'Procurar e juntar')) as FilledButton).onPressed != null;

  testWidgets('abre no mês de fim, com título em pt-PT e a semana a começar à segunda', (t) async {
    await abrir(t);
    expect(find.text('novembro 2026'), findsOneWidget);
    expect(find.text('Escolhe o início e o fim'), findsOneWidget);
    expect(find.text('1.º OK marca o início, 2.º OK marca o fim. Os dias depois de hoje não se escolhem.'),
        findsOneWidget);
    // S T Q Q S S D
    final cab = [for (final s in ['S', 'T', 'Q', 'Q', 'S', 'S', 'D']) s].join();
    expect(cab, 'STQQSSD');
    expect(find.text('S'), findsNWidgets(3));
    expect(find.text('Q'), findsNWidgets(2));
    // 1 de novembro de 2026 é domingo: seis vazios antes
    expect(t.getTopLeft(find.text('1')).dx > t.getTopLeft(find.text('D')).dx - 1, isTrue);
    expect(find.text('10 nov. 2026'), findsOneWidget);
    expect(find.text('19 nov. 2026'), findsOneWidget);
  });

  testWidgets('as setas mudam o dia e o mês, e não passam de hoje', (t) async {
    await abrir(t, inicio: hoje);
    await tecla(t, LogicalKeyboardKey.arrowDown); // 26 > hoje: fica
    await tecla(t, LogicalKeyboardKey.arrowRight); // 20 > hoje: fica
    expect(find.text('novembro 2026'), findsOneWidget);
    await tecla(t, LogicalKeyboardKey.arrowLeft); // do botão de volta à grelha
    await tecla(t, LogicalKeyboardKey.arrowUp); // 12
    await tecla(t, LogicalKeyboardKey.arrowLeft); // 11
    await tecla(t, LogicalKeyboardKey.enter);
    expect(find.text('11 nov. 2026'), findsOneWidget);
    // 11 -> 4 -> 28 out. (muda de mês)
    await tecla(t, LogicalKeyboardKey.arrowUp);
    await tecla(t, LogicalKeyboardKey.arrowUp);
    expect(find.text('outubro 2026'), findsOneWidget);
    await tecla(t, LogicalKeyboardKey.enter);
    expect(find.text('28 out. 2026'), findsOneWidget);
    await tecla(t, LogicalKeyboardKey.arrowLeft); // o 2.º OK levou o foco ao botão: volta à grelha
    // para a frente: 28 out. -> 4 nov. (muda de mês); ← de 1 nov. vai para 31 out.
    await tecla(t, LogicalKeyboardKey.arrowDown);
    expect(find.text('novembro 2026'), findsOneWidget);
    await tecla(t, LogicalKeyboardKey.arrowLeft);
    await tecla(t, LogicalKeyboardKey.arrowLeft);
    await tecla(t, LogicalKeyboardKey.arrowLeft);
    await tecla(t, LogicalKeyboardKey.arrowLeft); // 31 out.
    expect(find.text('outubro 2026'), findsOneWidget);
  });

  testWidgets('1.º OK marca o início, 2.º o fim, 2.º antes do 1.º troca, 3.º recomeça', (t) async {
    await abrir(t);
    await tecla(t, LogicalKeyboardKey.arrowLeft); // 18
    await tecla(t, LogicalKeyboardKey.select); // De 18
    expect(find.text('18 nov. 2026'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(procurarLigado(t), isFalse);
    for (var i = 0; i < 3; i++) {
      await tecla(t, LogicalKeyboardKey.arrowLeft);
    }
    await tecla(t, LogicalKeyboardKey.select); // 15, antes de 18: troca
    expect(find.text('15 nov. 2026'), findsOneWidget);
    expect(find.text('18 nov. 2026'), findsOneWidget);
    expect(find.text('—'), findsNothing);
    expect(procurarLigado(t), isTrue);
    // o foco passou para «Procurar e juntar»; volta à grelha com ↑ e recomeça com o 3.º OK
    expect(textosFocados(), 'Procurar e juntar');
    await tecla(t, LogicalKeyboardKey.arrowLeft);
    await tecla(t, LogicalKeyboardKey.select);
    expect(find.text('—'), findsOneWidget);
    expect(procurarLigado(t), isFalse);
  });

  testWidgets('«Recomeçar» limpa as marcas e «Procurar e juntar» devolve o intervalo', (t) async {
    DateTimeRange? r;
    var fechou = false;
    await abrir(t, aoFechar: (x) {
      r = x;
      fechou = true;
    });
    await t.tap(find.text('Recomeçar'));
    await t.pump();
    expect(find.text('—'), findsNWidgets(2));
    expect(procurarLigado(t), isFalse);
    await t.tap(find.text('3'));
    await t.pump();
    await t.tap(find.text('12'));
    await t.pump();
    expect(procurarLigado(t), isTrue);
    await t.tap(find.text('Procurar e juntar'));
    await t.pumpAndSettle();
    expect(fechou, isTrue);
    expect(r, DateTimeRange(start: DateTime(2026, 11, 3), end: DateTime(2026, 11, 12)));
  });

  testWidgets('Voltar devolve null', (t) async {
    DateTimeRange? r = DateTimeRange(start: hoje, end: hoje);
    var fechou = false;
    await abrir(t, aoFechar: (x) {
      r = x;
      fechou = true;
    });
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(fechou, isTrue);
    expect(r, isNull);
  });

  testWidgets('o toque num dia futuro não faz nada; os botões do mês mudam de mês', (t) async {
    await abrir(t);
    await t.tap(find.text('25'));
    await t.pump();
    expect(find.text('10 nov. 2026'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Mês anterior'));
    await t.pump();
    expect(find.text('outubro 2026'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Mês seguinte'));
    await t.pump();
    expect(find.text('novembro 2026'), findsOneWidget);
  });

  testWidgets('abre com o intervalo preenchido e chega a Procurar e juntar só com setas', (t) async {
    DateTimeRange? r;
    await abrir(t, aoFechar: (x) => r = x);
    await tecla(t, LogicalKeyboardKey.arrowDown); // 26 > hoje: bloqueado, foco no botão
    expect(textosFocados(), 'Procurar e juntar');
    await tecla(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), 'Recomeçar');
    await tecla(t, LogicalKeyboardKey.arrowUp);
    expect(textosFocados(), 'Procurar e juntar');
    await tecla(t, LogicalKeyboardKey.arrowLeft); // volta à grelha
    await tecla(t, LogicalKeyboardKey.arrowRight); // 20 > hoje
    expect(textosFocados(), 'Procurar e juntar');
    await tecla(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(r, DateTimeRange(start: DateTime(2026, 11, 10), end: hoje));
  });

  testWidgets('sem as duas datas, o movimento bloqueado leva a Recomeçar', (t) async {
    await abrir(t);
    await t.tap(find.text('Recomeçar'));
    await t.pump();
    await t.tap(find.text('19'));
    await t.pump(); // só «De»: Procurar desativado
    await tecla(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), 'Recomeçar');
  });

  testWidgets('↑ na primeira semana vai aos botões do mês, e ↓ volta à grelha', (t) async {
    await abrir(t, inicio: DateTime(2026, 11, 3), fim: DateTime(2026, 11, 4));
    for (var i = 0; i < 3; i++) {
      await tecla(t, LogicalKeyboardKey.arrowLeft); // 3, 2, 1 nov. (primeira linha visível)
    }
    await tecla(t, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Mês anterior');
    await tecla(t, LogicalKeyboardKey.enter);
    expect(find.text('outubro 2026'), findsOneWidget);
    await tecla(t, LogicalKeyboardKey.arrowRight);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Mês seguinte');
    await tecla(t, LogicalKeyboardKey.enter);
    expect(find.text('novembro 2026'), findsOneWidget);
    await tecla(t, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Calendário');
  });

  testWidgets('3.º OK na grelha recomeça com esse dia como início', (t) async {
    await abrir(t, inicio: DateTime(2026, 11, 3), fim: DateTime(2026, 11, 4));
    await tecla(t, LogicalKeyboardKey.select); // De 4
    await tecla(t, LogicalKeyboardKey.arrowLeft); // 3
    await tecla(t, LogicalKeyboardKey.select); // Até: foco salta para Procurar
    expect(textosFocados(), 'Procurar e juntar');
    await tecla(t, LogicalKeyboardKey.arrowLeft); // volta à grelha, ao dia 3
    await tecla(t, LogicalKeyboardKey.select); // 3.º OK: recomeça
    expect(find.text('3 nov. 2026'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(procurarLigado(t), isFalse);
  });

  testWidgets('na TV mostra as dicas de teclas e o dia focado tem o anel', (t) async {
    ecraTvTeste(t, largura: 960, altura: 540);
    await t.pumpWidget(appTeste(Builder(
      builder: (c) => TextButton(
          onPressed: () => escolherIntervalo(c, inicio: DateTime(2026, 11, 10), fim: hoje, hoje: hoje),
          child: const Text('abrir')),
    )));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    expect(find.text('←↑↓→'), findsOneWidget);
    expect(find.text('marcar'), findsOneWidget);
    expect(find.text('sair sem mudar'), findsOneWidget);
    expect(t.takeException(), isNull);
    final anel = find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).border?.top.color == Tokens.anelFoco);
    expect(anel, findsOneWidget);
  });
}
