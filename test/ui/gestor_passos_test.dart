import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/tarefas/servico_tarefas.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/gestor/passo_verificar.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/principal/barra_seccoes.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/verificar/servico.dart';

import 'ajuda_dpad.dart';

/// O Gestor em 3 passos (Importar → Verificar → Exportar), a partir do resumo, só com o comando.


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

  TelaGestor telaGestor() => TelaGestor(
      biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area), tarefas: ServicoTarefas());

  /// A app: Ver TV (vazio) e o Gestor nas secções da casca.
  Widget casca() =>
      TelaPrincipal(verTv: TelaInicio(biblioteca: bib, area: area), gestor: telaGestor(), definicoes: const SizedBox());

  /// Só com setas: de "Ir para o Gestor" (Ver TV vazio) ESQUERDA até à barra, BAIXO, OK.
  Future<void> aoGestor(WidgetTester t) async {
    expect(textosFocados(), 'Ir para o Gestor');
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(textosFocados(), 'Ver TV');
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), 'Gestor');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.text('Gestor de listas').hitTestable(), findsOneWidget);
  }

  Widget gestor() => Scaffold(body: telaGestor());

  /// O cartão do passo com este nome (no resumo).
  Finder passo(String nome) => find.ancestor(of: find.text(nome), matching: find.byType(CartaoModerno));

  /// Abre um passo com um toque no seu cartão do resumo.
  Future<void> abrir(WidgetTester t, String nome) async {
    await t.tap(find.descendant(of: passo(nome), matching: find.text(nome)));
    await t.pumpAndSettle();
  }

  testWidgets('o resumo: três passos numerados, cada um com o seu estado; as marcadas ficam no passo 3', (t) async {
    ecraTvTeste(t);
    t.view.physicalSize = const Size(1200, 2400);
    await comListas(t);
    await t.pumpWidget(appTeste(gestor()));
    await t.pump();
    for (final (n, nome) in [(1, 'Importar'), (2, 'Verificar'), (3, 'Exportar')]) {
      expect(find.descendant(of: passo(nome), matching: find.text('$n')), findsWidgets, reason: nome);
    }
    expect(find.text('5 listas no Gestor · escolhe por onde começar'), findsOneWidget);
    // passo 2: 1 por verificar, 2 funcionam, 1 não funciona; passo 3: 2 prontas a enviar
    expect(find.descendant(of: passo('Verificar'), matching: find.text('1')), findsNWidgets(2), reason: 'por verificar e não funciona');
    expect(find.descendant(of: passo('Verificar'), matching: find.text('2')), findsNWidgets(2), reason: 'o n.º e as que funcionam');
    expect(find.descendant(of: passo('Exportar'), matching: find.text('2')), findsOneWidget);
    await abrir(t, 'Exportar');
    expect(find.text('0 marcadas · OK marca/desmarca uma lista'), findsOneWidget);
    await t.ensureVisible(find.text('Funcionam (2)'));
    await t.tap(find.text('Funcionam (2)'));
    await t.pump();
    expect(find.text('2 marcadas · OK marca/desmarca uma lista'), findsOneWidget);
    // ao passo 2 e de volta pela faixa: as marcadas ficam
    await t.tap(find.text('2 · Verificar'));
    await t.pumpAndSettle();
    await t.tap(find.text('3 · Exportar'));
    await t.pumpAndSettle();
    expect(find.text('2 marcadas · OK marca/desmarca uma lista'), findsOneWidget);
  });

  testWidgets('entrar no passo 3 só com listas «Por verificar»: o foco fica em «Por verificar (N)»', (t) async {
    ecraTvTeste(t);
    t.view.physicalSize = const Size(1200, 2400);
    await t.runAsync(() => area.adicionar([
          Importada(contaDeLinha('http://a.com/l.m3u')!),
          Importada(contaDeLinha('http://b.com/l.m3u')!),
        ]));
    await t.pumpWidget(appTeste(gestor()));
    await t.pump();
    await abrir(t, 'Exportar');
    expect(find.text('Funcionam (0)'), findsOneWidget);
    expect(textosFocados(), 'Por verificar (2)');
  });

  testWidgets('Gestor vazio: os passos 2 e 3 dizem o que falta', (t) async {
    ecraTvTeste(t);
    t.view.physicalSize = const Size(1200, 2400);
    await t.pumpWidget(appTeste(gestor()));
    await t.pump();
    expect(find.text('0 listas no Gestor · escolhe por onde começar'), findsOneWidget);
    expect(find.text('Importe listas primeiro'), findsNWidgets(2));
  });

  testWidgets('os resultados filtram-se pelo estado (com o comando)', (t) async {
    ecraTvTeste(t);
    t.view.physicalSize = const Size(1200, 2400);
    await comListas(t);
    await t.pumpWidget(appTeste(gestor()));
    await t.pump();
    await abrir(t, 'Verificar');
    for (final c in ['Funcionam · 2', 'Inconclusivas · 1', 'Não funcionam · 1', 'Por verificar · 1']) {
      expect(find.widgetWithText(FilterChip, c), findsOneWidget, reason: c);
    }
    expect(find.textContaining('Todas · '), findsNothing, reason: 'nenhum estado ligado = todas');
    expect(find.textContaining('003MEIA'), findsOneWidget);
    // Tab até ao filtro "Não funcionam" e OK
    for (var i = 0; i < 60 && !textosFocados().startsWith('Não funcionam · '); i++) {
      await teclaDpad(t, LogicalKeyboardKey.tab);
    }
    await teclaDpad(t, LogicalKeyboardKey.select);
    expect(find.textContaining('004MORTA'), findsOneWidget);
    expect(find.textContaining('003MEIA'), findsNothing);
    expect(find.textContaining('001BOA'), findsNothing);
    // com o comando liga-se outro estado: as duas juntas
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('Por verificar · '));
    await teclaDpad(t, LogicalKeyboardKey.select);
    expect(find.textContaining('004MORTA'), findsOneWidget);
    expect(find.textContaining('005NOVA'), findsOneWidget);
    expect(find.textContaining('001BOA'), findsNothing);
    await teclaDpad(t, LogicalKeyboardKey.select);
    expect(find.textContaining('005NOVA'), findsNothing);
    // BAIXO chega à linha que ficou (os estados e a ☐ do cabeçalho estão por cima)
    for (var i = 0; i < 4 && !textosFocados().contains('004MORTA'); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    }
    expect(textosFocados(), contains('004MORTA'));
  });

  testWidgets('na TV, só com setas: da barra das secções ao resumo, ao passo 2 e pelas listas abaixo, e volta acima',
      (t) async {
    ecraTvTeste(t);
    await comListas(t);
    await t.pumpWidget(appTeste(casca()));
    await t.pump();
    await aoGestor(t);
    // DIREITA entra no Gestor, no 1.º cartão; os cartões estão lado a lado
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('1 | Importar'));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('2 | Verificar'));
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    // no passo 2: BAIXO desce da linha de cima pela ☐ do cabeçalho e pelas linhas
    final descer = <String>[textosFocados()];
    final nos = <FocusNode?>[FocusManager.instance.primaryFocus];
    for (var i = 0; i < 40 && !descer.any((d) => d.contains('005NOVA')); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
      descer.add(textosFocados());
      nos.add(FocusManager.instance.primaryFocus);
      expect(nos.last, isNot(nos[nos.length - 2]), reason: 'BAIXO preso: $descer');
    }
    final caminho = descer.join(' / ');
    for (final v in ['001BOA', '005NOVA']) {
      expect(caminho, contains(v), reason: 'BAIXO: $caminho');
    }
    expect(nos.map((n) => n?.debugLabel), contains('Selecionar as visíveis'), reason: 'BAIXO: $caminho');
    // e CIMA sobe tudo: as linhas, a faixa, "Voltar" e a barra das secções
    // (a pesquisa e a ☐ do cabeçalho não têm texto: compara-se o nó com o foco)
    final subir = <String>[descer.last];
    final nosCima = <FocusNode?>[FocusManager.instance.primaryFocus];
    for (var i = 0; i < 40 && subir.last != 'Gestor'; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowUp);
      subir.add(textosFocados());
      nosCima.add(FocusManager.instance.primaryFocus);
      expect(nosCima.last, isNot(nosCima[nosCima.length - 2]), reason: 'CIMA preso: $subir');
    }
    expect(subir.last, 'Gestor', reason: 'CIMA: $subir');
    expect(subir, contains('1 · Importar | 2 · Verificar | 3 · Exportar'), reason: 'CIMA: $subir');
  });

  testWidgets('na TV: DIREITA alcança os cartões e os botões ao lado (as origens da importação, '
      'Enviar e Exportar...)', (t) async {
    // o Gestor com a largura de antes da barra lateral (960): as origens em grelha de 4
    ecraTvTeste(t, largura: 960 + BarraSeccoes.largura);
    await comListas(t);
    await t.pumpWidget(appTeste(casca()));
    await t.pump();
    await aoGestor(t);
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('1 | Importar'));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('2 | Verificar'));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('3 | Exportar'));
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(textosFocados(), startsWith('1 | Importar'));
    // no princípio da linha, ESQUERDA vai à barra das secções; DIREITA volta
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(textosFocados(), 'Gestor');
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('1 | Importar'));
    // OK no passo 1: o ecrã de importar, com o foco na 1.ª origem
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(textosFocados(), startsWith('Ficheiros'));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('Adicionar lista'));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('Listas do stbstalker'));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('Listas do Telegram'));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('De Ver TV'));
    for (var i = 0; i < 4; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    }
    expect(textosFocados(), startsWith('Ficheiros'));
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(textosFocados(), 'Gestor');
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('Ficheiros'));
    // BAIXO vai ao painel da origem escolhida
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), startsWith('Escolher ficheiros'));
    // CIMA passa pela faixa e chega ao "Voltar"; OK regressa ao resumo, no cartão 1
    final cima = <String>[];
    for (var i = 0; i < 6 && textosFocados() != 'Voltar'; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowUp);
      cima.add(textosFocados());
    }
    expect(textosFocados(), 'Voltar', reason: 'CIMA: $cima');
    expect(cima, contains('1 · Importar | 2 · Verificar | 3 · Exportar'), reason: 'CIMA: $cima');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(textosFocados(), startsWith('1 | Importar'));
    // o passo 2 abre na pesquisa; Voltar do comando regressa ao cartão 2
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(PassoVerificar).hitTestable(), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(textosFocados(), startsWith('2 | Verificar'));
    // o passo 3: OK no chip marca as que funcionam; DIREITA numa linha vai a "Enviar", BAIXO a "Exportar"
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(textosFocados(), startsWith('Funcionam (2)'));
    await teclaDpad(t, LogicalKeyboardKey.select);
    for (var i = 0; i < 6 && !textosFocados().contains('001BOA'); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    }
    expect(textosFocados(), contains('001BOA'));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), 'Enviar 2 listas');
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), 'Exportar 2 listas');
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(textosFocados(), contains('001BOA'));
  });

  testWidgets('com um filtro, a linha com o foco que muda de estado sai e o foco passa à seguinte', (t) async {
    ecraTvTeste(t);
    t.view.physicalSize = const Size(1200, 2400);
    await comListas(t);
    await t.pumpWidget(appTeste(gestor()));
    await t.pump();
    await abrir(t, 'Verificar');
    for (var i = 0; i < 60 && !textosFocados().startsWith('Funcionam · '); i++) {
      await teclaDpad(t, LogicalKeyboardKey.tab);
    }
    await teclaDpad(t, LogicalKeyboardKey.select);
    for (var i = 0; i < 4 && !textosFocados().contains('001BOA'); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    }
    expect(textosFocados(), contains('001BOA'));
    // a verificação de agora diz que deixou de funcionar
    await t.runAsync(() => area.registarVerificacao(area.listas.first.id, _u('nao_funciona')));
    await t.pump();
    await t.pump();
    expect(find.textContaining('001BOA'), findsNothing);
    expect(textosFocados(), contains('002OUTRA'), reason: 'o foco não se perde');
    // e sem nenhuma linha com esse estado, o foco vai a Ações
    await t.runAsync(() => area.registarVerificacao(area.listas[1].id, _u('nao_funciona')));
    await t.pump();
    await t.pump();
    expect(textosFocados(), startsWith('Ações (0)'));
  });

  testWidgets('tirar linhas (a focada, por filtro, Remover e Limpar) não dá exceções nem asserções',
      (t) async {
    ecraTvTeste(t, largura: 1200, altura: 2400);
    await comListas(t);
    await t.pumpWidget(appTeste(gestor()));
    await t.pump();
    // no passo 3, as marcadas que saem do Gestor saem das marcadas
    await abrir(t, 'Exportar');
    // (os chips de marcar vão numa só fila: com a letra dos testes, larga, os da direita deslizam)
    await t.ensureVisible(find.text('Todas (5)'));
    await t.tap(find.text('Todas (5)'));
    await t.pump();
    await t.tap(find.text('2 · Verificar'));
    await t.pumpAndSettle();
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
    // estados que escondem e mostram linhas (ligar e desligar)
    for (final c in ['Não funcionam · 1', 'Por verificar · 1', 'Não funcionam · 1', 'Por verificar · 1']) {
      await t.ensureVisible(find.widgetWithText(FilterChip, c));
      await t.pump();
      await t.tap(find.widgetWithText(FilterChip, c));
      await t.pump();
      await t.pump();
      expect(t.takeException(), isNull, reason: c);
    }
    // Remover do gestor (as que funcionam) e Limpar
    await t.ensureVisible(find.widgetWithText(FilterChip, 'Funcionam · 1'));
    await t.pump();
    await t.tap(find.widgetWithText(FilterChip, 'Funcionam · 1'));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('caixaCabecalho')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('botaoAcoes')));
    await t.pumpAndSettle();
    await t.tap(find.text('Remover do gestor'));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.widgetWithText(FilledButton, 'Remover'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(area.listas, hasLength(3));
    await t.tap(find.text('3 · Exportar'));
    await t.pumpAndSettle();
    expect(find.text('3 marcadas · OK marca/desmarca uma lista'), findsOneWidget, reason: 'as removidas saíram');
    await t.tap(find.text('1 · Importar'));
    await t.pumpAndSettle();
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
