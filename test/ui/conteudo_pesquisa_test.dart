import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/design/barra_teclas.dart';
import 'package:player_iptv/ui/design/design.dart';

import 'ajuda_dpad.dart';

/// A lista aberta: uma só pesquisa para canais e grupos (variante C).

// 20 + 11 canais com "Desp" no nome, e dois que não têm
final _conteudo = ConteudoLista(['Desporto', 'Desporto Internacional', 'Notícias'], [
  for (var i = 1; i <= 20; i++) Canal(id: 'd$i', nome: 'Desporto $i', grupo: 'Desporto', numero: 200 + i),
  for (var i = 1; i <= 11; i++)
    Canal(id: 'i$i', nome: 'Desp. Mundo $i', grupo: 'Desporto Internacional', numero: 300 + i),
  const Canal(id: 'n1', nome: 'Notícias 1', grupo: 'Notícias', numero: 401),
  const Canal(id: 'n2', nome: 'Notícias 2', grupo: 'Notícias', numero: 402),
]);

final _pesquisa = find.byKey(const Key('pesquisa-canais'));
final _grupos = find.byKey(const Key('lista-grupos'));
final _canais = find.byKey(const Key('lista-canais'));

/// O texto do ListTile (canal ou grupo) com o foco.
String? _focado() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  final tile = ctx?.widget is ListTile ? ctx!.widget as ListTile : ctx?.findAncestorWidgetOfExactType<ListTile>();
  final t = tile?.title;
  return t is Text ? (t.data ?? t.textSpan?.toPlainText()) : null;
}

/// Os nomes nos ListTiles de uma coluna (os construídos).
List<String> _nomes(WidgetTester t, Finder coluna) => [
      for (final e in find.descendant(of: coluna, matching: find.byType(ListTile)).evaluate())
        if ((e.widget as ListTile).title case final Text x) x.data ?? x.textSpan!.toPlainText(),
    ];

bool _naPesquisa(WidgetTester t) =>
    t.widget<EditableText>(find.descendant(of: _pesquisa, matching: find.byType(EditableText))).focusNode.hasPrimaryFocus;

