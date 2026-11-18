import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/design/ecra.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

/// Regressões do feedback 1 (Android TV): tudo só com teclas (setas, OK, Voltar).

Widget _app(Widget w) =>
    MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

/// Android TV 1080p: 960×540 lógicos, tamanhos de TV, realce sempre ligado.
void _tv(WidgetTester t, {double largura = 960, double altura = 540}) {
  t.view.physicalSize = Size(largura, altura);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  EcraTv.nativo = true;
  addTearDown(() => EcraTv.nativo = false);
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
}

/// Os textos dentro do widget com o foco.
String _focado() {
  final no = FocusManager.instance.primaryFocus;
  final ctx = no?.context;
  if (ctx == null || no is FocusScopeNode) return '';
  final textos = <String>[];
  void visitar(Element e) {
    final w = e.widget;
    if (w is Text) textos.add(w.data ?? '');
    e.visitChildren(visitar);
  }

  (ctx as Element).visitChildren(visitar);
  if (textos.isEmpty) {
    final dica = ctx.findAncestorWidgetOfExactType<Tooltip>()?.message;
    if (dica != null) textos.add(dica);
  }
  return textos.join(' | ');
}

Future<void> _tecla(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300)); // o scroll até ao foco
}

void main() {
  late Directory pasta;
  late Biblioteca bib;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('dpad');
    bib = await Biblioteca.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  group('Início (Player): a grelha de listas', () {
    Future<void> comListas(WidgetTester t, int n) async {
      await t.runAsync(() => bib.adicionar([
            for (var i = 0; i < n; i++) Importada(contaDeLinha('http://h$i.com/l$i.m3u')!),
          ]));
      await t.pumpWidget(_app(TelaInicio(biblioteca: bib)));
      await t.pump();
      await t.pump();
    }

    testWidgets('BAIXO chega a todas as linhas e CIMA volta à primeira', (t) async {
      _tv(t);
      await comListas(t, 15); // 3 colunas a 960 → 5 linhas (as últimas fora do ecrã)
      expect(_focado(), contains('001H'));
      final caminho = <String>[];
      for (var i = 0; i < 6; i++) {
        await _tecla(t, LogicalKeyboardKey.arrowDown);
        caminho.add(_focado().split(' | ').first);
      }
      expect(caminho.any((c) => c.contains('013H')), isTrue, reason: 'BAIXO: $caminho');
      final subir = <String>[];
      for (var i = 0; i < 8; i++) {
        await _tecla(t, LogicalKeyboardKey.arrowUp);
        subir.add(_focado().split(' | ').first);
        if (subir.last.contains('001H')) break;
      }
      expect(subir.last, contains('001H'), reason: 'CIMA: $subir');
    });

    testWidgets('os cartões não têm "..." (Mais opções): OK mantido abre o menu com todas as ações, '
        'incluindo "Remover lista"', (t) async {
      _tv(t);
      await comListas(t, 2);
      expect(find.byTooltip('Mais opções'), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      // BAIXO no cartão não entra em nenhum botão de dentro: o foco fica num cartão
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      expect(_focado(), contains('001H'), reason: 'foco em: ${_focado()}');
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 50));
        await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      }
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      for (final a in ['Abrir', 'Atualizar canais', 'Editar', 'Copiar link', 'Remover lista']) {
        expect(find.widgetWithText(ListTile, a), findsOneWidget, reason: a);
      }
      // a última ação alcança-se com BAIXO
      for (var i = 0; i < 6; i++) {
        await _tecla(t, LogicalKeyboardKey.arrowDown);
      }
      expect(_focado(), 'Remover lista');
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.text('Remover lista?'), findsOneWidget);
      expect(_focado(), 'Cancelar', reason: 'o foco começa no lado seguro');
    });
  });
}
