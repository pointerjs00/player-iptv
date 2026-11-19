import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/principal/barra_seccoes.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/verificar/tela_verificar.dart';
import 'package:player_iptv/verificar/servico.dart';

import 'ajuda_dpad.dart';

/// O Gestor em 3 passos (Importar → Verificar → Enviar/Exportar), só com o comando.


UltimaVerificacao _u(String estado) =>
    UltimaVerificacao(estado: estado, data: DateTime(2026, 3, 1), validade: '2027-10-16');

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('gestor_passos');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Future<void> comListas(WidgetTester t) => t.runAsync(() => area.adicionar([
        Importada(contaDeLinha('http://boa.com/c/ 00:1A:79:00:00:01')!, _u('funciona')),
        Importada(contaDeLinha('http://outra.com/c/ 00:1A:79:00:00:02')!, _u('funciona')),
        Importada(contaDeLinha('http://meia.com/l.m3u')!, _u('inconclusivo')),
        Importada(contaDeLinha('http://morta.com/l.m3u')!, _u('nao_funciona')),
        Importada(contaDeLinha('http://nova.com/l.m3u')!),
      ]));

  /// A app: Ver TV (vazio) e o Gestor nas secções da casca.
  Widget casca() => TelaPrincipal(
      verTv: TelaInicio(biblioteca: bib, area: area),
      gestor: TelaVerificar(biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area)),
      definicoes: const SizedBox());

  /// Só com setas: de "Ir para o Gestor" (Ver TV vazio) ESQUERDA até à barra, BAIXO, OK.
  Future<void> aoGestor(WidgetTester t) async {
    expect(textosFocados(), 'Ir para o Gestor');
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(textosFocados(), 'Ver TV');
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), 'Gestor');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.text('Adicionar listas').hitTestable(), findsOneWidget);
  }

  Widget gestor() => Scaffold(
      body: TelaVerificar(biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area)));

  testWidgets('três passos numerados, cada um com o seu estado no cabeçalho', (t) async {
    ecraTvTeste(t);
    t.view.physicalSize = const Size(1200, 2400);
    await comListas(t);
    await t.pumpWidget(appTeste(gestor()));
    await t.pump();
    expect(find.text('1 · Importar'), findsOneWidget);
    expect(find.text('2 · Verificar'), findsOneWidget);
    expect(find.text('3 · Enviar / Exportar'), findsOneWidget);
    expect(find.text('5 listas no Gestor'), findsOneWidget);
    expect(find.text('2 a funcionar · 1 INC · 1 não funciona · 1 por verificar'), findsOneWidget);
    expect(find.text('Nenhuma selecionada'), findsOneWidget);
    await t.tap(find.widgetWithText(ActionChip, 'Funcionam'));
    await t.pump();
    expect(find.text('2 selecionadas'), findsOneWidget);
  });

  testWidgets('Gestor vazio: os passos 2 e 3 dizem o que falta', (t) async {
    ecraTvTeste(t);
    t.view.physicalSize = const Size(1200, 2400);
    await t.pumpWidget(appTeste(gestor()));
    await t.pump();
    expect(find.text('O Gestor está vazio'), findsOneWidget);
    expect(find.text('Importe listas primeiro'), findsNWidgets(2));
  });

  testWidgets('os resultados filtram-se pelo estado (com o comando)', (t) async {
    ecraTvTeste(t);
    t.view.physicalSize = const Size(1200, 2400);
    await comListas(t);
    await t.pumpWidget(appTeste(gestor()));
    await t.pump();
    for (final c in ['Todas (5)', 'Funcionam (2)', 'INC (1)', 'Não funcionam (1)', 'Por verificar (1)']) {
      expect(find.widgetWithText(ChoiceChip, c), findsOneWidget, reason: c);
    }
    expect(find.textContaining('003MEIA'), findsOneWidget);
    // Tab até ao filtro "Não funcionam" e OK
    for (var i = 0; i < 60 && !textosFocados().startsWith('Não funcionam ('); i++) {
      await teclaDpad(t, LogicalKeyboardKey.tab);
    }
    await teclaDpad(t, LogicalKeyboardKey.select);
    expect(find.textContaining('004MORTA'), findsOneWidget);
    expect(find.textContaining('003MEIA'), findsNothing);
    expect(find.textContaining('001BOA'), findsNothing);
    // BAIXO chega à linha que ficou
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('004MORTA'));
  });

  testWidgets('na TV, só com setas: da barra das secções desce por todos os passos até às listas e volta acima',
      (t) async {
    ecraTvTeste(t);
    await comListas(t);
    await t.pumpWidget(appTeste(casca()));
    await t.pump();
    await aoGestor(t);
    // DIREITA entra no Gestor, no 1.º controlo
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    final descer = <String>[textosFocados()];
    for (var i = 0; i < 40 && !descer.any((d) => d.contains('005NOVA')); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
      descer.add(textosFocados());
      if (descer.length > 1) {
        expect(descer.last, isNot(descer[descer.length - 2]), reason: 'BAIXO preso: $descer');
      }
    }
    expect(descer.first, startsWith('Adicionar listas'), reason: 'o 1.º passo começa por adicionar: $descer');
    final caminho = descer.join(' / ');
    for (final v in ['Limpar o Gestor', '/20', 'Verificar todas', 'Funcionam', 'Enviar para o Player', 'Accounts.json',
      'Ficheiros .ini', 'Exportar', 'Todas (5)', '001BOA', '005NOVA']) {
      expect(caminho, contains(v), reason: 'BAIXO: $caminho');
    }
    final subir = <String>[descer.last];
    // os vizinhos da direita alcançam-se com DIREITA (e ESQUERDA volta)
    for (var i = 0; i < 40 && subir.last != 'Gestor'; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowUp);
      subir.add(textosFocados());
      expect(subir.last, isNot(subir[subir.length - 2]), reason: 'CIMA preso: $subir');
    }
    expect(subir.last, 'Gestor', reason: 'CIMA: $subir');
  });

  testWidgets('na TV: DIREITA alcança os botões ao lado (Importar do Player, Iniciar pesquisa, Esmagar...)',
      (t) async {
    // o Gestor com a largura de antes da barra lateral (960): as datas e "Iniciar pesquisa" na
    // mesma linha (a 960 com a barra, o botão passa à linha de baixo e chega-se lá com BAIXO)
    ecraTvTeste(t, largura: 960 + BarraSeccoes.largura);
    await comListas(t);
    await t.pumpWidget(appTeste(casca()));
    await t.pump();
    await aoGestor(t);
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('Adicionar listas'));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('Importar do Player'));
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(textosFocados(), startsWith('Adicionar listas'));
    // no princípio da linha, ESQUERDA vai à barra das secções; DIREITA volta
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(textosFocados(), 'Gestor');
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('Adicionar listas'));
    for (var i = 0; i < 6 && !textosFocados().contains('/20'); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    }
    final direita = <String>[];
    for (var i = 0; i < 3; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
      direita.add(textosFocados());
    }
    expect(direita.join(' / '), contains('Iniciar pesquisa'), reason: '$direita');
    // e o 2.º passo: "Verificar todas" → (as selecionadas estão desligadas sem seleção)
    for (var i = 0; i < 6 && !textosFocados().startsWith('Verificar todas'); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    }
    expect(textosFocados(), startsWith('Verificar todas'));
    for (var i = 0; i < 6 && !textosFocados().startsWith('Enviar para o Player'); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    }
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('Remover do Gestor'));
  });

  testWidgets('com um filtro, a linha com o foco que muda de estado sai e o foco passa à seguinte', (t) async {
    ecraTvTeste(t);
    t.view.physicalSize = const Size(1200, 2400);
    await comListas(t);
    await t.pumpWidget(appTeste(gestor()));
    await t.pump();
    for (var i = 0; i < 60 && !textosFocados().startsWith('Funcionam ('); i++) {
      await teclaDpad(t, LogicalKeyboardKey.tab);
    }
    await teclaDpad(t, LogicalKeyboardKey.select);
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('001BOA'));
    // a verificação de agora diz que deixou de funcionar
    await t.runAsync(() => area.registarVerificacao(area.listas.first.id, _u('nao_funciona')));
    await t.pump();
    await t.pump();
    expect(find.textContaining('001BOA'), findsNothing);
    expect(textosFocados(), contains('002OUTRA'), reason: 'o foco não se perde');
    // e sem nenhuma linha no filtro, o foco fica no filtro
    await t.runAsync(() => area.registarVerificacao(area.listas[1].id, _u('nao_funciona')));
    await t.pump();
    await t.pump();
    expect(textosFocados(), startsWith('Funcionam (0)'));
  });

  testWidgets('tirar linhas (a focada, por filtro, Remover do Gestor e Limpar) não dá exceções nem asserções',
      (t) async {
    ecraTvTeste(t, largura: 1200, altura: 2400);
    await comListas(t);
    await t.pumpWidget(appTeste(gestor()));
    await t.pump();
    // a linha focada é removida do Gestor
    for (var i = 0; i < 60 && !textosFocados().contains('001BOA'); i++) {
      await teclaDpad(t, LogicalKeyboardKey.tab);
    }
    expect(textosFocados(), contains('001BOA'));
    await t.runAsync(() => area.remover([area.listas.first.id]));
    await t.pump();
    await t.pump();
    expect(t.takeException(), isNull);
    expect(textosFocados(), contains('002OUTRA'), reason: 'o foco passa à linha seguinte');
    // filtros que escondem e mostram linhas
    for (final c in ['Não funcionam (1)', 'Por verificar (1)', 'Todas (4)']) {
      await t.tap(find.widgetWithText(ChoiceChip, c));
      await t.pump();
      await t.pump();
      expect(t.takeException(), isNull, reason: c);
    }
    // Remover do Gestor (as que funcionam) e Limpar
    await t.tap(find.widgetWithText(ActionChip, 'Funcionam'));
    await t.pump();
    await t.tap(find.textContaining('Remover do Gestor'));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.widgetWithText(FilledButton, 'Remover'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(area.listas, hasLength(3));
    await t.tap(find.text('Limpar o Gestor'));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.widgetWithText(FilledButton, 'Limpar'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(area.listas, isEmpty);
    // e fechar o ecrã depois disto tudo
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });
}
