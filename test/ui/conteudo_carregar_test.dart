import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/protocolo.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/verificador.dart';

/// Task 8: ao abrir uma lista, cache vs servidor (loader moderno), e as listas mortas marcadas
/// sozinhas como "Não funciona".

Widget _app(Widget w, {bool semAnimacoes = false}) => MaterialApp(
      theme: temaApp(),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(disableAnimations: semAnimacoes),
        child: TemaConformeRealce(child: w!),
      ),
      home: w,
    );

void _tamanho(WidgetTester t, double l, double a) {
  t.view.physicalSize = Size(l, a);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

final _canais = ConteudoLista(['G'], const [Canal(id: '1', nome: 'RTP 1', grupo: 'G', url: 'u')]);

/// Um servidor falso controlado pelo teste.
class _Servidor {
  final pedidos = <Cancelamento?>[];
  Aviso? aviso;
  // criado dentro do teste (um erro não passa de uma zona para outra: o setUp tem a sua)
  Completer<ConteudoLista>? _resposta;
  Completer<ConteudoLista> get resposta => _resposta ??= Completer();

  Future<ConteudoLista> abrir(Conta c, {Cancelamento? cancelamento, Aviso? aviso}) {
    pedidos.add(cancelamento);
    this.aviso = aviso;
    return resposta.future;
  }
}

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late _Servidor srv;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('carregar');
    bib = await Biblioteca.abrir(pasta);
    srv = _Servidor();
  });
  tearDown(() async {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  /// IO real (disco) com pumps pelo meio, até `feito` (ou ~2 s).
  Future<void> esperar(WidgetTester t, bool Function() feito) async {
    for (var i = 0; i < 40 && !feito(); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<Lista> lista(WidgetTester t, {bool comCache = false, UltimaVerificacao? ultima}) async {
    await t.runAsync(() async {
      await bib.adicionar([Importada(Conta('', Tipo.xtream, 'http://h.com:8080', utilizador: 'u', password: 'p'), ultima)]);
      if (comCache) await bib.guardarCanais(bib.listas.single.id, _canais);
    });
    return bib.listas.single;
  }

  Future<void> abrir(WidgetTester t, Lista l,
      {bool atualizar = false, bool semAnimacoes = false, ResolverDns? dns}) async {
    _tamanho(t, 1200, 800);
    await t.pumpWidget(_app(
        TelaConteudo(biblioteca: bib, lista: l, atualizar: atualizar, abrirLista: srv.abrir, dns: dns ?? (_) async => null),
        semAnimacoes: semAnimacoes));
  }

  final loader = find.byType(CarregadorCanais);

  group('cache e servidor', () {
    testWidgets('sem cache: o loader em ecrã cheio com os passos, a barra (com total) e Cancelar', (t) async {
      final l = await lista(t);
      await abrir(t, l);
      await esperar(t, () => loader.evaluate().isNotEmpty);
      expect(loader, findsOneWidget);
      expect(find.text('A ligar…'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cancelar'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing, reason: 'sem total, sem barra');

      srv.aviso!('a ligar ao portal (/c)');
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('A ligar ao portal'), findsOneWidget);
      srv.aviso!('a pedir as categorias');
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('A pedir as categorias'), findsOneWidget);
      srv.aviso!('a pedir os canais · página 3/12');
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('A pedir os canais · página 3/12'), findsOneWidget);
      expect(t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, closeTo(.25, .001));

      srv.resposta.complete(_canais);
      await esperar(t, () => find.text('RTP 1').evaluate().isNotEmpty);
      expect(find.text('RTP 1'), findsOneWidget);
      expect(loader, findsNothing);
      expect(find.textContaining('da cache'), findsNothing, reason: 'acabados de chegar do servidor');
    });

    testWidgets('com cache: os canais logo, sem loader e sem pedir ao servidor; "da cache · hoje às…"', (t) async {
      final l = await lista(t, comCache: true);
      await abrir(t, l);
      await esperar(t, () => find.text('RTP 1').evaluate().isNotEmpty);
      expect(find.text('RTP 1'), findsOneWidget);
      expect(loader, findsNothing);
      expect(srv.pedidos, isEmpty);
      expect(find.textContaining(RegExp(r'^da cache · hoje às \d\d:\d\d$')), findsOneWidget);
      expect(find.byTooltip('Atualizar a lista de canais'), findsOneWidget);
    });

    testWidgets('Atualizar com cache: o loader por cima; Cancelar volta aos canais da cache', (t) async {
      final l = await lista(t, comCache: true);
      await abrir(t, l);
      await esperar(t, () => find.text('RTP 1').evaluate().isNotEmpty);
      await t.tap(find.byTooltip('Atualizar a lista de canais'));
      await t.pump();
      expect(loader, findsOneWidget);
      expect(srv.pedidos, hasLength(1));
      await t.tap(find.widgetWithText(OutlinedButton, 'Cancelar'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(srv.pedidos.single!.cancelado, isTrue);
      expect(loader, findsNothing);
      expect(find.text('RTP 1'), findsOneWidget);
    });

    testWidgets('"Atualizar canais" (do menu) com cache: pede ao servidor logo ao abrir', (t) async {
      final l = await lista(t, comCache: true);
      await abrir(t, l, atualizar: true);
      await esperar(t, () => loader.evaluate().isNotEmpty);
      expect(loader, findsOneWidget);
      expect(srv.pedidos, hasLength(1));
      srv.resposta.complete(ConteudoLista(['G'], const [Canal(id: '2', nome: 'SIC', grupo: 'G', url: 'u')]));
      await esperar(t, () => find.text('SIC').evaluate().isNotEmpty);
      expect(find.text('SIC'), findsOneWidget);
      expect(find.textContaining('da cache'), findsNothing);
    });

    testWidgets('movimento reduzido: o loader fica parado (nada a animar)', (t) async {
      final l = await lista(t);
      await abrir(t, l, semAnimacoes: true);
      await esperar(t, () => loader.evaluate().isNotEmpty);
      expect(loader, findsOneWidget);
      // sem animações infinitas: assenta
      await t.pumpAndSettle();
      expect(loader, findsOneWidget);
      srv.resposta.complete(_canais);
      await esperar(t, () => find.text('RTP 1').evaluate().isNotEmpty);
    });

    test('passoCarregamento: maiúscula, sem o caminho do portal, progresso com total', () {
      expect(passoCarregamento('a ligar ao portal (/stalker_portal)'), ('A ligar ao portal', null));
      expect(passoCarregamento('a pedir os canais · página 3/12'), ('A pedir os canais · página 3/12', .25));
      expect(passoCarregamento('a pedir os canais · página 3'), ('A pedir os canais · página 3', null));
      expect(passoCarregamento(''), ('A ligar…', null));
    });
  });

  group('listas mortas', () {
    Future<UltimaVerificacao?> falhar(WidgetTester t, Object erro,
        {UltimaVerificacao? antes, ResolverDns? dns}) async {
      final l = await lista(t, ultima: antes);
      await abrir(t, l, dns: dns);
      await esperar(t, () => srv.pedidos.isNotEmpty);
      srv.resposta.completeError(erro);
      await esperar(t, () => find.text('Tentar de novo').evaluate().isNotEmpty);
      // a gravação (IO real) acaba com pumps pelo meio
      for (var i = 0; i < 10; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump();
      }
      return (await t.runAsync(() => Biblioteca.abrir(pasta)))!.listas.single.ultima;
    }

    testWidgets('erro definitivo: marcada "Não funciona" com o motivo e a data (como uma verificação)', (t) async {
      final antes = DateTime.now();
      final u = await falhar(t, ErroLista('autenticação recusada', definitivo: true),
          antes: UltimaVerificacao(estado: 'funciona', data: DateTime(2026, 1, 1)));
      expect(u!.estado, 'nao_funciona');
      expect(u.motivo, 'autenticação recusada');
      expect(u.data.isAfter(antes.subtract(const Duration(seconds: 1))), isTrue);
      expect(bib.listas.single.ultima!.estado, 'nao_funciona');
      expect(find.descendant(of: find.byType(PilulaEstado), matching: find.text('Não funciona')), findsOneWidget);
    });

    testWidgets('DNS inexistente: marcada "Não funciona"', (t) async {
      final u = await falhar(t, const SocketException('Failed host lookup'),
          dns: (h) async => ResultadoVerificacao(EstadoV.naoFunciona, 'DNS: $h não existe'));
      expect(u!.estado, 'nao_funciona');
      expect(u.motivo, 'DNS: h.com não existe');
    });

    for (final (nome, erro) in [
      ('tempo esgotado', TimeoutException('t')),
      ('5xx', ErroHttp(503)),
      ('459', ErroHttp(459)),
      ('ErroLista não definitivo', ErroLista('o portal não devolveu canais')),
    ]) {
      testWidgets('erro temporário ($nome): o estado não muda', (t) async {
        final antes = UltimaVerificacao(estado: 'funciona', data: DateTime(2026, 1, 1), motivo: 'abriu RTP 1');
        final u = await falhar(t, erro, antes: antes,
            dns: (_) async => const ResultadoVerificacao(EstadoV.inconclusivo, 'DNS sem resposta'));
        expect((u!.estado, u.motivo, u.data), ('funciona', 'abriu RTP 1', DateTime(2026, 1, 1)));
      });
    }
  });
}
