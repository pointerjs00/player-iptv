import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/gestor/passo_enviar.dart';

import 'ajuda_dpad.dart';

final _agora = DateTime(2026, 11, 19, 15);

UltimaVerificacao _u(String estado) => UltimaVerificacao(estado: estado, data: _agora, motivo: '');

/// Cinco listas fictícias: 2 funcionam, 1 inconclusiva, 1 não funciona, 1 por verificar.
Future<void> _povoar(AreaGestor area) async {
  await area.adicionar([
    Importada(contaDeLinha('http://alfa1.exemplo.pt/c/ 00:1A:79:00:00:01')!, _u('funciona')),
    Importada(contaDeLinha('http://alfa2.exemplo.pt/c/ 00:1A:79:00:00:02')!, _u('funciona')),
    Importada(contaDeLinha('http://beta.exemplo.pt/c/ 00:1A:79:00:00:03')!, _u('inconclusivo')),
    Importada(contaDeLinha('http://gama.exemplo.pt/c/ 00:1A:79:00:00:04')!, _u('nao_funciona')),
    Importada(contaDeLinha('http://delta.exemplo.pt/c/ 00:1A:79:00:00:05')!, null),
  ]);
  final nomes = ['001ALFA 070927', '002ALFA 040227', 'INC 010BETA 030227', '007GAMA 201126', '019DELTA 161027'];
  for (final (i, l) in area.listas.indexed) {
    l.nomeProprio = nomes[i];
  }
}

