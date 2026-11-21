import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/principal/barra_seccoes.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';

import 'ajuda_dpad.dart';

/// A casca: três secções fixas (Ver TV, Gestor, Definições) que guardam o estado.

void _tamanho(WidgetTester t, double l, double a) {
  t.view.physicalSize = Size(l, a);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Uma secção com um campo (o texto escrito é estado da secção).
class _ComCampo extends StatelessWidget {
  const _ComCampo(this.nome);
  final String nome;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Text('ECRÃ $nome'),
          TextField(key: Key('campo-$nome')),
        ]),
      );
}

Widget _casca({Seccao inicial = Seccao.verTv, VoidCallback? sair, Widget? verTv}) => TelaPrincipal(
      verTv: verTv ?? const _ComCampo('VER TV'),
      gestor: const _ComCampo('GESTOR'),
      definicoes: const _ComCampo('DEFINIÇÕES'),
      inicial: inicial,
      sair: sair ?? () {},
    );

void main() {
  testWidgets('largura 1280: barra lateral com as 3 secções', (t) async {
    _tamanho(t, 1280, 800);
    await t.pumpWidget(appTeste(_casca()));
    await t.pump();
    final barra = find.byType(BarraSeccoes);
    expect(barra, findsOneWidget);
    expect(t.getSize(barra).width, 220);
    for (final r in ['Ver TV', 'Gestor', 'Definições']) {
      expect(find.descendant(of: barra, matching: find.text(r)), findsOneWidget, reason: r);
    }
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('ECRÃ VER TV'), findsOneWidget);
    expect(find.text('ECRÃ GESTOR'), findsNothing, reason: 'só a secção ativa está à vista');
  });

  testWidgets('largura 400: NavigationBar em baixo', (t) async {
    _tamanho(t, 400, 800);
    await t.pumpWidget(appTeste(_casca()));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byType(BarraSeccoes), findsNothing);
    final nav = find.byType(NavigationBar);
    expect(nav, findsOneWidget);
    expect(t.getRect(nav).bottom, 800, reason: 'colada ao fundo do ecrã');
    for (final r in ['Ver TV', 'Gestor', 'Definições']) {
      expect(find.descendant(of: nav, matching: find.text(r)), findsOneWidget, reason: r);
    }
    await t.tap(find.descendant(of: nav, matching: find.text('Definições')));
    await t.pumpAndSettle();
    expect(find.text('ECRÃ DEFINIÇÕES').hitTestable(), findsOneWidget);
  });

  testWidgets('largura 800 (tablet ao alto): NavigationBar em baixo, sem barra lateral', (t) async {
    _tamanho(t, 800, 1000);
    await t.pumpWidget(appTeste(_casca()));
    await t.pump();
    expect(find.byType(BarraSeccoes), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('largura 960 (Android TV): barra lateral', (t) async {
    ecraTvTeste(t);
    await t.pumpWidget(appTeste(_casca()));
    await t.pump();
    expect(find.byType(BarraSeccoes), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('trocar de secção guarda o estado', (t) async {
    _tamanho(t, 1280, 800);
    await t.pumpWidget(appTeste(_casca(inicial: Seccao.gestor)));
    await t.pump();
    expect(find.text('ECRÃ GESTOR'), findsOneWidget);
    await t.enterText(find.byKey(const Key('campo-GESTOR')), 'escrito no Gestor');
    await t.pump();
    final barra = find.byType(BarraSeccoes);
    await t.tap(find.descendant(of: barra, matching: find.text('Ver TV')));
    await t.pumpAndSettle();
    expect(find.text('ECRÃ VER TV').hitTestable(), findsOneWidget);
    expect(find.text('escrito no Gestor'), findsNothing, reason: 'o Gestor está escondido');
    await t.tap(find.descendant(of: barra, matching: find.text('Gestor')));
    await t.pumpAndSettle();
    expect(find.text('escrito no Gestor'), findsOneWidget, reason: 'o texto continua');
  });

  testWidgets('irPara muda de secção a partir do conteúdo', (t) async {
    _tamanho(t, 1280, 800);
    final botao = Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: FilledButton(onPressed: () => TelaPrincipal.irPara(c, Seccao.definicoes), child: const Text('Ir')),
        ),
      ),
    );
    await t.pumpWidget(appTeste(_casca(verTv: botao)));
    await t.pump();
    await t.tap(find.text('Ir'));
    await t.pumpAndSettle();
    expect(find.text('ECRÃ DEFINIÇÕES').hitTestable(), findsOneWidget);
  });

  testWidgets('Voltar em Gestor vai para Ver TV', (t) async {
    _tamanho(t, 1280, 800);
    var saidas = 0;
    await t.pumpWidget(appTeste(_casca(inicial: Seccao.gestor, sair: () => saidas++)));
    await t.pump();
    expect(find.text('ECRÃ GESTOR').hitTestable(), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('ECRÃ VER TV').hitTestable(), findsOneWidget);
    expect(find.text('Carregue outra vez em Voltar para sair'), findsNothing);
    expect(saidas, 0);
  });

  testWidgets('duplo Voltar em Ver TV chama sair', (t) async {
    _tamanho(t, 1280, 800);
    var saidas = 0;
    await t.pumpWidget(appTeste(_casca(sair: () => saidas++)));
    await t.pump();
    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.text('Carregue outra vez em Voltar para sair'), findsOneWidget);
    expect(saidas, 0);
    await t.pump(const Duration(milliseconds: 500));
    await t.binding.handlePopRoute();
    await t.pump();
    expect(saidas, 1);
  });

  group('D-pad', () {
    late Directory pasta;
    late Biblioteca bib;

    setUp(() async {
      pasta = Directory.systemTemp.createTempSync('principal');
      bib = await Biblioteca.abrir(pasta);
    });
    tearDown(() {
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });

    testWidgets('D-pad: ESQUERDA no conteúdo chega à barra; DIREITA volta ao conteúdo', (t) async {
      ecraTvTeste(t);
      await t.runAsync(() => bib.adicionar([
            Importada(contaDeLinha('http://a.com/l.m3u')!),
            Importada(contaDeLinha('http://b.com/l.m3u')!),
          ]));
      await t.pumpWidget(appTeste(_casca(verTv: TelaInicio(biblioteca: bib))));
      await t.pump();
      await t.pump();
      expect(textosFocados(), contains('001A'));
      // do 2.º cartão, ESQUERDA vai ao 1.º (e não à barra)
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
      expect(textosFocados(), contains('002B'));
      await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
      expect(textosFocados(), contains('001A'));
      // do 1.º cartão, ESQUERDA chega à secção ativa na barra
      await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
      expect(textosFocados(), 'Ver TV');
      // na barra, ESQUERDA não sai dela
      await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
      expect(textosFocados(), 'Ver TV');
      // DIREITA volta ao controlo onde se estava
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
      expect(textosFocados(), contains('001A'));
      // CIMA no topo do conteúdo também chega à barra
      for (var i = 0; i < 6 && textosFocados() != 'Ver TV'; i++) {
        await teclaDpad(t, LogicalKeyboardKey.arrowUp);
      }
      expect(textosFocados(), 'Ver TV');
      // BAIXO na barra anda entre as secções e pára na última
      final descer = <String>[];
      for (var i = 0; i < 3; i++) {
        await teclaDpad(t, LogicalKeyboardKey.arrowDown);
        descer.add(textosFocados());
      }
      expect(descer, ['Gestor', 'Definições', 'Definições']);
      await teclaDpad(t, LogicalKeyboardKey.arrowUp);
      expect(textosFocados(), 'Gestor');
      // OK mostra o Gestor e o foco fica na barra; DIREITA entra no conteúdo dele
      await teclaDpad(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.text('ECRÃ GESTOR').hitTestable(), findsOneWidget);
      expect(textosFocados(), 'Gestor');
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
      final campo = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>();
      expect(campo?.key, const Key('campo-GESTOR'), reason: 'o campo do Gestor; foco em: ${textosFocados()}');
      // Voltar no Gestor: Ver TV, com o foco onde estava (a pesquisa, de onde CIMA foi à barra)
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('ECRÃ GESTOR').hitTestable(), findsNothing);
      final pesquisa = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>();
      expect(pesquisa?.decoration?.hintText, 'Pesquisar listas', reason: 'foco em: ${textosFocados()}');
    });
  });
}
