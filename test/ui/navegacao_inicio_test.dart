import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

Widget _app(Widget w) =>
    MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

final _conteudo = ConteudoLista(['Portugal', 'Desporto'], const [
  Canal(id: '1', nome: 'RTP 1', grupo: 'Portugal'),
  Canal(id: '2', nome: 'SIC', grupo: 'Portugal'),
  Canal(id: '3', nome: 'Sport TV 1', grupo: 'Desporto'),
]);

/// Ver TV dentro da casca (o Voltar e a confirmação da saída são da casca).
Widget _casca(Biblioteca bib, VoidCallback sair) => TelaPrincipal(
    verTv: TelaInicio(biblioteca: bib), gestor: const SizedBox(), definicoes: const SizedBox(), sair: sair);

void main() {
  late Directory pasta;
  late Biblioteca bib;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('nav-inicio');
    bib = await Biblioteca.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  void tamanho(WidgetTester t) {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
  }

  Future<Lista> preparar(WidgetTester t, {bool visto = true}) async {
    tamanho(t);
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!), Importada(contaDeLinha('http://y.com/l.m3u')!)]);
      final l = bib.listas.last;
      await bib.guardarCanais(l.id, _conteudo);
      if (visto) await bib.registarVisto(l.id, _conteudo.canais[2]);
    });
    return bib.listas.last;
  }

  group('Continuar a ver', () {
    testWidgets('no topo do Player, com o canal e a lista; o foco começa nele e OK abre o player nesse canal',
        (t) async {
      final l = await preparar(t);
      (List<Canal>, int)? aberto;
      await t.pumpWidget(_app(TelaInicio(biblioteca: bib, abrirCanal: (c, i) {
        aberto = (c, i);
        return null;
      })));
      await t.pumpAndSettle();
      final cartao = find.byKey(const Key('continuar-a-ver'));
      expect(cartao, findsOneWidget);
      expect(find.descendant(of: cartao, matching: find.text('Continuar a ver')), findsOneWidget);
      expect(find.descendant(of: cartao, matching: find.text('Sport TV 1')), findsOneWidget);
      expect(find.descendant(of: cartao, matching: find.textContaining(l.nomeMostrado)), findsOneWidget);
      final focado = FocusManager.instance.primaryFocus!.context!;
      expect(find.descendant(of: cartao, matching: find.byWidget(focado.widget)), findsOneWidget,
          reason: 'o "Continuar a ver" tem o foco inicial');

      // a cache é lida do disco: IO real
      await t.runAsync(() async {
        await t.sendKeyEvent(LogicalKeyboardKey.select);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pumpAndSettle();
      expect(find.byType(TelaConteudo), findsOneWidget);
      expect(aberto, isNotNull);
      expect(aberto!.$1[aberto!.$2].id, '3');
    });

    testWidgets('sem nada visto (ou com a lista apagada) não aparece', (t) async {
      await preparar(t, visto: false);
      await t.pumpWidget(_app(TelaInicio(biblioteca: bib)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('continuar-a-ver')), findsNothing);
    });

    testWidgets('aparece logo que se vê um canal (a biblioteca avisa)', (t) async {
      final l = await preparar(t, visto: false);
      await t.pumpWidget(_app(TelaInicio(biblioteca: bib)));
      await t.pumpAndSettle();
      await t.runAsync(() => bib.registarVisto(l.id, _conteudo.canais.first));
      await t.pumpAndSettle();
      expect(find.text('RTP 1'), findsOneWidget);
    });
  });

  group('confirmar a saída', () {
    testWidgets('Voltar em Ver TV pede "Carregue outra vez em Voltar para sair"; a segunda vez em 2 s sai',
        (t) async {
      tamanho(t);
      var saidas = 0;
      await t.pumpWidget(_app(_casca(bib, () => saidas++)));
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.text('Carregue outra vez em Voltar para sair'), findsOneWidget);
      expect(saidas, 0);
      await t.pump(const Duration(milliseconds: 500));
      await t.binding.handlePopRoute();
      await t.pump();
      expect(saidas, 1);
    });

    testWidgets('passados 2 s volta a pedir', (t) async {
      tamanho(t);
      var saidas = 0;
      await t.pumpWidget(_app(_casca(bib, () => saidas++)));
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 2100));
      await t.binding.handlePopRoute();
      await t.pump();
      expect(saidas, 0);
      expect(find.text('Carregue outra vez em Voltar para sair'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(saidas, 1);
    });

    testWidgets('num ecrã por cima (canais), Voltar só fecha esse ecrã', (t) async {
      final l = await preparar(t, visto: false);
      var saidas = 0;
      await t.pumpWidget(_app(_casca(bib, () => saidas++)));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(find.text(l.nomeMostrado));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pumpAndSettle();
      expect(find.byType(TelaConteudo), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(TelaConteudo), findsNothing);
      expect(find.text('Carregue outra vez em Voltar para sair'), findsNothing);
      expect(saidas, 0);
    });

    testWidgets('no Windows a janela fecha normalmente (sem pedir)', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tamanho(t);
      await t.pumpWidget(_app(_casca(bib, () {})));
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.text('Carregue outra vez em Voltar para sair'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
