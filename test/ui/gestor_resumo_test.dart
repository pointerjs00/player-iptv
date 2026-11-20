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
import 'package:player_iptv/ui/campo_tv.dart';
import 'package:player_iptv/ui/design/barra_teclas.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/design/ecra.dart';
import 'package:player_iptv/ui/design/escala_interface.dart';
import 'package:player_iptv/ui/design/mensagens.dart';
import 'package:player_iptv/ui/design/tokens.dart';
import 'package:player_iptv/ui/gestor/indicador_atividade.dart';
import 'package:player_iptv/ui/gestor/passo_enviar.dart';
import 'package:player_iptv/ui/gestor/passo_verificar.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/ui/gestor/tela_verificacao.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';

import 'ajuda_dpad.dart';

/// O Gestor abre no resumo (variante A): três cartões, sem nenhum passo aberto; dentro de cada
/// passo, a faixa dos passos no topo.

UltimaVerificacao _u(String estado) => UltimaVerificacao(estado: estado, data: DateTime(2026, 3, 1));

/// As que têm "presa" no endereço ficam no "canal 2/3" até ao fim do teste; as outras acabam já.
class _Roteiro extends Verificador {
  final _nunca = Completer<void>();

  /// Deixa as presas acabar.
  void soltar() => _nunca.complete();

