import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/player/painel_definicoes.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

Future<void> _montar(WidgetTester t, List<ItemDefinicao> Function() itens) async {
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
  t.view.physicalSize = const Size(1920, 1080);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: temaApp(),
    builder: (_, c) => TemaConformeRealce(child: c!),
    home: Scaffold(body: StatefulBuilder(builder: (_, setState) => PainelDefinicoes(itens: itens()))),
  ));
  await t.pumpAndSettle();
}

String? _focado() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  final linha = ctx.findAncestorWidgetOfExactType<LinhaDefinicao>();
  return linha?.item.titulo;
}

void main() {
  testWidgets('o primeiro item fica com o foco; cima/baixo andam pelos itens', (t) async {
    await _montar(t, () => [
          DefinicaoInterruptor('Desentrelaçamento', valor: true, aoMudar: (_) {}),
          DefinicaoEscolha('Formato de imagem', opcoes: const ['Ajustar', 'Zoom'], atual: 0, aoMudar: (_) {}),
        ]);
    expect(_focado(), 'Desentrelaçamento');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(_focado(), 'Formato de imagem');
  });

  testWidgets('escolha: direita/OK passam à opção seguinte (dá a volta), esquerda à anterior', (t) async {
    final escolhas = <int>[];
    await _montar(t, () => [
          DefinicaoEscolha('Formato de imagem',
              opcoes: const ['Ajustar', 'Preencher', 'Zoom'], atual: 0, aoMudar: escolhas.add),
        ]);
    expect(find.text('Ajustar'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    expect(escolhas, [1, 2, 1]);
  });

  testWidgets('interruptor: OK troca; esquerda desliga, direita liga', (t) async {
    final valores = <bool>[];
    await _montar(t, () => [DefinicaoInterruptor('Silêncio', valor: false, aoMudar: valores.add)]);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    expect(valores, [true, true, false]);
  });

  testWidgets('passos: esquerda/direita (volume, atraso do áudio)', (t) async {
    final passos = <int>[];
    await _montar(t, () => [
          DefinicaoPassos('Volume', valor: '80', menos: () => passos.add(-1), mais: () => passos.add(1)),
        ]);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    expect(passos, [1, -1, -1]);
    expect(find.text('80'), findsOneWidget);
  });

  testWidgets('um item sem efeito aparece desligado, com a explicação, e o foco salta-o', (t) async {
    await _montar(t, () => [
          DefinicaoInterruptor('Desentrelaçamento',
              valor: false, nota: 'Na descodificação direta o aparelho trata disso.'),
          DefinicaoEscolha('Formato de imagem', opcoes: const ['Ajustar', 'Zoom'], atual: 0, aoMudar: (_) {}),
        ]);
    expect(find.text('Na descodificação direta o aparelho trata disso.'), findsOneWidget);
    expect(_focado(), 'Formato de imagem');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(_focado(), 'Formato de imagem');
  });

  testWidgets('ação (ex.: estatísticas) corre com OK e com toque', (t) async {
    var n = 0;
    await _montar(t, () => [DefinicaoAcao('Informação do stream', valor: 'Mostrar', aoCarregar: () => n++)]);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.tap(find.text('Informação do stream'));
    await t.pump();
    expect(n, 2);
  });

  testWidgets('o item focado mostra o realce (borda de foco) no modo do comando', (t) async {
    await _montar(t, () => [DefinicaoInterruptor('Silêncio', valor: false, aoMudar: (_) {})]);
    final moldura = t.widget<MolduraFoco>(find.ancestor(of: find.text('Silêncio'), matching: find.byType(MolduraFoco)));
    expect(moldura.focado, isTrue);
  });
}
