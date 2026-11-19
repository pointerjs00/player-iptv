import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/design/estado_lista.dart';
import 'package:player_iptv/ui/design/tokens.dart';
import 'package:player_iptv/ui/gestor/passo_verificar.dart';
import 'package:player_iptv/verificar/servico.dart';

import 'ajuda_dpad.dart';

final _agora = DateTime(2026, 11, 19, 15);

UltimaVerificacao _u(String estado, DateTime data, {String motivo = ''}) =>
    UltimaVerificacao(estado: estado, data: data, motivo: motivo);

const _nomes = ['018DELTA 181027', '019DELTA 161027', '001ALFA 070927', '010BETA 030227', '007GAMA 201126'];

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
  for (final (i, l) in area.listas.indexed) {
    l.nomeProprio = _nomes[i];
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
  var todas = 0;
  var removidas = <List<Lista>>[];

  Future<void> abrir(WidgetTester t, {FocusNode? focoInicial}) async {
    verificadas = [];
    removidas = [];
    todas = 0;
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
      aoVerVerificacao: () {},
      aoRemover: (ls) async => removidas.add(ls),
      focoInicial: focoInicial,
    ))));
    await t.pump();
  }

  // (as inconclusivas têm uma marca antes do nome)
  Finder linha(String nome) => find.ancestor(of: find.textContaining(nome), matching: find.byType(CheckboxListTile));
  Finder chip(String texto) => find.widgetWithText(FilterChip, texto);
  final botaoAcoes = find.byKey(const ValueKey('botaoAcoes'));
  final caixaCabecalho = find.byKey(const ValueKey('caixaCabecalho'));
  Finder itemMenu(String texto) =>
      find.ancestor(of: find.text(texto), matching: find.byWidgetPredicate((w) => w is PopupMenuItem));
  bool itemLigado(WidgetTester t, String texto) => (t.widget(itemMenu(texto)) as PopupMenuItem).enabled;
  bool? cabecalho(WidgetTester t) => t.widget<Checkbox>(caixaCabecalho).value;
  FocusNode focoAcoes(WidgetTester t) => t.widget<FilledButton>(botaoAcoes).focusNode!;
  FocusNode focoLinha(WidgetTester t, String nome) => t.widget<CheckboxListTile>(linha(nome)).focusNode!;
  List<String> visiveis() => [for (final n in _nomes) if (linha(n).evaluate().isNotEmpty) n];
  List<String> selecionadas(WidgetTester t) =>
      [for (final n in visiveis()) if (t.widget<CheckboxListTile>(linha(n)).value!) n];

  Future<void> abrirMenu(WidgetTester t) async {
    await t.tap(botaoAcoes);
    await t.pumpAndSettle();
  }

  Future<void> escolher(WidgetTester t, String acao) async {
    await abrirMenu(t);
    await t.tap(itemMenu(acao));
    await t.pumpAndSettle();
  }

  testWidgets('uma linha: pesquisa, os quatro estados com contagens e Ações (0) à direita; sem Selecionar: nem Todas',
      (t) async {
    await abrir(t);
    expect(find.text('Pesquisar listas…'), findsOneWidget);
    for (final f in ['Funcionam · 1', 'Inconclusivas · 1', 'Não funcionam · 1', 'Por verificar · 2']) {
      expect(chip(f), findsOneWidget, reason: f);
      expect(t.widget<FilterChip>(chip(f)).selected, isFalse, reason: f);
    }
    expect(find.text('Selecionar:'), findsNothing);
    expect(find.textContaining('Todas'), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('Ações (0)'), findsOneWidget);
    // tudo na mesma linha (o mesmo centro vertical), com Ações depois dos estados, à direita
    final y = t.getCenter(find.byType(TextField)).dy;
    for (final f in [chip('Funcionam · 1'), chip('Por verificar · 2'), botaoAcoes]) {
      expect(t.getCenter(f).dy, moreOrLessEquals(y, epsilon: 1), reason: '$f');
    }
    expect(t.getRect(chip('Funcionam · 1')).left, greaterThan(t.getRect(find.byType(TextField)).right));
    expect(t.getRect(botaoAcoes).left, greaterThan(t.getRect(chip('Funcionam · 1')).right));
    expect(t.getRect(botaoAcoes).right,
        moreOrLessEquals(t.getRect(find.byType(PassoVerificar)).right - Tokens.e16, epsilon: 1));
    for (final c in ['LISTA', 'ESTADO', 'MOTIVO', 'TESTE']) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
    expect(caixaCabecalho, findsOneWidget);
    expect(find.text('CANAIS'), findsNothing);
  });

  testWidgets('estados de escolha múltipla: Inconclusivas + Não funcionam mostram só essas; nenhum mostra todas',
      (t) async {
    await abrir(t);
    expect(visiveis(), _nomes);
    await t.tap(chip('Inconclusivas · 1'));
    await t.pump();
    expect(visiveis(), ['010BETA 030227']);
    await t.tap(chip('Não funcionam · 1'));
    await t.pump();
    expect(visiveis(), ['010BETA 030227', '007GAMA 201126']);
    expect(t.widget<FilterChip>(chip('Inconclusivas · 1')).selected, isTrue);
    expect(t.widget<FilterChip>(chip('Não funcionam · 1')).selected, isTrue);
    await t.tap(chip('Inconclusivas · 1'));
    await t.tap(chip('Não funcionam · 1'));
    await t.pump();
    expect(visiveis(), _nomes, reason: 'nenhum ligado: todas');
  });

  testWidgets('a ☐ do cabeçalho seleciona exatamente as visíveis (com pesquisa também) e volta a desselecionar; '
      'misto mostra o traço', (t) async {
    await abrir(t);
    expect(cabecalho(t), isFalse);
    await t.tap(chip('Inconclusivas · 1'));
    await t.tap(chip('Não funcionam · 1'));
    await t.pump();
    await t.tap(caixaCabecalho);
    await t.pump();
    expect(selecionadas(t), ['010BETA 030227', '007GAMA 201126']);
    expect(cabecalho(t), isTrue);
    expect(find.text('Ações (2)'), findsOneWidget);
    await t.tap(caixaCabecalho);
    await t.pump();
    expect(selecionadas(t), isEmpty);
    expect(cabecalho(t), isFalse);
    expect(find.text('Ações (0)'), findsOneWidget);
    // misto: uma de duas
    await t.tap(linha('010BETA 030227'));
    await t.pump();
    expect(cabecalho(t), isNull, reason: 'o traço');
    expect(t.widget<Checkbox>(caixaCabecalho).tristate, isTrue);
    // com a pesquisa: só as que a pesquisa deixa (a escondida sai da seleção)
    await t.tap(chip('Inconclusivas · 1'));
    await t.tap(chip('Não funcionam · 1'));
    await t.tap(find.byType(TextField));
    await t.pump();
    await t.enterText(find.byType(TextField), 'delta');
    await t.pump();
    expect(visiveis(), ['018DELTA 181027', '019DELTA 161027']);
    await t.tap(caixaCabecalho);
    await t.pump();
    expect(selecionadas(t), ['018DELTA 181027', '019DELTA 161027']);
    expect(find.text('Ações (2)'), findsOneWidget, reason: 'a 010BETA já não está');
    await t.enterText(find.byType(TextField), '');
    await t.pump();
    expect(selecionadas(t), ['018DELTA 181027', '019DELTA 161027']);
    expect(cabecalho(t), isNull);
  });

  testWidgets('OK numa linha alterna a caixa e Ações conta', (t) async {
    await abrir(t);
    Future<void> ok(String nome) async {
      focoLinha(t, nome).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
    }

    await ok('018DELTA 181027');
    await ok('019DELTA 161027');
    expect(find.text('Ações (2)'), findsOneWidget);
    expect(t.widget<CheckboxListTile>(linha('018DELTA 181027')).value, isTrue);
    await ok('018DELTA 181027');
    expect(find.text('Ações (1)'), findsOneWidget);
  });

  testWidgets('Ações abre o menu com as três ações (as da seleção desligadas com 0); '
      'Voltar fecha e o foco volta ao botão', (t) async {
    await abrir(t);
    focoAcoes(t).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    for (final a in ['Verificar selecionadas', 'Verificar todas', 'Remover do gestor']) {
      expect(itemMenu(a), findsOneWidget, reason: a);
    }
    expect(itemLigado(t, 'Verificar selecionadas'), isFalse);
    expect(itemLigado(t, 'Remover do gestor'), isFalse);
    expect(itemLigado(t, 'Verificar todas'), isTrue);
    expect(textosFocados(), 'Verificar todas', reason: 'o foco no 1.º item ligado');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(itemMenu('Verificar todas'), findsNothing);
    expect(focoAcoes(t).hasPrimaryFocus, isTrue);
    // com uma selecionada, todas ligadas
    await t.tap(linha('001ALFA 070927'));
    await t.pump();
    await abrirMenu(t);
    expect(itemLigado(t, 'Verificar selecionadas'), isTrue);
    expect(itemLigado(t, 'Remover do gestor'), isTrue);
    expect(textosFocados(), 'Verificar selecionadas');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(itemMenu('Verificar todas'), findsNothing);
  });

  testWidgets('as ações do menu: Verificar selecionadas, Verificar todas e Remover do gestor', (t) async {
    await abrir(t);
    await t.tap(linha('018DELTA 181027'));
    await t.tap(linha('001ALFA 070927'));
    await t.pump();
    await escolher(t, 'Verificar selecionadas');
    expect(verificadas.single.map((l) => l.nomeProprio), ['018DELTA 181027', '001ALFA 070927']);
    await escolher(t, 'Verificar todas');
    expect(todas, 1);
    await escolher(t, 'Remover do gestor');
    expect(removidas.single.map((l) => l.nomeProprio), ['018DELTA 181027', '001ALFA 070927']);
    // uma que sai do Gestor sai da contagem
    final id = area.listas.first.id;
    await t.runAsync(() => area.remover([id]));
    await t.pump();
    expect(find.text('Ações (1)'), findsOneWidget);
  });

  testWidgets('a tecla Menu numa linha abre o menu; a escrever na pesquisa não abre', (t) async {
    await abrir(t);
    focoLinha(t, '010BETA 030227').requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await t.pumpAndSettle();
    expect(itemMenu('Verificar todas'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(itemMenu('Verificar todas'), findsNothing);
    expect(focoLinha(t, '010BETA 030227').hasPrimaryFocus, isTrue, reason: 'o foco volta à linha');
    // a escrever na pesquisa (toque no campo): a tecla fica para o campo
    await t.tap(find.byType(TextField));
    await t.pump();
    await t.pump();
    expect(t.widget<TextField>(find.byType(TextField)).readOnly, isFalse, reason: 'a escrever');
    await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await t.pumpAndSettle();
    expect(itemMenu('Verificar todas'), findsNothing);
  });

  testWidgets('não há barra em baixo; as linhas têm uma altura fixa baixa', (t) async {
    await abrir(t);
    expect(find.byKey(const ValueKey('barraAcoes')), findsNothing);
    expect(find.text('Nenhuma selecionada'), findsNothing);
    expect(find.textContaining('Ver verificação'), findsNothing);
    // (uma com "A verificar · …" também não cresce)
    servico.passos[area.listas.first.id] = 'canal 2/3 · a abrir o canal';
    servico.notifyListeners();
    await t.pump();
    final alturas = {for (final n in _nomes) t.getSize(linha(n)).height};
    expect(alturas, hasLength(1), reason: '$alturas');
    expect(alturas.single, lessThanOrEqualTo(32));
    servico.passos.clear();
  });

  testWidgets('o cabeçalho fica alinhado com as colunas das linhas (e a ☐ com as caixas)', (t) async {
    await abrir(t);
    final l = linha('018DELTA 181027');
    double x(Finder f) => t.getTopLeft(f).dx;
    expect(x(find.text('LISTA')), x(find.descendant(of: l, matching: find.textContaining('018DELTA 181027'))));
    expect(x(find.text('TESTE')), x(find.descendant(of: l, matching: find.text('nunca'))));
    expect(x(find.text('MOTIVO')), x(find.descendant(of: l, matching: find.text('—'))));
    expect(t.getCenter(caixaCabecalho).dx,
        moreOrLessEquals(t.getCenter(find.descendant(of: l, matching: find.byType(Checkbox))).dx, epsilon: 1));
  });

  testWidgets('filtrar(estados) liga só esses, limpa a pesquisa e põe o foco no estado', (t) async {
    await abrir(t);
    await t.enterText(find.byType(TextField), 'alfa');
    await t.pump();
    t.state<PassoVerificarState>(find.byType(PassoVerificar)).filtrar({EstadoLista.porVerificar});
    await t.pump();
    await t.pump();
    expect(visiveis(), ['018DELTA 181027', '019DELTA 161027']);
    expect(t.widget<FilterChip>(chip('Por verificar · 2')).selected, isTrue);
    expect(t.widget<FilterChip>(chip('Funcionam · 1')).selected, isFalse);
    expect(textosFocados(), 'Por verificar · 2');
    // o estado com o foco fica à vista (os estados deslizam se não couberem): DIREITA chega a Ações
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(focoAcoes(t).hasPrimaryFocus, isTrue, reason: textosFocados());
    t.state<PassoVerificarState>(find.byType(PassoVerificar)).filtrar(<EstadoLista>{});
    await t.pump();
    expect(visiveis(), _nomes);
  });

  testWidgets('a linha com o foco sai e não fica nenhuma visível: o foco vai a Ações', (t) async {
    await abrir(t);
    await t.tap(caixaCabecalho);
    await t.pump();
    focoLinha(t, '001ALFA 070927').requestFocus();
    await t.pump();
    await t.runAsync(() => area.remover([for (final l in area.listas) l.id]));
    await t.pump();
    await t.pump();
    expect(area.listas, isEmpty);
    expect(find.text('Ações (0)'), findsOneWidget);
    expect(focoAcoes(t).hasPrimaryFocus, isTrue, reason: '${FocusManager.instance.primaryFocus}');
  });

  testWidgets('a linha com o foco sai e ficam outras: o foco passa à que ficou no lugar dela', (t) async {
    await abrir(t);
    focoLinha(t, '019DELTA 161027').requestFocus();
    await t.pump();
    await t.runAsync(() => area.remover([area.listas[1].id]));
    await t.pump();
    await t.pump();
    expect(focoLinha(t, '001ALFA 070927').hasPrimaryFocus, isTrue);
  });

  testWidgets('TESTE mostra nunca, há 2 h e ontem; MOTIVO o motivo', (t) async {
    await abrir(t);
    expect(find.descendant(of: linha('018DELTA 181027'), matching: find.text('nunca')), findsOneWidget);
    expect(find.descendant(of: linha('001ALFA 070927'), matching: find.text('há 2 h')), findsOneWidget);
    expect(find.descendant(of: linha('001ALFA 070927'), matching: find.text('3 de 3 canais com imagem')),
        findsOneWidget);
    expect(find.text('ontem'), findsNWidgets(2));
  });

  testWidgets('D-pad: CIMA da 1.ª linha vai à ☐ do cabeçalho e daí à linha da pesquisa; '
      'DIREITA nessa linha chega a Ações', (t) async {
    await abrir(t);
    focoLinha(t, '018DELTA 181027').requestFocus();
    await t.pump();
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Selecionar as visíveis');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    final caixa = FocusManager.instance.primaryFocus!.context!.findRenderObject()! as RenderBox;
    expect(caixa.localToGlobal(caixa.size.center(Offset.zero)).dy,
        moreOrLessEquals(t.getCenter(find.byType(TextField)).dy, epsilon: 2),
        reason: 'na linha da pesquisa: ${textosFocados()}');
    // DIREITA passa por todos os estados (os que não cabem deslizam para a vista) até Ações
    final direita = <String>[];
    for (var i = 0; i < 8 && !focoAcoes(t).hasPrimaryFocus; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
      direita.add(textosFocados());
    }
    expect(focoAcoes(t).hasPrimaryFocus, isTrue, reason: '$direita');
    expect(direita, containsAllInOrder(['Funcionam · 1', 'Inconclusivas · 1', 'Não funcionam · 1', 'Por verificar · 2']),
        reason: '$direita');
    // BAIXO em Ações desce à tabela
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<PassoVerificar>(), isNotNull);
    expect(focoAcoes(t).hasPrimaryFocus, isFalse);
  });
}
