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
import 'package:player_iptv/ui/gestor/indicador_atividade.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';

Widget _app(Widget w) =>
    MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

/// Fica preso até ao fim do teste.
class _Preso extends Verificador {
  @override
  Future<ResultadoVerificacao> verificarComLimite(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso, Duration? limite}) async {
    await Completer<void>().future;
    return const ResultadoVerificacao(EstadoV.funciona, 'ok');
  }
}

/// Responde logo.
class _Rapido extends Verificador {
  @override
  Future<ResultadoVerificacao> verificarComLimite(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso, Duration? limite}) async =>
      const ResultadoVerificacao(EstadoV.funciona, 'ok');
}

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;
  late ServicoTarefas tarefas;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('atividade_ui');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
    tarefas = ServicoTarefas();
  });
  tearDown(() async {
    tarefas.dispose();
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Widget casca(ServicoVerificacao s, {Seccao inicial = Seccao.verTv}) {
    final p = ValueNotifier<EcraGestor?>(null);
    return _app(TelaPrincipal(
      inicial: inicial,
      tarefas: tarefas,
      verificacao: s,
      pedidoGestor: p,
      verTv: const Scaffold(body: Text('ecra ver tv')),
      gestor: TelaGestor(biblioteca: bib, area: area, servico: s, tarefas: tarefas, pedido: p),
      definicoes: const SizedBox(),
    ));
  }

  void tamanho(WidgetTester t) {
    t.view.physicalSize = const Size(1200, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Future<void> abrirPainel(WidgetTester t) async {
    await t.tap(find.byType(IndicadorAtividade));
    // com tarefas a decorrer há barras a animar: não se espera que assente
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }

  Future<void> adicionar(WidgetTester t, List<String> linhas) => t.runAsync(() => area.adicionar([
        for (final l in linhas) Importada(contaDeLinha(l)!, null),
      ]));

  testWidgets('com uma verificacao e uma pesquisa a correr o painel mostra 2 cartoes a decorrer', (t) async {
    tamanho(t);
    await adicionar(t, ['http://a.com/c/ 00:1A:79:00:00:01']);
    final s = ServicoVerificacao(bib, colecao: area, verificador: _Preso());
    await t.pumpWidget(casca(s, inicial: Seccao.gestor));
    await t.pump();
    s.verificar(area.listas.first);
    final c = Completer<String>();
    tarefas.iniciar('Pesquisa no stbstalker · hoje', (p) => c.future);
    await t.pump();
    await abrirPainel(t);
    expect(find.text('Atividade'), findsOneWidget);
    expect(find.text('2 a decorrer · 0 terminadas'), findsOneWidget);
    expect(find.text('Verificação das listas'), findsOneWidget);
    expect(find.text('Pesquisa no stbstalker · hoje'), findsOneWidget);
    expect(find.text('Parar'), findsNWidgets(2));
    expect(find.text('Ver detalhe'), findsNWidgets(2));
    expect(find.textContaining('Podes fechar este painel'), findsOneWidget);
    s.parar();
    c.complete('ok');
    await t.pump();
  });

  testWidgets('uma tarefa de envio (nao cancelavel) nao mostra "Parar"', (t) async {
    tamanho(t);
    final s = ServicoVerificacao(bib, colecao: area, verificador: _Preso());
    await t.pumpWidget(casca(s, inicial: Seccao.gestor));
    final envio = Completer<String>(), pesquisa = Completer<String>();
    tarefas.iniciar('Enviar 2 listas para o Player', (p) => envio.future, cancelavel: false);
    tarefas.iniciar('Pesquisa no stbstalker · hoje', (p) => pesquisa.future);
    await t.pump();
    await abrirPainel(t);
    expect(find.text('Enviar 2 listas para o Player'), findsOneWidget);
    expect(find.text('Parar'), findsOneWidget, reason: 'só a pesquisa se pode parar');
    final cartaoEnvio = find.ancestor(of: find.text('Enviar 2 listas para o Player'), matching: find.byType(Column)).first;
    expect(find.descendant(of: cartaoEnvio, matching: find.text('Parar')), findsNothing);
    envio.complete('ok');
    pesquisa.complete('ok');
    await t.pump();
  });

  testWidgets('uma tarefa que falhou mostra "Tentar de novo" e chama repetir', (t) async {
    tamanho(t);
    final s = ServicoVerificacao(bib, colecao: area, verificador: _Preso());
    await t.pumpWidget(casca(s, inicial: Seccao.gestor));
    var repetiu = 0;
    tarefas.iniciar('Exportar 2 listas', (p) async => throw 'Sem espaço', repetir: () async => repetiu++);
    await t.pump();
    await t.pump();
    await abrirPainel(t);
    await t.tap(find.widgetWithText(TextButton, 'Tentar de novo'));
    await t.pump();
    expect(repetiu, 1);
  });

  testWidgets('em Ver TV, uma tarefa que acaba mostra o aviso com a acao', (t) async {
    tamanho(t);
    final s = ServicoVerificacao(bib, colecao: area, verificador: _Preso());
    await t.pumpWidget(casca(s));
    var acao = 0;
    tarefas.iniciar('Enviar 1 lista', (p) async => '1 lista enviada para o Player',
        rotuloAcao: 'Ir para Ver TV', aoAcao: () => acao++);
    await t.pump();
    await t.pump();
    expect(find.text('1 lista enviada para o Player'), findsOneWidget);
    expect(find.text('Menu: Ir para Ver TV'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await t.pump();
    expect(acao, 1);
  });

  testWidgets('uma tarefa que falha com repetir oferece "Tentar de novo" no aviso', (t) async {
    tamanho(t);
    final s = ServicoVerificacao(bib, colecao: area, verificador: _Preso());
    await t.pumpWidget(casca(s));
    var repetiu = 0;
    tarefas.iniciar('Exportar', (p) async => throw 'Sem espaço', repetir: () async => repetiu++);
    await t.pump();
    await t.pump();
    expect(find.text('Menu: Tentar de novo'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await t.pump();
    expect(repetiu, 1);
  });

  testWidgets('em Ver TV, quando a verificacao do Gestor acaba, "Ver resultados" leva ao Gestor', (t) async {
    tamanho(t);
    await adicionar(t, ['http://a.com/c/ 00:1A:79:00:00:01', 'http://b.com/c/ 00:1A:79:00:00:02']);
    final s = ServicoVerificacao(bib, colecao: area, verificador: _Rapido());
    await t.pumpWidget(casca(s));
    await t.pump();
    unawaited(s.verificarVarias(area.listas));
    for (var i = 0; i < 100 && find.textContaining('Verificação terminada').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(find.text('Verificação terminada: 2 funcionam, 0 não'), findsOneWidget);
    expect(find.text('Menu: Ver resultados'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await t.pumpAndSettle();
    expect(find.text('Verificação'), findsOneWidget, reason: 'o sub-ecrã da verificação está aberto');
  });

  testWidgets('Voltar fecha o painel e o foco regressa ao indicador', (t) async {
    tamanho(t);
    final s = ServicoVerificacao(bib, colecao: area, verificador: _Preso());
    await t.pumpWidget(casca(s, inicial: Seccao.gestor));
    await t.pump();
    await abrirPainel(t);
    expect(find.text('Atividade'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Atividade'), findsNothing);
    final foco = FocusManager.instance.primaryFocus!;
    expect(foco.debugLabel, 'Indicador de atividade');
  });
}
