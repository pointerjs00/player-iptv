import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/edicao.dart';
import 'package:player_iptv/idioma/ingles.dart';
import 'package:player_iptv/tarefas/servico_tarefas.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/gestor/indicador_atividade.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/verificar/servico.dart';

/// A edição de partilha não tem a pesquisa de listas no blog do stbstalker. Estes testes só
/// correm com `flutter test --dart-define=PARTILHA=true test/edicao` (o empacotar.py fá-lo antes
/// de construir essa edição); na edição completa o stbstalker é testado nos outros testes.
void main() {
  const soNaPartilha = edicaoPartilha ? null : 'só na edição de partilha (--dart-define=PARTILHA=true)';

  test('a edição completa é a omissão', () {
    expect(edicaoPartilha, const bool.fromEnvironment('PARTILHA'));
  });

  group('edição de partilha', () {
    late Directory pasta;
    setUp(() => pasta = Directory.systemTemp.createTempSync('partilha'));
    tearDown(() {
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });

    testWidgets('o Gestor não fala do stbstalker nem do Telegram: nem no resumo nem nas origens', (t) async {
      t.view.physicalSize = const Size(1200, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      late Biblioteca bib;
      late AreaGestor area;
      await t.runAsync(() async {
        bib = await Biblioteca.abrir(pasta);
        area = await AreaGestor.abrir(pasta);
      });
      final tarefas = ServicoTarefas();
      addTearDown(tarefas.dispose);
      await t.pumpWidget(MaterialApp(
          theme: temaApp(),
          home: Scaffold(
              body: TelaGestor(biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area), tarefas: tarefas))));
      await t.pump();
      expect(find.textContaining('stbstalker'), findsNothing);
      expect(find.text('Ficheiros, texto ou de Ver TV'), findsOneWidget);

      await t.tap(find.descendant(of: find.byType(CartaoModerno), matching: find.text('Importar')));
      await t.pumpAndSettle();
      expect(find.text('Ficheiros'), findsWidgets);
      expect(find.text('Adicionar lista'), findsWidgets);
      expect(find.text('De Ver TV'), findsWidgets);
      expect(find.textContaining('stbstalker'), findsNothing);
      expect(find.textContaining('Telegram'), findsNothing);
    }, skip: soNaPartilha != null);

    test('o indicador da atividade ignora uma tarefa com o título do stbstalker', () async {
      final bib = await Biblioteca.abrir(pasta);
      final tarefas = ServicoTarefas();
      addTearDown(tarefas.dispose);
      tarefas.iniciar('$tituloTarefaStb · hoje', (p) => Future<String>.delayed(const Duration(days: 1), () => ''));
      final texto = IndicadorAtividade.texto(ServicoVerificacao(bib), tarefas);
      expect(texto, isNot(contains('stbstalker')));
      expect(texto, '1 tarefa a decorrer');
    }, skip: soNaPartilha);

    test('as traduções da importação automática não estão no pacote', () {
      expect(textosIngles.keys.where((k) => k.contains('stbstalker') || k.contains('Telegram')), isEmpty);
    }, skip: soNaPartilha);
  });
}
