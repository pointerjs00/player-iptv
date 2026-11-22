import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/ui/definicoes/seletor_numero.dart';
import 'package:player_iptv/ui/definicoes/tela_definicoes.dart';

import 'ajuda_dpad.dart';

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;
  late Preferencias prefs;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('defver');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
    prefs = await Preferencias.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Future<void> abrir(WidgetTester t) async {
    ecraTvTeste(t, largura: 1000, altura: 1200);
    await t.pumpWidget(appTeste(TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs)));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Verificação'));
    await t.pump();
  }

  testWidgets('Verificação mostra as quatro opções por ordem, com as descrições do mockup', (t) async {
    await abrir(t);
    final ordem = ['Listas ao mesmo tempo', 'Tempo limite por lista', 'Tempo por canal', 'Canais de teste'];
    final ys = [for (final o in ordem) t.getTopLeft(find.text(o)).dy];
    expect([...ys]..sort(), ys, reason: 'ordem de cima para baixo');
    for (final d in [
      'Quantas listas se verificam em simultâneo (1 a 20). Mais é mais rápido, mas pesa na rede.',
      'Se uma lista não acabar neste tempo, fica inconclusiva e passa à seguinte.',
      'Quanto se espera por cada canal de teste.',
      'A lista funciona se um deles abrir.',
      'Com uma verificação a decorrer, as mudanças valem para as próximas listas. '
          'OK para mudar um valor, depois ← →; ↑ ↓ mudam de opção.',
    ]) {
      expect(find.text(d), findsOneWidget, reason: d);
    }
    expect(find.text('8'), findsOneWidget);
    expect(find.text('30 s'), findsOneWidget);
  });

  testWidgets('← → mudam as listas ao mesmo tempo, avisam e param nos limites', (t) async {
    await abrir(t);
    await teclaDpad(t, LogicalKeyboardKey.tab); // a primeira categoria
    await teclaDpad(t, LogicalKeyboardKey.arrowDown); // Verificação
    await teclaDpad(t, LogicalKeyboardKey.arrowRight); // a primeira opção
    expect(textosFocados(), contains('Listas ao mesmo tempo'));
    await teclaDpad(t, LogicalKeyboardKey.select); // OK: entra na edição
    expect(find.byKey(const ValueKey('seletorAEditar')), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    }
    expect(prefs.listasEmSimultaneo, 11);
    expect(find.text('Guardado · vale para as próximas listas'), findsOneWidget);
    for (var i = 0; i < 25; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    }
    expect(prefs.listasEmSimultaneo, 1);
    expect(textosFocados(), contains('Listas ao mesmo tempo'), reason: 'não salta para a categoria');
  });

  testWidgets('tempo limite por lista: 30 s, passo 10, máximo 300', (t) async {
    await abrir(t);
    await teclaDpad(t, LogicalKeyboardKey.tab);
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Tempo limite por lista'));
    await teclaDpad(t, LogicalKeyboardKey.select);
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(find.text('50 s'), findsOneWidget);
    expect(prefs.tempoLimiteLista, 50);
    for (var i = 0; i < 40; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    }
    expect(prefs.tempoLimiteLista, 300);
  });

  testWidgets('os botões − e + funcionam ao toque e o tempo por canal usa o seletor', (t) async {
    await abrir(t);
    final linha = find.ancestor(of: find.text('Tempo por canal'), matching: find.byType(SeletorNumero));
    final antes = prefs.timeoutVerificacao;
    await t.tap(find.descendant(of: linha, matching: find.text('+')));
    await t.pump();
    expect(prefs.timeoutVerificacao, antes + 1);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('sem OK, ← → não mudam o valor e ← vai ao menu lateral', (t) async {
    await abrir(t);
    await teclaDpad(t, LogicalKeyboardKey.tab);
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Tempo limite por lista'));
    final antes = prefs.tempoLimiteLista;
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(prefs.tempoLimiteLista, antes);
    expect(textosFocados(), contains('Tempo limite por lista'));
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(prefs.tempoLimiteLista, antes);
    expect(textosFocados(), contains('Verificação'), reason: 'foi ao menu lateral');
  });

  testWidgets('a editar, OK e Voltar saem da edição; ↓ sai e muda de opção', (t) async {
    await abrir(t);
    await teclaDpad(t, LogicalKeyboardKey.tab);
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    final editar = find.byKey(const ValueKey('seletorAEditar'));
    await teclaDpad(t, LogicalKeyboardKey.select);
    expect(editar, findsOneWidget);
    await teclaDpad(t, LogicalKeyboardKey.select);
    expect(editar, findsNothing);
    await teclaDpad(t, LogicalKeyboardKey.select);
    await teclaDpad(t, LogicalKeyboardKey.escape);
    expect(editar, findsNothing);
    expect(find.byType(TelaDefinicoes), findsOneWidget, reason: 'Voltar não sai do ecrã');
    expect(textosFocados(), contains('Listas ao mesmo tempo'));
    await teclaDpad(t, LogicalKeyboardKey.select);
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(editar, findsNothing);
    expect(textosFocados(), contains('Tempo limite por lista'));
    final antes = prefs.tempoLimiteLista;
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(prefs.tempoLimiteLista, antes, reason: 'a nova opção não está em edição');
  });

  testWidgets('↓ a partir de Listas ao mesmo tempo leva a Tempo limite por lista', (t) async {
    await abrir(t);
    await teclaDpad(t, LogicalKeyboardKey.tab);
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), contains('Listas ao mesmo tempo'));
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Tempo limite por lista'));
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Tempo por canal'));
    expect(prefs.listasEmSimultaneo, Preferencias.padraoListasEmSimultaneo);
  });
}
