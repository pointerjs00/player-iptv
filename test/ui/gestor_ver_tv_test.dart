import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/tarefas/servico_tarefas.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/verificar/servico.dart';

import 'ajuda_dpad.dart';

/// No Gestor, «Ver TV» é o nome do antigo «Player». Fica «Player IPTV» (a app) e «Stalker Portal
/// Player» (produto externo); qualquer outro «Player» visível é um resto por trocar.
final _resto = RegExp(r'(?<!Stalker Portal )Player(?! IPTV)');

/// Todos os textos visíveis: Text, tooltips e etiquetas de acessibilidade.
List<String> _textos(WidgetTester t) {
  final r = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    r.add(w.data ?? w.textSpan?.toPlainText() ?? '');
  }
  for (final e in find.byType(Tooltip).evaluate()) {
    r.add((e.widget as Tooltip).message ?? '');
  }
  for (final e in find.byType(Semantics).evaluate()) {
    r.add((e.widget as Semantics).properties.label ?? '');
  }
  return r;
}

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;
  late ServicoTarefas tarefas;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('gestor_ver_tv');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
    tarefas = ServicoTarefas();
  });
  tearDown(() {
    tarefas.dispose();
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  void semPlayer(WidgetTester t, String onde) {
    final maus = _textos(t).where(_resto.hasMatch).toList();
    expect(maus, isEmpty, reason: 'em $onde: $maus');
  }

  Finder cartao(String titulo) => find.ancestor(of: find.text(titulo), matching: find.byType(CartaoModerno));

  Future<void> espera(WidgetTester t) async {
    for (var i = 0; i < 100 && tarefas.recentes.isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
  }

  testWidgets('nenhum texto visível do Gestor diz «Player» (resumo, importar, enviar, diálogo, mensagens)',
      (t) async {
    ecraTvTeste(t, largura: 1400, altura: 1400);
    await t.runAsync(() => bib.adicionar([Importada(contaDeLinha('http://p.com/l.m3u')!)]));
    await t.runAsync(() => area.adicionar([
          Importada(contaDeLinha('http://a.com/l.m3u')!,
              UltimaVerificacao(estado: 'funciona', data: DateTime(2026, 3, 1))),
          Importada(contaDeLinha('http://b.com/l.m3u')!,
              UltimaVerificacao(estado: 'funciona', data: DateTime(2026, 3, 1))),
        ]));
    await t.pumpWidget(appTeste(Scaffold(
        body: TelaGestor(
            biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area), tarefas: tarefas))));
    await t.pump();
    semPlayer(t, 'resumo');
    expect(find.text('Em Ver TV'), findsOneWidget);

    await t.tap(cartao('Importar'));
    await t.pumpAndSettle();
    semPlayer(t, 'importar');
    await t.tap(find.text('De Ver TV'));
    await t.pumpAndSettle();
    semPlayer(t, 'importar de Ver TV');
    expect(find.text('Importar de Ver TV'), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.text('Importar de Ver TV'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await espera(t);
    await t.pump();
    semPlayer(t, 'importar, depois de importar');
    expect(tarefas.recentes.map((x) => x.resultado ?? '').where(_resto.hasMatch), isEmpty);
  });

  testWidgets('enviar: passo, diálogo e mensagens de fim sem «Player»', (t) async {
    ecraTvTeste(t, largura: 1400, altura: 1400);
    await t.runAsync(() => area.adicionar([
          Importada(contaDeLinha('http://a.com/l.m3u')!,
              UltimaVerificacao(estado: 'funciona', data: DateTime(2026, 3, 1))),
        ]));
    await t.pumpWidget(appTeste(Scaffold(
        body: TelaGestor(
            biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area), tarefas: tarefas))));
    await t.pump();
    await t.tap(cartao('Enviar ou exportar'));
    await t.pumpAndSettle();
    semPlayer(t, 'passo enviar');
    await t.tap(find.text('Funcionam (1)'));
    await t.pump();
    semPlayer(t, 'passo enviar, marcadas');
    await t.tap(find.widgetWithText(FilledButton, 'Enviar 1 lista'));
    await t.pumpAndSettle();
    semPlayer(t, 'diálogo de envio');
    expect(find.text('Enviar 1 lista para Ver TV'), findsOneWidget);
    await t.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Enviar 1 lista')));
    await espera(t);
    await t.pump();
    final resultado = tarefas.recentes.first.resultado ?? '';
    expect(resultado, '1 lista enviada para Ver TV · 1 nova');
    expect(_resto.hasMatch(resultado), isFalse);
    semPlayer(t, 'depois de enviar');
  });

  testWidgets('verificar, confirmar remover e confirmar limpar sem «Player»', (t) async {
    ecraTvTeste(t, largura: 1400, altura: 1400);
    await t.runAsync(() => area.adicionar([
          Importada(contaDeLinha('http://a.com/l.m3u')!,
              UltimaVerificacao(estado: 'funciona', data: DateTime(2026, 3, 1))),
        ]));
    await t.pumpWidget(appTeste(Scaffold(
        body: TelaGestor(
            biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area), tarefas: tarefas))));
    await t.pump();
    await t.tap(cartao('Verificar'));
    await t.pumpAndSettle();
    semPlayer(t, 'passo verificar');
    await t.tap(find.byKey(const ValueKey('caixaCabecalho')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('botaoAcoes')));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byWidgetPredicate((w) => w is PopupMenuItem), matching: find.text('Remover do gestor')));
    await t.pumpAndSettle();
    expect(find.text('Remover do Gestor?'), findsOneWidget);
    semPlayer(t, 'confirmar remover');
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();

    await t.tap(find.widgetWithText(TextButton, 'Voltar'));
    await t.pumpAndSettle();
    await t.tap(cartao('Importar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Limpar o Gestor'));
    await t.pumpAndSettle();
    expect(find.text('Limpar o Gestor?'), findsOneWidget);
    semPlayer(t, 'confirmar limpar');
  });
}
