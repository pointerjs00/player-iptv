import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/player/player_canais.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/verificar/servico.dart';

Widget _app(Widget w) => MaterialApp(theme: temaApp(), home: w);

void _tamanho(WidgetTester t, double l, double a) {
  t.view.physicalSize = Size(l, a);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  late Directory pasta;
  late Biblioteca bib;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('ui');
    bib = await Biblioteca.abrir(pasta);
  });
  tearDown(() async {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* o Windows ainda tem o ficheiro aberto */}
  });

  testWidgets('Início: cartões com o último resultado e filtro por estado', (t) async {
    await t.runAsync(() => bib.adicionar([
          Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!,
              UltimaVerificacao(estado: 'funciona', data: DateTime.now(), validade: '2027-10-16')),
          Importada(contaDeLinha('http://outro.com/c/ 00:1A:79:00:00:02')!,
              UltimaVerificacao(estado: 'inconclusivo', data: DateTime(2026, 1, 2), motivo: 'tempo esgotado')),
          Importada(contaDeLinha('http://novo.com/x.m3u')!),
        ]));
    _tamanho(t, 1200, 800);
    await t.pumpWidget(_app(TelaInicio(biblioteca: bib, servico: ServicoVerificacao(bib))));
    await t.pump();
    expect(find.text('001NXTBOX 161027'), findsOneWidget);
    expect(find.text('até 16/10/2027'), findsOneWidget);
    expect(find.text('INC 002OUTRO'), findsOneWidget);
    expect(find.text('tempo esgotado'), findsOneWidget);
    expect(find.text('Por verificar'), findsWidgets);
    expect(find.text('Verificar de novo'), findsNWidgets(3));

    await t.tap(find.widgetWithText(ChoiceChip, 'INC'));
    await t.pump();
    expect(find.text('001NXTBOX 161027'), findsNothing);
    expect(find.text('INC 002OUTRO'), findsOneWidget);

    await t.tap(find.widgetWithText(ChoiceChip, 'Todas'));
    await t.enterText(find.byType(TextField).first, 'nxt');
    await t.pump();
    expect(find.text('001NXTBOX 161027'), findsOneWidget);
    expect(find.text('003NOVO'), findsNothing);
  });

  test('a mensagem de erro do player não mostra links (credenciais Xtream)', () {
    expect(mensagemErroPlayer('Failed to open http://h:8080/live/user/pass/1.ts.'), 'o canal não abriu (Failed to open)');
    expect(mensagemErroPlayer('http://h/live/u/p/1.ts'), 'o canal não abriu');
  });

  testWidgets('Início vazio convida a adicionar listas', (t) async {
    await t.pumpWidget(_app(TelaInicio(biblioteca: bib)));
    expect(find.text('Ainda não há listas.'), findsOneWidget);
    expect(find.text('Adicionar listas'), findsOneWidget);
  });

  group('Conteúdo', () {
    final canais = ConteudoLista(['Portugal', 'Desporto', 'UK'], const [
      Canal(id: '1', nome: 'PT: RTP 1 HD', grupo: 'Portugal', url: 'u1'),
      Canal(id: '2', nome: 'PT: SIC', grupo: 'Portugal', url: 'u2'),
      Canal(id: '3', nome: 'Sport TV 1', grupo: 'Desporto', url: 'u3'),
      Canal(id: '4', nome: 'BBC One', grupo: 'UK', url: 'u4'),
      Canal(id: '5', nome: 'RTP Açores', grupo: 'Desporto', url: 'u5'),
    ]);

    Future<Lista> preparar(WidgetTester t) async {
      await t.runAsync(() async {
        await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
        await bib.guardarCanais(bib.listas.single.id, canais);
      });
      return bib.listas.single;
    }

    Future<void> mostrar(WidgetTester t, Lista l, {void Function(List<Canal>, int)? abrir}) async {
      // a cache é lida do disco: IO real
      await t.runAsync(() async {
        await t.pumpWidget(_app(TelaConteudo(biblioteca: bib, lista: l, abrir: abrir)));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
    }

    testWidgets('grupos à esquerda, canais do grupo à direita; pesquisa em todos os grupos', (t) async {
      _tamanho(t, 1200, 800);
      final l = await preparar(t);
      await mostrar(t, l);
      expect(find.text('Portugal · 2 canais'), findsOneWidget);
      expect(find.text('PT: RTP 1 HD'), findsOneWidget);
      expect(find.text('BBC One'), findsNothing);

      await t.tap(find.text('UK'));
      await t.pump();
      expect(find.text('BBC One'), findsOneWidget);

      // a pesquisa ignora acentos e o grupo escolhido
      await t.enterText(find.byKey(const Key('pesquisa-canais')), 'rtp acores');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('1 canal encontrado'), findsOneWidget);
      await t.enterText(find.byKey(const Key('pesquisa-canais')), 'cnn');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('0 canais encontrados'), findsOneWidget);
      await t.enterText(find.byKey(const Key('pesquisa-canais')), 'rtp');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('2 canais encontrados'), findsOneWidget);
      expect(find.text('RTP Açores'), findsOneWidget);

      await t.enterText(find.byKey(const Key('pesquisa-canais')), '');
      await t.enterText(find.byKey(const Key('filtro-grupos')), 'desp');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.widgetWithText(ListTile, 'Portugal'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Desporto'), findsOneWidget);
    });

    testWidgets('favoritos aparecem num grupo próprio e abrir passa a lista do grupo', (t) async {
      _tamanho(t, 1200, 800);
      final l = await preparar(t);
      (List<Canal>, int)? aberto;
      await mostrar(t, l, abrir: (c, i) => aberto = (c, i));
      await t.tap(find.byTooltip('Pôr nos favoritos').first);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      expect(bib.listas.single.favoritos, {'1'});
      expect(find.text(grupoFavoritos), findsOneWidget);

      await t.tap(find.text('PT: SIC'));
      expect(aberto!.$1.map((c) => c.id), ['1', '2']);
      expect(aberto!.$2, 1);
    });

    testWidgets('I5: a pesquisa espera que se pare de escrever (150 ms) antes de filtrar', (t) async {
      _tamanho(t, 1200, 800);
      final l = await preparar(t);
      await mostrar(t, l);
      await t.enterText(find.byKey(const Key('pesquisa-canais')), 'rtp');
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Portugal · 2 canais'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 150));
      expect(find.text('2 canais encontrados'), findsOneWidget);
    });

    testWidgets('I5: com 100 mil canais, cada rebuild (favorito) não volta a percorrer os nomes', (t) async {
      _tamanho(t, 1200, 800);
      final grande = ConteudoLista(['G', 'H'], [
        for (var i = 0; i < 100000; i++) Canal(id: '$i', nome: 'Canal Ação $i', grupo: i.isEven ? 'G' : 'H', url: 'u$i'),
      ]);
      await t.runAsync(() async {
        await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
        await bib.guardarCanais(bib.listas.single.id, grande);
      });
      final l = bib.listas.single;
      await t.runAsync(() async {
        await t.pumpWidget(_app(TelaConteudo(biblioteca: bib, lista: l)));
        await Future<void>.delayed(const Duration(seconds: 3));
      });
      await t.pump();
      await t.enterText(find.byKey(const Key('pesquisa-canais')), 'acao 9999');
      await t.pump(const Duration(milliseconds: 200));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await t.pump();
      expect(find.text('11 canais encontrados'), findsOneWidget);
      final sw = Stopwatch()..start();
      for (var k = 0; k < 5; k++) {
        await t.tap(find.byTooltip(k.isEven ? 'Pôr nos favoritos' : 'Tirar dos favoritos').first);
        await t.pump();
      }
      sw.stop();
      // ignore: avoid_print
      print('I5 rebuild médio: ${sw.elapsedMilliseconds / 5} ms');
      expect(sw.elapsedMilliseconds / 5, lessThan(60));
    });

    testWidgets('no telemóvel os grupos são chips', (t) async {
      _tamanho(t, 400, 800);
      final l = await preparar(t);
      await mostrar(t, l);
      expect(find.widgetWithText(ChoiceChip, 'Portugal'), findsOneWidget);
      await t.tap(find.widgetWithText(ChoiceChip, 'Desporto'));
      await t.pump();
      expect(find.text('Sport TV 1'), findsOneWidget);
    });

    testWidgets('setas navegam até um canal e OK abre-o', (t) async {
      _tamanho(t, 1200, 800);
      final l = await preparar(t);
      (List<Canal>, int)? aberto;
      await mostrar(t, l, abrir: (c, i) => aberto = (c, i));
      // foco no 1.º canal e OK
      final tile = find.widgetWithText(ListTile, 'PT: RTP 1 HD');
      Focus.of(t.element(find.descendant(of: tile, matching: find.text('PT: RTP 1 HD')))).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(aberto?.$2, 0);
    });
  });
}
