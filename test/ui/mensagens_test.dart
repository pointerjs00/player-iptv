import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/design/barra_teclas.dart';
import 'package:player_iptv/ui/design/mensagens.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';

/// Um ecrã com um botão (que tem o foco) e um botão que dispara a mensagem.
class _Ecra extends StatelessWidget {
  const _Ecra(this.dizer);
  final void Function(BuildContext) dizer;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          TextButton(key: const Key('foco'), autofocus: true, onPressed: () {}, child: const Text('A')),
          Builder(builder: (c) => TextButton(key: const Key('dizer'), onPressed: () => dizer(c), child: const Text('B'))),
        ]),
      );
}

Widget _casca(void Function(BuildContext) dizer) => MaterialApp(
      home: TelaPrincipal(verTv: _Ecra(dizer), gestor: const SizedBox(), definicoes: const SizedBox()),
    );

void main() {
  testWidgets('mostra o texto; a segunda substitui a primeira; desaparece após a duração', (t) async {
    await t.pumpWidget(_casca((c) => mostrarMensagem(c, 'Primeira', duracao: const Duration(seconds: 2))));
    await t.tap(find.byKey(const Key('dizer')));
    await t.pump();
    expect(find.text('Primeira'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(
        t.getSemantics(find.text('Primeira')).getSemanticsData().flagsCollection.isLiveRegion ||
            find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true).evaluate().isNotEmpty,
        isTrue);

    mostrarMensagem(t.element(find.byKey(const Key('dizer'))), 'Segunda');
    await t.pump();
    expect(find.text('Primeira'), findsNothing);
    expect(find.text('Segunda'), findsOneWidget);

    await t.pump(const Duration(seconds: 5));
    expect(find.text('Segunda'), findsNothing);
  });

  testWidgets('a tecla Menu ativa a ação e o foco não muda', (t) async {
    var feito = 0;
    await t.pumpWidget(_casca((c) =>
        mostrarMensagem(c, 'Apagado', acao: 'Desfazer', aoAcao: () => feito++)));
    await t.pump();
    final foco = FocusManager.instance.primaryFocus;
    await t.tap(find.byKey(const Key('dizer')), warnIfMissed: false);
    await t.pump();
    // o toque no botão mudou o foco para ele; fixa o foco de agora
    final antes = FocusManager.instance.primaryFocus;
    expect(find.text('Menu: Desfazer'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await t.pump();
    expect(feito, 1);
    expect(FocusManager.instance.primaryFocus, antes);
    expect(foco, isNotNull);
    expect(find.text('Apagado'), findsNothing);
    // sem mensagem, a tecla Menu já não faz nada
    await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    expect(feito, 1);
  });

  testWidgets('um toque na mensagem ativa a ação; com ação dura 8 s', (t) async {
    var feito = 0;
    await t.pumpWidget(_casca((c) => mostrarMensagem(c, 'Apagado', acao: 'Desfazer', aoAcao: () => feito++)));
    await t.tap(find.byKey(const Key('dizer')));
    await t.pump(const Duration(seconds: 6));
    expect(find.text('Apagado'), findsOneWidget);
    await t.tap(find.text('Apagado'));
    await t.pump();
    expect(feito, 1);
    expect(find.text('Apagado'), findsNothing);
  });

  testWidgets('com ação, some aos 8 s', (t) async {
    await t.pumpWidget(_casca((c) => mostrarMensagem(c, 'Apagado', acao: 'Desfazer', aoAcao: () {})));
    await t.tap(find.byKey(const Key('dizer')));
    await t.pump(const Duration(seconds: 9));
    expect(find.text('Apagado'), findsNothing);
  });

  testWidgets('fora da TelaPrincipal cai numa SnackBar', (t) async {
    var feito = 0;
    await t.pumpWidget(MaterialApp(
        home: _Ecra((c) => mostrarMensagem(c, 'Sozinha', acao: 'Desfazer', aoAcao: () => feito++))));
    await t.tap(find.byKey(const Key('dizer')));
    await t.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Sozinha'), findsOneWidget);
    await t.pump(const Duration(seconds: 1)); // a SnackBar acaba de entrar
    await t.tap(find.text('Desfazer'));
    await t.pump();
    expect(feito, 1);
  });

  testWidgets('BarraTeclas mostra a tecla e a ação', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: BarraTeclas([('OK', 'ver')]))));
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('ver'), findsOneWidget);
  });
}
