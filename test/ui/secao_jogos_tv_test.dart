import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/desporto/preferencias_jogos.dart';
import 'package:player_iptv/ui/definicoes/secao_jogos.dart';

import 'ajuda_dpad.dart';

/// Definições › Jogos na TV: o campo «Nome da equipa» com o comando.
void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('secao_jogos_tv'));
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  EditableText campo(WidgetTester t) => t.widget<EditableText>(
      find.descendant(of: find.widgetWithText(TextField, 'Nome da equipa'), matching: find.byType(EditableText)));

  bool focoNoCampo(WidgetTester t) {
    final e = t.element(find.descendant(of: find.widgetWithText(TextField, 'Nome da equipa'), matching: find.byType(EditableText)));
    return (e.widget as EditableText).focusNode.hasPrimaryFocus;
  }

  testWidgets('o foco no campo não abre o teclado; OK escreve e Voltar acaba sem tirar o foco', (t) async {
    ecraTvTeste(t);
    final prefs = (await t.runAsync(() => PreferenciasJogos.abrir(pasta)))!;
    await t.pumpWidget(appTeste(Scaffold(body: ListView(children: [SecaoJogos(preferencias: prefs)]))));
    campo(t).focusNode.requestFocus();
    await t.pump();
    expect(focoNoCampo(t), isTrue);
    expect(campo(t).readOnly, isTrue, reason: 'só com o foco o teclado não aparece');

    await teclaDpad(t, LogicalKeyboardKey.select);
    expect(campo(t).readOnly, isFalse, reason: 'OK começa a escrever');
    await t.enterText(find.widgetWithText(TextField, 'Nome da equipa'), 'Benfica');

    await teclaDpad(t, LogicalKeyboardKey.escape);
    expect(campo(t).readOnly, isTrue);
    expect(focoNoCampo(t), isTrue, reason: 'Voltar fecha o teclado e o foco fica no campo');

    // Enter físico a escrever adiciona a equipa
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(prefs.equipasFavoritas, ['Benfica']);
    await t.pump(const Duration(seconds: 5)); // a mensagem «Guardado» desaparece
  });
}
