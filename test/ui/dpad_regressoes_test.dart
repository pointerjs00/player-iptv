import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/definicoes/tela_definicoes.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/player/painel_definicoes.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

/// Regressões do feedback 1 (Android TV): tudo só com teclas (setas, OK, Voltar).

Widget _app(Widget w) =>
    MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

/// Android TV 1080p: 960×540 lógicos, tamanhos de TV, realce sempre ligado.
void _tv(WidgetTester t, {double largura = 960, double altura = 540}) {
  t.view.physicalSize = Size(largura, altura);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  EcraTv.nativo = true;
  addTearDown(() => EcraTv.nativo = false);
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
}

/// Os textos dentro do widget com o foco.
String _focado() {
  final no = FocusManager.instance.primaryFocus;
  final ctx = no?.context;
  if (ctx == null || no is FocusScopeNode) return '';
  final textos = <String>[];
  void visitar(Element e) {
    final w = e.widget;
    if (w is Text) textos.add(w.data ?? '');
    e.visitChildren(visitar);
  }

  (ctx as Element).visitChildren(visitar);
  if (textos.isEmpty) {
    final dica = ctx.findAncestorWidgetOfExactType<Tooltip>()?.message;
    if (dica != null) textos.add(dica);
  }
  return textos.join(' | ');
}

Future<void> _tecla(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300)); // o scroll até ao foco
}

