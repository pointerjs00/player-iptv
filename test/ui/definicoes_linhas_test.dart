import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/ui/definicoes/tela_definicoes.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/design/escala_interface.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

import 'ajuda_dpad.dart';

/// As Definições são uma lista de linhas simples: título e descrição à esquerda, o controlo à
/// direita (ou por baixo, se não cabe) e um separador fino entre linhas.
void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;
  late Preferencias prefs;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('linhas');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
    prefs = await Preferencias.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  TelaDefinicoes definicoes({bool android = false}) =>
      TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs, android: android);

  /// A casca a 80 %, como na TV no Compacto.
  Widget casca({bool android = false}) => MaterialApp(
      theme: temaApp(),
      builder: (_, c) => TemaConformeRealce(child: EscalaInterface(escala: escalaCompacto, child: c!)),
      home: TelaPrincipal(
          inicial: Seccao.definicoes,
          verTv: const SizedBox(),
          gestor: const SizedBox(),
          definicoes: definicoes(android: android)));

  testWidgets('sem caixa à volta de cada opção e com separadores entre as linhas', (t) async {
    ecraTvTeste(t);
    await t.pumpWidget(casca());
    await t.pump();
    for (final categoria in ['Imagem e som', 'Verificação', 'Ligação', 'Cópia de segurança', 'Sobre e licenças']) {
      await t.tap(find.text(categoria));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: categoria);
      expect(find.byType(SuperficieVidro), findsNothing, reason: '$categoria: sem caixas');
    }
    await t.tap(find.text('Imagem e som'));
    await t.pumpAndSettle();
    // 5 opções = 4 separadores
    expect(find.byType(Divider), findsNWidgets(4));
  });

  testWidgets('título e descrição à esquerda, o controlo à direita; os chips largos vão para baixo', (t) async {
    ecraTvTeste(t);
    await t.pumpWidget(casca());
    await t.pump();

    final tituloDes = t.getRect(find.text('Desentrelaçamento'));
    final chipsDes = t.getRect(find.widgetWithText(ChoiceChip, 'Automático'));
    expect(chipsDes.left, greaterThan(tituloDes.right), reason: 'os 3 chips cabem à direita do título');
    expect(chipsDes.center.dy, lessThan(t.getRect(find.text('Formato da imagem')).top), reason: 'na linha da opção');

    final tituloVol = t.getRect(find.text('Volume ao abrir'));
    final deslizador = t.getRect(find.byType(DeslizadorTv));
    expect(deslizador.left, greaterThan(tituloVol.right), reason: 'o deslizador à direita');

    final tituloFmt = t.getRect(find.text('Formato da imagem'));
    final chipsFmt = find.byWidgetPredicate((w) => w is ChoiceChip && w.label is Text, description: 'chips do formato');
    final primeiroFmt = t.getRect(find.widgetWithText(ChoiceChip, FormatoImagem.values.first.rotulo));
    expect(primeiroFmt.top, greaterThanOrEqualTo(tituloFmt.bottom), reason: 'os 6 chips por baixo do título');
    expect(primeiroFmt.left, moreOrLessEquals(tituloFmt.left, epsilon: 1), reason: 'alinhados com o título');
    expect(chipsFmt, findsWidgets);
  });

  testWidgets('na TV (960×540, a 80 %) «Imagem e som» mostra pelo menos 5 opções sem scroll', (t) async {
    ecraTvTeste(t);
    await t.pumpWidget(casca());
    await t.pump();
    expect(t.takeException(), isNull);
    final titulos = [
      'Tamanho da interface',
      'Desentrelaçamento',
      'Descodificação por hardware',
      'Formato da imagem',
      'Volume ao abrir',
    ];
    for (final x in titulos) {
      final r = t.getRect(find.text(x));
      expect(r.top, greaterThanOrEqualTo(0), reason: x);
      expect(r.bottom, lessThanOrEqualTo(540), reason: '$x à vista: $r');
    }
    // a de baixo mostra o controlo todo
    expect(t.getRect(find.byType(DeslizadorTv)).bottom, lessThanOrEqualTo(540));
  });

  testWidgets('com a letra do sistema a 1,5x nada transborda', (t) async {
    ecraTvTeste(t);
    t.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(casca(android: true));
    await t.pump();
    for (final categoria in ['Imagem e som', 'Verificação', 'Ligação', 'Cópia de segurança', 'Sobre e licenças']) {
      await t.tap(find.text(categoria));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: categoria);
    }
  });

  group('«Tamanho da interface»', () {
    testWidgets('no telemóvel não aparece (não faz nada)', (t) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await t.pumpWidget(appTeste(definicoes()));
      await t.pump();
      await t.tap(find.text('Imagem e som'));
      await t.pumpAndSettle();
      expect(find.text('Desentrelaçamento'), findsOneWidget);
      expect(find.text('Tamanho da interface'), findsNothing);
    });

    testWidgets('no Windows aparece', (t) async {
      t.view.physicalSize = const Size(1000, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await t.pumpWidget(appTeste(definicoes()));
      await t.pump();
      expect(find.text('Tamanho da interface'), findsOneWidget);
    });

    testWidgets('na TV aparece, mesmo em «Normal»', (t) async {
      ecraTvTeste(t);
      prefs.tamanhoInterface = TamanhoInterface.normal;
      await t.pumpWidget(appTeste(definicoes()));
      await t.pump();
      expect(find.text('Tamanho da interface'), findsOneWidget);
    });
  });
}