void main() {
  late Directory pasta;
  late AreaGestor area;
  late Set<String> marcadas;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('passo_enviar');
    area = await AreaGestor.abrir(pasta);
    marcadas = {};
  });
  tearDown(() async {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  var enviadas = <List<Lista>>[];
  var exportadas = <List<Lista>>[];
  var mudou = 0;

  Future<void> abrir(WidgetTester t, {double largura = 1200}) async {
    enviadas = [];
    exportadas = [];
    mudou = 0;
    await t.runAsync(() => _povoar(area));
    t.view.physicalSize = Size(largura, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(appTeste(Scaffold(
        body: PassoEnviar(
      area: area,
      marcadas: marcadas,
      aoMudarMarcadas: () => mudou++,
      aoEnviar: enviadas.add,
      aoExportar: exportadas.add,
    ))));
    await t.pump();
  }

  Finder linha(String nome) => find.ancestor(of: find.text(nome), matching: find.byType(CheckboxListTile));
  Finder botao(String texto) =>
      find.ancestor(of: find.text(texto), matching: find.byWidgetPredicate((w) => w is FilledButton || w is OutlinedButton));
  bool ligado(WidgetTester t, String texto) {
    final w = t.widget(botao(texto));
    return (w is FilledButton ? w.onPressed : (w as OutlinedButton).onPressed) != null;
  }

  FocusNode? focoDe(WidgetTester t, String texto) {
    final w = t.widget(botao(texto));
    return w is FilledButton ? w.focusNode : (w as OutlinedButton).focusNode;
  }

  /// Carrega num chip de marcar (a fila desliza: primeiro leva-o à vista).
  Future<void> tocarChip(WidgetTester t, Finder chip) async {
    await t.ensureVisible(chip);
    await t.tap(chip);
  }

  testWidgets('os textos do mockup: marcar com contagens, cartões e rodapé', (t) async {
    await abrir(t);
    for (final s in [
      'Marcar:',
      'As que funcionam (2)',
      '+ inconclusivas (3)',
      'Todas (5)',
      'Nenhuma',
      'Enviar para o Player',
      'Adicionar às que já lá estão, ou substituir (escolhes a seguir).',
      'Exportar para ficheiro',
      'Accounts.json (sfvip) ou .ini num zip (Stalker). O ficheiro leva os dados de acesso.',
      '0 marcadas · OK marca/desmarca uma lista',
    ]) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    expect(find.text('Funciona'), findsNWidgets(2));
    expect(find.text('Inconclusiva'), findsOneWidget);
    expect(find.text('Não funciona'), findsOneWidget);
  });

  testWidgets('cada chip substitui a marcação', (t) async {
    await abrir(t);
    await tocarChip(t, find.text('As que funcionam (2)'));
    await t.pump();
    expect(find.text('2 marcadas · OK marca/desmarca uma lista'), findsOneWidget);
    await tocarChip(t, find.text('+ inconclusivas (3)'));
    await t.pump();
    expect(find.text('3 marcadas · OK marca/desmarca uma lista'), findsOneWidget);
    await tocarChip(t, find.text('Todas (5)'));
    await t.pump();
    expect(find.text('5 marcadas · OK marca/desmarca uma lista'), findsOneWidget);
    await tocarChip(t, find.text('As que funcionam (2)'));
    await t.pump();
    expect(find.text('2 marcadas · OK marca/desmarca uma lista'), findsOneWidget);
    expect(t.widget<CheckboxListTile>(linha('019DELTA 161027')).value, isFalse);
    await tocarChip(t, find.text('Nenhuma'));
    await t.pump();
    expect(marcadas, isEmpty);
    expect(mudou, 5);
  });

  testWidgets('OK numa linha marca e desmarca', (t) async {
    await abrir(t);
    t.widget<CheckboxListTile>(linha('007GAMA 201126')).focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(find.text('1 marcada · OK marca/desmarca uma lista'), findsOneWidget);
    expect(t.widget<CheckboxListTile>(linha('007GAMA 201126')).value, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(find.text('0 marcadas · OK marca/desmarca uma lista'), findsOneWidget);
  });

  testWidgets('botões com a contagem, singular e desativados com 0', (t) async {
    await abrir(t);
    expect(ligado(t, 'Enviar 0 listas'), isFalse);
    expect(ligado(t, 'Exportar 0 listas'), isFalse);
    await t.tap(linha('001ALFA 070927'));
    await t.pump();
    expect(ligado(t, 'Enviar 1 lista'), isTrue);
    expect(ligado(t, 'Exportar 1 lista'), isTrue);
    await t.tap(linha('002ALFA 040227'));
    await t.pump();
    expect(find.text('Enviar 2 listas'), findsOneWidget);
    expect(find.text('Exportar 2 listas'), findsOneWidget);
  });

  testWidgets('os botões entregam as marcadas pela ordem da lista', (t) async {
    await abrir(t);
    await t.tap(linha('007GAMA 201126'));
    await t.tap(linha('001ALFA 070927'));
    await t.pump();
    await t.tap(find.text('Enviar 2 listas'));
    await t.tap(find.text('Exportar 2 listas'));
    expect(enviadas.single.map((l) => l.nomeProprio), ['001ALFA 070927', '007GAMA 201126']);
    expect(exportadas.single.map((l) => l.nomeProprio), ['001ALFA 070927', '007GAMA 201126']);
  });

  testWidgets('uma marcada que sai do Gestor deixa de contar', (t) async {
    await abrir(t);
    await tocarChip(t, find.text('Todas (5)'));
    await t.pump();
    await t.runAsync(() => area.remover([area.listas.first.id]));
    await t.pump();
    expect(find.text('4 marcadas · OK marca/desmarca uma lista'), findsOneWidget);
    expect(find.text('Enviar 4 listas'), findsOneWidget);
    expect(marcadas.length, 4);
  });

  testWidgets('a marcação vem do conjunto da tela (sobrevive a mudar de passo)', (t) async {
    await abrir(t);
    marcadas.add(area.listas.first.id);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(appTeste(Scaffold(
        body: PassoEnviar(
            area: area, marcadas: marcadas, aoMudarMarcadas: () {}, aoEnviar: (_) {}, aoExportar: (_) {}))));
    await t.pump();
    expect(find.text('1 marcada · OK marca/desmarca uma lista'), findsOneWidget);
  });

  testWidgets('→ da lista leva aos cartões; ← volta à linha', (t) async {
    await abrir(t);
    await tocarChip(t, find.text('Todas (5)'));
    await t.pump();
    final linhaNo = t.widget<CheckboxListTile>(linha('002ALFA 040227')).focusNode!;
    linhaNo.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(focoDe(t, 'Enviar 5 listas')!.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(focoDe(t, 'Exportar 5 listas')!.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    expect(linhaNo.hasPrimaryFocus, isTrue);
  });

  testWidgets('com 0 marcadas o foco num botão passa ao chip As que funcionam', (t) async {
    await abrir(t);
    await t.tap(linha('001ALFA 070927'));
    await t.pump();
    final no = focoDe(t, 'Enviar 1 lista')!;
    no.requestFocus();
    await t.pump();
    expect(no.hasPrimaryFocus, isTrue);
    await t.runAsync(() => area.remover([area.listas.first.id]));
    await t.pump();
    await t.pump();
    expect(textosFocados(), 'As que funcionam (1)');
  });

  testWidgets('o Gestor esvazia-se com o foco em Exportar: o foco passa ao chip As que funcionam', (t) async {
    await abrir(t);
    await tocarChip(t, find.textContaining('Todas ('));
    await t.pump();
    final no = focoDe(t, 'Exportar 5 listas')!;
    no.requestFocus();
    await t.pump();
    expect(no.hasPrimaryFocus, isTrue);
    await t.runAsync(() => area.remover([for (final l in area.listas) l.id]));
    await t.pump();
    await t.pump();
    expect(area.listas, isEmpty);
    expect(textosFocados(), 'As que funcionam (0)');
  });

  testWidgets('a pílula das linhas é compacta: não passa a altura da linha, nem com a letra a 2x', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await abrir(t);
    final l = linha('001ALFA 070927');
    final pilula = find.descendant(of: l, matching: find.byType(PilulaEstado));
    expect(t.getRect(l).height, Tokens.alturaLinhaTabela);
    expect(t.getRect(pilula).height, lessThanOrEqualTo(Tokens.alturaLinhaTabela));
    expect(t.getRect(pilula).top, greaterThanOrEqualTo(t.getRect(l).top));
    expect(t.getRect(pilula).bottom, lessThanOrEqualTo(t.getRect(l).bottom));
  });

  testWidgets('a fila dos chips tem barra de deslocamento e «Marcar:» fica fixo fora dela', (t) async {
    await abrir(t, largura: 760);
    final barra = find.byType(Scrollbar);
    expect(find.ancestor(of: find.text('Nenhuma'), matching: barra), findsOneWidget);
    expect(find.ancestor(of: find.text('Marcar:'), matching: barra), findsNothing);
    final marcar = t.getRect(find.text('Marcar:'));
    final antes = t.getRect(find.text('As que funcionam (2)'));
    expect(antes.left, greaterThan(marcar.right), reason: 'os chips à direita de «Marcar:»');
    await t.ensureVisible(find.text('Nenhuma'));
    await t.pumpAndSettle();
    expect(t.getRect(find.text('Marcar:')), marcar, reason: '«Marcar:» não desliza');
    expect(t.getRect(find.text('As que funcionam (2)')).left, lessThan(antes.left), reason: 'os chips deslizaram');
  });

  testWidgets('ecrã estreito: os cartões ficam por baixo da lista', (t) async {
    await abrir(t, largura: 420);
    final lista = t.getTopLeft(find.text('001ALFA 070927'));
    final cartao = t.getTopLeft(find.text('Enviar para o Player'));
    expect(cartao.dy, greaterThan(lista.dy));
    expect(cartao.dx, lessThan(100));
  });
}
