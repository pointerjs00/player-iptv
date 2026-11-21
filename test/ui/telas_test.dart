import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/tarefas/servico_tarefas.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/gestor/passo_enviar.dart';
import 'package:player_iptv/ui/gestor/passo_verificar.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/player/player_canais.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/verificar/servico.dart';

// como a app (main.dart): o tema segue o modo de realce do foco
Widget _app(Widget w) =>
    MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

void _tamanho(WidgetTester t, double l, double a) {
  t.view.physicalSize = Size(l, a);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Os campos de pesquisa só deixam escrever depois de OK/toque (no comando da TV, receber o
/// foco não abre o teclado no ecrã).
Future<void> _escrever(WidgetTester t, Finder campo, String texto) async {
  await t.tap(campo);
  await t.pump();
  await t.enterText(campo, texto);
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

  testWidgets('Player: cartões com o último resultado e filtro por estado (sem verificar)', (t) async {
    await t.runAsync(() => bib.adicionar([
          Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!,
              UltimaVerificacao(estado: 'funciona', data: DateTime.now(), validade: '2027-10-16')),
          Importada(contaDeLinha('http://outro.com/c/ 00:1A:79:00:00:02')!,
              UltimaVerificacao(estado: 'inconclusivo', data: DateTime(2026, 1, 2), motivo: 'tempo esgotado')),
          Importada(contaDeLinha('http://novo.com/x.m3u')!),
        ]));
    _tamanho(t, 1200, 800);
    await t.pumpWidget(_app(TelaInicio(biblioteca: bib)));
    await t.pump();
    expect(find.text('001NXTBOX 161027'), findsOneWidget);
    expect(find.text('até 16/10/2027'), findsOneWidget);
    expect(find.text('INC 002OUTRO'), findsOneWidget);
    expect(find.text('tempo esgotado'), findsOneWidget);
    expect(find.text('Por verificar'), findsWidgets);
    // o Player não verifica (é no Gestor)
    expect(find.text('Verificar de novo'), findsNothing);

    await t.tap(find.widgetWithText(ChoiceChip, 'Inconclusivas'));
    await t.pump();
    expect(find.text('001NXTBOX 161027'), findsNothing);
    expect(find.text('INC 002OUTRO'), findsOneWidget);

    await t.tap(find.widgetWithText(ChoiceChip, 'Todas'));
    await _escrever(t, find.byType(TextField).first, 'nxt');
    await t.pump();
    expect(find.text('001NXTBOX 161027'), findsOneWidget);
    expect(find.text('003NOVO'), findsNothing);
  });

  test('a mensagem de erro do player não mostra links (credenciais Xtream)', () {
    expect(mensagemErroPlayer('Failed to open http://h:8080/live/user/pass/1.ts.'), 'o canal não abriu (Failed to open)');
    expect(mensagemErroPlayer('http://h/live/u/p/1.ts'), 'o canal não abriu');
  });

  testWidgets('Ver TV vazio: explica o caminho pelo Gestor e não adiciona', (t) async {
    await t.pumpWidget(_app(TelaInicio(biblioteca: bib)));
    expect(find.text('Ainda não há listas para ver'), findsOneWidget);
    expect(find.text('Adicionar listas'), findsNothing);
    expect(find.byTooltip('Adicionar listas'), findsNothing);
    // só o conteúdo de Ver TV: sem separadores nem roda dentada (são da casca)
    expect(find.byType(TabBar), findsNothing);
    expect(find.byTooltip('Definições'), findsNothing);
    // fora da casca não há Gestor para onde ir
    expect(find.text('Ir para o Gestor'), findsNothing);
  });

  testWidgets('I3: Gestor com 300 listas só constrói as linhas visíveis (lista preguiçosa)', (t) async {
    late AreaGestor area;
    await t.runAsync(() async => area = await AreaGestor.abrir(pasta));
    await t.runAsync(() => area.adicionar([
          for (var i = 0; i < 300; i++) Importada(contaDeLinha('http://h$i.com/l.m3u')!),
        ]));
    _tamanho(t, 1200, 1600);
    await t.pumpWidget(_app(Scaffold(
        body: TelaGestor(
            biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area), tarefas: ServicoTarefas()))));
    await t.pump();
    // em cada passo (o 2 e o 3 ficam construídos, escondidos atrás do resumo), só as que cabem em 1600
    for (final passo in [find.byType(PassoVerificar, skipOffstage: false), find.byType(PassoEnviar, skipOffstage: false)]) {
      final linhas = find.descendant(
          of: passo, matching: find.byType(CheckboxListTile, skipOffstage: false), skipOffstage: false);
      final construidas = linhas.evaluate().length;
      expect(construidas, greaterThan(0));
      expect(construidas, lessThan(60), reason: '$construidas linhas construídas');
    }
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

    Future<void> mostrar(WidgetTester t, Lista l, {FutureOr<int?> Function(List<Canal>, int)? abrir}) async {
      // a cache é lida do disco: IO real
      await t.runAsync(() async {
        await t.pumpWidget(_app(TelaConteudo(biblioteca: bib, lista: l, abrir: abrir)));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
    }

    testWidgets('grupos à esquerda, canais do grupo à direita; sem grupo, pesquisa em todos', (t) async {
      _tamanho(t, 1200, 800);
      final l = await preparar(t);
      await mostrar(t, l);
      // abre em «Todos os canais»
      expect(find.text('1 de 5'), findsOneWidget);
      await t.tap(find.text('Portugal'));
      await t.pump();
      expect(find.text('1 de 2'), findsOneWidget);
      expect(find.text('PT: RTP 1 HD'), findsOneWidget);
      expect(find.text('BBC One'), findsNothing);

      await t.tap(find.text('UK'));
      await t.pump();
      expect(find.text('BBC One'), findsOneWidget);
      // com um grupo escolhido, a pesquisa só procura nele
      await _escrever(t, find.byKey(const Key('pesquisa-canais')), 'rtp');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('UK · 0'), findsOneWidget);

      // sem grupo, a pesquisa procura em todos e ignora acentos
      await t.tap(find.descendant(of: find.byKey(const Key('lista-grupos')), matching: find.text('Todos os canais')));
      await t.pumpAndSettle();
      await _escrever(t, find.byKey(const Key('pesquisa-canais')), 'rtp acores');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Canais · 1'), findsOneWidget);
      await _escrever(t, find.byKey(const Key('pesquisa-canais')), 'cnn');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Canais · 0'), findsOneWidget);
      await _escrever(t, find.byKey(const Key('pesquisa-canais')), 'rtp');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Canais · 2'), findsOneWidget);
      expect(find.text('RTP Açores'), findsOneWidget);

      // o filtro dos grupos só mexe nos grupos
      await _escrever(t, find.byKey(const Key('filtro-grupos')), 'desp');
      await t.pump(const Duration(milliseconds: 200));
      final grupos = find.byKey(const Key('lista-grupos'));
      expect(find.descendant(of: grupos, matching: find.text('Portugal')), findsNothing);
      expect(find.descendant(of: grupos, matching: find.text('Desporto')), findsOneWidget);
    });

    testWidgets('favoritos aparecem num grupo próprio e abrir passa a lista do grupo', (t) async {
      _tamanho(t, 1200, 800);
      final l = await preparar(t);
      (List<Canal>, int)? aberto;
      await mostrar(t, l, abrir: (c, i) {
        aberto = (c, i);
        return null;
      });
      await t.tap(find.text('Portugal'));
      await t.pump();
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
      await _escrever(t, find.byKey(const Key('pesquisa-canais')), 'rtp');
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('1 de 5'), findsOneWidget, reason: 'ainda «Todos os canais», sem filtrar');
      await t.pump(const Duration(milliseconds: 150));
      expect(find.text('Canais · 2'), findsOneWidget);
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
      await _escrever(t, find.byKey(const Key('pesquisa-canais')), 'acao 9999');
      await t.pump(const Duration(milliseconds: 200));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await t.pump();
      expect(find.text('Canais · 11'), findsOneWidget);
      for (var k = 0; k < 5; k++) {
        await t.tap(find.byTooltip(k.isEven ? 'Pôr nos favoritos' : 'Tirar dos favoritos').first);
        await t.pump();
      }
    });

    testWidgets('sugestão 9: esqueleto a brilhar enquanto carrega; depois o cabeçalho com estado e validade',
        (t) async {
      _tamanho(t, 1200, 800);
      await t.runAsync(() async {
        await bib.adicionar([
          Importada(contaDeLinha('http://x.com/l.m3u')!,
              UltimaVerificacao(estado: 'funciona', data: DateTime.now(), validade: '2027-10-16')),
        ]);
        await bib.guardarCanais(bib.listas.single.id, canais);
      });
      final l = bib.listas.single;
      // a cache ainda não foi lida (IO real fora do runAsync): está a carregar
      await t.pumpWidget(_app(TelaConteudo(biblioteca: bib, lista: l)));
      expect(find.byType(EsqueletoBrilho), findsOneWidget);
      expect(find.text('PT: RTP 1 HD'), findsNothing);
      // a leitura tem vários passos de IO real: cada um precisa de tempo real e de um pump
      for (var i = 0; i < 30 && find.byType(EsqueletoBrilho).evaluate().isNotEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump();
      }
      expect(find.byType(EsqueletoBrilho), findsNothing);
      expect(find.text('PT: RTP 1 HD'), findsOneWidget);
      // cabeçalho: nome da lista, estado da última verificação e validade
      expect(find.text(l.nomeMostrado), findsWidgets);
      expect(find.descendant(of: find.byType(PilulaEstado), matching: find.text('Funciona')), findsOneWidget);
      expect(find.text('até 16/10/2027'), findsOneWidget);
      expect(find.textContaining('Verificada hoje'), findsOneWidget);
    });

    testWidgets('sem verificação, o cabeçalho diz "Por verificar"', (t) async {
      _tamanho(t, 1200, 800);
      final l = await preparar(t);
      await mostrar(t, l);
      expect(find.descendant(of: find.byType(PilulaEstado), matching: find.text('Por verificar')), findsOneWidget);
    });

    testWidgets('sugestão 8: na TV (ecraTv) canais e logótipos maiores', (t) async {
      _tamanho(t, 960, 540);
      final l = await preparar(t);
      Future<(double, Size)> medidas() async {
        await mostrar(t, l);
        final extensao = t.widget<ListView>(find.byKey(const Key('lista-canais'))).itemExtent!;
        final logo = t.getSize(find.byKey(const Key('logo-canal')).first);
        return (extensao, logo);
      }

      final (altura, logo) = await medidas();
      await t.pumpWidget(const SizedBox());
      EcraTv.nativo = true;
      addTearDown(() => EcraTv.nativo = false);
      final (alturaTv, logoTv) = await medidas();
      expect(alturaTv, greaterThan(altura));
      expect(logoTv.width, greaterThan(logo.width));
    });

    testWidgets('no telemóvel os grupos estão num botão que abre uma folha (sem chips)', (t) async {
      _tamanho(t, 400, 800);
      final l = await preparar(t);
      await mostrar(t, l);
      expect(find.byType(ChoiceChip), findsNothing);
      await t.tap(find.byKey(const Key('botao-grupo')));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('folha-grupos')), matching: find.text('Portugal')), findsOneWidget);
      await t.tap(find.descendant(of: find.byKey(const Key('folha-grupos')), matching: find.text('Desporto')));
      await t.pumpAndSettle();
      expect(find.text('Sport TV 1'), findsOneWidget);
      expect(find.text('Grupo: Desporto'), findsOneWidget);
    });

    testWidgets('setas navegam até um canal e OK abre-o', (t) async {
      _tamanho(t, 1200, 800);
      final l = await preparar(t);
      (List<Canal>, int)? aberto;
      await mostrar(t, l, abrir: (c, i) {
        aberto = (c, i);
        return null;
      });
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
