import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/design/escala_interface.dart';
import 'package:player_iptv/ui/design/revelar_topo.dart';

import 'ajuda_dpad.dart';

Widget _ecra({double escala = 1}) => EscalaInterface(
      escala: escala,
      child: Scaffold(
        body: ListView(children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Título', key: Key('titulo'))),
          SizedBox(
            height: 56,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < 20; i++)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: FilterChip(
                      key: Key('chip$i'), label: Text('Chip $i'), onSelected: (_) {}, autofocus: i == 0),
                ),
            ]),
          ),
          for (var i = 0; i < 50; i++) ListTile(key: Key('linha$i'), title: Text('Linha $i'), onTap: () {}),
        ]),
      ),
    );

double _offset(WidgetTester t) =>
    t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

void main() {
  setUp(() {
    RevelarTopo.instalar();
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    RevelarTopo.retirar();
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Future<void> descer(WidgetTester t, int n) async {
    for (var i = 0; i < n; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    }
  }

  testWidgets('ao subir ao primeiro controlo, a página volta ao topo e o título fica visível', (t) async {
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(appTeste(_ecra()));
    await t.pumpAndSettle();
    await descer(t, 31);
    expect(_offset(t), greaterThan(0));
    for (var i = 0; i < 31; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    }
    await t.pumpAndSettle();
    expect(_offset(t), 0);
    expect(t.getTopLeft(find.byKey(const Key('titulo'))).dy, greaterThanOrEqualTo(0));
  });

  testWidgets('o mesmo com a interface reduzida (Compacto)', (t) async {
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(appTeste(_ecra(escala: .8)));
    await t.pumpAndSettle();
    await descer(t, 31);
    expect(_offset(t), greaterThan(0));
    for (var i = 0; i < 31; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    }
    await t.pumpAndSettle();
    expect(_offset(t), 0);
  });

  testWidgets('subir de uma linha para a anterior não vai ao topo', (t) async {
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(appTeste(_ecra()));
    await t.pumpAndSettle();
    await descer(t, 31);
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(_offset(t), greaterThan(0));
  });

  testWidgets('um Scrollable horizontal não é mexido', (t) async {
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(appTeste(_ecra()));
    await t.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    }
    await t.pumpAndSettle();
    final horizontal = t.state<ScrollableState>(find.byType(Scrollable).at(1)).position.pixels;
    expect(horizontal, greaterThan(0));
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(t.state<ScrollableState>(find.byType(Scrollable).at(1)).position.pixels, greaterThan(0));
  });

  testWidgets('lista longa virtualizada: subir a meio não vai ao topo', (t) async {
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(appTeste(Scaffold(
      body: ListView.builder(
        itemCount: 2000,
        itemBuilder: (_, i) => ListTile(key: Key('l$i'), title: Text('Linha $i'), onTap: () {}, autofocus: i == 0),
      ),
    )));
    await t.pumpAndSettle();
    await descer(t, 500);
    final antes = _offset(t);
    expect(antes, greaterThan(1000));
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(_offset(t), greaterThan(antes - 200));
  });

  testWidgets('lista vertical encaixada: subir dentro dela não puxa a exterior ao topo', (t) async {
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(appTeste(Scaffold(
      body: ListView(children: [
        const SizedBox(height: 300, child: Text('Título')),
        SizedBox(
          height: 400,
          child: ListView(children: [
            for (var i = 0; i < 10; i++) ListTile(title: Text('Interna $i'), onTap: () {}, autofocus: i == 0),
          ]),
        ),
        for (var i = 0; i < 30; i++) ListTile(title: Text('Externa $i'), onTap: () {}),
      ]),
    )));
    await t.pumpAndSettle();
    // desce pela lista interior até ao primeiro controlo da exterior: os de cima (Interna) estão
    // dentro de um scroll encaixado e contam; a exterior não volta ao topo (o título não tem controlos)
    for (var i = 0; i < 14 && !textosFocados().contains('Externa 0'); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    }
    await t.pumpAndSettle();
    expect(textosFocados(), contains('Externa 0'));
    expect(t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, greaterThan(0));
  });
}
