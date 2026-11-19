import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/protocolo.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/tarefas/servico_tarefas.dart';
import 'package:player_iptv/ui/design/componentes.dart';
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
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso}) async {
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
        colecao: area, verificador: roteiro, ritmo: RitmoHost(intervalo: Duration.zero), agora: agora);
  }

  Future<void> abrirVerificacao(WidgetTester t, ServicoVerificacao s) async {
    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
        _app(Scaffold(body: TelaGestor(biblioteca: bib, area: area, servico: s, tarefas: ServicoTarefas()))));
    await t.pump();
    await t.tap(find.descendant(of: find.byType(CartaoModerno), matching: find.text('Verificar')));
    await t.pumpAndSettle();
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
    expect(find.textContaining('Verificação parada'), findsOneWidget);
    // as que estavam a correr param assim que o verificador devolve
    roteiro.soltar();
    await esperar(t, () => !s.ocupado);
    expect(find.text('Parar'), findsNothing);
  });

  testWidgets('"Verificar mais (fila)" vai ao principal com o filtro "Por verificar"', (t) async {
    await t.runAsync(() => area.adicionar([
          Importada(_conta('boa', 1), UltimaVerificacao(estado: 'funciona', data: DateTime(2026, 3, 1))),
          Importada(_conta('nova', 2)),
        ]));
    await abrirVerificacao(t, servico({}));
    await t.tap(find.text('Verificar mais (fila)'));
    await t.pumpAndSettle();
    expect(find.text('Gestor de listas'), findsOneWidget);
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Por verificar · 1')).selected, isTrue);
    expect(find.textContaining('NOVA'), findsWidgets);
    expect(find.text('Verificar (entra na fila)'), findsOneWidget);
  });
}
