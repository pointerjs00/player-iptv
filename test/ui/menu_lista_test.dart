import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/protocolo.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

/// Task 8: o menu de ações dos cartões do Player.

Widget _app(Widget w) =>
    MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

void _tamanho(WidgetTester t, double l, double a) {
  t.view.physicalSize = Size(l, a);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

String _focado() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return '';
  final textos = <String>[];
  void visitar(Element e) {
    if (e.widget is Text) textos.add((e.widget as Text).data ?? '');
    e.visitChildren(visitar);
  }

  (ctx as Element).visitChildren(visitar);
  if (textos.isEmpty) textos.add(ctx.findAncestorWidgetOfExactType<Tooltip>()?.message ?? '');
  return textos.join(' | ');
}

const _acoes = ['Abrir', 'Atualizar canais', 'Editar', 'Copiar link', 'Enviar para o Gestor', 'Remover lista'];

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;
  final pedidos = <Conta>[];

  Future<ConteudoLista> abrirFalso(Conta c, {Cancelamento? cancelamento, Aviso? aviso}) async {
    pedidos.add(c);
    return ConteudoLista(['G'], const [Canal(id: '1', nome: 'Canal novo', grupo: 'G', url: 'u')]);
  }

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('menu');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(Directory('${pasta.path}${Platform.pathSeparator}g'));
    pedidos.clear();
  });
  tearDown(() async {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Future<void> montar(WidgetTester t) async {
    _tamanho(t, 1200, 800);
    await t.runAsync(() => bib.adicionar([
          Importada(Conta('', Tipo.xtream, 'http://srv.com:8080', utilizador: 'joao', password: 'segredo'),
              UltimaVerificacao(estado: 'funciona', data: DateTime.now(), validade: '2027-10-16')),
          Importada(contaDeLinha('http://b.com/l.m3u')!),
        ]));
    await t.pumpWidget(_app(TelaInicio(
        biblioteca: bib, area: area, abrirLista: abrirFalso)));
    await t.pump();
  }

  /// IO real (disco) com pumps pelo meio, até `feito` (ou ~2 s).
  Future<void> esperar(WidgetTester t, bool Function() feito) async {
    for (var i = 0; i < 40 && !feito(); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50)); // as animações também andam
    }
  }

  void verMenu() {
    for (final a in _acoes) {
      expect(find.widgetWithText(ListTile, a), findsOneWidget, reason: a);
    }
    expect(find.text('Verificar de novo'), findsNothing);
  }

  Future<void> fecharMenu(WidgetTester t) async {
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Abrir'), findsNothing);
  }

  testWidgets('toque longo e clique direito abrem o mesmo menu (sem "Verificar de novo" nem "Mais opções")',
      (t) async {
    await montar(t);
    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    verMenu();
    await fecharMenu(t);
    await t.tap(find.text('001SRV 161027'), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await t.pumpAndSettle();
    verMenu();
    await fecharMenu(t);
    expect(find.byTooltip('Mais opções'), findsNothing);
  });

  testWidgets('OK mantido no cartão abre o menu; setas escolhem; Voltar devolve o foco ao cartão', (t) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await montar(t);
    expect(_focado(), contains('001SRV'));
    await t.sendKeyDownEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 50));
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    }
    await t.pumpAndSettle();
    verMenu();
    expect(_focado(), 'Abrir', reason: 'o foco começa na 1.ª ação');
    // as repetições e o soltar do OK que abriu o menu não escolhem nada
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await t.sendKeyUpEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    verMenu();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(_focado(), 'Atualizar canais');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(_focado(), contains('001SRV'));
    // um OK curto continua a abrir a lista
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(TelaConteudo), findsOneWidget);
  });

  testWidgets('Abrir e Atualizar canais abrem a lista (Atualizar pede os canais ao servidor)', (t) async {
    await montar(t);
    await t.runAsync(() => bib.guardarCanais(bib.listas.first.id,
        ConteudoLista(['G'], const [Canal(id: '1', nome: 'Canal da cache', grupo: 'G', url: 'u')])));
    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Abrir'));
    await t.pump();
    await esperar(t, () => find.text('Canal da cache').evaluate().isNotEmpty);
    expect(find.text('Canal da cache'), findsOneWidget);
    expect(pedidos, isEmpty, reason: 'com cache, abrir não pede ao servidor');
    await t.binding.handlePopRoute();
    await t.pump();
    await t.pump(const Duration(seconds: 1));

    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Atualizar canais'));
    await t.pump();
    await esperar(t, () => find.text('Canal novo').evaluate().isNotEmpty);
    expect(pedidos, hasLength(1));
    expect(find.text('Canal novo'), findsOneWidget);
  });

  testWidgets('Editar: nome próprio e password mudam e persistem; endereço inválido não guarda', (t) async {
    await montar(t);
    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Editar'));
    await t.pumpAndSettle();
    expect(find.text('Editar lista'), findsOneWidget);
    // a password não se vê
    expect(
        t.widget<EditableText>(find.descendant(
            of: find.byKey(const Key('editar-password')), matching: find.byType(EditableText))).obscureText,
        isTrue);

    Future<void> escrever(String campo, String texto) async {
      final f = find.byKey(Key('editar-$campo'));
      await t.tap(f);
      await t.pump();
      await t.enterText(find.descendant(of: f, matching: find.byType(EditableText)), texto);
    }

    await escrever('endereco', 'srv.com');
    await t.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await t.pumpAndSettle();
    expect(find.textContaining('http://'), findsWidgets, reason: 'erro do endereço');
    expect(bib.listas.first.conta.endereco, 'http://srv.com:8080');

    await escrever('endereco', 'http://srv.com:8080');
    await escrever('nome', 'Sala');
    await escrever('password', 'nova');
    await t.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await t.pump();
    await esperar(t, () => find.text('Editar lista').evaluate().isEmpty);
    await t.pumpAndSettle();
    expect(find.text('Editar lista'), findsNothing);
    expect(find.text('Sala'), findsOneWidget);
    expect(bib.listas.first.conta.password, 'nova');
    final relida = await t.runAsync(() => Biblioteca.abrir(pasta));
    expect(relida!.listas.first.nome, 'Sala');
    expect(relida.listas.first.conta.password, 'nova');
  });

  testWidgets('Copiar link: vai para a área de transferência sem aparecer no ecrã', (t) async {
    String? copiado;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'Clipboard.setData') copiado = (c.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await montar(t);
    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Copiar link'));
    await t.pumpAndSettle();
    expect(copiado, startsWith('http://srv.com:8080/get.php?username=joao&password=segredo'));
    expect(find.text('Link copiado'), findsOneWidget);
    expect(find.textContaining('segredo'), findsNothing);
    expect(find.textContaining('get.php'), findsNothing);
  });

  testWidgets('Enviar para o Gestor: copia a conta e o último resultado, sem duplicar', (t) async {
    await montar(t);
    for (var vez = 0; vez < 2; vez++) {
      await t.longPress(find.text('001SRV 161027'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ListTile, 'Enviar para o Gestor'));
      await t.pump();
      final aviso = find.text(vez == 0 ? 'Enviada para o Gestor' : 'Já estava no Gestor');
      await esperar(t, () => aviso.evaluate().isNotEmpty);
      expect(aviso, findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      await t.pumpAndSettle();
    }
    expect(area.listas, hasLength(1));
    expect(area.listas.single.conta.utilizador, 'joao');
    expect(area.listas.single.ultima!.estado, 'funciona');
  });

  testWidgets('Remover lista pede confirmação; Cancelar não apaga; Remover apaga e o foco fica num cartão',
      (t) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await montar(t);
    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Remover lista'));
    await t.pumpAndSettle();
    expect(find.text('Remover lista?'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(bib.listas, hasLength(2));

    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Remover lista'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Remover'));
    await t.pump();
    await esperar(t, () => find.text('001SRV 161027').evaluate().isEmpty);
    await t.pumpAndSettle();
    expect(bib.listas, hasLength(1));
    expect(find.text('001SRV 161027'), findsNothing);
    expect(_focado(), contains('002B'));
  });
}
