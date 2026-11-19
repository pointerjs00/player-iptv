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
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/principal/barra_seccoes.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/verificar/servico.dart';

import 'ajuda_dpad.dart';

/// O Gestor em 3 passos (Importar → Verificar → Enviar ou exportar), só com o comando.


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

  /// BAIXO a partir de um filtro até sair dos filtros (na TV ocupam duas linhas).
  Future<void> baixoAteAsListas(WidgetTester t) async {
    for (var i = 0; i < 3 && textosFocados().contains(' · '); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    }
  }

  /// O cartão do passo com este nome.
  Finder passo(String nome) => find.ancestor(of: find.text(nome), matching: find.byType(CartaoModerno));

  testWidgets('três passos numerados, sempre à vista, cada um com o seu estado', (t) async {
    ecraTvTeste(t);
    t.view.physicalSize = const Size(1200, 2400);
    await comListas(t);
    await t.pumpWidget(appTeste(gestor()));
    await t.pump();
    for (final (n, nome) in [(1, 'Importar'), (2, 'Verificar'), (3, 'Enviar ou exportar')]) {
      expect(find.descendant(of: passo(nome), matching: find.text('$n')), findsOneWidget, reason: nome);
    }
    expect(find.descendant(of: passo('Importar'), matching: find.text('5 listas no Gestor')), findsOneWidget);
    expect(find.text('2 funcionam · 1 inconclusiva · 1 não funciona · 1 por verificar'), findsOneWidget);
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
    for (final c in ['Todas · 5', 'Funcionam · 2', 'Inconclusivas · 1', 'Não funcionam · 1', 'Por verificar · 1']) {
      expect(find.widgetWithText(ChoiceChip, c), findsOneWidget, reason: c);
    }
    expect(find.textContaining('003MEIA'), findsOneWidget);
    // Tab até ao filtro "Não funcionam" e OK
    for (var i = 0; i < 60 && !textosFocados().startsWith('Não funcionam · '); i++) {
      await teclaDpad(t, LogicalKeyboardKey.tab);
    }
    await teclaDpad(t, LogicalKeyboardKey.select);
    expect(find.textContaining('004MORTA'), findsOneWidget);
    expect(find.textContaining('003MEIA'), findsNothing);
    expect(find.textContaining('001BOA'), findsNothing);
    // BAIXO chega à linha que ficou (os filtros podem ocupar duas linhas na TV)
    await baixoAteAsListas(t);
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
    expect(descer.first, startsWith('1 | Importar'), reason: 'começa no 1.º passo: $descer');
    final caminho = descer.join(' / ');
    for (final v in ['Todas · 5', 'Funcionam', 'Verificar (entra na fila)', '001BOA', '005NOVA']) {
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

  testWidgets('na TV: DIREITA alcança os passos e os botões ao lado (as origens da importação, '
      'Exportar...)', (t) async {
    // o Gestor com a largura de antes da barra lateral (960): as quatro origens na mesma linha
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
    expect(textosFocados(), startsWith('3 | Enviar ou exportar'));
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(textosFocados(), startsWith('1 | Importar'));
    // no princípio da linha, ESQUERDA vai à barra das secções; DIREITA volta
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(textosFocados(), 'Gestor');
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('1 | Importar'));
    // OK no passo 1: o sub-ecrã de importar, com o foco na 1.ª origem
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(textosFocados(), startsWith('Ficheiros'));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('Colar texto'));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('Listas do stbstalker'));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('Do Player'));
    for (var i = 0; i < 3; i++) {
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
    // CIMA chega ao "Voltar" e OK regressa ao passo 1
    for (var i = 0; i < 6 && textosFocados() != 'Voltar'; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    }
    expect(textosFocados(), 'Voltar');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(textosFocados(), startsWith('1 | Importar'));
    // o passo 2: "Verificar todas"; Voltar do comando regressa ao passo 2
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(textosFocados(), startsWith('Verificar todas'));
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(textosFocados(), startsWith('2 | Verificar'));
    // a barra das selecionadas: "Verificar (entra na fila)" → "Enviar para o Player" → "Exportar" → "Remover"
    for (var i = 0; i < 8 && !textosFocados().startsWith('Verificar ('); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    }
    for (var i = 0; i < 4 && !textosFocados().startsWith('Verificar ('); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    }
    expect(textosFocados(), startsWith('Verificar (entra na fila)'));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), startsWith('Enviar para o Player'));
    // na TV a barra ocupa duas linhas: BAIXO e ESQUERDA chegam a "Exportar" e "Remover"
    final resto = <String>{};
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    resto.add(textosFocados());
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    resto.add(textosFocados());
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    resto.add(textosFocados());
    expect(resto, containsAll(['Exportar', 'Remover']), reason: '$resto');
  });

  testWidgets('com um filtro, a linha com o foco que muda de estado sai e o foco passa à seguinte', (t) async {
    ecraTvTeste(t);
    t.view.physicalSize = const Size(1200, 2400);
    await comListas(t);
    await t.pumpWidget(appTeste(gestor()));
    await t.pump();
    for (var i = 0; i < 60 && !textosFocados().startsWith('Funcionam · '); i++) {
      await teclaDpad(t, LogicalKeyboardKey.tab);
    }
    await teclaDpad(t, LogicalKeyboardKey.select);
    await baixoAteAsListas(t);
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
    expect(textosFocados(), startsWith('Funcionam · 0'));
  });

  testWidgets('tirar linhas (a focada, por filtro, Remover e Limpar) não dá exceções nem asserções',
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
    for (final c in ['Não funcionam · 1', 'Por verificar · 1', 'Todas · 4']) {
      await t.tap(find.widgetWithText(ChoiceChip, c));
      await t.pump();
      await t.pump();
      expect(t.takeException(), isNull, reason: c);
    }
    // Remover do Gestor (as que funcionam) e Limpar
    await t.tap(find.widgetWithText(ActionChip, 'Funcionam'));
    await t.pump();
    await t.tap(find.widgetWithText(OutlinedButton, 'Remover'));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.widgetWithText(FilledButton, 'Remover'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(area.listas, hasLength(3));
    await t.tap(find.descendant(of: passo('Importar'), matching: find.text('Importar')));
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