void main() {
  late Directory pasta;
  late Biblioteca bib;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('dpad');
    bib = await Biblioteca.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  group('Início (Player): a grelha de listas', () {
    Future<void> comListas(WidgetTester t, int n) async {
      await t.runAsync(() => bib.adicionar([
            for (var i = 0; i < n; i++) Importada(contaDeLinha('http://h$i.com/l$i.m3u')!),
          ]));
      await t.pumpWidget(_app(TelaInicio(biblioteca: bib)));
      await t.pump();
      await t.pump();
    }

    testWidgets('BAIXO chega a todas as linhas e CIMA volta à primeira', (t) async {
      _tv(t);
      await comListas(t, 15); // 3 colunas a 960 → 5 linhas (as últimas fora do ecrã)
      expect(_focado(), contains('001H'));
      final caminho = <String>[];
      for (var i = 0; i < 6; i++) {
        await _tecla(t, LogicalKeyboardKey.arrowDown);
        caminho.add(_focado().split(' | ').first);
      }
      expect(caminho.any((c) => c.contains('013H')), isTrue, reason: 'BAIXO: $caminho');
      final subir = <String>[];
      for (var i = 0; i < 8; i++) {
        await _tecla(t, LogicalKeyboardKey.arrowUp);
        subir.add(_focado().split(' | ').first);
        if (subir.last.contains('001H')) break;
      }
      expect(subir.last, contains('001H'), reason: 'CIMA: $subir');
    });

    testWidgets('os cartões não têm "..." (Mais opções): OK mantido abre o menu com todas as ações, '
        'incluindo "Remover lista"', (t) async {
      _tv(t);
      await comListas(t, 2);
      expect(find.byTooltip('Mais opções'), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      // BAIXO no cartão não entra em nenhum botão de dentro: o foco fica num cartão
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      expect(_focado(), contains('001H'), reason: 'foco em: ${_focado()}');
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 50));
        await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      }
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      for (final a in ['Abrir', 'Atualizar canais', 'Editar', 'Copiar link', 'Remover lista']) {
        expect(find.widgetWithText(ListTile, a), findsOneWidget, reason: a);
      }
      // a última ação alcança-se com BAIXO
      for (var i = 0; i < 6; i++) {
        await _tecla(t, LogicalKeyboardKey.arrowDown);
      }
      expect(_focado(), 'Remover lista');
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.text('Remover lista?'), findsOneWidget);
      expect(_focado(), 'Cancelar', reason: 'o foco começa no lado seguro');
    });
  });

  group('Conteúdo: a lista de canais de um grupo', () {
    Future<Lista> mostrar(WidgetTester t, {int n = 20}) async {
      await t.runAsync(() async {
        await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
        await bib.guardarCanais(bib.listas.single.id, ConteudoLista(['G', 'H'], [
          for (var i = 0; i < n; i++) Canal(id: '$i', nome: 'Canal $i', grupo: 'G', url: 'u$i'),
          const Canal(id: 'h', nome: 'Outro', grupo: 'H', url: 'uh'),
        ]));
        await t.pumpWidget(_app(TelaConteudo(biblioteca: bib, lista: bib.listas.single, abrir: (_, _) => null)));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
      return bib.listas.single;
    }

    /// O foco está numa linha de canal (o ListTile), não na estrela nem noutro botão.
    String? canalFocado() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return null;
      final w = ctx.widget;
      final tile = w is ListTile ? w : ctx.findAncestorWidgetOfExactType<ListTile>();
      if (ctx.findAncestorWidgetOfExactType<IconButton>() != null) return null;
      final titulo = tile?.title;
      return titulo is Text ? titulo.data : null;
    }

    testWidgets('CIMA/BAIXO vão sempre de canal em canal (a estrela não é uma paragem)', (t) async {
      _tv(t);
      await mostrar(t);
      expect(_focado(), contains('G'));
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      expect(canalFocado(), 'Canal 0', reason: 'foco em: ${_focado()}');
      for (var i = 1; i < 20; i++) {
        await _tecla(t, LogicalKeyboardKey.arrowDown);
        expect(canalFocado(), 'Canal $i', reason: 'BAIXO n.º $i; foco em: ${_focado()}');
      }
      for (var i = 18; i >= 0; i--) {
        await _tecla(t, LogicalKeyboardKey.arrowUp);
        expect(canalFocado(), 'Canal $i', reason: 'CIMA; foco em: ${_focado()}');
      }
      // DIREITA num canal também não vai para a estrela
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      expect(canalFocado(), 'Canal 0', reason: 'DIREITA; foco em: ${_focado()}');
      // ESQUERDA volta aos grupos
      await _tecla(t, LogicalKeyboardKey.arrowLeft);
      expect(_focado(), contains('G'));
    });

    testWidgets('OK mantido num canal põe/tira dos favoritos (com aviso) e o foco fica no canal', (t) async {
      _tv(t);
      final l = await mostrar(t, n: 3);
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      expect(canalFocado(), 'Canal 0');
      Future<void> okMantido() async {
        await t.sendKeyDownEvent(LogicalKeyboardKey.select);
        await t.pump(duracaoOkMantido + const Duration(milliseconds: 50));
        await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
        await t.sendKeyUpEvent(LogicalKeyboardKey.select);
        await t.pump();
      }

      await okMantido();
      expect(l.favoritos, {'0'});
      expect(find.text('Canal 0 está nos favoritos'), findsOneWidget);
      expect(canalFocado(), 'Canal 0', reason: 'o foco fica no canal');
      await okMantido();
      expect(l.favoritos, isEmpty);
      expect(find.text('Canal 0 saiu dos favoritos'), findsOneWidget);
    });
  });

  testWidgets('Conteúdo: no grupo dos favoritos, tirar um canal passa o foco ao seguinte', (t) async {
    _tv(t);
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
      final id = bib.listas.single.id;
      await bib.guardarCanais(id, ConteudoLista(['G'], const [
        Canal(id: '1', nome: 'Um', grupo: 'G', url: 'u1'),
        Canal(id: '2', nome: 'Dois', grupo: 'G', url: 'u2'),
        Canal(id: '3', nome: 'Tres', grupo: 'G', url: 'u3'),
      ]));
      for (final c in ['1', '2', '3']) {
        await bib.alternarFavorito(id, c);
      }
      await t.pumpWidget(_app(TelaConteudo(biblioteca: bib, lista: bib.listas.single, abrir: (_, _) => null)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump();
    expect(_focado(), contains(grupoFavoritos));
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    await _tecla(t, LogicalKeyboardKey.arrowDown);
    expect(_focado(), contains('Dois'));
    await t.sendKeyDownEvent(LogicalKeyboardKey.select);
    await t.pump(duracaoOkMantido + const Duration(milliseconds: 50));
    await t.sendKeyUpEvent(LogicalKeyboardKey.select);
    await t.pump();
    await t.pump();
    expect(bib.listas.single.favoritos, {'1', '3'});
    expect(_focado(), contains('Tres'), reason: 'o foco não se perde');
  });

  group('Definições: CIMA/BAIXO andam sempre entre as definições', () {
    /// Uma identificação do controlo com o foco (o texto, ou o tipo do widget se não tem texto).
    String id() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return '';
      if (ctx.findAncestorWidgetOfExactType<Slider>() != null) return 'Slider@${ctx.hashCode}';
      final f = _focado();
      return f.isNotEmpty ? f : '${ctx.widget.runtimeType}@${ctx.hashCode}';
    }

    testWidgets('no Android TV (navegação "tradicional") nenhum controlo prende CIMA/BAIXO', (t) async {
      _tv(t);
      final (area, prefs) = (await t.runAsync(() async => (await AreaGestor.abrir(pasta), await Preferencias.abrir(pasta))))!;
      await t.pumpWidget(_app(TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs, android: true)));
      await t.pump(const Duration(milliseconds: 400));
      final inicio = id();
      final timeout = prefs.timeoutVerificacao, volume = prefs.volume;
      final descer = <String>[inicio];
      for (var i = 0; i < 40 && !descer.last.contains('Exportar cópia'); i++) {
        await _tecla(t, LogicalKeyboardKey.arrowDown);
        descer.add(id());
        // a mesma paragem duas vezes seguidas = BAIXO preso
        expect(descer[descer.length - 1], isNot(descer[descer.length - 2]), reason: 'BAIXO preso: $descer');
      }
      expect(descer.last, contains('Exportar cópia'), reason: 'BAIXO: $descer');
      expect(descer.where((d) => d.startsWith('Slider')), hasLength(2), reason: 'os dois deslizadores: $descer');
      expect(prefs.timeoutVerificacao, timeout, reason: 'CIMA/BAIXO não mudam o tempo limite');
      expect(prefs.volume, volume, reason: 'CIMA/BAIXO não mudam o volume');
      // CIMA até ao topo (pára na primeira linha de chips, a dos canais de teste)
      final subir = <String>[descer.last];
      for (var i = 0; i < 40; i++) {
        await _tecla(t, LogicalKeyboardKey.arrowUp);
        if (id() == subir.last) break;
        subir.add(id());
      }
      expect(subir.where((d) => d.startsWith('Slider')), hasLength(2), reason: 'CIMA: $subir');
      expect(find.ancestor(of: find.text(subir.last), matching: find.byType(FilterChip)), findsOneWidget,
          reason: 'CIMA chega aos canais de teste: $subir');
      for (var i = 0; i < 6 && id() != inicio; i++) {
        await _tecla(t, LogicalKeyboardKey.arrowLeft);
      }
      expect(id(), inicio);
      expect(prefs.timeoutVerificacao, timeout);
      // ESQUERDA/DIREITA no deslizador continuam a mudar o valor
      final iSlider = descer.indexWhere((d) => d.startsWith('Slider'));
      for (var i = 0; i < iSlider; i++) {
        await _tecla(t, LogicalKeyboardKey.arrowDown);
      }
      expect(id(), startsWith('Slider'));
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      expect(prefs.timeoutVerificacao, timeout + 1);
      await _tecla(t, LogicalKeyboardKey.arrowLeft);
      expect(prefs.timeoutVerificacao, timeout);
    });
  });

  testWidgets('Painel de definições do player: CIMA/BAIXO passam por todos os tipos de item; '
      'ESQUERDA/DIREITA mudam o valor sem sair', (t) async {
    _tv(t);
    var escolha = 0, ligado = false, passos = 0;
    await t.pumpWidget(_app(Scaffold(
      body: StatefulBuilder(
        builder: (_, set) => PainelDefinicoes(itens: [
          DefinicaoEscolha('Formato', opcoes: const ['A', 'B', 'C'], atual: escolha,
              aoMudar: (v) => set(() => escolha = v)),
          DefinicaoInterruptor('Desentrelaçar', valor: ligado, aoMudar: (v) => set(() => ligado = v)),
          const DefinicaoEscolha('Áudio', opcoes: ['Só um'], atual: 0, nota: 'Só há uma faixa'),
          DefinicaoPassos('Volume', valor: '$passos', menos: () => set(() => passos--), mais: () => set(() => passos++)),
          DefinicaoAcao('Estatísticas', valor: 'Ver', aoCarregar: () {}),
        ]),
      ),
    )));
    await t.pump();
    String titulo() => _focado().split(' | ').first;
    expect(titulo(), 'Formato');
    final caminho = <String>[titulo()];
    for (var i = 0; i < 3; i++) {
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      caminho.add(titulo());
    }
    expect(caminho, ['Formato', 'Desentrelaçar', 'Volume', 'Estatísticas'], reason: 'o item desligado salta-se');
    for (final k in [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowUp]) {
      await _tecla(t, k);
    }
    expect(titulo(), 'Desentrelaçar');
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    expect(ligado, isTrue);
    expect(titulo(), 'Desentrelaçar', reason: 'DIREITA não sai do item');
    await _tecla(t, LogicalKeyboardKey.arrowDown);
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    expect(passos, 1);
    await _tecla(t, LogicalKeyboardKey.arrowUp);
    await _tecla(t, LogicalKeyboardKey.arrowUp);
    expect(titulo(), 'Formato');
    await _tecla(t, LogicalKeyboardKey.arrowLeft);
    expect(escolha, 2);
  });
}
