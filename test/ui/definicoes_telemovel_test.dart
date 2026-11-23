import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/ui/definicoes/linha_opcao.dart';
import 'package:player_iptv/ui/definicoes/seletor_numero.dart';
import 'package:player_iptv/ui/definicoes/tela_definicoes.dart';
import 'package:player_iptv/ui/design/barra_teclas.dart';
import 'package:player_iptv/ui/design/ecra.dart';

import 'apoio_telemovel.dart';

/// As Definições num telemóvel ao alto (360×800 e 412×915, letra a 1 e a 1,3, com a Roboto): sem
/// as dicas do comando, sem a opção só da Android TV e nada transborda. E a barra de teclas só na
/// TV e no computador.

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;
  late Preferencias prefs;

  setUpAll(carregarRoboto);
  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('defs_telemovel');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
    prefs = await Preferencias.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {
      /* Windows */
    }
  });

  /// Android (não TV) e, no fim do corpo, o repor (antes das verificações do teste).
  void noAndroid(String nome, Future<void> Function(WidgetTester t, Size ecra) corpo) =>
      noTelemovel(nome, (t, ecra) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await corpo(t, ecra);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

  Future<void> abrir(WidgetTester t, String categoria) async {
    await t.pumpWidget(appTelemovel(TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs, android: true)));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text(categoria));
    await t.pump(const Duration(milliseconds: 400));
  }

  /// Desliza a lista das opções até ao fim (para montar e medir todas as linhas).
  /// `aCada` corre antes de cada passo e no fim (a lista só monta as linhas à vista).
  Future<void> ateAoFim(WidgetTester t, {void Function()? aCada}) async {
    for (var i = 0; i < 12; i++) {
      aCada?.call();
      await t.drag(find.byType(ListView).last, const Offset(0, -300));
      await t.pump(const Duration(milliseconds: 200));
    }
    aCada?.call();
  }

  noAndroid('Imagem e som: sem «Ajustar a taxa do ecrã ao canal (Android TV)» fora da TV', (t, ecra) async {
    await abrir(t, 'Imagem e som');
    expect(find.text('Desentrelaçamento'), findsOneWidget);
    await ateAoFim(t, aCada: () {
      expect(find.text('Ajustar a taxa do ecrã ao canal'), findsNothing);
      expect(find.text('Evita soluços nas imagens (Android TV)'), findsNothing);
    });
  });

  noAndroid('Imagem e som: sem opções de volume (no canal o volume é o do sistema)', (t, ecra) async {
    await abrir(t, 'Imagem e som');
    await ateAoFim(t, aCada: () {
      expect(find.text('Volume inicial do sistema'), findsNothing);
      expect(find.text('Volume ao abrir'), findsNothing);
    });
  });

  noAndroid('Verificação: sem a nota «← → mudam o valor» e os números por baixo do título', (t, ecra) async {
    await abrir(t, 'Verificação');
    for (final titulo in ['Listas ao mesmo tempo', 'Tempo limite por lista', 'Tempo por canal']) {
      final linha = find.widgetWithText(SeletorNumero, titulo);
      final mais = find.descendant(of: linha, matching: find.text('+'));
      // o controlo passa para baixo do título (ao lado, o texto ficava apertado)
      final texto = find.descendant(of: linha, matching: find.byType(TextoOpcao));
      expect(t.getRect(mais).top, greaterThan(t.getRect(texto).bottom), reason: titulo);
      alvo48(t, find.ancestor(of: mais, matching: find.byType(InkWell)).first, motivo: titulo);
    }
    await ateAoFim(t, aCada: () {
      expect(find.textContaining('mudam o valor'), findsNothing);
      expect(find.textContaining('mudam de opção'), findsNothing);
    });
    expect(find.text('Com uma verificação a decorrer, as mudanças valem para as próximas listas.'), findsOneWidget);
  });

  for (final c in ['Ligação', 'Cópia de segurança', 'Sobre e licenças']) {
    noAndroid('$c: nada transborda', (t, ecra) async {
      await abrir(t, c);
      await ateAoFim(t);
    });
  }

  group('barra de teclas', () {
    Future<void> montar(WidgetTester t) async {
      await t.pumpWidget(appTelemovel(const Scaffold(body: BarraTeclas([('OK', 'abrir')]))));
    }

    testWidgets('no telemóvel (Android, não TV) não aparece', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await montar(t);
      debugDefaultTargetPlatformOverride = null;
      expect(find.text('abrir'), findsNothing);
    });

    testWidgets('no Windows aparece', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await montar(t);
      debugDefaultTargetPlatformOverride = null;
      expect(find.text('abrir'), findsOneWidget);
    });

    testWidgets('na TV aparece', (t) async {
      EcraTv.nativo = true;
      addTearDown(() => EcraTv.nativo = false);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await montar(t);
      debugDefaultTargetPlatformOverride = null;
      expect(find.text('abrir'), findsOneWidget);
    });
  });
}
