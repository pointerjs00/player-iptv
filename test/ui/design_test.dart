import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

Widget _app(Widget w, {bool semAnimacoes = false}) => MaterialApp(
      theme: temaApp(),
      builder: (c, w) => TemaConformeRealce(
        child: MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: semAnimacoes), child: w!),
      ),
      home: Scaffold(body: Center(child: w)),
    );

void _tamanho(WidgetTester t, double l, double a) {
  t.view.physicalSize = Size(l, a);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void _modo(FocusHighlightStrategy s) {
  FocusManager.instance.highlightStrategy = s;
  addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
}

void main() {
  group('CartaoModerno', () {
    double escala(WidgetTester t) => t
        .widget<AnimatedScale>(find.descendant(of: find.byType(CartaoModerno), matching: find.byType(AnimatedScale)))
        .scale;
    // a sombra do cartão (a primeira SombraExterior é o brilho do realce, a de dentro a do cartão)
    List<BoxShadow> sombra(WidgetTester t) => t
        .widgetList<SombraExterior>(
            find.descendant(of: find.byType(CartaoModerno), matching: find.byType(SombraExterior)))
        .last
        .sombras;

    Widget cartao() => SizedBox(
        width: 200, height: 120, child: CartaoModerno(autofocus: true, onTap: () {}, child: const Text('Lista')));

    testWidgets('com o comando (traditional): o foco aumenta 1.04, sobe a sombra e tem realce', (t) async {
      _modo(FocusHighlightStrategy.alwaysTraditional);
      await t.pumpWidget(_app(cartao()));
      await t.pumpAndSettle();
      expect(escala(t), 1.04);
      expect(sombra(t), Tokens.sombraFoco);
      final caixas = t.widgetList<DecoratedBox>(
          find.descendant(of: find.byType(CartaoModerno), matching: find.byType(DecoratedBox)));
      expect(
          caixas.any((d) =>
              d.decoration is BoxDecoration &&
              (d.decoration as BoxDecoration).border == Border.fromBorderSide(Realce.borda)),
          isTrue,
          reason: 'borda de realce');
    });

    testWidgets('no toque (telemóvel/rato) o foco automático não aumenta nem sobe a sombra', (t) async {
      _modo(FocusHighlightStrategy.alwaysTouch);
      await t.pumpWidget(_app(cartao()));
      await t.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context, isNotNull);
      expect(escala(t), 1);
      expect(sombra(t), Tokens.sombra1);
    });

    testWidgets('o rato por cima sobe a sombra (sem aumentar)', (t) async {
      _modo(FocusHighlightStrategy.alwaysTouch);
      await t.pumpWidget(_app(cartao()));
      final rato = await t.createGesture(kind: PointerDeviceKind.mouse);
      await rato.addPointer(location: Offset.zero);
      addTearDown(rato.removePointer);
      await rato.moveTo(t.getCenter(find.byType(CartaoModerno)));
      await t.pumpAndSettle();
      expect(sombra(t), Tokens.sombra2);
      expect(escala(t), 1);
    });
  });

  group('entradaEmCascata', () {
    // só as de dentro do ecrã (a rota do ecrã também tem as suas)
    Finder transicoes() => find.ancestor(
        of: find.text('x'), matching: find.descendant(of: find.byType(Scaffold), matching: find.byType(FadeTransition)));

    testWidgets('anima (fade + slide) a entrada', (t) async {
      await t.pumpWidget(_app(entradaEmCascata(2, const Text('x'))));
      expect(transicoes(), findsWidgets);
      expect(t.widget<FadeTransition>(transicoes().first).opacity.value, lessThan(1));
      await t.pumpAndSettle();
      expect(t.widget<FadeTransition>(transicoes().first).opacity.value, 1);
    });

    testWidgets('sem animação com disableAnimations (reduzir movimento)', (t) async {
      await t.pumpWidget(_app(entradaEmCascata(2, const Text('x')), semAnimacoes: true));
      expect(transicoes(), findsNothing);
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('sem animação para índices > 30 (listas grandes)', (t) async {
      await t.pumpWidget(_app(entradaEmCascata(31, const Text('x'))));
      expect(transicoes(), findsNothing);
    });
  });

  testWidgets('PilulaEstado: cores e textos dos 4 estados', (t) async {
    final casos = <String?, (String, Color)>{
      'funciona': ('Funciona', Tokens.ok),
      'nao_funciona': ('Não funciona', Tokens.mau),
      'inconclusivo': ('Inconclusivo', Tokens.aviso),
      null: ('Por verificar', Tokens.neutro),
    };
    for (final MapEntry(key: estado, value: (texto, cor)) in casos.entries) {
      await t.pumpWidget(_app(PilulaEstado(estado)));
      expect(t.widget<Text>(find.text(texto)).style?.color, cor, reason: '$estado');
      final caixa = t.widget<Container>(
          find.descendant(of: find.byType(PilulaEstado), matching: find.byType(Container)).first);
      expect((caixa.decoration! as BoxDecoration).color, cor.withValues(alpha: .16), reason: '$estado');
    }
  });

  group('EsqueletoBrilho', () {
    testWidgets('brilha (anima) enquanto está no ecrã', (t) async {
      await t.pumpWidget(_app(const EsqueletoBrilho(child: BlocoEsqueleto(largura: 100, altura: 20))));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.hasRunningAnimations, isTrue);
    });

    testWidgets('parado com disableAnimations', (t) async {
      await t.pumpWidget(
          _app(const EsqueletoBrilho(child: BlocoEsqueleto(largura: 100, altura: 20)), semAnimacoes: true));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.hasRunningAnimations, isFalse);
    });
  });

  group('ecraTv', () {
    late bool tv;
    Widget sonda() => Builder(builder: (c) {
          tv = ecraTv(c);
          return const SizedBox();
        });

    testWidgets('ecrã largo com rato/toque não é TV', (t) async {
      _tamanho(t, 1920, 1080);
      await t.pumpWidget(_app(sonda()));
      expect(tv, isFalse);
    });

    testWidgets('o canal nativo de TV (Android TV) diz que é TV, mesmo a 960 lógicos', (t) async {
      _tamanho(t, 960, 540);
      EcraTv.nativo = true;
      addTearDown(() => EcraTv.nativo = false);
      await t.pumpWidget(_app(sonda()));
      expect(tv, isTrue);
    });

    testWidgets('≥ 1200 lógicos sem toque (navegação direcional) é TV; mais estreito não', (t) async {
      Widget direcional(Widget w) => Builder(
          builder: (c) => MediaQuery(
              data: MediaQuery.of(c).copyWith(navigationMode: NavigationMode.directional), child: w));
      _tamanho(t, 1280, 720);
      await t.pumpWidget(_app(direcional(sonda())));
      expect(tv, isTrue);
      _tamanho(t, 1000, 720);
      await t.pumpWidget(_app(direcional(sonda())));
      expect(tv, isFalse);
    });
  });

  testWidgets('configurarRealceFoco guarda se é TV (para ecraTv)', (t) async {
    addTearDown(() {
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
      EcraTv.nativo = false;
    });
    await configurarRealceFoco(eTv: () async => true);
    expect(EcraTv.nativo, isTrue);
    await configurarRealceFoco(eTv: () async => false);
    expect(EcraTv.nativo, isFalse);
  });

  testWidgets('rotaSuave: fade-through ao abrir, instantânea com disableAnimations', (t) async {
    Future<void> abrir(bool sem) async {
      await t.pumpWidget(_app(
          Builder(
              builder: (c) => TextButton(
                  onPressed: () => Navigator.of(c).push(rotaSuave(const Text('nova'))), child: const Text('abrir'))),
          semAnimacoes: sem));
      await t.tap(find.text('abrir'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 120));
    }

    double opacidadeNova() => find
        .ancestor(of: find.text('nova'), matching: find.byType(FadeTransition))
        .evaluate()
        .map((e) => (e.widget as FadeTransition).opacity.value)
        .fold(1.0, (a, b) => a * b);

    await abrir(false);
    expect(opacidadeNova(), lessThan(1));
    await t.pumpAndSettle();
    expect(opacidadeNova(), 1);

    await t.pumpWidget(const SizedBox());
    await abrir(true);
    expect(opacidadeNova(), 1);
    await t.pumpAndSettle();
  });

  test('Tokens: raios, durações e cores do design', () {
    expect(Tokens.fundo, const Color(0xFF0B0F17));
    expect(Tokens.raioCartao, 20);
    expect(Tokens.raioBotao, 14);
    expect(Tokens.gradienteAcento.colors, const [Color(0xFF6C7BFF), Color(0xFF9B6CFF)]);
    expect(Tokens.curva, Curves.easeOutCubic);
    for (final d in [Tokens.duracaoRapida, Tokens.duracaoMedia, Tokens.duracaoLenta]) {
      expect(d.inMilliseconds, inInclusiveRange(180, 320));
    }
  });
}
