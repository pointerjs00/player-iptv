import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/player/aviso_buffering.dart';

Widget _app({required bool aberto, required bool buffering, double? pct, bool semAnimacoes = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: semAnimacoes),
        child: Scaffold(
          body: AvisoBuffering(aberto: aberto, buffering: buffering, percentagem: pct),
        ),
      ),
    );

void main() {
  testWidgets('a meio do canal: aparece só passados ~300 ms, com a percentagem, e sai quando volta a tocar',
      (t) async {
    await t.pumpWidget(_app(aberto: true, buffering: false));
    expect(find.textContaining('A carregar'), findsNothing);

    await t.pumpWidget(_app(aberto: true, buffering: true, pct: 45));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('A carregar'), findsNothing, reason: 'engasgos curtos não piscam');
    await t.pump(const Duration(milliseconds: 150));
    expect(find.text('A carregar… 45%'), findsOneWidget);

    await t.pumpWidget(_app(aberto: true, buffering: true, pct: 80));
    await t.pump();
    expect(find.text('A carregar… 80%'), findsOneWidget);

    await t.pumpWidget(_app(aberto: true, buffering: false, pct: 100));
    await t.pump();
    expect(find.textContaining('A carregar'), findsNothing);
  });

  testWidgets('um buffering mais curto que o atraso nunca aparece', (t) async {
    await t.pumpWidget(_app(aberto: true, buffering: true));
    await t.pump(const Duration(milliseconds: 250));
    await t.pumpWidget(_app(aberto: true, buffering: false));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('A carregar'), findsNothing);
  });

  testWidgets('a tocar normalmente não aparece', (t) async {
    await t.pumpWidget(_app(aberto: true, buffering: false, pct: 100));
    await t.pump(const Duration(seconds: 2));
    expect(find.byType(AnelCarregamento), findsNothing);
  });

  testWidgets('enquanto o canal abre não aparece (aí já há o indicador de abertura)', (t) async {
    await t.pumpWidget(_app(aberto: false, buffering: true, pct: 10));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('A carregar'), findsNothing);
  });

  testWidgets('sem percentagem: só "A carregar…"', (t) async {
    await t.pumpWidget(_app(aberto: true, buffering: true));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('A carregar…'), findsOneWidget);
    expect(find.byType(AnelCarregamento), findsOneWidget);
  });

  testWidgets('não apanha teclas nem toques (zapping e Voltar continuam)', (t) async {
    await t.pumpWidget(_app(aberto: true, buffering: true));
    await t.pump(const Duration(milliseconds: 400));
    expect(
        t.widget<ExcludeFocus>(find.descendant(of: find.byType(AvisoBuffering), matching: find.byType(ExcludeFocus)))
            .excluding,
        isTrue);
    final ignora = t.widget<IgnorePointer>(
        find.descendant(of: find.byType(AvisoBuffering), matching: find.byType(IgnorePointer)).first);
    expect(ignora.ignoring, isTrue);
  });

  testWidgets('reduzir movimento: o anel fica parado', (t) async {
    await t.pumpWidget(_app(aberto: true, buffering: true, semAnimacoes: true));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(AnelCarregamento), findsOneWidget);
    expect(t.hasRunningAnimations, isFalse);
  });
}
