import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/guia/servico_guia.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/definicoes/tela_definicoes.dart';
import 'package:player_iptv/ui/design/ecra.dart';
import 'package:player_iptv/ui/poupanca_dados.dart';

import '../guia/servico_guia_test.dart' show FonteFalsa, agora;
import 'ajuda_dpad.dart';
import 'apoio_telemovel.dart';

final _pergunta = find.byKey(const Key('pergunta-dados-moveis'));

void main() {
  group('a pergunta', () {
    late EstadoLigacao ligacao;
    late bool ativa;
    late BuildContext ctx;
    PoupancaDados criar() => PoupancaDados(ligacao: () async => ligacao, ativa: () => ativa);

    setUp(() {
      ligacao = (movel: true, limitada: true);
      ativa = true;
    });

    Future<void> montar(WidgetTester t) async {
      await t.pumpWidget(appTeste(Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: Text('base'));
      })));
    }

    /// Pede autorização e responde à pergunta (se aparecer) com `botao`; devolve o resultado.
    Future<(bool, bool)> pedir(WidgetTester t, PoupancaDados p, AcaoDados acao,
        {bool automatico = false, String botao = 'Agora não', int quantas = 1}) async {
      bool? r;
      p.autorizar(ctx, acao, automatico: automatico, quantas: quantas).then((v) => r = v);
      await t.pumpAndSettle();
      final perguntou = _pergunta.evaluate().isNotEmpty;
      if (perguntou) {
        await t.tap(find.text(botao));
        await t.pumpAndSettle();
      }
      return (r!, perguntou);
    }

    testWidgets('sem dados móveis (Wi‑Fi): não pergunta', (t) async {
      await montar(t);
      ligacao = (movel: false, limitada: false);
      expect(await pedir(t, criar(), AcaoDados.canais), (true, false));
    });

    testWidgets('com a opção desligada (ou fora do telemóvel): não pergunta', (t) async {
      await montar(t);
      ativa = false;
      expect(await pedir(t, criar(), AcaoDados.guia), (true, false));
    });

    testWidgets('com dados móveis: pergunta; aceitar vale para o resto da sessão', (t) async {
      await montar(t);
      final p = criar();
      bool? r;
      p.autorizar(ctx, AcaoDados.canais).then((v) => r = v);
      await t.pumpAndSettle();
      expect(find.text('Está a usar dados móveis'), findsOneWidget);
      expect(find.text('Carregar os canais desta lista do servidor? Uma lista grande pode gastar vários MB.'),
          findsOneWidget);
      await t.tap(find.text('Carregar'));
      await t.pumpAndSettle();
      expect(r, isTrue);
      expect(await pedir(t, p, AcaoDados.canais), (true, false), reason: 'já aceite nesta sessão');
    });

    testWidgets('«Agora não»: o automático (guia) não volta a perguntar; o pedido do utilizador volta', (t) async {
      await montar(t);
      final p = criar();
      expect(await pedir(t, p, AcaoDados.guia, automatico: true), (false, true));
      expect(await pedir(t, p, AcaoDados.guia, automatico: true), (false, false));
      expect(await pedir(t, p, AcaoDados.guia, botao: 'Descarregar'), (true, true));
    });

    testWidgets('numa rede limitada (sem ser dados móveis) também pergunta, com o título dela', (t) async {
      await montar(t);
      ligacao = (movel: false, limitada: true);
      bool? r;
      criar().autorizar(ctx, AcaoDados.verificacao, quantas: 12).then((v) => r = v);
      await t.pumpAndSettle();
      expect(find.text('Está numa rede limitada'), findsOneWidget);
      expect(find.textContaining('Verificar 12 listas?'), findsOneWidget);
      await t.tap(find.text('Agora não'));
      await t.pumpAndSettle();
      expect(r, isFalse);
    });

    testWidgets('fora de um aparelho Android (aqui, o computador dos testes), por omissão, nunca pergunta', (t) async {
      await montar(t);
      expect(await pedir(t, PoupancaDados(ligacao: () async => ligacao), AcaoDados.canais), (true, false));
    });
  });

  test('o guia: sem autorização, não descarrega o de todos, mas pede o do canal', () async {
    final f = FonteFalsa(todosDa: () => {}, canalDa: (_) => const []);
    final s = ServicoGuia(chave: 'l', conta: Conta('x', Tipo.xtream, 'http://x'), fonte: f, agora: () => agora)
      ..autorizarTodos = () async => false;
    await s.usarCanais(const [Canal(id: '1', nome: 'RTP 1', grupo: 'PT')]);
    expect(f.pedidosTodos, 0);
    expect(s.poupado, isTrue);
    expect(s.estado, EstadoGuia.soPorCanal);
    await s.pedirCanal(const Canal(id: '1', nome: 'RTP 1', grupo: 'PT'));
    expect(f.pedidosCanal, ['1'], reason: 'o de um canal gasta pouco');
    s.dispose();
  });

  group('no ecrã', () {
    late Directory pasta;
    late Biblioteca bib;
    final antes = PoupancaDados.atual;
    setUp(() async {
      pasta = Directory.systemTemp.createTempSync('poupar');
      bib = await Biblioteca.abrir(pasta);
      PoupancaDados.atual = PoupancaDados(ligacao: () async => (movel: true, limitada: true), ativa: () => true);
    });
    tearDown(() {
      PoupancaDados.atual = antes;
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });

    testWidgets('Ver TV com dados móveis: pergunta antes do guia; «Agora não» deixa a pesquisa só pelo nome',
        (t) async {
      ecraTvTeste(t);
      final fonte = FonteFalsa(todosDa: () => {}, canalDa: (_) => const []);
      await t.runAsync(() async {
        await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
        await bib.guardarCanais(bib.listas.single.id,
            ConteudoLista(['PT'], const [Canal(id: '1', nome: 'RTP 1', grupo: 'PT')]));
      });
      final l = bib.listas.single;
      await t.runAsync(() async {
        await t.pumpWidget(appTeste(TelaConteudo(biblioteca: bib, lista: l, abrir: (c, i) => null,
            guia: (l) => ServicoGuia(chave: l.id, conta: l.conta, fonte: fonte, agora: () => agora))));
        await t.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pumpAndSettle();
      expect(find.text('Descarregar a programação de todos os canais desta lista? Pode gastar dezenas de MB. '
          'Sem ela, a programação de um canal só é pedida quando o escolhe (poucos dados), e a pesquisa é só pelo nome.'),
          findsOneWidget);
      await t.tap(find.text('Agora não'));
      // a pergunta abriu-se no relógio real (o guia arrancou no runAsync): a resposta segue nele
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(fonte.pedidosTodos, 0);
      await t.tap(find.byKey(const Key('pesquisa-canais')));
      await t.pump();
      await t.enterText(find.byKey(const Key('pesquisa-canais')), 'jornal');
      await t.pump(const Duration(milliseconds: 200));
      await t.pumpAndSettle();
      expect(find.text('A programação de todos os canais ficou por descarregar (dados móveis): a pesquisa é só pelo nome.'),
          findsOneWidget);
    });
  });

  group('Definições › Ligação', () {
    late Directory pasta;
    setUp(() => pasta = Directory.systemTemp.createTempSync('poupar_defs'));
    tearDown(() {
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });

    Future<Preferencias> abrir(WidgetTester t, {required bool tv}) async {
      late Biblioteca bib;
      late AreaGestor area;
      late Preferencias prefs;
      await t.runAsync(() async {
        bib = await Biblioteca.abrir(pasta);
        area = await AreaGestor.abrir(pasta);
        prefs = await Preferencias.abrir(pasta);
      });
      await t.pumpWidget(appTelemovel(TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs, android: true)));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Ligação'));
      await t.pump(const Duration(milliseconds: 400));
      return prefs;
    }

    testWidgets('no telemóvel: «Poupar dados móveis», ligada por omissão, e desliga-se', (t) async {
      final prefs = await abrir(t, tv: false);
      expect(find.text('Poupar dados móveis'), findsOneWidget);
      expect(prefs.pouparDados, isTrue);
      await t.tap(find.text('Poupar dados móveis'));
      await t.pump();
      expect(prefs.pouparDados, isFalse);
    });

    testWidgets('na TV não aparece', (t) async {
      EcraTv.nativo = true;
      addTearDown(() => EcraTv.nativo = false);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await abrir(t, tv: true);
      debugDefaultTargetPlatformOverride = null;
      expect(find.text('Poupar dados móveis'), findsNothing);
    });
  });
}
