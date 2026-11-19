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

/// A lista aberta: «Filtrar grupos» no topo dos grupos e «Pesquisar canais ou número» no topo dos canais.

// 20 + 11 canais com "Desp" no nome, e dois que não têm
final _conteudo = ConteudoLista(['Desporto', 'Desporto Internacional', 'Notícias'], [
  for (var i = 1; i <= 20; i++) Canal(id: 'd$i', nome: 'Desporto $i', grupo: 'Desporto', numero: 200 + i),
  for (var i = 1; i <= 11; i++)
    Canal(id: 'i$i', nome: 'Desp. Mundo $i', grupo: 'Desporto Internacional', numero: 300 + i),
  const Canal(id: 'n1', nome: 'Notícias 1', grupo: 'Notícias', numero: 401),
  const Canal(id: 'n2', nome: 'Notícias 2', grupo: 'Notícias', numero: 402),
]);

final _pesquisa = find.byKey(const Key('pesquisa-canais'));
final _filtro = find.byKey(const Key('filtro-grupos'));
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

bool _noCampo(WidgetTester t, Finder campo) =>
    t.widget<EditableText>(find.descendant(of: campo, matching: find.byType(EditableText))).focusNode.hasPrimaryFocus;

bool _naPesquisa(WidgetTester t) => _noCampo(t, _pesquisa);

