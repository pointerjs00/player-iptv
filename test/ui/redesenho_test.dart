import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/design/ponto_direto.dart';
import 'package:player_iptv/ui/inicio/cartao_lista.dart';
import 'package:player_iptv/ui/principal/barra_seccoes.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/design/tokens.dart';
import 'package:player_iptv/ui/tema.dart';

/// O redesenho de 2026: a mira do foco (os cantos de visor que se fecham sobre o elemento com o
/// foco) e o fundo com as faixas curvas de luz.

/// O progresso da mira (0 = escondida, 1 = fechada), lido do pintor.
double progressoMira(WidgetTester t, Finder mira) {
  final pintura = t.widget<CustomPaint>(find.descendant(of: mira, matching: find.byType(CustomPaint)).first);
  return (pintura.foregroundPainter! as dynamic).t as double;
}

void main() {
  setUp(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional);
  tearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);

  Widget app(Widget filho, {bool semAnimacoes = false}) => MaterialApp(
        theme: temaApp(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: semAnimacoes),
          child: Scaffold(body: Center(child: filho)),
        ),
      );

  testWidgets('a mira aparece com o foco, fecha-se sobre o elemento e sai quando ele o perde', (t) async {
    final a = FocusNode(), b = FocusNode();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    Widget botao(FocusNode f, String nome) => RealceFoco(
          construir: (_, aoMudar) => ListTile(focusNode: f, onFocusChange: aoMudar, title: Text(nome), onTap: () {}),
        );
    await t.pumpWidget(app(SizedBox(width: 300, child: Column(children: [botao(a, 'A'), botao(b, 'B')]))));
    final miraA = find.ancestor(of: find.text('A'), matching: find.byType(Mira));
    expect(progressoMira(t, miraA), 0);
    a.requestFocus();
    await t.pump();
    await t.pump(const Duration(milliseconds: 80));
    final aMeio = progressoMira(t, miraA);
    expect(aMeio, inExclusiveRange(0, 1), reason: 'anima: não aparece de repente');
    await t.pumpAndSettle();
    expect(progressoMira(t, miraA), 1);
    b.requestFocus();
    await t.pumpAndSettle();
    expect(progressoMira(t, miraA), 0, reason: 'sai do que perdeu o foco');
    expect(progressoMira(t, find.ancestor(of: find.text('B'), matching: find.byType(Mira))), 1);
  });

  testWidgets('com «reduzir movimento» a mira aparece logo, sem animar', (t) async {
    final a = FocusNode();
    addTearDown(a.dispose);
    await t.pumpWidget(app(
      SizedBox(width: 300, child: RealceFoco(
        construir: (_, aoMudar) => ListTile(focusNode: a, onFocusChange: aoMudar, title: const Text('A'), onTap: () {}),
      )),
      semAnimacoes: true,
    ));
    a.requestFocus();
    await t.pump();
    await t.pump();
    expect(progressoMira(t, find.byType(Mira)), 1);
  });

  testWidgets('no modo toque (telemóvel, rato) não há mira', (t) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    final a = FocusNode();
    addTearDown(a.dispose);
    await t.pumpWidget(app(SizedBox(width: 300, child: RealceFoco(
      construir: (_, aoMudar) => ListTile(focusNode: a, onFocusChange: aoMudar, title: const Text('A'), onTap: () {}),
    ))));
    a.requestFocus();
    await t.pumpAndSettle();
    expect(progressoMira(t, find.byType(Mira)), 0);
  });

  test('o fundo pinta o gradiente e as faixas curvas (escala a qualquer tamanho)', () {
    final gravador = ui.PictureRecorder();
    final canvas = Canvas(gravador);
    // em 1920 × 1080 e num telemóvel ao alto: não falha nem sai do retângulo
    FundoCinema.pintarFaixas(canvas, const Rect.fromLTWH(0, 0, 1920, 1080));
    FundoCinema.pintarFaixas(canvas, const Rect.fromLTWH(0, 0, 390, 844));
    expect(gravador.endRecording(), isNotNull);
  });

  testWidgets('a barra lateral estreita: a secção ativa num cartão branco, o texto escuro', (t) async {
    await t.pumpWidget(app(SizedBox(height: 600, child: BarraSeccoes(atual: Seccao.gestor, aoEscolher: (_) {}))));
    expect(t.getSize(find.byType(BarraSeccoes)).width, 112);
    Color corDe(String rotulo) => t.widget<Text>(find.text(rotulo)).style!.color!;
    expect(corDe('Gestor'), Tokens.fundo, reason: 'ativa: texto escuro sobre branco');
    expect(corDe('Ver TV'), Tokens.texto2);
  });

  testWidgets('na grelha, o cartão da lista tem o número dela em marca de água (só decoração)', (t) async {
    final l = Lista(id: 'a', ordem: 7, conta: Conta('n', Tipo.stalker, 'http://portal.tv/c/', mac: '00:1A:79:00:00:01'));
    await t.pumpWidget(app(SizedBox(width: 320, height: CartaoLista.altura(false), child: CartaoLista(lista: l, aoAbrir: () {}))));
    final marca = t.widget<RichText>(find.byKey(const Key('marca-dagua-lista')));
    expect(marca.text.toPlainText(), '007');
    expect(find.text('007'), findsNothing, reason: 'não é um Text: não entra no texto do cartão');
    expect(t.takeException(), isNull);
  });

  testWidgets('o ponto do direto pulsa ao aparecer e depois fica aceso (nenhum ecrã anima sem fim)', (t) async {
    await t.pumpWidget(app(const PontoDireto()));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.binding.hasScheduledFrame, isTrue, reason: 'a pulsar');
    // três pulsos de 1,6 s e pára: o pumpAndSettle acaba
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
  });
}
