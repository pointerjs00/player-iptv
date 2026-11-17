import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/copia_seguranca.dart';
import 'package:player_iptv/dados/guardar_ficheiro.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/definicoes/tela_definicoes.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

Widget _app(Widget w) => MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;
  late Preferencias prefs;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('defs');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
    prefs = await Preferencias.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Future<void> abrir(WidgetTester t,
      {EscolherCopia? escolher, Future<ResultadoGuardar> Function(String, List<int>)? guardar}) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(TelaDefinicoes(
        biblioteca: bib, area: area, preferencias: prefs, escolherCopia: escolher, guardarCopia: guardar)));
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('mostra as secções e muda os canais de teste', (t) async {
    await abrir(t);
    for (final s in ['Canais de teste', 'Verificação', 'Preferências do player', 'User-agent', 'Cópia de segurança']) {
      expect(find.text(s), findsOneWidget);
    }
    await t.tap(find.text('DAZN 1'));
    await t.pump();
    expect(bib.canaisTeste, containsAll(['rtp1', 'dazn1']));
  });

  testWidgets('o tempo limite muda com as setas e fica gravado', (t) async {
    await abrir(t);
    expect(find.text('Tempo limite: 8 s'), findsOneWidget);
    await t.tap(find.byType(Slider).first);
    await t.pump();
    final v = prefs.timeoutVerificacao;
    expect(v, inInclusiveRange(5, 30));
    // a gravação é IO real com continuações na zona do teste: alterna-se entre as duas
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump();
    }
    final m = jsonDecode(File('${pasta.path}${Platform.pathSeparator}preferencias.json').readAsStringSync()) as Map;
    expect(m['timeoutVerificacao'], v);
  });

  testWidgets('o user-agent escrito fica nas preferências', (t) async {
    await abrir(t);
    await t.ensureVisible(find.byType(TextField));
    await t.tap(find.byType(TextField));
    await t.pump();
    await t.enterText(find.byType(TextField), 'MeuPlayer/3');
    expect(prefs.userAgent, 'MeuPlayer/3');
  });

  testWidgets('exportar guarda um .json com a biblioteca', (t) async {
    await t.runAsync(() => bib.adicionar([Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!)]));
    String? nome;
    String? texto;
    await abrir(t, guardar: (n, b) async {
      nome = n;
      texto = utf8.decode(b);
      return const ResultadoGuardar('Transferências/x.json');
    });
    await t.ensureVisible(find.text('Exportar cópia'));
    await t.tap(find.text('Exportar cópia'));
    await t.pump();
    expect(nome, endsWith('.json'));
    expect(texto, contains('nxtbox.uk'));
    expect(find.textContaining('Cópia guardada em Transferências/x.json'), findsOneWidget);
  });

  testWidgets('importar um ficheiro inválido mostra o erro e não muda nada', (t) async {
    await t.runAsync(() => bib.adicionar([Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!)]));
    await abrir(t, escolher: () async => 'isto não é uma cópia');
    await t.ensureVisible(find.text('Importar cópia'));
    await t.tap(find.text('Importar cópia'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('Nada foi alterado'), findsOneWidget);
    expect(bib.listas, hasLength(1));
  });

  testWidgets('importar pede confirmação e Cancelar não muda nada', (t) async {
    final outra = (await t.runAsync(() async {
      final o = await Biblioteca.abrir(Directory.systemTemp.createTempSync('defs2'));
      await o.adicionar([Importada(contaDeLinha('http://outro.com/c/ 00:1A:79:00:00:02')!)]);
      return o;
    }))!;
    final texto = utf8.decode(codificarCopia(outra, area, prefs));
    await abrir(t, escolher: () async => texto);
    await t.ensureVisible(find.text('Importar cópia'));
    await t.tap(find.text('Importar cópia'));
    await t.pumpAndSettle();
    expect(find.text('Importar cópia de segurança'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(bib.listas, isEmpty);
    await t.tap(find.text('Importar cópia'));
    await t.pumpAndSettle();
    await t.tap(find.text('Juntar'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    expect(bib.listas, hasLength(1));
  });

  testWidgets('na TV: a roda dentada do Início abre as Definições com o comando e o foco fica visível', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(TelaInicio(
      biblioteca: bib,
      area: area,
      separadorGestor: const SizedBox(),
      definicoes: (_) => TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs),
    )));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Definições'), findsOneWidget);
    // Tab até à roda dentada e OK
    for (var i = 0; i < 30; i++) {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx != null && ctx.findAncestorWidgetOfExactType<Tooltip>()?.message == 'Definições') break;
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('Canais de teste'), findsOneWidget);
    // o foco entra no ecrã (primeiro controlo)
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Canais de teste'), findsNothing);
  });
}