String _texto(WidgetTester t, Finder campo) =>
    t.widget<TextField>(find.descendant(of: campo, matching: find.byType(TextField))).controller!.text;

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

  Future<void> filtrar(WidgetTester t, String texto) async {
    await t.tap(_filtro);
    await t.pump();
    await t.enterText(_filtro, texto);
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

  testWidgets('dois campos separados: filtrar grupos e pesquisar canais ou número; sem Tudo · Canais · Grupos', (t) async {
    await abrir(t);
    expect(find.text('Filtrar grupos'), findsOneWidget);
    expect(find.text('Pesquisar canais ou número'), findsOneWidget);
    // cada campo no topo da sua coluna
    expect(t.getRect(_filtro).bottom, lessThanOrEqualTo(t.getRect(_grupos).top + 1));
    expect(t.getRect(_pesquisa).bottom, lessThanOrEqualTo(t.getRect(_canais).top + 1));
    expect(t.getRect(_filtro).right, lessThan(t.getRect(_pesquisa).left));
    expect(find.widgetWithText(ChoiceChip, 'Tudo'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Canais'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Grupos'), findsNothing);
  });

  testWidgets('filtrar grupos mostra só esses grupos e não mexe nos canais', (t) async {
    await abrir(t);
    await filtrar(t, 'desp');
    expect(_nomes(t, _grupos), ['Desporto', 'Desporto Internacional']);
    expect(find.textContaining('Grupos ·'), findsNothing);
    // a parte encontrada vem destacada
    final destaque = t.widget<Text>(find.descendant(of: _grupos, matching: find.text('Desporto Internacional')));
    final partes = (destaque.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(partes.firstWhere((p) => p.text == 'Desp').style?.color, Tokens.anelFoco);
    // os canais continuam os do grupo escolhido
    expect(find.textContaining('Canais ·'), findsNothing);
    expect(find.descendant(of: _canais, matching: find.text('Desporto 1')), findsOneWidget);
    expect(find.text('Desp. Mundo 1'), findsNothing);
    await filtrar(t, 'notic');
    expect(_nomes(t, _grupos), ['Notícias']);
    expect(find.descendant(of: _canais, matching: find.text('Desporto 1')), findsOneWidget);
  });

  testWidgets('pesquisar canais procura em todos os grupos e não mexe nos grupos', (t) async {
    await abrir(t);
    await escrever(t, 'desp');
    expect(find.text('Canais · 31'), findsOneWidget);
    expect(_nomes(t, _grupos), ['Desporto', 'Desporto Internacional', 'Notícias']);
    // o resultado todo, com scroll: o último canal encontrado alcança-se (sem "+ N canais")
    expect(find.textContaining(RegExp(r'\+ ?\d+ canais')), findsNothing);
    await t.scrollUntilVisible(find.text('Desp. Mundo 11'), 300, scrollable: find.descendant(
        of: _canais, matching: find.byType(Scrollable)));
    expect(find.text('Desp. Mundo 11'), findsOneWidget);
    expect(find.text('Notícias 1'), findsNothing);
    // o número do canal também encontra
    await escrever(t, '402');
    expect(find.text('Canais · 1'), findsOneWidget);
    expect(find.descendant(of: _canais, matching: find.text('Notícias 2')), findsOneWidget);
  });

  testWidgets('os dois campos funcionam em conjunto, cada um com o seu texto', (t) async {
    await abrir(t);
    await filtrar(t, 'notic');
    await escrever(t, 'desp. mundo 3');
    expect(_nomes(t, _grupos), ['Notícias']);
    expect(find.text('Canais · 1'), findsOneWidget);
    expect(_texto(t, _filtro), 'notic');
    expect(_texto(t, _pesquisa), 'desp. mundo 3');
  });

  testWidgets('OK num grupo com a pesquisa de canais ativa limpa a pesquisa e abre o grupo', (t) async {
    await abrir(t);
    await escrever(t, 'internac');
    await voltar(t); // acaba de escrever
    await focar(t, 'Desporto Internacional');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(_texto(t, _pesquisa), '');
    expect(find.textContaining('Canais ·'), findsNothing);
    expect(find.descendant(of: _canais, matching: find.text('Desp. Mundo 1')), findsOneWidget);
    expect(find.text('Desporto 1'), findsNothing);
    expect(_focado(), 'Desporto Internacional');
  });

  testWidgets('OK num grupo filtrado abre-o e o filtro fica', (t) async {
    await abrir(t);
    await filtrar(t, 'internac');
    await voltar(t); // acaba de escrever
    await focar(t, 'Desporto Internacional');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(_texto(t, _filtro), 'internac');
    expect(_nomes(t, _grupos), ['Desporto Internacional']);
    expect(find.descendant(of: _canais, matching: find.text('Desp. Mundo 1')), findsOneWidget);
  });

  testWidgets('Voltar com texto limpa a pesquisa dos canais; sem texto sai', (t) async {
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
    expect(_texto(t, _pesquisa), '');
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

  testWidgets('Voltar com texto no filtro dos grupos limpa o filtro (e só esse campo)', (t) async {
    await abrir(t);
    await filtrar(t, 'notic');
    await escrever(t, 'desp');
    await voltar(t); // acaba de escrever na pesquisa
    // com o foco na coluna dos grupos, o Voltar limpa o filtro e deixa a pesquisa
    await focar(t, 'Notícias');
    await voltar(t);
    expect(_texto(t, _filtro), '');
    expect(_texto(t, _pesquisa), 'desp');
    expect(_nomes(t, _grupos), ['Desporto', 'Desporto Internacional', 'Notícias']);
    expect(_focado(), isNotNull, reason: 'o foco não se perde: ${textosFocados()}');
    // com o foco nos canais, limpa a pesquisa
    await focar(t, 'Desporto 1');
    await voltar(t);
    expect(_texto(t, _pesquisa), '');
    expect(find.byType(TelaConteudo), findsOneWidget);
    // e o Voltar do sistema com texto só no filtro também o limpa antes de sair
    await filtrar(t, 'desp');
    await voltar(t);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(_texto(t, _filtro), '');
    expect(find.byType(TelaConteudo), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(TelaConteudo), findsNothing);
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

  testWidgets('↑ no primeiro grupo vai ao filtro dos grupos; ↑ no primeiro canal à pesquisa dos canais', (t) async {
    await abrir(t);
    // o foco começa no grupo escolhido (o primeiro)
    expect(_focado(), 'Desporto');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_noCampo(t, _filtro), isTrue, reason: 'do 1.º grupo: ${textosFocados()}');
    await focar(t, 'Desporto 1');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_naPesquisa(t), isTrue, reason: 'do 1.º canal: ${textosFocados()}');
    // de um grupo que não é o primeiro, ↑ vai ao de cima
    await focar(t, 'Desporto Internacional');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_focado(), 'Desporto');
    // com o filtro, o 1.º grupo encontrado também sobe ao filtro
    await filtrar(t, 'internac');
    await voltar(t);
    await focar(t, 'Desporto Internacional');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_noCampo(t, _filtro), isTrue);
    // com pesquisa, ↑ no 1.º canal encontrado vai à pesquisa
    await escrever(t, 'desp');
    await voltar(t);
    await focar(t, 'Desporto 1');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_naPesquisa(t), isTrue);
    // e ↓ do campo volta à primeira linha da coluna
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(_focado(), 'Desporto 1', reason: textosFocados());
  });

  testWidgets('no ecrã estreito há só a pesquisa de canais, e os grupos vão numa fila de chips', (t) async {
    await abrir(t, largura: 400, altura: 800);
    expect(_filtro, findsNothing);
    expect(_pesquisa, findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Desporto'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Desporto Internacional'), findsOneWidget);
    await escrever(t, 'desp');
    expect(find.text('Canais · 31'), findsOneWidget);
    // os chips continuam (a pesquisa é só dos canais) e ficam por cima dos canais
    expect(find.widgetWithText(ChoiceChip, 'Desporto Internacional'), findsOneWidget);
    expect(t.getRect(find.widgetWithText(ChoiceChip, 'Desporto')).bottom,
        lessThanOrEqualTo(t.getRect(find.text('Canais · 31')).top));
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
    await escrever(t, 'desp');
    expect(find.text('Canais · 10000'), findsOneWidget);
    // continua virtualizada: só se constroem as linhas à vista
    final lista = t.widget<ListView>(_canais);
    expect(lista.itemExtent, isNotNull);
    expect(find.descendant(of: _canais, matching: find.byType(ListTile)).evaluate().length, lessThan(40));
    // filtrar os 5000 grupos: só os encontrados («Filmes 12», «Filmes 12N», «Filmes 12NN»)
    await filtrar(t, 'filmes 12');
    expect(find.descendant(of: _grupos, matching: find.text('Filmes 12')), findsOneWidget);
    expect(find.descendant(of: _grupos, matching: find.text('Filmes 0')), findsNothing);
    expect(find.descendant(of: _grupos, matching: find.text('Desporto')), findsNothing);
    // cada rebuild com filtro e pesquisa (aqui, pôr/tirar favoritos) não volta a normalizar os 5000 grupos
    for (var k = 0; k < 5; k++) {
      await t.tap(find.byTooltip(k.isEven ? 'Pôr nos favoritos' : 'Tirar dos favoritos').first);
      await t.pump();
    }
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
