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
import 'package:player_iptv/ui/design/barra_teclas.dart';
import 'package:player_iptv/ui/definicoes/tela_definicoes.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/player/painel_definicoes.dart';

import 'ajuda_dpad.dart';

/// Regressões do feedback 1 (Android TV): tudo só com teclas (setas, OK, Voltar).


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
      await t.pumpWidget(appTeste(TelaInicio(biblioteca: bib)));
      await t.pump();
      await t.pump();
    }

    testWidgets('BAIXO chega a todas as linhas e CIMA volta à primeira', (t) async {
      ecraTvTeste(t);
      await comListas(t, 15); // 3 colunas a 960 → 5 linhas (as últimas fora do ecrã)
      expect(textosFocados(), contains('001H'));
      final caminho = <String>[];
      for (var i = 0; i < 6; i++) {
        await teclaDpad(t, LogicalKeyboardKey.arrowDown);
        caminho.add(textosFocados().split(' | ').first);
      }
      expect(caminho.any((c) => c.contains('013H')), isTrue, reason: 'BAIXO: $caminho');
      final subir = <String>[];
      for (var i = 0; i < 8; i++) {
        await teclaDpad(t, LogicalKeyboardKey.arrowUp);
        subir.add(textosFocados().split(' | ').first);
        if (subir.last.contains('001H')) break;
      }
      expect(subir.last, contains('001H'), reason: 'CIMA: $subir');
    });

    testWidgets('os cartões não têm "..." (Mais opções): OK mantido abre o menu com todas as ações, '
        'incluindo "Remover lista"', (t) async {
      ecraTvTeste(t);
      await comListas(t, 2);
      expect(find.byTooltip('Mais opções'), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      // BAIXO no cartão não entra em nenhum botão de dentro: o foco fica num cartão
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
      expect(textosFocados(), contains('001H'), reason: 'foco em: ${textosFocados()}');
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 50));
        await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      }
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      for (final a in ['Atualizar canais', 'Editar lista', if (Platform.isWindows) 'Copiar link', 'Remover lista']) {
        expect(find.widgetWithText(ListTile, a), findsOneWidget, reason: a);
      }
      // a última ação alcança-se com BAIXO
      for (var i = 0; i < 6; i++) {
        await teclaDpad(t, LogicalKeyboardKey.arrowDown);
      }
      expect(textosFocados(), startsWith('Remover lista'));
      await teclaDpad(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.text('Remover lista?'), findsOneWidget);
      expect(textosFocados(), 'Cancelar', reason: 'o foco começa no lado seguro');
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
        await t.pumpWidget(appTeste(TelaConteudo(biblioteca: bib, lista: bib.listas.single, abrir: (_, _) => null)));
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
      ecraTvTeste(t);
      await mostrar(t);
      expect(textosFocados(), contains('G'));
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
      expect(canalFocado(), 'Canal 0', reason: 'foco em: ${textosFocados()}');
      for (var i = 1; i < 20; i++) {
        await teclaDpad(t, LogicalKeyboardKey.arrowDown);
        expect(canalFocado(), 'Canal $i', reason: 'BAIXO n.º $i; foco em: ${textosFocados()}');
      }
      for (var i = 18; i >= 0; i--) {
        await teclaDpad(t, LogicalKeyboardKey.arrowUp);
        expect(canalFocado(), 'Canal $i', reason: 'CIMA; foco em: ${textosFocados()}');
      }
      // DIREITA num canal também não vai para a estrela
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
      expect(canalFocado(), 'Canal 0', reason: 'DIREITA; foco em: ${textosFocados()}');
      // ESQUERDA volta aos grupos
      await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
      expect(textosFocados(), contains('G'));
    });

    testWidgets('OK mantido num canal põe/tira dos favoritos (com aviso) e o foco fica no canal', (t) async {
      ecraTvTeste(t);
      final l = await mostrar(t, n: 3);
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
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
    ecraTvTeste(t);
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
      await t.pumpWidget(appTeste(TelaConteudo(biblioteca: bib, lista: bib.listas.single, abrir: (_, _) => null)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump();
    expect(textosFocados(), contains(grupoFavoritos));
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Dois'));
    await t.sendKeyDownEvent(LogicalKeyboardKey.select);
    await t.pump(duracaoOkMantido + const Duration(milliseconds: 50));
    await t.sendKeyUpEvent(LogicalKeyboardKey.select);
    await t.pump();
    await t.pump();
    expect(bib.listas.single.favoritos, {'1', '3'});
    expect(textosFocados(), contains('Tres'), reason: 'o foco não se perde');
  });

  group('Definições: CIMA/BAIXO andam sempre entre as definições', () {
    /// Uma identificação do controlo com o foco (o texto, ou o tipo do widget se não tem texto).
    String id() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return '';
      if (ctx.findAncestorWidgetOfExactType<Slider>() != null) return 'Slider@${ctx.hashCode}';
      final f = textosFocados();
      return f.isNotEmpty ? f : '${ctx.widget.runtimeType}@${ctx.hashCode}';
    }

    testWidgets('no Android TV (navegação "tradicional") nenhum controlo prende CIMA/BAIXO', (t) async {
      ecraTvTeste(t);
      final (area, prefs) = (await t.runAsync(() async => (await AreaGestor.abrir(pasta), await Preferencias.abrir(pasta))))!;
      await t.pumpWidget(appTeste(TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs, android: true)));
      await t.pump(const Duration(milliseconds: 400));
      final inicio = id();
      final timeout = prefs.timeoutVerificacao, volume = prefs.volume;
      final descer = <String>[inicio];
      for (var i = 0; i < 40 && !descer.last.contains('Exportar cópia'); i++) {
        await teclaDpad(t, LogicalKeyboardKey.arrowDown);
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
        await teclaDpad(t, LogicalKeyboardKey.arrowUp);
        if (id() == subir.last) break;
        subir.add(id());
      }
      expect(subir.where((d) => d.startsWith('Slider')), hasLength(2), reason: 'CIMA: $subir');
      expect(find.ancestor(of: find.text(subir.last), matching: find.byType(FilterChip)), findsOneWidget,
          reason: 'CIMA chega aos canais de teste: $subir');
      for (var i = 0; i < 6 && id() != inicio; i++) {
        await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
      }
      expect(id(), inicio);
      expect(prefs.timeoutVerificacao, timeout);
      // ESQUERDA/DIREITA no deslizador continuam a mudar o valor
      final iSlider = descer.indexWhere((d) => d.startsWith('Slider'));
      for (var i = 0; i < iSlider; i++) {
        await teclaDpad(t, LogicalKeyboardKey.arrowDown);
      }
      expect(id(), startsWith('Slider'));
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
      expect(prefs.timeoutVerificacao, timeout + 1);
      await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
      expect(prefs.timeoutVerificacao, timeout);
    });
  });

  testWidgets('Painel de definições do player: CIMA/BAIXO passam por todos os tipos de item; '
      'ESQUERDA/DIREITA mudam o valor sem sair', (t) async {
    ecraTvTeste(t);
    var escolha = 0, ligado = false, passos = 0;
    await t.pumpWidget(appTeste(Scaffold(
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
    String titulo() => textosFocados().split(' | ').first;
    expect(titulo(), 'Formato');
    final caminho = <String>[titulo()];
    for (var i = 0; i < 3; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowDown);
      caminho.add(titulo());
    }
    expect(caminho, ['Formato', 'Desentrelaçar', 'Volume', 'Estatísticas'], reason: 'o item desligado salta-se');
    for (final k in [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowUp]) {
      await teclaDpad(t, k);
    }
    expect(titulo(), 'Desentrelaçar');
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(ligado, isTrue);
    expect(titulo(), 'Desentrelaçar', reason: 'DIREITA não sai do item');
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(passos, 1);
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    expect(titulo(), 'Formato');
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(escolha, 2);
  });

  group('Conteúdo: a barra de teclas', () {
    Future<void> mostrarCanais(WidgetTester t) async {
      await t.runAsync(() async {
        await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
        await bib.guardarCanais(bib.listas.single.id, ConteudoLista(['G'], const [
          Canal(id: '1', nome: 'Um', grupo: 'G', url: 'u1'),
        ]));
        await t.pumpWidget(appTeste(TelaConteudo(biblioteca: bib, lista: bib.listas.single, abrir: (_, _) => null)));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
    }

    testWidgets('na TV a barra de teclas em baixo diz o que cada tecla faz', (t) async {
      ecraTvTeste(t);
      await mostrarCanais(t);
      final barra = find.byType(BarraTeclas);
      expect(barra, findsOneWidget);
      for (final texto in ['OK', 'ver', 'OK mantido', 'favorito', '←', 'grupos', '0–9', 'ir para o canal', 'Menu',
        'opções dos canais']) {
        expect(find.descendant(of: barra, matching: find.text(texto)), findsOneWidget, reason: texto);
      }
    });
  });
}
