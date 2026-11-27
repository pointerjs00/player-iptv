import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/jogos/linha_jogo.dart';

import 'apoio_telemovel.dart';
import 'jogos_apoio.dart';

/// O ecrã «Jogos» num telemóvel ao alto (360×800 e 412×915, letra a 1 e a 1,3).
void main() {
  setUpAll(carregarRoboto);

  Future<Montagem> montar(WidgetTester t, {bool semCanal = true}) async {
    final m = (await t.runAsync(prepararJogos))!;
    addTearDown(() => arrumarJogos(m));
    m.prefs.mostrarSemCanal = semCanal;
    await t.pumpWidget(appTelemovel(Scaffold(body: m.tela())));
    await t.pump();
    return m;
  }

  noTelemovel('nada transborda, sem a coluna à direita', (t, ecra) async {
    await montar(t);
    expect(find.byType(LinhaJogo), findsWidgets);
    expect(find.text('Onde dá'), findsNothing, reason: 'o detalhe abre-se ao tocar');
    // o jogo ao vivo com o resultado, e a etiqueta do canal à vista
    expect(find.text('● AO VIVO'), findsOneWidget);
    expect(find.text('Sport TV 1'), findsWidgets);
  });

  noTelemovel('os filtros ficam numa só fila que desliza', (t, ecra) async {
    await montar(t);
    final filtros = t.getRect(find.widgetWithText(FilterChip, 'Filtros'));
    final aoVivo = t.getRect(find.widgetWithText(FilterChip, 'Ao vivo (1)'));
    expect(aoVivo.top, filtros.top, reason: 'na mesma fila');
    expect(find.byType(TextField), findsOneWidget, reason: 'a pesquisa por equipa por cima');
    final fila = find.ancestor(of: find.widgetWithText(FilterChip, 'Filtros'), matching: find.byType(Scrollable)).first;
    expect(t.widget<Scrollable>(fila).axisDirection, AxisDirection.right);
  });

  noTelemovel('o dia e as setas veem-se inteiros, numa fila por cima dos filtros', (t, ecra) async {
    await montar(t);
    for (final f in [find.byTooltip('Dia anterior'), find.text('Hoje, 27 nov'), find.byTooltip('Dia seguinte')]) {
      final r = t.getRect(f);
      expect(r.left >= 0 && r.right <= ecra.width, isTrue, reason: '$f à vista ($r)');
    }
    expect(t.getRect(find.text('Hoje, 27 nov')).bottom,
        lessThanOrEqualTo(t.getRect(find.widgetWithText(FilterChip, 'Filtros')).top));
    await t.tap(find.byTooltip('Dia seguinte'));
    await t.pump();
    expect(find.widgetWithText(ActionChip, 'Hoje'), findsOneWidget);
    expect(t.getRect(find.widgetWithText(ActionChip, 'Hoje')).right, lessThanOrEqualTo(ecra.width));
  });

  noTelemovel('«● AO VIVO» cabe na coluna da hora', (t, ecra) async {
    await montar(t);
    final hora = find.ancestor(of: find.text('● AO VIVO'), matching: find.byType(HoraJogo));
    final texto = t.getRect(find.text('● AO VIVO'));
    expect(texto.right, lessThanOrEqualTo(t.getRect(hora).right + .5));
    final p = t.renderObject<RenderParagraph>(find.text('● AO VIVO'));
    expect(p.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(p.size.width + .5), reason: 'não é cortado');
  });

  noTelemovel('os jogos de uma competição (de «Competições») não transbordam', (t, ecra) async {
    await montar(t);
    await t.tap(find.byTooltip('Competições'));
    await t.pumpAndSettle();
    await t.tap(find.text('Liga Portugal Betclic'));
    await t.pumpAndSettle();
    expect(find.text('Hoje, 27 nov'), findsOneWidget);
    expect(find.byType(LinhaJogo), findsWidgets);
  });

  noTelemovel('tocar num jogo abre o detalhe, com os canais e «Ver»', (t, ecra) async {
    await montar(t);
    await t.tap(find.text('Benfica'));
    await t.pumpAndSettle();
    expect(find.text('Benfica – Porto'), findsOneWidget);
    expect(find.text('Onde dá'), findsOneWidget);
    expect(find.text('BTV'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Ver'), findsOneWidget);
  });
}