  @override
  Future<ResultadoVerificacao> verificarComLimite(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso, Duration? limite}) async {
    if (!conta.endereco.contains('presa')) return const ResultadoVerificacao(EstadoV.funciona, 'ok');
    aviso?.call('canal 2/3');
    await _nunca.future;
    return const ResultadoVerificacao(EstadoV.funciona, 'ok');
  }
}

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;
  late ServicoTarefas tarefas;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('gestor_resumo');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
    tarefas = ServicoTarefas();
  });
  tearDown(() {
    tarefas.dispose();
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  /// 24 listas: 12 funcionam, 3 inconclusivas, 4 não funcionam e 5 por verificar.
  Future<void> vinteQuatro(WidgetTester t) => t.runAsync(() => area.adicionar([
        for (var i = 0; i < 24; i++)
          Importada(
              contaDeLinha('http://h$i.com/l.m3u')!,
              i < 12
                  ? _u('funciona')
                  : i < 15
                      ? _u('inconclusivo')
                      : i < 19
                          ? _u('nao_funciona')
                          : null),
      ]));

  TelaGestor telaGestor([ServicoVerificacao? s]) =>
      TelaGestor(biblioteca: bib, area: area, servico: s ?? ServicoVerificacao(bib, colecao: area), tarefas: tarefas);

  Widget gestor([ServicoVerificacao? s]) => appTeste(Scaffold(body: telaGestor(s)));

  /// A app já no Gestor (o Voltar do sistema passa pela casca).
  Widget casca([ServicoVerificacao? s]) => appTeste(TelaPrincipal(
      inicial: Seccao.gestor,
      verTv: TelaInicio(biblioteca: bib, area: area),
      gestor: telaGestor(s),
      definicoes: const SizedBox()));

  Finder cartao(String titulo) => find.ancestor(of: find.text(titulo), matching: find.byType(CartaoModerno));
  Finder em(Finder pai, String texto) => find.descendant(of: pai, matching: find.text(texto));

  /// Tab até ao controlo cujos textos começam por `texto`.
  Future<void> irPara(WidgetTester t, String texto) async {
    for (var i = 0; i < 60 && !textosFocados().startsWith(texto); i++) {
      await teclaDpad(t, LogicalKeyboardKey.tab);
    }
    expect(textosFocados(), startsWith(texto));
  }

  BoxDecoration faixa(WidgetTester t, int n) =>
      t.widget<Container>(find.byKey(ValueKey('faixa $n'))).decoration! as BoxDecoration;
  Color? corFaixa(WidgetTester t, int n) => faixa(t, n).color;

  /// O foco está na pesquisa do passo 2.
  bool naPesquisa() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<CampoTv>() != null;

  /// O foco está na faixa, com o realce no passo `n`.
  void naFaixa(WidgetTester t, int n) {
    expect(textosFocados(), '1 · Importar | 2 · Verificar | 3 · Enviar ou exportar');
    for (final i in [1, 2, 3]) {
      expect(faixa(t, i).border, i == n ? isNotNull : isNull, reason: 'realce no passo $n');
    }
    // o anel com a espessura do resto da app (4 px), na cor do foco
    final anel = (faixa(t, n).border! as Border).top;
    expect((anel.width, anel.color), (4.0, Tokens.anelFoco));
  }

  testWidgets('ao entrar: título, resumo, três cartões com "OK: abrir →" e o foco no cartão 1', (t) async {
    ecraTvTeste(t, altura: 900);
    await vinteQuatro(t);
    await t.pumpWidget(appTeste(TelaPrincipal(
        verTv: TelaInicio(biblioteca: bib, area: area), gestor: telaGestor(), definicoes: const SizedBox())));
    await t.pump();
    expect(textosFocados(), 'Ir para o Gestor');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.text('Gestor de listas').hitTestable(), findsOneWidget);
    expect(find.text('24 listas no Gestor · escolhe por onde começar'), findsOneWidget);
    final c1 = cartao('Importar'), c2 = cartao('Verificar'), c3 = cartao('Enviar ou exportar');
    for (final (n, c) in [(1, c1), (2, c2), (3, c3)]) {
      expect(em(c, '$n'), findsOneWidget, reason: 'cartão $n');
      expect(em(c, 'OK: abrir →'), findsOneWidget, reason: 'cartão $n');
    }
    expect(em(c1, 'Ficheiros, texto, stbstalker ou de Ver TV'), findsOneWidget);
    expect(em(c1, 'Última importação'), findsNothing, reason: 'só depois de uma importação nesta sessão');
    expect(em(c2, '5'), findsOneWidget);
    expect(em(c2, 'por verificar'), findsOneWidget);
    expect(em(c2, 'Funcionam'), findsOneWidget);
    expect(em(c2, '12'), findsOneWidget);
    expect(em(c2, 'Não funcionam'), findsOneWidget);
    expect(em(c2, '4'), findsOneWidget);
    expect(em(c3, '12'), findsOneWidget);
    expect(em(c3, 'prontas a enviar'), findsOneWidget);
    expect(em(c3, 'Em Ver TV'), findsOneWidget);
    expect(em(c3, '0 listas'), findsOneWidget);
    expect(find.textContaining('Nenhum passo está aberto'), findsNothing, reason: 'sem o texto de rodapé');
    expect(find.byType(PassoVerificar).hitTestable(), findsNothing, reason: 'nenhum passo aberto');
    expect(textosFocados(), startsWith('1 | Importar'), reason: 'o foco começa no cartão 1');
    // as cores do mockup: por verificar em aviso, funcionam em ok, não funcionam em mau
    expect(t.widget<Text>(em(c2, '5')).style?.color, Tokens.aviso);
    expect(t.widget<Text>(em(c2, '12')).style?.color, Tokens.ok);
    expect(t.widget<Text>(em(c2, '4')).style?.color, Tokens.mau);
    // sem nada a decorrer, não há barra de atividade
    expect(find.textContaining('A verificar'), findsNothing);
  });

  testWidgets('o indicador de atividade fica no canto direito do topo', (t) async {
    ecraTvTeste(t, largura: 1600, altura: 900);
    await t.pumpWidget(gestor());
    await t.pump();
    final ecra = t.getRect(find.byType(TelaGestor));
    final indicador = t.getRect(find.byType(IndicadorAtividade));
    expect(ecra.right - indicador.right, lessThan(Tokens.e16 + 1), reason: 'encostado à margem direita');
    expect(indicador.left, greaterThan(ecra.center.dx), reason: 'não fica a meio do topo');
    // e as mensagens do canto aparecem por baixo dele, sem o tapar
    expect(indicador.bottom, lessThanOrEqualTo(alturaBarraTopo));
  });

  testWidgets('Gestor vazio: os cartões 2 e 3 dizem "Importe listas primeiro"', (t) async {
    ecraTvTeste(t, altura: 900);
    await t.pumpWidget(gestor());
    await t.pump();
    expect(find.text('0 listas no Gestor · escolhe por onde começar'), findsOneWidget);
    expect(em(cartao('Verificar'), 'Importe listas primeiro'), findsOneWidget);
    expect(em(cartao('Enviar ou exportar'), 'Importe listas primeiro'), findsOneWidget);
    expect(em(cartao('Verificar'), 'por verificar'), findsNothing);
  });

  testWidgets('"No Player" conta as listas de Ver TV; depois de importar, o cartão 1 diz quando e quantas',
      (t) async {
    ecraTvTeste(t, largura: 1400, altura: 1400);
    await t.runAsync(() => bib.adicionar([
          Importada(contaDeLinha('http://a.com/l.m3u')!),
          Importada(contaDeLinha('http://b.com/l.m3u')!),
          Importada(contaDeLinha('http://c.com/l.m3u')!),
        ]));
    await t.pumpWidget(casca());
    await t.pump();
    expect(em(cartao('Enviar ou exportar'), '3 listas'), findsOneWidget);
    await t.tap(em(cartao('Importar'), 'Importar'));
    await t.pumpAndSettle();
    await t.tap(find.text('De Ver TV'));
    await t.pump();
    await t.runAsync(() async {
      await t.tap(find.text('Importar de Ver TV'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    for (var i = 0; i < 50 && tarefas.recentes.isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    final c1 = cartao('Importar');
    expect(em(c1, 'Última importação'), findsOneWidget);
    expect(em(c1, 'agora'), findsOneWidget);
    expect(em(c1, 'Entraram'), findsOneWidget);
    expect(em(c1, '3 novas'), findsOneWidget);
  });

  testWidgets('a verificar: a barra "A verificar 2/5" com a estimativa; OK nela abre o progresso', (t) async {
    ecraTvTeste(t, altura: 900);
    await t.runAsync(() => area.adicionar([
          for (final h in ['ok1', 'ok2', 'presa1', 'presa2', 'presa3']) Importada(contaDeLinha('http://$h.com/l.m3u')!),
        ]));
    var agora = DateTime(2026, 11, 19, 10);
    final s = ServicoVerificacao(bib,
        colecao: area, verificador: _Roteiro(), workers: 4, ritmo: RitmoHost(intervalo: Duration.zero), agora: () => agora);
    await t.pumpWidget(gestor(s));
    await t.pump();
    s.verificarVarias(area.listas);
    // 20 s depois do início acabam as duas primeiras: 20 s ÷ 2 × 3 que faltam = 30 s
    agora = agora.add(const Duration(seconds: 20));
    for (var i = 0; i < 100 && s.feitas < 2; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    await t.pump();
    final barra = find.byKey(const ValueKey('barraAtividade'));
    expect(em(barra, 'A verificar 2/5'), findsOneWidget);
    expect(em(barra, 'faltam cerca de 30 s'), findsOneWidget);
    // BAIXO desde o cartão 1 chega à barra
    await irPara(t, '1 | Importar');
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), startsWith('A verificar 2/5'));
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(TelaVerificacao).hitTestable(), findsOneWidget);
    expect(textosFocados(), contains('Verificar mais (fila)'));
    s.parar();
  });

  testWidgets('a verificação acaba com o foco na barra do resumo: o foco passa ao cartão 2', (t) async {
    ecraTvTeste(t, altura: 900);
    await t.runAsync(() => area.adicionar([Importada(contaDeLinha('http://presa.com/l.m3u')!)]));
    final roteiro = _Roteiro();
    final s = ServicoVerificacao(bib, colecao: area, verificador: roteiro, ritmo: RitmoHost(intervalo: Duration.zero));
    await t.pumpWidget(gestor(s));
    await t.pump();
    s.verificar(area.listas.first);
    await t.pump();
    await irPara(t, '1 | Importar');
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), startsWith('A verificar 0/1'));
    // a verificação acaba
    roteiro.soltar();
    for (var i = 0; i < 50 && s.ocupado; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    await t.pump();
    expect(s.ocupado, isFalse);
    expect(find.byKey(const ValueKey('barraAtividade')), findsNothing);
    expect(textosFocados(), startsWith('2 | Verificar'), reason: 'o foco não se perde');
  });

  testWidgets('OK no cartão 2 abre o passo 2 com a faixa (passo 2 realçado); → na faixa muda para o passo 3',
      (t) async {
    ecraTvTeste(t);
    await vinteQuatro(t);
    await t.pumpWidget(gestor());
    await t.pump();
    await irPara(t, '2 | Verificar');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(PassoVerificar).hitTestable(), findsOneWidget);
    for (final f in ['1 · Importar', '2 · Verificar', '3 · Enviar ou exportar']) {
      expect(find.text(f).hitTestable(), findsOneWidget, reason: f);
    }
    expect(corFaixa(t, 2), Tokens.acento);
    expect(corFaixa(t, 1), Tokens.superficie2);
    expect(corFaixa(t, 3), Tokens.superficie2);
    // a faixa fica no topo, acima do passo (e da sua linha de cima, com Ações)
    expect(t.getRect(find.text('2 · Verificar')).bottom,
        lessThan(t.getRect(find.byKey(const ValueKey('botaoAcoes'))).top));
    // CIMA a partir do passo chega à faixa (no passo aberto)
    expect(naPesquisa(), isTrue, reason: 'o passo abre no 1.º controlo (a pesquisa)');
    await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    naFaixa(t, 2);
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(find.byType(PassoEnviar).hitTestable(), findsOneWidget);
    expect(find.byType(PassoVerificar).hitTestable(), findsNothing);
    expect(corFaixa(t, 3), Tokens.acento);
    expect(corFaixa(t, 2), Tokens.superficie2);
    naFaixa(t, 3);
    // ← volta ao passo 2; BAIXO entra no passo
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(find.byType(PassoVerificar).hitTestable(), findsOneWidget);
    naFaixa(t, 2);
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(naPesquisa(), isTrue);
  });

  testWidgets('Voltar no passo 2 → resumo (foco no cartão 2); o indicador do topo → progresso; '
      'Voltar no progresso → passo 2, com o foco onde estava', (t) async {
    ecraTvTeste(t);
    await t.runAsync(() => area.adicionar([Importada(contaDeLinha('http://presa.com/l.m3u')!)]));
    final s = ServicoVerificacao(bib, colecao: area, verificador: _Roteiro(), ritmo: RitmoHost(intervalo: Duration.zero));
    await t.pumpWidget(casca(s));
    await t.pump();
    await irPara(t, '2 | Verificar');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(PassoVerificar).hitTestable(), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(PassoVerificar).hitTestable(), findsNothing);
    expect(find.text('Gestor de listas').hitTestable(), findsOneWidget);
    expect(textosFocados(), startsWith('2 | Verificar'), reason: 'o foco volta ao cartão 2');
    // de novo no passo 2, com uma verificação a decorrer
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    s.verificar(area.listas.first);
    await t.pump();
    await irPara(t, 'A verificar 0/1');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(TelaVerificacao).hitTestable(), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(PassoVerificar).hitTestable(), findsOneWidget, reason: 'Voltar no progresso vai ao passo 2');
    expect(textosFocados(), startsWith('A verificar 0/1'), reason: 'o foco não se perde');
    // e daí ao resumo, com a barra da verificação (sem estimativa: nenhuma acabou)
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(textosFocados(), startsWith('2 | Verificar'));
    expect(find.text('A verificar 0/1').hitTestable(), findsWidgets);
    expect(find.textContaining('faltam cerca de'), findsNothing);
    // no resumo, Voltar já é da casca: vai para Ver TV
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Gestor de listas').hitTestable(), findsNothing);
    s.parar();
  });

  testWidgets('enviar do passo 3 com 3 marcadas pergunta só o modo e envia as 3', (t) async {
    ecraTvTeste(t, largura: 1400, altura: 1400);
    await t.runAsync(() => area.adicionar([
          Importada(contaDeLinha('http://a.com/l.m3u')!, _u('funciona')),
          Importada(contaDeLinha('http://b.com/l.m3u')!, _u('funciona')),
          Importada(contaDeLinha('http://c.com/l.m3u')!, _u('funciona')),
          Importada(contaDeLinha('http://d.com/l.m3u')!, _u('nao_funciona')),
        ]));
    await t.pumpWidget(gestor());
    await t.pump();
    await t.tap(em(cartao('Enviar ou exportar'), 'Enviar ou exportar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Funcionam (3)'));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Enviar 3 listas'));
    await t.pumpAndSettle();
    final dialogo = find.byType(AlertDialog);
    expect(em(dialogo, 'Enviar 3 listas para Ver TV'), findsOneWidget);
    expect(em(dialogo, 'Adicionar às listas de Ver TV'), findsOneWidget);
    expect(em(dialogo, 'Substituir as listas de Ver TV'), findsOneWidget);
    expect(find.text('Que listas enviar?'), findsNothing, reason: 'o «quais» sai do diálogo');
    expect(find.textContaining('Só as que funcionam'), findsNothing);
    await t.tap(find.descendant(of: dialogo, matching: find.widgetWithText(FilledButton, 'Enviar 3 listas')));
    for (var i = 0; i < 100 && tarefas.recentes.isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect([for (final l in bib.listas) hostDe(l.conta.endereco)], ['a.com', 'b.com', 'c.com']);
    expect(tarefas.recentes.first.resultado, '3 listas enviadas para Ver TV · 3 novas');
  });

  /// O indicador de atividade do topo (com o texto `texto`).
  Finder indicador(String texto) =>
      find.descendant(of: find.byType(IndicadorAtividade), matching: find.text(texto));
  bool indicadorEBotao() =>
      find.descendant(of: find.byType(IndicadorAtividade), matching: find.byType(TextButton)).evaluate().isNotEmpty;

  testWidgets('no passo 2 o indicador é o da verificação: «nada a decorrer» (sem parar o foco); a correr '
      '«A verificar 2/5» e OK abre o progresso; fora do passo 2 continua a abrir o painel', (t) async {
    ecraTvTeste(t, altura: 900);
    await t.runAsync(() => area.adicionar([
          for (final h in ['ok1', 'ok2', 'presa1', 'presa2', 'presa3']) Importada(contaDeLinha('http://$h.com/l.m3u')!),
        ]));
    final roteiro = _Roteiro();
    final s = ServicoVerificacao(bib,
        colecao: area, verificador: roteiro, workers: 4, ritmo: RitmoHost(intervalo: Duration.zero));
    await t.pumpWidget(casca(s));
    await t.pump();
    expect(indicador('Nada a decorrer'), findsOneWidget, reason: 'no resumo, o de sempre');
    await t.tap(em(cartao('Verificar'), 'Verificar'));
    await t.pumpAndSettle();
    expect(indicador('nada a decorrer'), findsOneWidget);
    expect(indicadorEBotao(), isFalse, reason: 'sem verificação não abre nada (nem pára o foco)');
    expect(find.textContaining('Ver verificação'), findsNothing);
    // no topo, à direita do título
    expect(t.getRect(indicador('nada a decorrer')).left, greaterThan(t.getRect(find.text('Verificar listas')).left));
    expect(t.getRect(indicador('nada a decorrer')).bottom, lessThan(t.getRect(find.text('2 · Verificar')).top));
    s.verificarVarias(area.listas);
    for (var i = 0; i < 100 && s.feitas < 2; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    await t.pump();
    expect(indicador('A verificar 2/5'), findsOneWidget);
    expect(indicadorEBotao(), isTrue);
    await irPara(t, 'A verificar 2/5');
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.byType(TelaVerificacao).hitTestable(), findsOneWidget, reason: 'OK abre o progresso');
    expect(find.text('Atividade'), findsNothing, reason: 'e não o painel');
    // no resumo, o mesmo indicador abre o painel de atividade
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Gestor de listas').hitTestable(), findsOneWidget);
    await t.tap(find.descendant(of: find.byType(IndicadorAtividade), matching: find.byType(TextButton)));
    await t.pumpAndSettle();
    expect(find.text('Atividade'), findsOneWidget);
    s.parar();
    roteiro.soltar();
  });

  testWidgets('no passo 2, depois de uma ronda acabar: «nada a decorrer · ver última» (com a dica) e OK abre o '
      'progresso', (t) async {
    ecraTvTeste(t, altura: 900);
    await t.runAsync(() => area.adicionar([Importada(contaDeLinha('http://ok.com/l.m3u')!)]));
    final s = ServicoVerificacao(bib, colecao: area, verificador: _Roteiro(), ritmo: RitmoHost(intervalo: Duration.zero));
    await t.pumpWidget(gestor(s));
    await t.pump();
    await t.tap(em(cartao('Verificar'), 'Verificar'));
    await t.pumpAndSettle();
    s.verificar(area.listas.first);
    for (var i = 0; i < 100 && (s.ocupado || s.fimRonda == null); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    await t.pump();
    expect(s.fimRonda, isNotNull);
    expect(indicador('nada a decorrer · ver última'), findsOneWidget);
    expect(indicadorEBotao(), isTrue, reason: 'houve uma verificação nesta sessão');
    final semanticaLigada = t.ensureSemantics();
    await t.pump();
    final nos = find.bySemanticsLabel(RegExp('nada a decorrer · ver última'));
    final dicas = [for (var i = 0; i < nos.evaluate().length; i++) t.getSemantics(nos.at(i)).hint];
    expect(dicas, contains('abre o progresso da verificação'), reason: '$dicas');
    semanticaLigada.dispose();
    await t.tap(indicador('nada a decorrer · ver última'));
    await t.pumpAndSettle();
    expect(find.byType(TelaVerificacao).hitTestable(), findsOneWidget);
  });

  testWidgets('na TV (960×540, a 80 %) o passo 2 mostra pelo menos 12 linhas, sem barra em baixo', (t) async {
    ecraTvTeste(t);
    await t.runAsync(() => area.adicionar([
          for (var i = 0; i < 30; i++) Importada(contaDeLinha('http://h$i.com/l.m3u')!, i.isEven ? _u('funciona') : null),
        ]));
    await t.pumpWidget(MaterialApp(
        theme: temaApp(),
        builder: (_, c) => TemaConformeRealce(child: EscalaInterface(escala: escalaCompacto, child: c!)),
        home: TelaPrincipal(
            inicial: Seccao.gestor,
            verTv: TelaInicio(biblioteca: bib, area: area),
            gestor: telaGestor(),
            definicoes: const SizedBox())));
    await t.pump();
    await t.tap(em(cartao('Verificar'), 'Verificar'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final passo = find.byType(PassoVerificar);
    final janela = t.getRect(find.descendant(
        of: passo, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)));
    final linhas = find.descendant(of: passo, matching: find.byType(CheckboxListTile));
    final alturas = <double>{};
    var inteiras = 0;
    for (var i = 0; i < linhas.evaluate().length; i++) {
      final r = t.getRect(linhas.at(i));
      alturas.add((r.height * 10).roundToDouble() / 10);
      if (r.top >= janela.top && r.bottom <= janela.bottom && r.bottom <= 540) inteiras++;
    }
    expect(inteiras, greaterThanOrEqualTo(12), reason: 'linhas inteiras à vista em $janela');
    expect(alturas, hasLength(1), reason: 'altura fixa: $alturas');
    // a 80 %: 32 lógicos são 25,6 no ecrã
    expect(alturas.single, lessThanOrEqualTo(32 * escalaCompacto));
    expect(find.byKey(const ValueKey('barraAcoes')), findsNothing);
    // Ações no topo, à direita, na linha da pesquisa
    final acoes = t.getRect(find.byKey(const ValueKey('botaoAcoes')));
    expect(acoes.bottom, lessThan(t.getRect(linhas.first).top));
    expect(acoes.right, lessThanOrEqualTo(960));
    expect(acoes.center.dy, moreOrLessEquals(t.getCenter(find.descendant(of: passo, matching: find.byType(TextField))).dy,
        epsilon: 1));
  });

  /// A casca já no Gestor, a 80 % (como na TV no Compacto).
  Widget cascaCompacta() => MaterialApp(
      theme: temaApp(),
      builder: (_, c) => TemaConformeRealce(child: EscalaInterface(escala: escalaCompacto, child: c!)),
      home: TelaPrincipal(
          inicial: Seccao.gestor,
          verTv: TelaInicio(biblioteca: bib, area: area),
          gestor: telaGestor(),
          definicoes: const SizedBox()));

  testWidgets('na TV (960×540, a 80 %) o resumo tem cartões baixos (≤ 160) e sem o texto de rodapé', (t) async {
    ecraTvTeste(t);
    await vinteQuatro(t);
    await t.pumpWidget(cascaCompacta());
    await t.pump();
    expect(t.takeException(), isNull);
    final c1 = cartao('Importar'), c2 = cartao('Verificar'), c3 = cartao('Enviar ou exportar');
    for (final (n, c) in [(1, c1), (2, c2), (3, c3)]) {
      final r = t.getRect(c);
      expect(r.height, lessThanOrEqualTo(160 * escalaCompacto), reason: 'cartão $n: $r');
      expect(r.bottom, lessThanOrEqualTo(540), reason: 'cartão $n à vista');
      expect(em(c, 'OK: abrir →'), findsOneWidget, reason: 'cartão $n');
    }
    // a informação fica: o número, o rótulo e as duas linhas
    for (final (c, textos) in [
      (c2, ['5', 'por verificar', 'Funcionam', '12', 'Não funcionam', '4']),
      (c3, ['12', 'prontas a enviar', 'Em Ver TV', '0 listas']),
    ]) {
      for (final x in textos) {
        expect(em(c, x), findsOneWidget, reason: x);
      }
    }
    expect(find.textContaining('Nenhum passo está aberto'), findsNothing);
    // os três lado a lado, com a mesma altura
    expect(t.getRect(c2).top, moreOrLessEquals(t.getRect(c1).top, epsilon: 1));
    expect(t.getRect(c3).height, moreOrLessEquals(t.getRect(c1).height, epsilon: 1));
  });

  testWidgets('na TV (960×540, a 80 %) o passo 3: linhas como as do Verificar, chips numa linha e → aos dois destinos',
      (t) async {
    ecraTvTeste(t);
    await t.runAsync(() => area.adicionar([
          for (var i = 0; i < 30; i++) Importada(contaDeLinha('http://h$i.com/l.m3u')!, i.isEven ? _u('funciona') : null),
        ]));
    await t.pumpWidget(cascaCompacta());
    await t.pump();
    await t.tap(em(cartao('Enviar ou exportar'), 'Enviar ou exportar'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final passo = find.byType(PassoEnviar);
    final linhas = find.descendant(of: passo, matching: find.byType(CheckboxListTile));
    final alturas = <double>{};
    var inteiras = 0;
    for (var i = 0; i < linhas.evaluate().length; i++) {
      final r = t.getRect(linhas.at(i));
      alturas.add((r.height * 10).roundToDouble() / 10);
      if (r.bottom <= 540) inteiras++;
    }
    expect(alturas, hasLength(1), reason: 'altura fixa: $alturas');
    expect(alturas.single, moreOrLessEquals(PassoVerificarState.alturaLinha * escalaCompacto, epsilon: .1),
        reason: 'a altura das linhas do passo 2');
    expect(inteiras, greaterThanOrEqualTo(10), reason: 'linhas à vista');
    // «Marcar:» e os seis chips numa só linha
    final marcar = t.getCenter(find.descendant(of: passo, matching: find.text('Marcar:'))).dy;
    final chips = find.descendant(of: passo, matching: find.byWidgetPredicate((w) => w is FilterChip || w is ActionChip));
    expect(chips, findsNWidgets(6));
    for (var i = 0; i < 6; i++) {
      expect(t.getCenter(chips.at(i)).dy, moreOrLessEquals(marcar, epsilon: 2), reason: 'chip $i');
    }
    // → numa linha leva ao Enviar; ↓ ao Exportar; os dois à vista
    // (a fila desliza: com o comando, o foco leva o chip à vista)
    await t.ensureVisible(find.text('Todas (30)'));
    await t.tap(find.text('Todas (30)'));
    await t.pump();
    final linhaNo = t.widget<CheckboxListTile>(linhas.at(2)).focusNode!;
    linhaNo.requestFocus();
    await t.pump();
    await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    expect(textosFocados(), 'Enviar 30 listas');
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), 'Exportar 30 listas');
    for (final b in ['Enviar 30 listas', 'Exportar 30 listas']) {
      expect(t.getRect(find.text(b)).bottom, lessThanOrEqualTo(540), reason: b);
    }
    await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
    expect(linhaNo.hasPrimaryFocus, isTrue);
    // → pela fila dos chips chega ao último (desliza para a vista)
    await irPara(t, 'Funcionam');
    for (var i = 0; i < 6 && textosFocados() != 'Nenhuma'; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
    }
    expect(textosFocados(), 'Nenhuma');
    expect(t.getRect(find.text('Nenhuma')).right, lessThanOrEqualTo(960));
  });

  testWidgets('no passo 2 a tecla Menu abre as ações também do «Voltar», da faixa e do indicador', (t) async {
    ecraTvTeste(t, altura: 900);
    await vinteQuatro(t);
    final s = ServicoVerificacao(bib, colecao: area, verificador: _Roteiro(), ritmo: RitmoHost(intervalo: Duration.zero));
    await t.runAsync(() => area.adicionar([Importada(contaDeLinha('http://presa.com/l.m3u')!)]));
    await t.pumpWidget(gestor(s));
    await t.pump();
    await t.tap(em(cartao('Verificar'), 'Verificar'));
    await t.pumpAndSettle();
    s.verificar(area.listas.last);
    await t.pump();
    final menu = find.ancestor(of: find.text('Verificar todas'), matching: find.byWidgetPredicate((w) => w is PopupMenuItem));
    for (final onde in ['Voltar', '1 · Importar | 2 · Verificar | 3 · Enviar ou exportar', 'A verificar 0/1']) {
      await irPara(t, onde);
      await teclaDpad(t, LogicalKeyboardKey.contextMenu);
      await t.pumpAndSettle();
      expect(menu, findsOneWidget, reason: onde);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(menu, findsNothing);
      expect(textosFocados(), startsWith(onde), reason: 'o foco volta a $onde');
    }
    s.parar();
  });

  testWidgets('a faixa dos passos: 36 na TV, 48 no telemóvel (o alvo de toque)', (t) async {
    await vinteQuatro(t);
    ecraTvTeste(t, altura: 900);
    await t.pumpWidget(gestor());
    await t.pump();
    await t.tap(em(cartao('Verificar'), 'Verificar'));
    await t.pumpAndSettle();
    expect(t.getSize(find.byKey(const ValueKey('faixa 2'))).height, 36);
    EcraTv.nativo = false;
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(gestor());
    await t.pump();
    await t.tap(em(cartao('Verificar'), 'Verificar'));
    await t.pumpAndSettle();
    expect(t.getSize(find.byKey(const ValueKey('faixa 2'))).height, 48);
  });

  testWidgets('a barra de teclas: no resumo "OK abrir o passo"; num passo "Voltar resumo do Gestor"', (t) async {
    ecraTvTeste(t);
    await vinteQuatro(t);
    await t.pumpWidget(casca());
    await t.pump();
    List<(String, String)> itens() =>
        t.widget<BarraTeclas>(find.descendant(of: find.byType(TelaGestor), matching: find.byType(BarraTeclas))).itens;
    expect(itens(), contains(('OK', 'abrir o passo')));
    for (final passo in ['Importar', 'Verificar', 'Enviar ou exportar']) {
      await t.tap(em(cartao(passo), passo));
      await t.pumpAndSettle();
      expect(itens(), contains(('Voltar', 'resumo do Gestor')), reason: passo);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(itens(), contains(('OK', 'abrir o passo')), reason: passo);
    }
  });
}
