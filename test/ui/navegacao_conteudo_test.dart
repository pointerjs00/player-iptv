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

  testWidgets('D-pad: OK mantido no grupo esconde-o; "Mostrar grupos escondidos" e voltar a mostrar',
      (t) async {
    final l = await preparar(t);
    await mostrar(t, l);
    expect(_focado(), 'Portugal');
    await _okMantido(t);
    expect(find.text('Esconder o grupo'), findsOneWidget);
    expect(_focado(), 'Esconder o grupo');
    await _tecla(t, LogicalKeyboardKey.select);
    expect(grupo('Portugal'), findsNothing);
    expect(l.gruposEscondidos, {'Portugal'});
    // (a gravação no disco está nos testes da Biblioteca: aqui o IO real não acaba no relógio falso)
    // o grupo escolhido passou para o primeiro visível, com o foco
    expect(find.text('Desporto · 2 canais'), findsOneWidget);
    expect(_focado(), isNotNull);

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

  testWidgets('D-pad: as opções do topo chegam-se com as setas e ordenam A–Z (persistente)', (t) async {
    final l = await preparar(t);
    await mostrar(t, l);
    expect(_nomesCanais(t), ['SIC', 'RTP 1']);
    // do grupo, CIMA leva ao filtro e depois ao topo; DIREITA até às opções
    for (var i = 0; i < 6 && FocusManager.instance.primaryFocus?.context?.widget is! IconButton; i++) {
      await _tecla(t, LogicalKeyboardKey.arrowUp);
    }
    for (var i = 0; i < 4; i++) {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx?.findAncestorWidgetOfExactType<Tooltip>()?.message == 'Opções dos canais') break;
      await _tecla(t, LogicalKeyboardKey.arrowRight);
    }
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Tooltip>()?.message,
        'Opções dos canais');
    await _tecla(t, LogicalKeyboardKey.select);
    for (var i = 0; i < 5 && _focado() != 'Ordenar A–Z'; i++) {
      await _tecla(t, LogicalKeyboardKey.arrowDown);
    }
    expect(_focado(), 'Ordenar A–Z');
    await _tecla(t, LogicalKeyboardKey.select);
    expect(_nomesCanais(t), ['RTP 1', 'SIC']);
    expect(l.ordemCanais, OrdemCanais.az);

    // outra vez o ecrã: continua A–Z
    await mostrar(t, bib.listas.single);
    expect(_nomesCanais(t), ['RTP 1', 'SIC']);
  });

  testWidgets('a pesquisa não mostra canais de grupos escondidos (só com "Mostrar grupos escondidos")', (t) async {
    final l = await preparar(t);
    await t.runAsync(() => bib.esconderGrupo(l.id, 'UK', true));
    await mostrar(t, l);
    await t.tap(find.byKey(const Key('pesquisa-canais')));
    await t.pump();
    await t.enterText(find.byKey(const Key('pesquisa-canais')), 'bbc');
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('0 canais encontrados'), findsOneWidget);
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
    expect(find.text('$grupoVistos · 2 canais'), findsOneWidget);
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
    expect(find.text('Desporto · 2 canais'), findsOneWidget);
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
}
