import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/desporto/servico_jogos.dart';
import 'package:player_iptv/ui/design/escala_interface.dart';
import 'package:player_iptv/ui/jogos/folha_onde_ver.dart';
import 'package:player_iptv/ui/jogos/linha_jogo.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

import 'ajuda_dpad.dart';
import 'jogos_apoio.dart';

/// O ecrã «Jogos» na Android TV (960×540, a interface a 80 %), só com o comando.
void main() {
  late Montagem m;
  tearDown(() => arrumarJogos(m));

  Future<void> montar(WidgetTester t) async {
    ecraTvTeste(t);
    m = (await t.runAsync(prepararJogos))!;
    await t.pumpWidget(MaterialApp(
      theme: temaApp(),
      builder: (_, c) => TemaConformeRealce(child: EscalaInterface(escala: escalaCompacto, child: c!)),
      home: Scaffold(body: m.tela()),
    ));
    await t.pump();
  }

  /// O foco no chip «Filtros» (a fila de cima), e BAIXO até à primeira linha.
  Future<void> irParaPrimeiro(WidgetTester t) async {
    Focus.of(t.element(find.text('Filtros'))).requestFocus();
    await t.pump();
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
  }

  LinhaJogoState linha(String casa) =>
      tFind<LinhaJogoState>(find.ancestor(of: find.text(casa).first, matching: find.byType(LinhaJogo)));

  testWidgets('a 960×540 a 80 % veem-se pelo menos 5 jogos inteiros', (t) async {
    await montar(t);
    final ecra = t.view.physicalSize;
    final inteiras = find.byType(LinhaJogo).evaluate().where((e) {
      final r = t.getRect(find.byWidget(e.widget));
      return r.top >= 0 && r.bottom <= ecra.height;
    });
    expect(inteiras.length, greaterThanOrEqualTo(5));
    expect(t.takeException(), isNull, reason: 'nada transborda');
  });

  testWidgets('BAIXO percorre os jogos, uma paragem por linha, e passa os títulos das competições', (t) async {
    await montar(t);
    await irParaPrimeiro(t);
    expect(textosFocados(), contains('Marítimo'));
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Benfica'));
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Moreirense'));
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(textosFocados(), contains('Benfica'));
    // até ao fim da Liga Portugal e para o bloco seguinte (o título não recebe o foco)
    for (var i = 0; i < 4; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    }
    expect(textosFocados(), contains('Famalicão'));
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Arsenal'));
  });

  testWidgets('←/→ escolhem a etiqueta; OK abre o «Onde ver» dela; BACK fecha e o foco volta à linha', (t) async {
    await montar(t);
    await irParaPrimeiro(t);
    expect(linha('Marítimo').etiqueta, 0);
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(linha('Marítimo').etiqueta, 1);
    expect(textosFocados(), contains('Marítimo'), reason: 'o foco fica na linha');
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(linha('Marítimo').etiqueta, 1, reason: 'não passa da última');
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(FolhaOndeVer), findsOneWidget);
    expect(find.text('Onde ver: Sport TV 2'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(FolhaOndeVer), findsNothing);
    expect(textosFocados(), contains('Marítimo'));
    expect(linha('Marítimo').etiqueta, 1, reason: 'a etiqueta escolhida mantém-se');
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(linha('Marítimo').etiqueta, 0);
  });

  testWidgets('no «Onde ver», OK na primeira fonte abre-a no player', (t) async {
    await montar(t);
    await irParaPrimeiro(t);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(textosFocados(), contains('Lista 1'), reason: 'o foco começa na primeira fonte');
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(FolhaOndeVer), findsNothing);
    expect(m.abertas.single.map((f) => f.lista.id), ['1', '2']);
  });

  testWidgets('OK mantido faz «▶ Ver» (todas as fontes do jogo)', (t) async {
    await montar(t);
    await irParaPrimeiro(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.select);
    await t.pump(const Duration(milliseconds: 600));
    await t.sendKeyUpEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(FolhaOndeVer), findsNothing, reason: 'o OK longo não abre o «Onde ver»');
    expect(m.abertas.single.map((f) => f.canalTv), ['sporttv1', 'sporttv1', 'sporttv2']);
  });

  // ---- a pesquisa por equipa e os controlos de cima ----

  EditableText campo(WidgetTester t) => t.widget<EditableText>(find.byType(EditableText));

  Future<void> focarPesquisa(WidgetTester t) async {
    campo(t).focusNode.requestFocus();
    await t.pump();
  }

  /// O foco não se perdeu (está num controlo, não só no âmbito da página).
  void comFoco() {
    final f = FocusManager.instance.primaryFocus;
    expect(f == null || f is FocusScopeNode, isFalse, reason: 'o foco perdeu-se');
  }

  testWidgets('a pesquisa com o foco não abre o teclado; BAIXO, DIREITA saem; OK escreve e Voltar acaba', (t) async {
    await montar(t);
    await focarPesquisa(t);
    expect(campo(t).readOnly, isTrue, reason: 'só com o foco fica só de leitura');
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(campo(t).focusNode.hasFocus, isFalse, reason: 'BAIXO sai do campo');
    comFoco();

    await focarPesquisa(t);
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), 'Competições', reason: 'DIREITA vai ao botão ao lado');
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), 'Atualizar');

    await focarPesquisa(t);
    await teclaDpad(t, LogicalKeyboardKey.select);
    expect(campo(t).readOnly, isFalse, reason: 'OK começa a escrever');
    await t.enterText(find.byType(EditableText), 'benf');
    await t.pump();
    expect(find.text('Benfica'), findsWidgets);
    expect(find.text('Marítimo'), findsNothing);
    await teclaDpad(t, LogicalKeyboardKey.escape);
    expect(campo(t).readOnly, isTrue, reason: 'Voltar acaba a edição');
    expect(campo(t).focusNode.hasFocus, isTrue);
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(campo(t).focusNode.hasFocus, isFalse);
    comFoco();
  });

  testWidgets('«Dia anterior» no primeiro dia fica com o foco', (t) async {
    await montar(t);
    Focus.of(t.element(find.descendant(of: find.byTooltip('Dia anterior'), matching: find.byType(Icon)))).requestFocus();
    await t.pump();
    await teclaDpad(t, LogicalKeyboardKey.select); // hoje → ontem (o primeiro)
    await teclaDpad(t, LogicalKeyboardKey.select); // já no primeiro: não faz nada
    expect(textosFocados(), 'Dia anterior');
    expect(m.servico.cargas.length, 1);
  });

  testWidgets('«Hoje» desaparece ao carregar nele: o foco fica ao lado', (t) async {
    await montar(t);
    Focus.of(t.element(find.descendant(of: find.byTooltip('Dia seguinte'), matching: find.byType(Icon)))).requestFocus();
    await t.pump();
    await teclaDpad(t, LogicalKeyboardKey.select); // amanhã: aparece «Hoje»
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), 'Hoje');
    await teclaDpad(t, LogicalKeyboardKey.select);
    expect(find.text('Hoje'), findsNothing);
    comFoco();
    expect(textosFocados(), 'Dia seguinte');
  });

  testWidgets('«Atualizar» a carregar continua com o foco', (t) async {
    await montar(t);
    Focus.of(t.element(find.byIcon(Icons.refresh_rounded))).requestFocus();
    await t.pump();
    m.servico.definir(hojeJogos, jogosTeste(), estado: const EstadoJogos(carga: Carga.aCarregar));
    await t.pump();
    expect(textosFocados(), 'Atualizar');
  });

  testWidgets('«Limpar a pesquisa» do ecrã vazio: o foco não se perde', (t) async {
    await montar(t);
    await focarPesquisa(t);
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.enterText(find.byType(EditableText), 'zzz');
    await teclaDpad(t, LogicalKeyboardKey.escape);
    Focus.of(t.element(find.text('Limpar a pesquisa'))).requestFocus();
    await t.pump();
    await teclaDpad(t, LogicalKeyboardKey.select);
    expect(find.text('Marítimo'), findsWidgets);
    comFoco();
  });

  testWidgets('o jogo com o foco sai da lista (dados novos): o foco passa a outro jogo', (t) async {
    await montar(t);
    await irParaPrimeiro(t);
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Benfica'));
    m.servico.definir(hojeJogos, [for (final j in jogosTeste()) if (j.jogo.casa != 'Benfica') j]);
    await t.pump();
    await t.pump();
    comFoco();
    expect(textosFocados(), anyOf(contains('Marítimo'), contains('Moreirense')), reason: 'o foco está no jogo ao lado');
  });
}

T tFind<T extends State>(Finder f) => (f.evaluate().single as StatefulElement).state as T;