void main() {
  late Directory pasta;
  late Biblioteca bib;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('conteudo-pesquisa');
    bib = await Biblioteca.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  /// A lista aberta por cima de um ecrã "base" (para o Voltar ter para onde ir).
  Future<Lista> abrir(WidgetTester t, {ConteudoLista? conteudo, double largura = 960, double altura = 540}) async {
    ecraTvTeste(t, largura: largura, altura: altura);
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
      await bib.guardarCanais(bib.listas.single.id, conteudo ?? _conteudo);
    });
    final l = bib.listas.single;
    await t.runAsync(() async {
      await t.pumpWidget(appTeste(const Scaffold(body: Text('base'))));
      Navigator.of(t.element(find.text('base'))).push(MaterialPageRoute<void>(
          builder: (_) => TelaConteudo(biblioteca: bib, lista: l, abrir: (c, i) => null)));
      await t.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpAndSettle();
    return l;
  }

  Future<void> escrever(WidgetTester t, String texto) async {
    await t.tap(_pesquisa);
    await t.pump();
    await t.enterText(_pesquisa, texto);
    await t.pump(const Duration(milliseconds: 200));
    await t.pumpAndSettle();
  }

  /// A tecla Voltar do comando (o simulador não tem tecla física para o goBack: usa-se a do Esc).
  Future<void> voltar(WidgetTester t) async {
    await t.sendKeyEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.escape);
    await t.pumpAndSettle();
  }

  /// Põe o foco na linha (grupo ou canal) com este texto.
  Future<void> focar(WidgetTester t, String texto) async {
    final noGrupo = find.descendant(of: _grupos, matching: find.text(texto));
    final f = noGrupo.evaluate().isNotEmpty ? noGrupo : find.descendant(of: _canais, matching: find.text(texto));
    Focus.of(t.element(f.first)).requestFocus();
    await t.pumpAndSettle();
    expect(_focado(), texto);
  }

  testWidgets('a pesquisa encontra grupos e canais', (t) async {
    await abrir(t);
    expect(find.text('Pesquisar canais, grupos ou o número'), findsOneWidget);
    await escrever(t, 'desp');
    expect(find.text('Grupos · 2'), findsOneWidget);
    expect(find.text('Canais · 31'), findsOneWidget);
    expect(_nomes(t, _grupos), ['Desporto', 'Desporto Internacional']);
    // a parte encontrada vem destacada
    final destaque = t.widget<Text>(find.descendant(of: _grupos, matching: find.text('Desporto Internacional')));
    final partes = (destaque.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(partes.firstWhere((p) => p.text == 'Desp').style?.color, Tokens.anelFoco);
    // o resultado todo, com scroll: o último canal encontrado alcança-se (sem "+ N canais")
    expect(find.textContaining(RegExp(r'\+ ?\d+ canais')), findsNothing);
    await t.scrollUntilVisible(find.text('Desp. Mundo 11'), 300, scrollable: find.descendant(
        of: _canais, matching: find.byType(Scrollable)));
    expect(find.text('Desp. Mundo 11'), findsOneWidget);
    expect(find.text('Notícias 1'), findsNothing);
  });

  testWidgets('Canais / Grupos limitam a pesquisa', (t) async {
    await abrir(t);
    await escrever(t, 'desp');
    // com «Grupos», os canais são os do grupo escolhido, como sem pesquisa
    await t.tap(find.widgetWithText(ChoiceChip, 'Grupos'));
    await t.pumpAndSettle();
    expect(find.text('Grupos · 2'), findsOneWidget);
    expect(find.text('Canais · 31'), findsNothing);
    expect(find.descendant(of: _canais, matching: find.text('Desporto 1')), findsOneWidget);
    expect(find.text('Desp. Mundo 1'), findsNothing);
    // com «Canais», a coluna dos grupos mostra todos
    await t.tap(find.widgetWithText(ChoiceChip, 'Canais'));
    await t.pumpAndSettle();
    expect(find.text('Canais · 31'), findsOneWidget);
    expect(find.textContaining('Grupos ·'), findsNothing);
    expect(_nomes(t, _grupos), ['Desporto', 'Desporto Internacional', 'Notícias']);
    // e «Tudo» volta aos dois
    await t.tap(find.widgetWithText(ChoiceChip, 'Tudo'));
    await t.pumpAndSettle();
    expect(find.text('Grupos · 2'), findsOneWidget);
    expect(find.text('Canais · 31'), findsOneWidget);
  });

  testWidgets('OK num grupo encontrado limpa a pesquisa e abre o grupo', (t) async {
    await abrir(t);
    await escrever(t, 'internac');
    expect(find.text('Grupos · 1'), findsOneWidget);
    await voltar(t); // acaba de escrever
    await focar(t, 'Desporto Internacional');
    expect(_focado(), 'Desporto Internacional');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(t.widget<TextField>(find.descendant(of: _pesquisa, matching: find.byType(TextField))).controller!.text, '');
    expect(find.textContaining('Grupos ·'), findsNothing);
    expect(_nomes(t, _grupos), ['Desporto', 'Desporto Internacional', 'Notícias']);
    expect(find.descendant(of: _canais, matching: find.text('Desp. Mundo 1')), findsOneWidget);
    expect(find.text('Desporto 1'), findsNothing);
    expect(_focado(), 'Desporto Internacional');
  });

  testWidgets('Voltar com texto limpa a pesquisa; sem texto sai', (t) async {
    await abrir(t);
    await escrever(t, 'desp');
    // a escrever, o primeiro Voltar só fecha o teclado (no Android TV chega como "voltar" do sistema)
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Canais · 31'), findsOneWidget);
    // a barra de teclas diz o que fazem as teclas com texto na pesquisa
    expect(t.widget<BarraTeclas>(find.byType(BarraTeclas)).itens,
        [('↑', 'pesquisa'), ('OK', 'abrir'), ('Voltar', 'limpar')]);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Canais · 31'), findsNothing);
    expect(t.widget<TextField>(find.descendant(of: _pesquisa, matching: find.byType(TextField))).controller!.text, '');
    expect(find.byType(TelaConteudo), findsOneWidget);
    // também com a tecla Voltar, e com o foco nos canais
    await escrever(t, 'desp');
    await voltar(t);
    await focar(t, 'Desporto 1');
    await voltar(t);
    await t.pumpAndSettle();
    expect(find.text('Canais · 31'), findsNothing);
    expect(find.byType(TelaConteudo), findsOneWidget);
    // sem texto, sai
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(TelaConteudo), findsNothing);
    expect(find.text('base'), findsOneWidget);
  });

  testWidgets('Voltar com o foco num canal encontrado leva o foco ao 1.º canal do grupo', (t) async {
    await abrir(t);
    await escrever(t, 'desp');
    await voltar(t); // acaba de escrever
    await focar(t, 'Desporto 3');
    await voltar(t); // limpa a pesquisa
    expect(find.text('Canais · 31'), findsNothing);
    // o foco não fica numa linha qualquer (outro canal na mesma posição): vai ao 1.º do grupo
    expect(_focado(), 'Desporto 1', reason: textosFocados());
    expect(t.widget<Text>(find.byKey(const Key('contador-canais'))).data, '1 de 20');
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(_focado(), 'Desporto 2');
    expect(t.widget<Text>(find.byKey(const Key('contador-canais'))).data, '2 de 20');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_focado(), 'Desporto 1');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_naPesquisa(t), isTrue);
  });

  testWidgets('Voltar com o foco num canal que fica sem par no grupo não perde o foco', (t) async {
    await abrir(t);
    await escrever(t, 'desp');
    await voltar(t);
    // a 25.ª linha dos resultados: o grupo «Desporto» só tem 20
    await t.scrollUntilVisible(find.text('Desp. Mundo 5'), 300,
        scrollable: find.descendant(of: _canais, matching: find.byType(Scrollable)));
    await focar(t, 'Desp. Mundo 5');
    await voltar(t);
    expect(_focado(), 'Desporto 1', reason: textosFocados());
    expect(t.widget<Text>(find.byKey(const Key('contador-canais'))).data, '1 de 20');
  });

  testWidgets('↑ no primeiro grupo ou no primeiro canal vai à pesquisa', (t) async {
    await abrir(t);
    // o foco começa no grupo escolhido (o primeiro)
    expect(_focado(), 'Desporto');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_naPesquisa(t), isTrue, reason: 'do 1.º grupo: ${textosFocados()}');
    await focar(t, 'Desporto 1');
    expect(_focado(), 'Desporto 1');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_naPesquisa(t), isTrue, reason: 'do 1.º canal: ${textosFocados()}');
    // com pesquisa, o mesmo nas duas colunas de resultados
    await escrever(t, 'desp');
    await voltar(t);
    await focar(t, 'Desporto');
    expect(_focado(), 'Desporto');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_naPesquisa(t), isTrue);
    // e de um grupo que não é o primeiro, ↑ vai ao de cima
    await focar(t, 'Desporto Internacional');
    expect(_focado(), 'Desporto Internacional');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_focado(), 'Desporto');
  });

  testWidgets('a escolha Tudo · Canais · Grupos recebe o foco com → a partir da pesquisa', (t) async {
    await abrir(t);
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_naPesquisa(t), isTrue);
    final caminho = <String>[];
    for (final _ in [1, 2, 3]) {
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
      caminho.add(textosFocados());
    }
    expect(caminho, ['Tudo', 'Canais', 'Grupos']);
    await teclaDpad(t, LogicalKeyboardKey.select);
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Grupos')).selected, isTrue);
  });

  testWidgets('no ecrã estreito os grupos encontrados vão numa fila de chips por cima dos canais', (t) async {
    await abrir(t, largura: 400, altura: 800);
    await escrever(t, 'desp');
    expect(find.widgetWithText(ChoiceChip, 'Desporto'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Desporto Internacional'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Notícias'), findsNothing);
    expect(find.text('Canais · 31'), findsOneWidget);
    expect(t.getRect(find.widgetWithText(ChoiceChip, 'Desporto')).bottom,
        lessThanOrEqualTo(t.getRect(find.text('Canais · 31')).top));
  });

  testWidgets('já não existe o campo filtro-grupos', (t) async {
    await abrir(t);
    expect(find.byKey(const Key('filtro-grupos')), findsNothing);
    expect(find.text('Filtrar grupos…'), findsNothing);
  });

  testWidgets('pesquisa numa lista de 100 mil canais (e 5000 grupos)', (t) async {
    // 1 em cada 10 no Desporto; os outros por 4999 grupos "Filmes N"
    final grande = ConteudoLista(['Desporto', for (var g = 0; g < 4999; g++) 'Filmes $g'], [
      for (var i = 0; i < 100000; i++)
        Canal(id: '$i', nome: i % 10 == 0 ? 'Desporto $i' : 'Filme $i',
            grupo: i % 10 == 0 ? 'Desporto' : 'Filmes ${i % 4999}'),
    ]);
    await abrir(t, conteudo: grande);
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2))); // os nomes indexados
    await t.pump();
    final sw = Stopwatch()..start();
    await escrever(t, 'desp');
    sw.stop();
    expect(find.text('Canais · 10000'), findsOneWidget);
    expect(find.text('Grupos · 1'), findsOneWidget);
    // continua virtualizada: só se constroem as linhas à vista
    final lista = t.widget<ListView>(_canais);
    expect(lista.itemExtent, isNotNull);
    expect(find.descendant(of: _canais, matching: find.byType(ListTile)).evaluate().length, lessThan(40));
    expect(sw.elapsedMilliseconds, lessThan(2000), reason: 'escrever bloqueou ${sw.elapsedMilliseconds} ms');
    // cada rebuild com pesquisa (aqui, pôr/tirar favoritos) não volta a normalizar os 5000 grupos
    // (com «Grupos»: os canais à vista são os do grupo escolhido, com a estrela)
    await t.tap(find.widgetWithText(ChoiceChip, 'Grupos'));
    await escrever(t, 'filmes 12');
    expect(find.text('Grupos · 111'), findsOneWidget);
    final reb = Stopwatch()..start();
    for (var k = 0; k < 5; k++) {
      await t.tap(find.byTooltip(k.isEven ? 'Pôr nos favoritos' : 'Tirar dos favoritos').first);
      await t.pump();
    }
    reb.stop();
    expect(reb.elapsedMilliseconds / 5, lessThan(250), reason: 'rebuild médio ${reb.elapsedMilliseconds / 5} ms');
  });

  testWidgets('‹ Início sai logo, mesmo com texto na pesquisa', (t) async {
    await abrir(t);
    await escrever(t, 'desp');
    await t.tap(find.text('‹ Início'));
    await t.pumpAndSettle();
    expect(find.byType(TelaConteudo), findsNothing);
    expect(find.text('base'), findsOneWidget);
  });
}
