import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/estatisticas.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/guia/programa.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/definicoes/tela_definicoes.dart';
import 'package:player_iptv/ui/inicio/cartao_semana.dart';
import 'package:player_iptv/ui/inicio/tela_estatisticas.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

import 'ajuda_dpad.dart';

/// As estatísticas no Início («A tua semana»), o ecrã das Estatísticas, o programa no «Continuar
/// a ver» e o apagar nas Definições.

Widget _app(Widget w) => MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

final _agora = DateTime(2026, 11, 26, 21);
const _sport = Canal(id: 'S', nome: 'Sport TV 1', grupo: 'Desporto');
const _rtp = Canal(id: 'R', nome: 'RTP 1', grupo: 'Portugal');

void main() {
  late Directory pasta;
  late Biblioteca bib;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('estatisticas_ui');
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
  }

  Future<Lista> umaLista(WidgetTester t) async {
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://a.com/l.m3u')!)]);
      await bib.guardarCanais(bib.listas.single.id, ConteudoLista(['Desporto', 'Portugal'], const [_sport, _rtp]));
    });
    return bib.listas.single;
  }

  Future<void> abrirInicio(WidgetTester t, Estatisticas e, {Future<GuiaLista?> Function(Lista)? guia}) async {
    await t.pumpWidget(_app(TelaInicio(biblioteca: bib, estatisticas: e, agora: () => _agora, guiaGuardado: guia,
        abrirCanal: (c, i) => null)));
    for (var i = 0; i < 15; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  testWidgets('sem tempo visto, o Início não mostra «A tua semana»', (t) async {
    tamanho(t);
    await umaLista(t);
    await abrirInicio(t, Estatisticas.emMemoria());
    expect(find.byType(CartaoSemana), findsNothing);
  });

  testWidgets('«A tua semana»: as horas, a comparação e os mais vistos; OK abre as Estatísticas', (t) async {
    tamanho(t);
    final l = await umaLista(t);
    final e = Estatisticas.emMemoria()
      ..somar(l.id, l.nomeMostrado, _sport, const Duration(hours: 2, minutes: 10), quando: _agora)
      ..somar(l.id, l.nomeMostrado, _rtp, const Duration(minutes: 50), quando: _agora.subtract(const Duration(days: 2)))
      ..somar(l.id, l.nomeMostrado, _rtp, const Duration(hours: 1), quando: _agora.subtract(const Duration(days: 9)));
    await abrirInicio(t, e);
    final cartao = find.byType(CartaoSemana);
    expect(cartao, findsOneWidget);
    expect(find.descendant(of: cartao, matching: find.text('3 h')), findsOneWidget);
    expect(find.descendant(of: cartao, matching: find.text('+2 h que na semana anterior')), findsOneWidget);
    expect(find.descendant(of: cartao, matching: find.text('Sport TV 1')), findsOneWidget);
    expect(find.descendant(of: cartao, matching: find.text('2 h 10')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(cartao);
    await t.pumpAndSettle();
    expect(find.byType(TelaEstatisticas), findsOneWidget);
    expect(find.text('Canais mais vistos · 30 dias'), findsOneWidget);
    expect(find.text('DIAS SEGUIDOS'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('«Continuar a ver» mostra o programa a dar, do guia guardado (sem rede)', (t) async {
    tamanho(t);
    final l = await umaLista(t);
    await t.runAsync(() => bib.registarVisto(l.id, _sport));
    final s = _agora.millisecondsSinceEpoch ~/ 1000;
    final guia = GuiaLista({
      'S': [Programa(s - 1800, s + 1800, 'Liga Europa · Benfica x Ajax')],
    }, criado: _agora);
    await abrirInicio(t, Estatisticas.emMemoria(), guia: (_) async => guia);
    expect(find.text('Liga Europa · Benfica x Ajax'), findsOneWidget);
    expect(t.widget<LinearProgressIndicator>(find.byKey(const Key('continuar-progresso'))).value, closeTo(.5, 1e-9));
  });

  testWidgets('o ecrã das Estatísticas: o top com a lista, sem nada a transbordar; ↓ desliza', (t) async {
    ecraTvTeste(t);
    final e = Estatisticas.emMemoria();
    for (var i = 0; i < 12; i++) {
      e.somar('l', 'Lista A', Canal(id: '$i', nome: 'Canal número $i', grupo: 'G'), Duration(minutes: 10 + i * 5),
          quando: _agora.subtract(Duration(days: i)));
    }
    await t.pumpWidget(_app(TelaEstatisticas(estatisticas: e, agora: () => _agora)));
    await t.pumpAndSettle();
    expect(find.text('Canal número 11'), findsOneWidget, reason: 'o mais visto primeiro');
    expect(t.takeException(), isNull);
    final antes = t.getTopLeft(find.text('Canal número 11')).dy;
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('Canal número 11')).dy, lessThan(antes), reason: '↓ desliza a página');
  });

  testWidgets('Definições › Imagem e som: contar o tempo e apagar (com confirmação)', (t) async {
    tamanho(t);
    final antes = Estatisticas.atual;
    final e = Estatisticas.emMemoria()..somar('l', 'L', _rtp, const Duration(hours: 1), quando: _agora);
    Estatisticas.atual = e;
    addTearDown(() => Estatisticas.atual = antes);
    late AreaGestor area;
    late Preferencias prefs;
    await t.runAsync(() async {
      area = await AreaGestor.abrir(pasta);
      prefs = await Preferencias.abrir(pasta);
    });
    await t.pumpWidget(_app(TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs)));
    await t.pump();
    await t.scrollUntilVisible(find.text('Apagar as estatísticas'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Contar o tempo de visualização'), findsOneWidget);
    await t.tap(find.text('Contar o tempo de visualização'));
    await t.pump();
    expect(prefs.contarTempo, isFalse);
    await t.tap(find.byKey(const Key('apagar-estatisticas')));
    await t.pumpAndSettle();
    expect(find.text('Apagar as estatísticas?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Apagar'));
    await t.pumpAndSettle();
    expect(e.vazio, isTrue);
  });
}
