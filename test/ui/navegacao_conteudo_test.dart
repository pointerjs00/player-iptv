import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

import 'ajuda_dpad.dart' show textosFocados;

Widget _app(Widget w) =>
    MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

final _conteudo = ConteudoLista(['Portugal', 'Desporto', 'UK'], const [
  Canal(id: '1', nome: 'SIC', grupo: 'Portugal'),
  Canal(id: '2', nome: 'RTP 1', grupo: 'Portugal'),
  Canal(id: '3', nome: 'Sport TV 1', grupo: 'Desporto'),
  Canal(id: '4', nome: 'BBC One', grupo: 'UK'),
  Canal(id: '5', nome: 'Eleven', grupo: 'Desporto'),
]);

/// O texto do ListTile com o foco.
String? _focado() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  final tile = ctx?.findAncestorWidgetOfExactType<ListTile>() ??
      (ctx?.widget is ListTile ? ctx!.widget as ListTile : null);
  final t = tile?.title;
  return t is Text ? t.data : null;
}

Future<void> _tecla(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pumpAndSettle();
}

/// OK mantido no comando (abre o menu do grupo).
Future<void> _okMantido(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.select);
  await t.pump(duracaoOkMantido + const Duration(milliseconds: 50));
  await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
  await t.sendKeyUpEvent(LogicalKeyboardKey.select);
  await t.pumpAndSettle();
}

List<String> _nomesCanais(WidgetTester t) => [
      for (final e in find.descendant(of: find.byKey(const Key('lista-canais')), matching: find.byType(ListTile))
          .evaluate())
        ((e.widget as ListTile).title as Text).data!,
    ];

