import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/design/tokens.dart';
import 'package:player_iptv/ui/gestor/passo_verificar.dart';
import 'package:player_iptv/verificar/servico.dart';

import 'ajuda_dpad.dart';

final _agora = DateTime(2026, 11, 19, 15);

UltimaVerificacao _u(String estado, DateTime data, {String motivo = ''}) =>
    UltimaVerificacao(estado: estado, data: data, motivo: motivo);

/// Cinco listas fictícias: 2 por verificar, 1 funciona, 1 inconclusiva, 1 não funciona.
Future<void> _povoar(AreaGestor area) async {
  await area.adicionar([
    Importada(contaDeLinha('http://delta1.exemplo.pt/c/ 00:1A:79:00:00:01')!, null),
    Importada(contaDeLinha('http://delta2.exemplo.pt/c/ 00:1A:79:00:00:02')!, null),
    Importada(contaDeLinha('http://alfa.exemplo.pt/c/ 00:1A:79:00:00:03')!,
        _u('funciona', _agora.subtract(const Duration(hours: 2)), motivo: '3 de 3 canais com imagem')),
    Importada(contaDeLinha('http://beta.exemplo.pt/c/ 00:1A:79:00:00:04')!,
        _u('inconclusivo', DateTime(2026, 11, 18, 10), motivo: 'abriu 1 de 3 canais')),
    Importada(contaDeLinha('http://gama.exemplo.pt/c/ 00:1A:79:00:00:05')!,
        _u('nao_funciona', DateTime(2026, 11, 18, 9), motivo: 'conta expirada')),
  ]);
  final nomes = ['018DELTA 181027', '019DELTA 161027', '001ALFA 070927', '010BETA 030227', '007GAMA 201126'];
  for (final (i, l) in area.listas.indexed) {
    l.nomeProprio = nomes[i];
  }
}

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;
  late ServicoVerificacao servico;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('passo_verificar');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
    servico = ServicoVerificacao(bib, colecao: area);
  });
  tearDown(() async {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  var verificadas = <List<Lista>>[];
  var todas = 0, ver = 0;
  var removidas = <List<Lista>>[];

  Future<void> abrir(WidgetTester t) async {
    verificadas = [];
    removidas = [];
    todas = ver = 0;
    await t.runAsync(() => _povoar(area));
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(appTeste(Scaffold(
        body: PassoVerificar(
      area: area,
      servico: servico,
      agora: () => _agora,
      aoVerificar: verificadas.add,
      aoVerificarTodas: () => todas++,
      aoVerVerificacao: () => ver++,
      aoRemover: (ls) async => removidas.add(ls),
    ))));
    await t.pump();
  }

  Finder linha(String nome) => find.ancestor(of: find.text(nome), matching: find.byType(CheckboxListTile));
  bool eBotao(Widget w) => w is FilledButton || w is OutlinedButton;
  Finder botao(String texto) => find.ancestor(of: find.text(texto), matching: find.byWidgetPredicate(eBotao));
  FocusNode? focoDe(Widget w) => w is FilledButton ? w.focusNode : (w as OutlinedButton).focusNode;
  bool ligado(WidgetTester t, String texto) {
    final w = t.widget(botao(texto));
    return (w is FilledButton ? w.onPressed : (w as OutlinedButton).onPressed) != null;
  }

  testWidgets('mostra pesquisa, filtros com contagens, seleção e cabeçalho', (t) async {
    await abrir(t);
    expect(find.text('Pesquisar listas…'), findsOneWidget);
    for (final f in ['Todas · 5', 'Funcionam · 1', 'Inconclusivas · 1', 'Não funcionam · 1', 'Por verificar · 2']) {
      expect(find.text(f), findsOneWidget, reason: f);
    }
    expect(find.text('Selecionar:'), findsOneWidget);
    for (final s in ['Todas as visíveis', 'Por verificar', 'Nenhuma']) {
      expect(find.widgetWithText(ActionChip, s), findsOneWidget, reason: s);
    }
    for (final c in ['LISTA', 'ESTADO', 'MOTIVO', 'TESTE']) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
    expect(find.text('CANAIS'), findsNothing);
  });

  testWidgets('pesquisa e filtro limitam as linhas; Todas as visíveis só marca essas', (t) async {
    await abrir(t);
    await t.enterText(find.byType(TextField), 'delta');
    await t.pump();
    expect(linha('018DELTA 181027'), findsOneWidget);
    expect(linha('019DELTA 161027'), findsOneWidget);
    expect(linha('001ALFA 070927'), findsNothing);
    await t.tap(find.text('Todas as visíveis'));
    await t.pump();
    expect(find.text('2 selecionadas'), findsOneWidget);
    await t.tap(find.text('Nenhuma'));
    await t.enterText(find.byType(TextField), '');
    await t.tap(find.text('Funcionam · 1'));
    await t.pump();
    expect(linha('001ALFA 070927'), findsOneWidget);
    expect(linha('018DELTA 181027'), findsNothing);
    await t.tap(find.text('Todas as visíveis'));
    await t.pump();
    expect(find.text('1 selecionada'), findsOneWidget);
  });

  testWidgets('OK numa linha alterna a caixa e a barra conta', (t) async {
    await abrir(t);
    expect(find.text('Nenhuma selecionada'), findsOneWidget);
    Future<void> ok(String nome) async {
      t.widget<CheckboxListTile>(linha(nome)).focusNode!.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
    }

    await ok('018DELTA 181027');
    await ok('019DELTA 161027');
    expect(find.text('2 selecionadas'), findsOneWidget);
    expect(t.widget<CheckboxListTile>(linha('018DELTA 181027')).value, isTrue);
    await ok('018DELTA 181027');
    expect(find.text('1 selecionada'), findsOneWidget);
  });

  testWidgets('a barra: botões certos, fundo superficie3, desativados sem seleção', (t) async {
    await abrir(t);
    final barra = find.byKey(const ValueKey('barraAcoes'));
    expect(barra, findsOneWidget);
    expect((t.widget<Container>(barra).decoration as BoxDecoration).color, Tokens.superficie3);
    expect(find.descendant(of: barra, matching: find.byWidgetPredicate(eBotao)), findsNWidgets(4));
    for (final b in ['Verificar selecionadas', 'Verificar todas', 'Ver verificação', 'Remover do gestor']) {
      expect(botao(b), findsOneWidget, reason: b);
    }
    expect(ligado(t, 'Verificar selecionadas'), isFalse);
    expect(ligado(t, 'Remover do gestor'), isFalse);
    expect(ligado(t, 'Verificar todas'), isTrue);
    await t.tap(linha('001ALFA 070927'));
    await t.pump();
    expect(ligado(t, 'Verificar selecionadas'), isTrue);
    expect(ligado(t, 'Remover do gestor'), isTrue);
  });

  testWidgets('Ver verificação: desativado antes de qualquer verificação, com contagem a correr', (t) async {
    await abrir(t);
    expect(ligado(t, 'Ver verificação'), isFalse);
    expect(find.text('nenhuma verificação'), findsOneWidget);
    servico.passos['x'] = 'na fila';
    servico.feitas = 2;
    servico.total = 5;
    servico.notifyListeners();
    await t.pump();
    expect(find.text('nenhuma verificação'), findsNothing);
    expect(find.text('Ver verificação · 2/5'), findsOneWidget);
    await t.tap(find.text('Ver verificação · 2/5'));
    expect(ver, 1);
    servico.passos.clear();
    servico.feitas = servico.total = 0;
  });

  testWidgets('Ver verificação fica ligado depois de uma ronda acabar', (t) async {
    await abrir(t);
    servico.fimRonda = _agora;
    servico.notifyListeners();
    await t.pump();
    expect(ligado(t, 'Ver verificação'), isTrue);
    expect(find.text('nenhuma verificação'), findsNothing);
  });

  testWidgets('o cabeçalho fica alinhado com as colunas das linhas', (t) async {
    await abrir(t);
    final l = linha('018DELTA 181027');
    double x(Finder f) => t.getTopLeft(f).dx;
    expect(x(find.text('LISTA')), x(find.descendant(of: l, matching: find.text('018DELTA 181027'))));
    expect(x(find.text('TESTE')), x(find.descendant(of: l, matching: find.text('nunca'))));
    expect(x(find.text('MOTIVO')), x(find.descendant(of: l, matching: find.text('—'))));
  });

  testWidgets('Verificar selecionadas chama aoVerificar e o foco fica na barra', (t) async {
    await abrir(t);
    await t.tap(linha('018DELTA 181027'));
    await t.tap(linha('001ALFA 070927'));
    await t.pump();
    final no = focoDe(t.widget(botao('Verificar selecionadas')))!;
    no.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(verificadas.single.map((l) => l.nomeProprio), ['018DELTA 181027', '001ALFA 070927']);
    expect(no.hasPrimaryFocus, isTrue);
    await t.tap(find.text('Verificar todas'));
    expect(todas, 1);
  });

  testWidgets('Remover do gestor entrega as selecionadas; uma que sai do Gestor sai da contagem', (t) async {
    await abrir(t);
    await t.tap(linha('018DELTA 181027'));
    await t.tap(linha('019DELTA 161027'));
    await t.pump();
    expect(find.text('2 selecionadas'), findsOneWidget);
    await t.tap(find.text('Remover do gestor'));
    await t.pump();
    expect(removidas.single.length, 2);
    final id = area.listas.first.id;
    await t.runAsync(() => area.remover([id]));
    await t.pump();
    expect(find.text('1 selecionada'), findsOneWidget);
  });

  testWidgets('TESTE mostra nunca, há 2 h e ontem; MOTIVO o motivo', (t) async {
    await abrir(t);
    expect(find.descendant(of: linha('018DELTA 181027'), matching: find.text('nunca')), findsOneWidget);
    expect(find.descendant(of: linha('001ALFA 070927'), matching: find.text('há 2 h')), findsOneWidget);
    expect(find.descendant(of: linha('001ALFA 070927'), matching: find.text('3 de 3 canais com imagem')),
        findsOneWidget);
    expect(find.text('ontem'), findsNWidgets(2));
  });

  testWidgets('D-pad: BAIXO da última linha vai à barra e CIMA volta a essa linha', (t) async {
    await abrir(t);
    final ultima = t.widget<CheckboxListTile>(linha('007GAMA 201126')).focusNode!;
    ultima.requestFocus();
    await t.pump();
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Verificar todas'));
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(ultima.hasPrimaryFocus, isTrue);
  });
}
