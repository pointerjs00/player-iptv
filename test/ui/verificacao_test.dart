import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/protocolo.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/tarefas/servico_tarefas.dart';
import 'package:player_iptv/ui/gestor/painel_atividade.dart';
import 'package:player_iptv/ui/gestor/passo_verificar.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/ui/gestor/tela_verificacao.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';

Widget _app(Widget w) => MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

/// Pelo servidor: os que têm um resultado dado acabam logo; os outros ficam no "canal 2/3" até
/// ao fim do teste (sem relógios: o teste acaba sem tempos pendentes).
class _Roteiro extends Verificador {
  _Roteiro(this.resultados);
  final Map<String, ResultadoVerificacao> resultados;
  final _nunca = Completer<void>();

  /// Deixa as presas acabar (as paradas saem sem gravar).
  void soltar() => _nunca.complete();

  @override
  Future<ResultadoVerificacao> verificarComLimite(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso, Duration? limite}) async {
    for (final e in resultados.entries) {
      if (conta.endereco.contains(e.key)) return e.value;
    }
    aviso?.call('canal 2/3 · a abrir o stream');
    await _nunca.future;
    return const ResultadoVerificacao(EstadoV.funciona, 'ok');
  }
}

Conta _conta(String host, int n) =>
    contaDeLinha('http://$host.com/c/ 00:1A:79:00:00:${n.toRadixString(16).padLeft(2, '0')}')!;

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('verificacao_ui');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  late _Roteiro roteiro;

  ServicoVerificacao servico(Map<String, ResultadoVerificacao> r, {DateTime Function()? agora}) {
    roteiro = _Roteiro(r);
    return ServicoVerificacao(bib,
        colecao: area, verificador: roteiro, workers: 4, ritmo: RitmoHost(intervalo: Duration.zero), agora: agora);
  }

  Future<void> abrirVerificacao(WidgetTester t, ServicoVerificacao s) async {
    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // o progresso abre do passo 2 (o indicador do topo) ou da casca ("Ver resultados"): aqui pela casca
    final pedido = ValueNotifier<EcraGestor?>(null);
    addTearDown(pedido.dispose);
    await t.pumpWidget(_app(Scaffold(
        body: TelaGestor(biblioteca: bib, area: area, servico: s, tarefas: ServicoTarefas(), pedido: pedido))));
    await t.pump();
    pedido.value = EcraGestor.verificacao;
    await t.pumpAndSettle();
    expect(find.byType(TelaVerificacao).hitTestable(), findsOneWidget);
  }

  /// Deixa acabar as escritas em disco (IO real).
  Future<void> esperar(WidgetTester t, bool Function() feito) async {
    for (var i = 0; i < 200 && !feito(); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    await t.pump();
    expect(feito(), isTrue);
  }

  test('os textos: estimativa em minutos ou segundos, e o canal a testar', () {
    expect(TelaVerificacao.textoEstimativa(const Duration(minutes: 3)), 'faltam cerca de 3 min');
    expect(TelaVerificacao.textoEstimativa(const Duration(seconds: 40)), 'faltam cerca de 40 s');
    expect(TelaVerificacao.textoEstimativa(Duration.zero), 'faltam cerca de 1 s');
    expect(TelaVerificacao.textoPasso('canal 2/3 · a abrir o stream'), 'A testar canal 2 de 3');
    expect(TelaVerificacao.textoPasso('a resolver o DNS'), 'A resolver o DNS');
  });

  testWidgets('a correr: "11 de 17 verificadas", a estimativa, o canal a testar, "Verificar mais" e "Parar"',
      (t) async {
    // 11 acabam logo (vêm primeiro), 6 ficam presas: 4 a correr e 2 na fila
    await t.runAsync(() => area.adicionar([
          for (var i = 0; i < 11; i++) Importada(_conta('ok$i', i + 1)),
          for (var i = 0; i < 6; i++) Importada(_conta('presa$i', i + 20)),
        ]));
    final base = DateTime(2026, 1, 1);
    late final ServicoVerificacao s;
    // cada lista acabada custou 20 s: 220 s ÷ 11 × 6 que faltam = 2 min
    s = servico({'ok': const ResultadoVerificacao(EstadoV.funciona, 'ok')},
        agora: () => base.add(Duration(seconds: 20 * s.feitas)));
    await abrirVerificacao(t, s);
    expect(find.text('Parar'), findsNothing, reason: 'sem verificação não há Parar');
    s.verificarVarias(area.listas);
    await esperar(t, () => s.feitas == 11);
    expect(find.text('A verificar 17 listas'), findsOneWidget);
    expect(find.text('11 de 17 verificadas'), findsOneWidget);
    expect(find.text('faltam cerca de 2 min'), findsOneWidget);
    expect(find.text('11 funcionam'), findsOneWidget);
    expect(find.text('A testar canal 2 de 3'), findsWidgets);
    expect(find.text('Na fila'), findsWidgets);
    expect(find.text('Pode sair, continua sozinha'), findsOneWidget);
    expect(find.text('Verificar mais (fila)'), findsOneWidget);
    expect(find.text('Parar'), findsOneWidget);
  });

  testWidgets('cada lista acabada mostra o motivo: "Não funciona · …" e "Funciona · 2 de 3 canais com imagem"',
      (t) async {
    await t.runAsync(() => area.adicionar([
          Importada(_conta('morta', 1)),
          Importada(_conta('boa', 2)),
          Importada(_conta('presa', 3)),
        ]));
    final s = servico({
      'morta': const ResultadoVerificacao(EstadoV.naoFunciona, 'acesso recusado (403)'),
      'boa': const ResultadoVerificacao(EstadoV.funciona, 'abriu RTP 1', canal: 'RTP 1', canais: [
        {'id': 'a', 'nome': 'A', 'estado': 'funciona', 'motivo': ''},
        {'id': 'b', 'nome': 'B', 'estado': 'funciona', 'motivo': ''},
        {'id': 'c', 'nome': 'C', 'estado': 'nao_funciona', 'motivo': 'sem imagem'},
      ]),
    });
    await abrirVerificacao(t, s);
    s.verificarVarias(area.listas);
    await esperar(t, () => s.feitas == 2);
    expect(find.text('Não funciona · acesso recusado (403)'), findsOneWidget);
    expect(find.text('Funciona · 2 de 3 canais com imagem'), findsOneWidget);
    expect(find.text('A testar canal 2 de 3'), findsOneWidget);
  });

  testWidgets('"Parar" pára a verificação e mostra a mensagem', (t) async {
    await t.runAsync(() => area.adicionar([Importada(_conta('presa', 1)), Importada(_conta('presa2', 2))]));
    final s = servico({});
    await abrirVerificacao(t, s);
    s.verificarVarias(area.listas);
    await t.pump();
    expect(s.ocupado, isTrue);
    await t.tap(find.text('Parar'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    // pede confirmação: "Cancelar" não pára
    expect(find.text('Parar a verificação?'), findsOneWidget);
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancelar')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(s.parada, isFalse);
    expect(s.ocupado, isTrue);
    await t.tap(find.text('Parar'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.widgetWithText(FilledButton, 'Parar'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(s.parada, isTrue);
    expect(find.textContaining('Verificação parada'), findsOneWidget);
    // as que estavam a correr param assim que o verificador devolve
    roteiro.soltar();
    await esperar(t, () => !s.ocupado);
    expect(find.text('Parar'), findsNothing);
  });

  testWidgets('depois de parar, a Atividade mostra o relatório; a confirmação não é larga demais', (t) async {
    await t.runAsync(() => area.adicionar([Importada(_conta('boa', 1)), Importada(_conta('presa', 2))]));
    final s = servico({'boa': const ResultadoVerificacao(EstadoV.funciona, 'abriu RTP 1')});
    final tarefas = ServicoTarefas();
    addTearDown(tarefas.dispose);
    var verRelatorio = 0;
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(Scaffold(
        body: Align(
            alignment: Alignment.centerRight,
            child: PainelAtividade(servico: s, tarefas: tarefas, aoVerVerificacao: () => verRelatorio++)))));
    s.verificarVarias(area.listas);
    await esperar(t, () => s.feitas == 1);
    expect(find.text('Verificação das listas'), findsOneWidget);
    await t.tap(find.text('Parar'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(t.getSize(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Material)).first).width,
        lessThan(560));
    await t.tap(find.widgetWithText(FilledButton, 'Parar'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    roteiro.soltar();
    await esperar(t, () => !s.ocupado);
    expect(find.textContaining('Parada às'), findsOneWidget);
    expect(find.text('1 funcionam, 0 não'), findsOneWidget);
    expect(find.text('0 a decorrer · 1 terminadas'), findsOneWidget);
    await t.tap(find.text('Ver detalhe'));
    expect(verRelatorio, 1);
  });

  testWidgets('"Verificar mais (fila)" vai ao passo 2 com o filtro "Por verificar" (e o foco nele)', (t) async {
    await t.runAsync(() => area.adicionar([
          Importada(_conta('boa', 1), UltimaVerificacao(estado: 'funciona', data: DateTime(2026, 3, 1))),
          Importada(_conta('nova', 2)),
        ]));
    await abrirVerificacao(t, servico({}));
    await t.tap(find.text('Verificar mais (fila)'));
    await t.pumpAndSettle();
    expect(find.byType(PassoVerificar).hitTestable(), findsOneWidget);
    final chip = find.widgetWithText(FilterChip, 'Por verificar · 1');
    expect(t.widget<FilterChip>(chip).selected, isTrue);
    for (final c in ['Funcionam · 1', 'Inconclusivas · 0', 'Não funcionam · 0']) {
      expect(t.widget<FilterChip>(find.widgetWithText(FilterChip, c)).selected, isFalse, reason: c);
    }
    expect(find.textContaining('NOVA'), findsWidgets);
    expect(find.textContaining('BOA'), findsNothing);
    expect(find.text('Ações (0)'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<FilterChip>()?.label,
        isA<Text>().having((t) => t.data, 'texto', 'Por verificar · 1'),
        reason: 'o foco vai ao filtro escolhido');
  });

  group('ronda 1 da revisão', () {
    testWidgets('acabada a ronda, o ecrã guarda as linhas, a barra e as contagens (Última verificação)', (t) async {
      await t.runAsync(() => area.adicionar([Importada(_conta('ok1', 1)), Importada(_conta('ok2', 2))]));
      final s = servico({'ok': const ResultadoVerificacao(EstadoV.funciona, 'abriu RTP 1')});
      await abrirVerificacao(t, s);
      s.verificarVarias(area.listas);
      await esperar(t, () => s.feitas == 2 || !s.ocupado);
      await esperar(t, () => !s.ocupado);
      expect(find.text('Última verificação: 2 listas'), findsOneWidget);
      expect(find.text('2 funcionam'), findsOneWidget);
      expect(find.text('Funciona · abriu RTP 1'), findsNWidgets(2));
      expect(find.text('Parar'), findsNothing);
    });

    testWidgets('re-juntar à fila uma lista já acabada na ronda conta-a e mostra-a uma só vez', (t) async {
      await t.runAsync(() => area.adicionar([Importada(_conta('ok1', 1)), Importada(_conta('presa', 2))]));
      final s = servico({'ok': const ResultadoVerificacao(EstadoV.funciona, 'abriu RTP 1')});
      await abrirVerificacao(t, s);
      s.verificarVarias(area.listas);
      await esperar(t, () => s.feitas == 1);
      final ok = area.listas.first;
      s.verificar(ok);
      expect(s.total, 2, reason: 'a mesma lista não conta duas vezes');
      expect(s.feitas, 0);
      expect(s.concluidas, isNot(contains(ok.id)));
      await esperar(t, () => s.feitas == 1);
      expect(s.total, 2);
      expect(s.concluidas.where((id) => id == ok.id), hasLength(1));
      expect(find.text('Funciona · abriu RTP 1'), findsOneWidget);
      expect(find.text('11 funcionam'), findsNothing);
      expect(find.text('1 funciona'), findsOneWidget);
    });

    testWidgets('cada linha a correr ou na fila tem "Cancelar", ao alcance do D-pad', (t) async {
      await t.runAsync(() => area.adicionar([Importada(_conta('presa1', 1)), Importada(_conta('presa2', 2))]));
      final s = servico({});
      await abrirVerificacao(t, s);
      s.verificarVarias(area.listas);
      await t.pump();
      expect(find.widgetWithText(TextButton, 'Cancelar'), findsNWidgets(2));
      var chegou = false;
      for (var i = 0; i < 30 && !chegou; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        final c = FocusManager.instance.primaryFocus?.context;
        chegou = c != null && find.descendant(of: find.byWidget(c.widget), matching: find.text('Cancelar')).evaluate().isNotEmpty ||
            (c?.widget is TextButton && find.descendant(of: find.byWidget(c!.widget), matching: find.text('Cancelar')).evaluate().isNotEmpty);
      }
      expect(chegou, isTrue, reason: 'Tab chega a um Cancelar');
      final id = area.listas.first.id;
      await t.tap(find.widgetWithText(TextButton, 'Cancelar').first);
      await t.pump();
      expect(s.aVerificar(id), isFalse);
      expect(s.total, 1);
      expect(find.widgetWithText(TextButton, 'Cancelar'), findsOneWidget);
    });

    testWidgets('"Verificar todas" junta todas à fila sem mexer na seleção', (t) async {
      await t.runAsync(() => area.adicionar([Importada(_conta('presa1', 1)), Importada(_conta('presa2', 2))]));
      final s = servico({});
      await abrirVerificacao(t, s);
      await t.tap(find.text('Verificar todas (2)'));
      await t.pump();
      expect(area.listas.every((l) => s.aVerificar(l.id)), isTrue);
      await t.tap(find.widgetWithText(TextButton, 'Voltar'));
      await t.pumpAndSettle();
      expect(find.text('Ações (0)'), findsOneWidget);
    });
  });
}
