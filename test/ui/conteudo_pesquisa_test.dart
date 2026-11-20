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
  Future<Lista> abrir(WidgetTester t,
      {ConteudoLista? conteudo, double largura = 960, double altura = 540, List<String> favoritos = const []}) async {
    ecraTvTeste(t, largura: largura, altura: altura);
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
      await bib.guardarCanais(bib.listas.single.id, conteudo ?? _conteudo);
      for (final f in favoritos) {
        await bib.alternarFavorito(bib.listas.single.id, f);
      }
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

  for (final largura in [1100.0, 1800.0]) {
    testWidgets('a $largura px, «Ordem» e «Grupos escondidos» ficam no canto direito do topo', (t) async {
      await abrir(t, largura: largura, altura: 900);
      final ecra = t.getRect(find.byType(TelaConteudo));
      final ordem = t.getRect(find.ancestor(of: find.textContaining('Ordem:'), matching: find.byType(OutlinedButton)));
      final escondidos =
          t.getRect(find.ancestor(of: find.textContaining('Grupos escondidos:'), matching: find.byType(OutlinedButton)));
      expect(escondidos.left, greaterThan(ordem.right - 1), reason: 'a ordem antes dos escondidos');
      // só o botão de atualizar (≈48) e a margem cabem à direita dos dois
      expect(ecra.right - escondidos.right, lessThan(80), reason: 'encostados à direita, não a meio');
    });
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
    await t.tap(find.descendant(of: _grupos, matching: find.text('Desporto')));
    await t.pumpAndSettle();
    await filtrar(t, 'desp');
    // «Todos os canais» não é filtrada: fica sempre no topo
    expect(_nomes(t, _grupos), ['Todos os canais', 'Desporto', 'Desporto Internacional']);
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
    expect(_nomes(t, _grupos), ['Todos os canais', 'Notícias']);
    expect(find.descendant(of: _canais, matching: find.text('Desporto 1')), findsOneWidget);
  });

  testWidgets('pesquisar canais procura em todos os grupos e não mexe nos grupos', (t) async {
    await abrir(t);
    await escrever(t, 'desp');
    expect(find.text('Canais · 31'), findsOneWidget);
    expect(_nomes(t, _grupos), ['Todos os canais', 'Desporto', 'Desporto Internacional', 'Notícias']);
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
    expect(_nomes(t, _grupos), ['Todos os canais', 'Notícias']);
    // sem grupo escolhido, a pesquisa procura em todos (também fora dos grupos filtrados)
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
    expect(_nomes(t, _grupos), ['Todos os canais', 'Desporto Internacional']);
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
    expect(_nomes(t, _grupos), ['Todos os canais', 'Desporto', 'Desporto Internacional', 'Notícias']);
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

  testWidgets('Voltar com o foco num canal encontrado leva o foco ao 1.º canal do que fica à vista', (t) async {
    await abrir(t);
    await escrever(t, 'desp');
    await voltar(t); // acaba de escrever
    await focar(t, 'Desporto 3');
    await voltar(t); // limpa a pesquisa
    expect(find.text('Canais · 31'), findsNothing);
    // o foco não fica numa linha qualquer (outro canal na mesma posição): vai ao 1.º de «Todos os canais»
    expect(_focado(), 'Desporto 1', reason: textosFocados());
    expect(t.widget<Text>(find.byKey(const Key('contador-canais'))).data, '1 de 33');
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(_focado(), 'Desporto 2');
    expect(t.widget<Text>(find.byKey(const Key('contador-canais'))).data, '2 de 33');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_focado(), 'Desporto 1');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_naPesquisa(t), isTrue);
  });

  testWidgets('Voltar com o foco num canal encontrado lá em baixo não perde o foco', (t) async {
    await abrir(t);
    await escrever(t, 'desp');
    await voltar(t);
    // a 25.ª linha dos resultados (a pesquisa só procura no grupo escolhido: os resultados nunca
    // têm mais linhas do que o que fica à vista depois de limpar)
    await t.scrollUntilVisible(find.text('Desp. Mundo 5'), 300,
        scrollable: find.descendant(of: _canais, matching: find.byType(Scrollable)));
    await focar(t, 'Desp. Mundo 5');
    await voltar(t);
    expect(_focado(), 'Desporto 1', reason: textosFocados());
    expect(t.widget<Text>(find.byKey(const Key('contador-canais'))).data, '1 de 33');
  });

  testWidgets('↑ no primeiro grupo vai ao filtro dos grupos; ↑ no primeiro canal à pesquisa dos canais', (t) async {
    await abrir(t);
    // o foco começa no escolhido: «Todos os canais», a 1.ª linha
    expect(_focado(), 'Todos os canais');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_noCampo(t, _filtro), isTrue, reason: 'da 1.ª linha: ${textosFocados()}');
    await focar(t, 'Desporto 1');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_naPesquisa(t), isTrue, reason: 'do 1.º canal: ${textosFocados()}');
    // de um grupo que não é o primeiro, ↑ vai ao de cima (do 1.º grupo, a «Todos os canais»)
    await focar(t, 'Desporto Internacional');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_focado(), 'Desporto');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_focado(), 'Todos os canais');
    // com o filtro, o 1.º grupo encontrado sobe a «Todos os canais» e daí ao filtro
    await filtrar(t, 'internac');
    await voltar(t);
    await focar(t, 'Desporto Internacional');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(_focado(), 'Todos os canais', reason: textosFocados());
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

  testWidgets('largo → estreito com o filtro ativo: o filtro limpa-se e o Voltar sai logo', (t) async {
    await abrir(t);
    await filtrar(t, 'desp');
    await voltar(t); // acaba de escrever
    expect(t.widget<BarraTeclas>(find.byType(BarraTeclas)).itens, contains(('Voltar', 'limpar')));
    t.view.physicalSize = const Size(400, 800);
    await t.pumpAndSettle();
    expect(_filtro, findsNothing);
    expect(t.widget<BarraTeclas>(find.byType(BarraTeclas)).itens, isNot(contains(('Voltar', 'limpar'))));
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(TelaConteudo), findsNothing);
    expect(find.text('base'), findsOneWidget);
  });

  testWidgets('← nos canais com o grupo escolhido escondido pelo filtro vai ao filtro dos grupos', (t) async {
    await abrir(t);
    await t.tap(find.descendant(of: _grupos, matching: find.text('Desporto')));
    await t.pumpAndSettle();
    await filtrar(t, 'zzz');
    await voltar(t);
    // só fica «Todos os canais» (nunca é filtrada); o grupo escolhido não está à vista
    expect(_nomes(t, _grupos), ['Todos os canais']);
    await focar(t, 'Desporto 1');
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(_noCampo(t, _filtro), isTrue, reason: '${textosFocados()} ${FocusManager.instance.primaryFocus?.debugLabel}');
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
    // 5 alternâncias (pôr, tirar, pôr, tirar, pôr): o mesmo canal fica nos favoritos, e o filtro e a pesquisa mantêm-se
    expect(find.byTooltip('Tirar dos favoritos'), findsOneWidget);
    expect(find.text('Canais · 10000'), findsOneWidget);
    expect(find.descendant(of: _grupos, matching: find.text('Filmes 12')), findsOneWidget);

    // a pesquisa dentro de um grupo (só as posições dele)
    await filtrar(t, 'desporto');
    await t.tap(find.descendant(of: _grupos, matching: find.text('Desporto')));
    await t.pumpAndSettle();
    await escrever(t, 'filme');
    expect(find.text('Desporto · 0'), findsOneWidget, reason: 'os 90 mil «Filme N» são de outros grupos');
    // Desporto 10, 100–190, 1000–1990 e 10000–19990
    await escrever(t, 'desporto 1');
    expect(find.text('Desporto · 1111'), findsOneWidget);
    expect(find.descendant(of: _canais, matching: find.byType(ListTile)).evaluate().length, lessThan(40));
    // e nos favoritos (só «Desporto 0», das alternâncias de cima)
    await filtrar(t, '');
    await t.tap(find.descendant(of: _grupos, matching: find.text(grupoFavoritos)));
    await t.pumpAndSettle();
    await escrever(t, 'desporto');
    expect(find.text('$grupoFavoritos · 1'), findsOneWidget);
    await escrever(t, 'filme');
    expect(find.text('$grupoFavoritos · 0'), findsOneWidget);
  });

  testWidgets('100 mil canais em A–Z: o 1.º frame mostra os canais e, já ordenados, ficam A–Z', (t) async {
    // os nomes ao contrário: na ordem da lista o primeiro é «Canal 99999»
    final grande = ConteudoLista(['G'], [
      for (var i = 0; i < 100000; i++)
        Canal(id: '$i', nome: 'Canal ${(99999 - i).toString().padLeft(5, '0')}', grupo: 'G'),
    ]);
    final l = await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
      await bib.guardarCanais(bib.listas.single.id, grande);
      await bib.definirOrdem(bib.listas.single.id, OrdemCanais.az);
      return bib.listas.single;
    });
    ecraTvTeste(t, largura: 960, altura: 540);
    await t.runAsync(() async {
      await t.pumpWidget(appTeste(TelaConteudo(biblioteca: bib, lista: l!, abrir: (c, i) => null)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump();
    // o primeiro frame com canais já tem a lista (ordenada ou ainda pela ordem original)
    expect(find.descendant(of: _canais, matching: find.byType(ListTile)), findsWidgets);
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await t.pumpAndSettle();
    expect(_nomes(t, _canais).take(3), ['Canal 00000', 'Canal 00001', 'Canal 00002']);
    expect(find.text('A ordenar…'), findsNothing);
    // o grupo também (com as posições já ordenadas)
    await t.tap(find.descendant(of: _grupos, matching: find.text('G')));
    await t.pumpAndSettle();
    expect(_nomes(t, _canais).first, 'Canal 00000');
  });

  /// A dica (hintText) da pesquisa dos canais.
  String? dica(WidgetTester t) =>
      t.widget<TextField>(find.descendant(of: _pesquisa, matching: find.byType(TextField))).decoration?.hintText;

  bool chipEscolhido(WidgetTester t, String texto) => t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, texto)).selected;

  group('a pesquisa procura só no grupo escolhido', () {
    testWidgets('ao abrir, «Todos os canais» está escolhido (com o foco) e a dica é a de todos', (t) async {
      await abrir(t);
      expect(_nomes(t, _grupos).first, 'Todos os canais');
      expect(_focado(), 'Todos os canais', reason: textosFocados());
      final todos = t.widget<ListTile>(find.ancestor(
          of: find.descendant(of: _grupos, matching: find.text('Todos os canais')), matching: find.byType(ListTile)));
      expect(todos.selected, isTrue);
      expect(todos.trailing, isA<Row>());
      expect(find.descendant(of: _grupos, matching: find.text('33')), findsOneWidget, reason: 'o total dos canais');
      expect(dica(t), 'Pesquisar canais ou número');
      // os canais de todos os grupos
      expect(find.descendant(of: _canais, matching: find.text('Desporto 1')), findsOneWidget);
    });

    testWidgets('com «Desporto» escolhido, pesquisar «1» só encontra canais desse grupo', (t) async {
      await abrir(t);
      await t.tap(find.descendant(of: _grupos, matching: find.text('Desporto')));
      await t.pumpAndSettle();
      expect(dica(t), 'Pesquisar em Desporto');
      await escrever(t, '1');
      // Desporto 1 e 10–19 (os «Desp. Mundo 1…» e «Notícias 1» são de outros grupos)
      expect(find.text('Desporto · 11'), findsOneWidget);
      expect(find.text('Canais · 11'), findsNothing);
      expect(find.descendant(of: _canais, matching: find.text('Desp. Mundo 1')), findsNothing);
      expect(find.descendant(of: _canais, matching: find.text('Notícias 1')), findsNothing);
      // o número também, mas só no grupo
      await escrever(t, '401');
      expect(find.text('Desporto · 0'), findsOneWidget);
      await escrever(t, '205');
      expect(find.text('Desporto · 1'), findsOneWidget);
      expect(find.descendant(of: _canais, matching: find.text('Desporto 5')), findsOneWidget);
    });

    testWidgets('escolher «Todos os canais» volta a pesquisar em todos os grupos', (t) async {
      await abrir(t);
      await t.tap(find.descendant(of: _grupos, matching: find.text('Desporto')));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: _grupos, matching: find.text('Todos os canais')));
      await t.pumpAndSettle();
      expect(dica(t), 'Pesquisar canais ou número');
      await escrever(t, '1');
      // Desporto 1, 10–19; Desp. Mundo 1, 10, 11; Notícias 1
      expect(find.text('Canais · 15'), findsOneWidget);
    });

    testWidgets('com Favoritos escolhido, a pesquisa só encontra favoritos', (t) async {
      await abrir(t, favoritos: ['d1', 'd12', 'i1', 'n2']);
      // abre em «Todos os canais», mesmo com favoritos
      expect(_focado(), 'Todos os canais');
      await t.tap(find.descendant(of: _grupos, matching: find.text(grupoFavoritos)));
      await t.pumpAndSettle();
      expect(dica(t), 'Pesquisar em Favoritos');
      await escrever(t, '1');
      expect(find.text('$grupoFavoritos · 3'), findsOneWidget);
      expect(find.descendant(of: _canais, matching: find.text('Desporto 10')), findsNothing);
      expect(find.descendant(of: _canais, matching: find.text('Notícias 1')), findsNothing);
      expect(find.descendant(of: _canais, matching: find.text('Desp. Mundo 1')), findsOneWidget);
      await escrever(t, '402');
      expect(find.text('$grupoFavoritos · 1'), findsOneWidget);
    });

    testWidgets('no ecrã estreito o 1.º chip é «Todos» e tira a escolha do grupo', (t) async {
      await abrir(t, largura: 400, altura: 800);
      final chips = find.byType(ChoiceChip);
      expect(find.descendant(of: chips.first, matching: find.text('Todos')), findsOneWidget);
      expect(chipEscolhido(t, 'Todos'), isTrue);
      await t.tap(find.widgetWithText(ChoiceChip, 'Desporto'));
      await t.pumpAndSettle();
      expect(chipEscolhido(t, 'Todos'), isFalse);
      expect(chipEscolhido(t, 'Desporto'), isTrue);
      await escrever(t, '1');
      expect(find.text('Desporto · 11'), findsOneWidget);
      await t.tap(find.widgetWithText(ChoiceChip, 'Todos'));
      await t.pumpAndSettle();
      expect(chipEscolhido(t, 'Todos'), isTrue);
      await escrever(t, '1');
      expect(find.text('Canais · 15'), findsOneWidget);
    });

    testWidgets('↑ em «Todos os canais» vai ao filtro dos grupos; o filtro não a esconde', (t) async {
      await abrir(t);
      expect(_focado(), 'Todos os canais');
      await teclaDpad(t, LogicalKeyboardKey.arrowUp);
      expect(_noCampo(t, _filtro), isTrue, reason: textosFocados());
      await filtrar(t, 'zzz');
      expect(_nomes(t, _grupos), ['Todos os canais']);
    });

    testWidgets('atualizar a lista sem o grupo escolhido volta a «Todos os canais»', (t) async {
      ecraTvTeste(t, largura: 960, altura: 540);
      await t.runAsync(() async {
        await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
        await bib.guardarCanais(bib.listas.single.id, _conteudo);
      });
      final novo = ConteudoLista(['Desporto'], [
        for (var i = 1; i <= 3; i++) Canal(id: 'd$i', nome: 'Desporto $i', grupo: 'Desporto'),
      ]);
      await t.runAsync(() async {
        await t.pumpWidget(appTeste(TelaConteudo(biblioteca: bib, lista: bib.listas.single, abrir: (c, i) => null,
            abrirLista: (c, {cancelamento, aviso}) async => novo)));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: _grupos, matching: find.text('Notícias')));
      await t.pumpAndSettle();
      expect(dica(t), 'Pesquisar em Notícias');
      await t.tap(find.byTooltip('Atualizar a lista de canais'));
      // a gravação da cache é IO real: pumps pelo meio até o loader fechar
      for (var i = 0; i < 40 && find.text('A atualizar os canais').evaluate().isNotEmpty || i == 0; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pumpAndSettle();
      expect(find.descendant(of: _grupos, matching: find.text('Notícias')), findsNothing);
      expect(dica(t), 'Pesquisar canais ou número');
      // a linha e o cabeçalho
      expect(find.text('Todos os canais'), findsNWidgets(2));
      expect(find.text('1 de 3'), findsOneWidget);
    });

    testWidgets('tirar o último favorito com Favoritos escolhido e pesquisa volta a «Todos os canais»', (t) async {
      await abrir(t, favoritos: ['d1']);
      await t.tap(find.descendant(of: _grupos, matching: find.text(grupoFavoritos)));
      await t.pumpAndSettle();
      await escrever(t, 'desporto');
      expect(find.text('$grupoFavoritos · 1'), findsOneWidget);
      await t.tap(find.byTooltip('Tirar dos favoritos'));
      await t.pumpAndSettle();
      expect(find.descendant(of: _grupos, matching: find.text(grupoFavoritos)), findsNothing);
      expect(dica(t), 'Pesquisar canais ou número');
      // a pesquisa fica, agora em todos
      expect(find.text('Canais · 20'), findsOneWidget);
    });
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