void main() {
  late Directory pasta;
  late Biblioteca bib;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('nav-ui');
    bib = await Biblioteca.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Future<Lista> preparar(WidgetTester t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
      await bib.guardarCanais(bib.listas.single.id, _conteudo);
    });
    return bib.listas.single;
  }

  Future<void> mostrar(WidgetTester t, Lista l,
      {FutureOr<int?> Function(List<Canal>, int)? abrir, String? continuar}) async {
    await t.runAsync(() async {
      await t.pumpWidget(_app(TelaConteudo(biblioteca: bib, lista: l, abrir: abrir, continuar: continuar)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpAndSettle();
  }

  Finder grupo(String g) => find.descendant(of: find.byKey(const Key('lista-grupos')), matching: find.text(g));

  testWidgets('escolher outro grupo mostra os canais dele a partir do primeiro', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
      await bib.guardarCanais(
          bib.listas.single.id,
          ConteudoLista(['Muitos', 'Outros'], [
            for (var i = 0; i < 80; i++) Canal(id: 'm$i', nome: 'Muitos $i', grupo: 'Muitos'),
            for (var i = 0; i < 80; i++) Canal(id: 'o$i', nome: 'Outro $i', grupo: 'Outros'),
          ]));
    });
    await mostrar(t, bib.listas.single);
    await t.tap(grupo('Muitos'));
    await t.pumpAndSettle();
    // desce até ao fim dos canais do grupo
    await t.drag(find.byKey(const Key('lista-canais')), const Offset(0, -6000));
    await t.pumpAndSettle();
    expect(find.text('Muitos 0'), findsNothing);
    await t.tap(grupo('Outros'));
    await t.pumpAndSettle();
    expect(_nomesCanais(t).first, 'Outro 0');
    expect(find.text('Outro 0').hitTestable(), findsOneWidget, reason: 'à vista, no topo');
  });

  testWidgets('esconder o grupo aberto (com a lista a meio) volta a «Todos os canais» no topo', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
      await bib.guardarCanais(
          bib.listas.single.id,
          ConteudoLista(['Primeiro', 'Muitos', 'Outros'], [
            const Canal(id: 'p', nome: 'O primeiro', grupo: 'Primeiro'),
            for (var i = 0; i < 80; i++) Canal(id: 'm$i', nome: 'Muitos $i', grupo: 'Muitos'),
            for (var i = 0; i < 80; i++) Canal(id: 'o$i', nome: 'Outro $i', grupo: 'Outros'),
          ]));
    });
    await mostrar(t, bib.listas.single);
    await t.tap(grupo('Muitos'));
    await t.pumpAndSettle();
    await t.drag(find.byKey(const Key('lista-canais')), const Offset(0, -2000));
    await t.pumpAndSettle();
    await t.longPress(grupo('Muitos'));
    await t.pumpAndSettle();
    await t.tap(find.text('Esconder o grupo'));
    await t.pumpAndSettle();
    expect(_nomesCanais(t).first, 'O primeiro');
    expect(find.text('O primeiro').hitTestable(), findsOneWidget, reason: 'no topo');
  });

  testWidgets('→ num grupo vai sempre ao primeiro canal (mesmo com a lista a meio)', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
      await bib.guardarCanais(
          bib.listas.single.id,
          ConteudoLista(['G1', 'G2', 'G3', 'G4', 'G5', 'G6', 'Muitos'], [
            for (var g = 1; g <= 6; g++) Canal(id: 'g$g', nome: 'Canal G$g', grupo: 'G$g'),
            for (var i = 0; i < 80; i++) Canal(id: 'm$i', nome: 'Muitos $i', grupo: 'Muitos'),
          ]));
    });
    await mostrar(t, bib.listas.single);
    await t.tap(grupo('Muitos'));
    await t.pumpAndSettle();
    // os canais a meio da lista e o foco no grupo (que está mais abaixo do que o 1.º canal)
    await t.drag(find.byKey(const Key('lista-canais')), const Offset(0, -2000));
    await t.pumpAndSettle();
    Focus.of(t.element(grupo('Muitos'))).requestFocus();
    await t.pump();
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    expect(_focado(), 'Muitos 0');
    expect(find.text('Muitos 0').hitTestable(), findsOneWidget);
  });

  testWidgets('D-pad: OK mantido no grupo esconde-o; "Mostrar grupos escondidos" e voltar a mostrar',
      (t) async {
    final l = await preparar(t);
    await mostrar(t, l);
    // abre em «Todos os canais»: BAIXO vai a Portugal e OK escolhe-o
    expect(_focado(), 'Todos os canais');
    await _tecla(t, LogicalKeyboardKey.arrowDown);
    expect(_focado(), 'Portugal');
    await _tecla(t, LogicalKeyboardKey.select);
    expect(_nomesCanais(t), ['SIC', 'RTP 1']);
    await _okMantido(t);
    expect(find.text('Esconder o grupo'), findsOneWidget);
    expect(_focado(), 'Esconder o grupo');
    await _tecla(t, LogicalKeyboardKey.select);
    expect(grupo('Portugal'), findsNothing);
    expect(l.gruposEscondidos, {'Portugal'});
    expect(find.text('Grupo "Portugal" escondido'), findsOneWidget);
    // Desfazer repõe o grupo
    await t.tap(find.text('Desfazer'));
    await t.pumpAndSettle();
    expect(l.gruposEscondidos, isEmpty);
    expect(grupo('Portugal'), findsOneWidget);
    // (outra vez, para o resto do teste)
    await t.longPress(grupo('Portugal'));
    await t.pumpAndSettle();
    await t.tap(find.text('Esconder o grupo'));
    await t.pumpAndSettle();
    expect(l.gruposEscondidos, {'Portugal'});
    // (a gravação no disco está nos testes da Biblioteca: aqui o IO real não acaba no relógio falso)
    // o grupo escolhido desapareceu: fica «Todos os canais» (sem os 2 de Portugal), com o foco
    expect(find.text('1 de 3'), findsOneWidget);
    expect(_focado(), 'Todos os canais');

    // as opções no topo (ao alcance das setas): mostrar os escondidos
    await t.tap(find.byTooltip('Opções dos canais'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mostrar grupos escondidos (1)'));
    await t.pumpAndSettle();
    expect(grupo('Portugal'), findsOneWidget);
    expect(find.byKey(const Key('grupo-escondido')), findsOneWidget);

    // no ecrã tátil, o toque longo abre o mesmo menu
    await t.longPress(grupo('Portugal'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mostrar o grupo'));
    await t.pumpAndSettle();
    expect(l.gruposEscondidos, isEmpty);
  });

  testWidgets('quando o grupo escolhido desaparece, fica «Todos os canais» (esconder, ocultar, último favorito)',
      (t) async {
    final l = await preparar(t);
    await mostrar(t, l);
    final cabecalho = find.descendant(of: find.byType(TelaConteudo), matching: find.text('Todos os canais'));
    // sem grupo, o cabeçalho dos canais diz o mesmo que a linha
    expect(cabecalho, findsNWidgets(2));

    // 1. esconder o grupo escolhido
    await t.tap(grupo('Desporto'));
    await t.pumpAndSettle();
    expect(_nomesCanais(t), ['Sport TV 1', 'Eleven']);
    await t.longPress(grupo('Desporto'));
    await t.pumpAndSettle();
    await t.tap(find.text('Esconder o grupo'));
    await t.pumpAndSettle();
    expect(l.gruposEscondidos, {'Desporto'});
    expect(_nomesCanais(t), ['SIC', 'RTP 1', 'BBC One']);
    expect(_focado(), 'Todos os canais');
    expect(cabecalho, findsNWidgets(2));

    // 2. ocultar os escondidos com um deles escolhido
    await t.tap(find.byTooltip('Opções dos canais'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mostrar grupos escondidos (1)'));
    await t.pumpAndSettle();
    await t.tap(grupo('Desporto'));
    await t.pumpAndSettle();
    expect(_nomesCanais(t), ['Sport TV 1', 'Eleven']);
    await t.tap(find.byTooltip('Opções dos canais'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ocultar grupos escondidos'));
    await t.pumpAndSettle();
    expect(grupo('Desporto'), findsNothing);
    expect(_nomesCanais(t), ['SIC', 'RTP 1', 'BBC One']);
    expect(_focado(), 'Todos os canais');

    // 3. tirar o último favorito com os favoritos escolhidos
    await t.tap(find.byTooltip('Pôr nos favoritos').first);
    await t.pumpAndSettle();
    await t.tap(grupo(grupoFavoritos));
    await t.pumpAndSettle();
    expect(_nomesCanais(t), ['SIC']);
    await t.tap(find.byTooltip('Tirar dos favoritos'));
    await t.pumpAndSettle();
    expect(grupo(grupoFavoritos), findsNothing);
    expect(_nomesCanais(t), ['SIC', 'RTP 1', 'BBC One']);
    expect(_focado(), 'Todos os canais');
  });

  testWidgets('D-pad: as opções do topo chegam-se com as setas e ordenam A–Z (persistente)', (t) async {
    final l = await preparar(t);
    await mostrar(t, l);
    // abre em «Todos os canais», pela ordem da lista
    expect(_nomesCanais(t), ['SIC', 'RTP 1', 'Sport TV 1', 'BBC One', 'Eleven']);
    // de «Todos os canais», CIMA leva ao filtro dos grupos e outra vez ao "‹ Início"
    await _tecla(t, LogicalKeyboardKey.arrowUp);
    await _tecla(t, LogicalKeyboardKey.arrowUp);
    expect(textosFocados(), '‹ Início');
    // as opções (Ordem, Grupos escondidos, Atualizar) estão juntas no canto direito, por cima da
    // coluna dos canais: BAIXO volta ao filtro dos grupos, DIREITA vai à pesquisa dos canais, CIMA
    // chega às opções e ESQUERDA anda até à "Ordem"
    await _tecla(t, LogicalKeyboardKey.arrowDown);
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    await _tecla(t, LogicalKeyboardKey.arrowUp);
    for (var i = 0; i < 4; i++) {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx?.findAncestorWidgetOfExactType<Tooltip>()?.message == 'Opções dos canais') break;
      await _tecla(t, LogicalKeyboardKey.arrowLeft);
    }
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Tooltip>()?.message,
        'Opções dos canais');
    await _tecla(t, LogicalKeyboardKey.select);
    for (var i = 0; i < 5 && _focado() != 'Ordenar A–Z'; i++) {
      await _tecla(t, LogicalKeyboardKey.arrowDown);
    }
    expect(_focado(), 'Ordenar A–Z');
    await _tecla(t, LogicalKeyboardKey.select);
    expect(_nomesCanais(t), ['BBC One', 'Eleven', 'RTP 1', 'SIC', 'Sport TV 1']);
    expect(l.ordemCanais, OrdemCanais.az);

    // outra vez o ecrã: continua A–Z
    await mostrar(t, bib.listas.single);
    expect(_nomesCanais(t), ['BBC One', 'Eleven', 'RTP 1', 'SIC', 'Sport TV 1']);
  });

  testWidgets('a pesquisa não mostra canais de grupos escondidos (só com "Mostrar grupos escondidos")', (t) async {
    final l = await preparar(t);
    await t.runAsync(() => bib.esconderGrupo(l.id, 'UK', true));
    await mostrar(t, l);
    // «Todos os canais» também os deixa de fora (e não os conta)
    expect(_nomesCanais(t), ['SIC', 'RTP 1', 'Sport TV 1', 'Eleven']);
    expect(find.descendant(of: find.byKey(const Key('lista-grupos')), matching: find.text('4')), findsOneWidget);
    await t.tap(find.byKey(const Key('pesquisa-canais')));
    await t.pump();
    await t.enterText(find.byKey(const Key('pesquisa-canais')), 'bbc');
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Canais · 0'), findsOneWidget);
  });

  testWidgets('abrir um canal regista-o como "último visto" (e o que tocava ao sair)', (t) async {
    final l = await preparar(t);
    await mostrar(t, l, abrir: (c, i) => 1);
    await t.tap(find.text('SIC'));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(bib.ultimoVisto!.canal, '2', reason: 'saiu do player no RTP 1');
    expect(bib.ultimoVisto!.lista, l.id);
  });

  testWidgets('o grupo "Vistos há pouco" mostra os vistos que ainda existem, o mais recente primeiro', (t) async {
    final l = await preparar(t);
    l.vistos.addAll(['5', 'fantasma', '1']);
    await mostrar(t, l);
    expect(grupo(grupoVistos), findsOneWidget);
    await t.tap(grupo(grupoVistos));
    await t.pumpAndSettle();
    expect(_nomesCanais(t), ['Eleven', 'SIC']);
    expect(find.text('1 de 2'), findsOneWidget);
  });

  testWidgets('sem vistos não há grupo "Vistos há pouco"', (t) async {
    final l = await preparar(t);
    await mostrar(t, l);
    expect(grupo(grupoVistos), findsNothing);
  });

  testWidgets('"Continuar a ver": abre logo o player nesse canal, com a lista do grupo (na ordem escolhida)',
      (t) async {
    final l = await preparar(t);
    await t.runAsync(() => bib.definirOrdem(l.id, OrdemCanais.az));
    (List<Canal>, int)? aberto;
    await mostrar(t, l, continuar: '3', abrir: (c, i) {
      aberto = (c, i);
      return null;
    });
    expect(aberto, isNotNull);
    expect(aberto!.$1.map((c) => c.nome), ['Eleven', 'Sport TV 1']);
    expect(aberto!.$2, 1);
    expect(find.text('1 de 2'), findsOneWidget);
  });

  testWidgets('"Continuar a ver" escolhe o grupo do canal e, ao voltar do player, o canal fica com o foco',
      (t) async {
    final l = await preparar(t);
    await mostrar(t, l, continuar: '5', abrir: (c, i) => i); // volta no mesmo canal
    await t.pumpAndSettle();
    // abriu-se no grupo do canal (Desporto), não em «Todos os canais»
    final desporto = t.widget<ListTile>(find.ancestor(of: grupo('Desporto'), matching: find.byType(ListTile)));
    expect(desporto.selected, isTrue);
    final todos = t.widget<ListTile>(find.ancestor(of: grupo('Todos os canais'), matching: find.byType(ListTile)));
    expect(todos.selected, isFalse);
    expect(_nomesCanais(t), ['Sport TV 1', 'Eleven']);
    expect(_focado(), 'Eleven');
    expect(find.text('2 de 2'), findsOneWidget);
  });

  testWidgets('"Continuar a ver" com um canal que já não existe avisa', (t) async {
    final l = await preparar(t);
    var abriu = false;
    await mostrar(t, l, continuar: 'nada', abrir: (c, i) {
      abriu = true;
      return null;
    });
    expect(abriu, isFalse);
    expect(find.textContaining('já não está nesta lista'), findsOneWidget);
  });

  group('Lista aberta: um canal por linha', () {
    Future<Lista> comCanais(WidgetTester t, int n) async {
      t.view.physicalSize = const Size(1280, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      await t.runAsync(() async {
        await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
        await bib.guardarCanais(bib.listas.single.id, ConteudoLista(['Geral'], [
          for (var i = 1; i <= n; i++) Canal(id: '$i', nome: 'Canal $i', grupo: 'Geral'),
        ]));
      });
      return bib.listas.single;
    }

    testWidgets('cada canal ocupa uma linha inteira (mesmo dx, dy diferente) e não há painel à direita', (t) async {
      final l = await comCanais(t, 54);
      await mostrar(t, l);
      final a = t.getTopLeft(find.widgetWithText(ListTile, 'Canal 1'));
      final b = t.getTopLeft(find.widgetWithText(ListTile, 'Canal 2'));
      expect(b.dx, a.dx);
      expect(b.dy, greaterThan(a.dy));
      expect(b.dy - a.dy, 56);
      // a linha vai de ponta a ponta da área dos canais
      expect(t.getSize(find.widgetWithText(ListTile, 'Canal 1')).width, greaterThan(700));
    });

    testWidgets('o cabeçalho mostra o grupo e "2 de 54" com o foco no 2.º canal', (t) async {
      final l = await comCanais(t, 54);
      await mostrar(t, l);
      expect(find.text('1 de 54'), findsOneWidget);
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      expect(_focado(), 'Canal 2');
      expect(find.text('2 de 54'), findsOneWidget);
      expect(find.text('Canal 1'), findsOneWidget);
    });

    testWidgets('o topo tem a ordem, os grupos escondidos e o contador de canais', (t) async {
      final l = await comCanais(t, 54);
      await mostrar(t, l);
      expect(find.text('‹ Início'), findsOneWidget);
      expect(find.text('54 canais'), findsOneWidget);
      expect(find.text('Ordem: da lista'), findsOneWidget);
      expect(find.text('Grupos escondidos: 0'), findsOneWidget);
      expect(find.text('Pesquisar canais ou número'), findsOneWidget);
      expect(find.text('Filtrar grupos'), findsOneWidget);
    });

    testWidgets('OK mantido põe nos favoritos, avisa com "Desfazer", e Desfazer repõe', (t) async {
      final l = await comCanais(t, 5);
      await mostrar(t, l);
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      expect(_focado(), 'Canal 2');
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      await t.pump(duracaoOkMantido + const Duration(milliseconds: 50));
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(l.favoritos, {'2'});
      expect(find.text('Canal 2 está nos favoritos'), findsOneWidget);
      expect(find.text('Desfazer'), findsOneWidget);
      await t.tap(find.text('Desfazer'));
      await t.pumpAndSettle();
      expect(l.favoritos, isEmpty);
    });

    testWidgets('0–9: escrever o número leva o foco ao canal', (t) async {
      final l = await comCanais(t, 54);
      await mostrar(t, l);
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      await t.sendKeyEvent(LogicalKeyboardKey.digit3);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.digit7);
      await t.pumpAndSettle();
      expect(_focado(), 'Canal 37');
      expect(find.text('37 de 54'), findsOneWidget);
    });

    testWidgets('escrever um número na pesquisa encontra o canal com esse número', (t) async {
      final l = await comCanais(t, 54);
      await mostrar(t, l);
      await t.tap(find.byKey(const Key('pesquisa-canais')));
      await t.pump();
      await t.enterText(find.byKey(const Key('pesquisa-canais')), '37');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Canais · 1'), findsOneWidget);
    });
  });
}
