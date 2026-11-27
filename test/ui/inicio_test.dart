import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/design/escala_interface.dart';
import 'package:player_iptv/ui/inicio/favoritos_inicio.dart';
import 'package:player_iptv/ui/inicio/cartao_lista.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

import 'ajuda_dpad.dart';

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
    Future<List<(List<Canal>, int)>> abrir(WidgetTester t, {Widget? filaJogos}) async {
      final abertos = <(List<Canal>, int)>[];
      await t.pumpWidget(_app(TelaInicio(biblioteca: bib, filaJogos: filaJogos, abrirCanal: (c, i) {
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
      expect(find.descendant(of: cartao, matching: find.text('Canal 3')), findsOneWidget);
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

    testWidgets('«Hoje há jogo» fica por cima das listas', (t) async {
      tamanho(t);
      await preparar(t);
      await abrir(t, filaJogos: const Text('FILA DOS JOGOS'));
      expect(find.text('FILA DOS JOGOS'), findsOneWidget);
      expect(t.getRect(find.text('FILA DOS JOGOS')).top, lessThan(t.getRect(find.text('Listas · 3')).top));
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
      expect(find.text('3 canais'), findsNWidgets(2));
      expect(find.text(' · verificada há 2 h'), findsOneWidget);
      expect(find.text('Funciona'), findsOneWidget);
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

    /// IO real e frames até `feito` (ou, sem ele, uns quantos passos), com prazo.
    Future<void> assentar(WidgetTester t, [bool Function()? feito]) async {
      for (var i = 0; i < (feito == null ? 10 : 100) && !(feito?.call() ?? false); i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await t.pump();
      }
    }

    testWidgets('um favorito na lista A relê só a cache de A (no máximo uma vez), não a de B', (t) async {
      tamanho(t);
      await preparar(t);
      await abrir(t);
      final [a, b, _] = bib.listas;
      expect(find.text('Favoritos · 3'), findsOneWidget);
      bib.leiturasCache.clear();
      await t.runAsync(() => bib.alternarFavorito(a.id, 'A3'));
      await assentar(t, () => find.text('Favoritos · 4').evaluate().isNotEmpty);
      expect(find.text('Favoritos · 4'), findsOneWidget, reason: 'o favorito novo aparece');
      expect(bib.leiturasCache[a.id] ?? 0, lessThanOrEqualTo(1));
      expect(bib.leiturasCache[b.id] ?? 0, 0, reason: 'B não mudou');
      // um "visto" na lista B não relê a A
      bib.leiturasCache.clear();
      await t.runAsync(() => bib.registarVisto(b.id, _conteudo('B').canais[1]));
      await assentar(t, () => find.text('Canal 2').evaluate().isNotEmpty);
      expect(find.text('Canal 2'), findsOneWidget);
      expect(bib.leiturasCache[a.id] ?? 0, 0);
      expect(bib.leiturasCache[b.id] ?? 0, lessThanOrEqualTo(1));
    });

    testWidgets('com outra rota por cima (lista aberta, player), o Início não lê caches; lê ao voltar',
        (t) async {
      tamanho(t);
      await preparar(t);
      await abrir(t);
      final [a, b, _] = bib.listas;
      final nav = t.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('player'))));
      await t.pumpAndSettle();
      bib.leiturasCache.clear();
      // zapping no player e um favorito: nada se lê enquanto o Início está tapado
      await t.runAsync(() async {
        for (final c in _conteudo('B').canais) {
          await bib.registarVisto(b.id, c);
        }
        await bib.alternarFavorito(a.id, 'A3');
      });
      await assentar(t);
      expect(bib.leiturasCache, isEmpty, reason: 'o Início não está à vista');
      nav.pop();
      await t.pumpAndSettle();
      await assentar(t, () =>
          find.text('Favoritos · 4').evaluate().isNotEmpty && find.text('Canal 3').evaluate().isNotEmpty);
      await t.pumpAndSettle();
      expect(find.text('Favoritos · 4'), findsOneWidget, reason: 'ao voltar fica em dia');
      expect(find.text('Canal 3'), findsOneWidget);
      expect(bib.leiturasCache[a.id] ?? 0, lessThanOrEqualTo(1));
      expect(bib.leiturasCache[b.id] ?? 0, lessThanOrEqualTo(1));
    });

    testWidgets('no computador, a barra de teclas tem as três dicas', (t) async {
      tamanho(t);
      await preparar(t);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await abrir(t);
        expect(find.text('abrir'), findsOneWidget);
        expect(find.text('opções da lista'), findsOneWidget);
        expect(find.text('menu'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
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
      expect(find.text('Ficheiro, texto colado, stbstalker ou Telegram'), findsOneWidget);
      expect(find.text('Testamos 3 canais de cada lista'), findsOneWidget);
      expect(find.text('As que funcionam aparecem aqui'), findsOneWidget);
      // o Início não oferece importar a cópia de segurança (é nas Definições)
      expect(find.text('Importar cópia de segurança'), findsNothing);
    });
  });

  /// Nove listas Stalker (as pares verificadas, com validade; a 2 não funciona, com motivo), a
  /// primeira com cache, um favorito e um canal visto.
  Future<void> povoarCompacto(WidgetTester t) => t.runAsync(() async {
        await bib.adicionar([
          for (var i = 0; i < 9; i++)
            Importada(
                contaDeLinha('http://servidor-$i.exemplo.pt/c/ 00:1A:79:00:00:0$i')!,
                i.isEven
                    ? UltimaVerificacao(
                        estado: i == 2 ? 'nao_funciona' : 'funciona',
                        motivo: i == 2 ? 'sem resposta' : '',
                        validade: '2027-10-16',
                        data: DateTime.now().subtract(const Duration(hours: 2)))
                    : null),
        ]);
        await bib.guardarCanais(bib.listas.first.id, _conteudo('A'));
        await bib.alternarFavorito(bib.listas.first.id, 'A1');
        await bib.registarVisto(bib.listas.first.id, _conteudo('A').canais[2]);
      });

  /// Espera pelos resumos (contagens, número do canal visto), lidos das caches fora do build.
  Future<void> esperarResumos(WidgetTester t) async {
    for (var i = 0; i < 50 && find.text('3 canais').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  /// A casca no Início, a 80 % (como na TV no Compacto).
  Widget cascaCompacta() => MaterialApp(
      theme: temaApp(),
      builder: (_, c) => TemaConformeRealce(child: EscalaInterface(escala: escalaCompacto, child: c!)),
      home: TelaPrincipal(verTv: TelaInicio(biblioteca: bib), gestor: const SizedBox(), definicoes: const SizedBox()));

  group('compacto na TV (960×540, a 80 %, na casca)', () {
    testWidgets('«Continuar a ver» baixo, pesquisa e filtros numa linha e pelo menos 3 cartões por linha',
        (t) async {
      ecraTvTeste(t);
      await povoarCompacto(t);
      await t.pumpWidget(cascaCompacta());
      await esperarResumos(t);
      expect(t.takeException(), isNull);

      // «Continuar a ver»: uma faixa baixa (≤ 72 lógicos), com o canal, a lista e o botão Ver
      final continuar = find.byKey(const Key('continuar-a-ver'));
      expect(t.getRect(continuar).height, lessThanOrEqualTo(72 * escalaCompacto));
      for (final s in ['A Sport TV', 'Canal 3', 'Ver', 'CONTINUAR A VER']) {
        expect(find.descendant(of: continuar, matching: find.textContaining(s)), findsOneWidget, reason: s);
      }

      // a pesquisa e os filtros na mesma linha
      final pesquisa = t.getCenter(find.byType(TextField));
      for (final f in ['Todas', 'Funcionam']) {
        expect(t.getCenter(find.widgetWithText(ChoiceChip, f)).dy, moreOrLessEquals(pesquisa.dy, epsilon: 2), reason: f);
      }

      // pelo menos 3 cartões na primeira linha
      final cartoes = find.byType(CartaoLista);
      final topo = t.getRect(cartoes.first).top;
      var naLinha = 0;
      for (var i = 0; i < cartoes.evaluate().length; i++) {
        if ((t.getRect(cartoes.at(i)).top - topo).abs() < 1) naLinha++;
      }
      expect(naLinha, greaterThanOrEqualTo(3));

      // cada cartão: o tipo ao lado do servidor, as contagens inteiras por baixo; a validade ao lado
      // da pílula ou, quando não cabe (com a letra larga dos testes nunca cabe), logo por baixo
      final c = find.byWidget(t.widget<CartaoLista>(cartoes.first));
      final tipo = t.getCenter(find.descendant(of: c, matching: find.text('STALKER')));
      expect(t.getCenter(find.descendant(of: c, matching: find.byKey(const Key('lista-servidor')))).dy,
          moreOrLessEquals(tipo.dy, epsilon: 1));
      final canais = find.descendant(of: c, matching: find.text('3 canais'));
      expect(t.getCenter(canais).dy, greaterThan(tipo.dy));
      expect(t.renderObject<RenderParagraph>(canais).didExceedMaxLines, isFalse, reason: 'as contagens inteiras');
      final pilula = t.getRect(find.descendant(of: c, matching: find.byType(PilulaEstado)));
      final validade = t.getRect(find.descendant(of: c, matching: find.text('até 16/10/2027')));
      expect(validade.top >= pilula.bottom || (validade.center.dy - pilula.center.dy).abs() < 1, isTrue,
          reason: 'pílula $pilula, validade $validade');
      expect(validade.bottom, lessThanOrEqualTo(t.getRect(c).bottom), reason: 'cabe no cartão');
      // o estado nunca se corta
      expect(t.renderObject<RenderParagraph>(find.descendant(of: c, matching: find.text('Funciona'))).didExceedMaxLines,
          isFalse);
      // o motivo continua no cartão que não funciona
      expect(find.text('sem resposta'), findsOneWidget);
    });

    for (final f in [1.5, 2.0]) {
      testWidgets('com a letra do sistema a ${f}x, as alturas crescem e nada transborda', (t) async {
        ecraTvTeste(t);
        t.platformDispatcher.textScaleFactorTestValue = f;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await povoarCompacto(t);
        await t.pumpWidget(cascaCompacta());
        await esperarResumos(t);
        expect(t.takeException(), isNull, reason: 'sem overflow');
        expect(find.textContaining('Canal 3'), findsOneWidget);
        // desce até aos cartões (com a letra grande ficam por baixo da dobra) e ao que tem motivo
        final rolo = find.descendant(
            of: find.byType(TelaInicio),
            matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down));
        await t.scrollUntilVisible(find.text('sem resposta'), 120, scrollable: rolo.first);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'sem overflow nos cartões');
        expect(find.byType(CartaoLista), findsWidgets);
      });
    }
  });

  group('no telemóvel (360)', () {
    void telemovel(WidgetTester t) {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
    }

    testWidgets('a pílula mostra «Funciona · verificada há 3 dias» completo; a validade passa para baixo',
        (t) async {
      telemovel(t);
      await t.runAsync(() => bib.adicionar([
            Importada(
                contaDeLinha('http://servidor.exemplo.pt/c/ 00:1A:79:00:00:01')!,
                UltimaVerificacao(
                    estado: 'funciona',
                    validade: '2027-10-16',
                    data: DateTime.now().subtract(const Duration(days: 3, minutes: 5)))),
          ]));
      await t.pumpWidget(_app(TelaInicio(biblioteca: bib)));
      await t.pump();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final estado = find.text('Funciona'), detalhe = find.text(' · verificada há 3 dias');
      expect(estado, findsOneWidget);
      expect(detalhe, findsOneWidget);
      expect(t.renderObject<RenderParagraph>(estado).didExceedMaxLines, isFalse, reason: 'o estado inteiro');
      expect(t.renderObject<RenderParagraph>(detalhe).didExceedMaxLines, isFalse, reason: 'o detalhe inteiro');
      final pilula = t.getRect(find.byType(PilulaEstado));
      final validade = t.getRect(find.text('até 16/10/2027'));
      expect(validade.top, greaterThanOrEqualTo(pilula.bottom), reason: 'não cabe ao lado: vai para baixo');
      expect(validade.bottom, lessThanOrEqualTo(t.getRect(find.byType(CartaoLista)).bottom));
    });

    for (final f in [1.5, 2.0]) {
      testWidgets('com a letra do sistema a ${f}x, nada transborda', (t) async {
        telemovel(t);
        t.platformDispatcher.textScaleFactorTestValue = f;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await povoarCompacto(t);
        await t.pumpWidget(_app(TelaInicio(biblioteca: bib)));
        await esperarResumos(t);
        expect(t.takeException(), isNull, reason: 'sem overflow');
        expect(find.byKey(const Key('continuar-a-ver')), findsOneWidget);
        expect(find.text('Favoritos · 1'), findsOneWidget);
        await t.scrollUntilVisible(find.text('sem resposta'), 120,
            scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'sem overflow nos cartões');
      });
    }
  });
}
