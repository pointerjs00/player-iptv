import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/inicio/favoritos_inicio.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

Widget _app(Widget w) =>
    MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

ConteudoLista _conteudo(String prefixo) => ConteudoLista(['Portugal', 'Desporto'], [
      Canal(id: '${prefixo}1', nome: '$prefixo RTP 1', grupo: 'Portugal'),
      Canal(id: '${prefixo}2', nome: '$prefixo SIC', grupo: 'Portugal'),
      Canal(id: '${prefixo}3', nome: '$prefixo Sport TV', grupo: 'Desporto'),
    ]);

void main() {
  late Directory pasta;
  late Biblioteca bib;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('inicio');
    bib = await Biblioteca.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  void tamanho(WidgetTester t) {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
  }

  /// Duas listas com cache (A e B, com favoritos) e uma terceira sem cache.
  Future<void> preparar(WidgetTester t) async {
    await t.runAsync(() async {
      await bib.adicionar([
        Importada(contaDeLinha('http://a.com/l.m3u')!),
        Importada(contaDeLinha('http://b.com/l.m3u')!,
            UltimaVerificacao(estado: 'funciona', data: DateTime.now().subtract(const Duration(hours: 2)))),
        Importada(contaDeLinha('http://c.com/l.m3u')!),
      ]);
      final [a, b, c] = bib.listas;
      await bib.guardarCanais(a.id, _conteudo('A'));
      await bib.guardarCanais(b.id, _conteudo('B'));
      await bib.alternarFavorito(a.id, 'A2');
      await bib.alternarFavorito(a.id, 'A1');
      await bib.alternarFavorito(b.id, 'B3');
      await bib.alternarFavorito(c.id, 'C1'); // sem cache: ignorada
    });
  }

  group('favoritosInicio', () {
    testWidgets('junta os favoritos das listas pela ordem das listas e dos canais; ignora lista sem cache',
        (t) async {
      await preparar(t);
      final f = (await t.runAsync(() => favoritosInicio(bib)))!;
      expect([for (final x in f) x.canal.id], ['A1', 'A2', 'B3']);
      expect(f[2].lista.id, bib.listas[1].id);
    });

    testWidgets('respeita o máximo', (t) async {
      await preparar(t);
      final f = (await t.runAsync(() => favoritosInicio(bib, maximo: 2)))!;
      expect([for (final x in f) x.canal.id], ['A1', 'A2']);
    });
  });

  group('Início com listas', () {
    Future<List<(List<Canal>, int)>> abrir(WidgetTester t) async {
      final abertos = <(List<Canal>, int)>[];
      await t.pumpWidget(_app(TelaInicio(biblioteca: bib, abrirCanal: (c, i) {
        abertos.add((c, i));
        return null;
      })));
      // os resumos lêem as caches do disco (IO real, vários passos): alterna-se IO real e frames
      for (var i = 0; i < 15; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await t.pump();
      }
      await t.pumpAndSettle();
      return abertos;
    }

    testWidgets('"Continuar a ver" mostra o canal, a lista e o número do canal', (t) async {
      tamanho(t);
      await preparar(t);
      final b = bib.listas[1];
      await t.runAsync(() => bib.registarVisto(b.id, _conteudo('B').canais[2]));
      await abrir(t);
      final cartao = find.byKey(const Key('continuar-a-ver'));
      expect(cartao, findsOneWidget);
      expect(find.descendant(of: cartao, matching: find.text('B Sport TV')), findsOneWidget);
      expect(find.descendant(of: cartao, matching: find.textContaining('CONTINUAR A VER')), findsOneWidget);
      expect(find.descendant(of: cartao, matching: find.textContaining(b.nomeMostrado)), findsOneWidget);
      expect(find.descendant(of: cartao, matching: find.text('Canal 3 · Desporto')), findsOneWidget);
      expect(find.descendant(of: cartao, matching: find.text('Ver')), findsOneWidget);
    });

    testWidgets('a fila "Favoritos · n" mostra o canal com o nome da lista por baixo', (t) async {
      tamanho(t);
      await preparar(t);
      await abrir(t);
      expect(find.text('Favoritos · 3'), findsOneWidget);
      expect(find.text('A RTP 1'), findsOneWidget);
      expect(find.text('B Sport TV'), findsOneWidget);
      expect(find.text('Listas · 3'), findsOneWidget);
    });

    testWidgets('sem favoritos não há a fila', (t) async {
      tamanho(t);
      await t.runAsync(() => bib.adicionar([Importada(contaDeLinha('http://a.com/l.m3u')!)]));
      await abrir(t);
      expect(find.textContaining('Favoritos'), findsNothing);
      expect(find.text('Listas · 1'), findsOneWidget);
    });

    testWidgets('os cartões das listas mostram a pílula de estado; só os com cache mostram a contagem',
        (t) async {
      tamanho(t);
      await preparar(t);
      await abrir(t);
      expect(find.byType(PilulaEstado), findsNWidgets(3));
      expect(find.text('3 canais · 2 grupos'), findsNWidgets(2));
      expect(find.text('Funciona · verificada há 2 h'), findsOneWidget);
      // a lista C não tem cache: nenhuma contagem no cartão dela
      final c = find.ancestor(
          of: find.textContaining(bib.listas[2].nomeMostrado), matching: find.byType(CartaoModerno));
      expect(c, findsOneWidget);
      expect(find.descendant(of: c, matching: find.textContaining('canais')), findsNothing);
    });

    testWidgets('OK num favorito abre esse canal da lista certa', (t) async {
      tamanho(t);
      await preparar(t);
      final abertos = await abrir(t);
      await t.tap(find.text('B Sport TV'));
      await t.runAsync(() async {
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pumpAndSettle();
      expect(abertos, hasLength(1));
      expect(abertos.single.$1.every((c) => c.id.startsWith('B')), isTrue, reason: 'canais da lista B');
      expect(abertos.single.$1[abertos.single.$2].id, 'B3');
    });

    testWidgets('a barra de teclas tem as três dicas', (t) async {
      tamanho(t);
      await preparar(t);
      await abrir(t);
      expect(find.text('abrir'), findsOneWidget);
      expect(find.text('opções da lista'), findsOneWidget);
      expect(find.text('menu'), findsOneWidget);
    });
  });

  group('Início sem listas', () {
    testWidgets('mostra o ecrã de primeira vez com os 3 passos', (t) async {
      tamanho(t);
      await t.pumpWidget(_app(TelaInicio(biblioteca: bib)));
      await t.pump();
      expect(find.text('Ainda não há listas para ver'), findsOneWidget);
      expect(
          find.text(
              'As listas entram pelo Gestor. Lá podes importá-las, ver quais funcionam e enviar as boas para aqui.'),
          findsOneWidget);
      for (final s in ['Importar', 'Verificar', 'Enviar']) {
        expect(find.text(s), findsOneWidget);
      }
      expect(find.text('Ficheiro, texto colado ou listas do stbstalker'), findsOneWidget);
      expect(find.text('Testamos 3 canais de cada lista'), findsOneWidget);
      expect(find.text('As que funcionam aparecem aqui'), findsOneWidget);
      // o Início não oferece importar a cópia de segurança (é nas Definições)
      expect(find.text('Importar cópia de segurança'), findsNothing);
    });
  });
}
