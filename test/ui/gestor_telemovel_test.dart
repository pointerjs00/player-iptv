import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/design/estado_lista.dart';
import 'package:player_iptv/ui/design/tokens.dart';
import 'package:player_iptv/ui/gestor/indicador_atividade.dart';
import 'package:player_iptv/ui/gestor/passo_enviar.dart';
import 'package:player_iptv/ui/gestor/passo_verificar.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';

/// O Gestor num telemóvel ao alto (360×800 e 412×915, letra a 1 e a 1,3, com a Roboto): nada
/// transborda, os nomes e os rótulos ficam inteiros, os alvos de toque têm 48 e as dicas do
/// comando não aparecem.

const _hosts = [
  'alfa', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel', 'india', 'juliett', //
  'kilo', 'lima', 'mike', 'november', 'oscar', 'papa', 'quebec', 'romeo', 'sierra', 'tango',
];

/// 10 funcionam, 5 inconclusivas, 3 não funcionam e 2 por verificar (a cada 20).
UltimaVerificacao? _ultima(int i) {
  final ontem = DateTime.now().subtract(const Duration(days: 1));
  return switch (i % 4) {
    0 ||
    1 => UltimaVerificacao(estado: 'funciona', motivo: '3/3 canais com imagem', data: ontem, validade: '2027-09-07'),
    2 => UltimaVerificacao(
      estado: 'inconclusivo',
      motivo: 'Só 1 de 3 canais abriu (tempo esgotado)',
      data: ontem,
      validade: '2027-01-15',
    ),
    _ =>
      i % 8 == 3
          ? UltimaVerificacao(estado: 'nao_funciona', motivo: 'Servidor recusou a ligação (403)', data: ontem)
          : null,
  };
}

List<Importada> _importadas(int n, {int desde = 0}) => [
  for (var i = desde; i < desde + n; i++)
    Importada(
      contaDeLinha('http://${_hosts[i % _hosts.length]}${i < _hosts.length ? '' : i}.exemplo.invalid/lista.m3u')!,
      _ultima(i),
    ),
];

/// Fica preso em todas as listas até [soltar].
class _VerificadorPreso extends Verificador {
  final _nunca = Completer<void>();
  void soltar() {
    if (!_nunca.isCompleted) _nunca.complete();
  }

  @override
  Future<ResultadoVerificacao> verificarComLimite(
    Conta conta,
    List<String> canaisTeste, {
    Duration timeout = const Duration(seconds: 8),
    Cancelamento? cancelamento,
    Aviso? aviso,
    Duration? limite,
  }) async {
    aviso?.call('canal 2/3');
    await _nunca.future;
    return const ResultadoVerificacao(EstadoV.funciona, 'ok');
  }
}

/// A Roboto do Flutter (a letra do telemóvel), também no lugar da letra quadrada dos testes: com
/// ela as larguras seriam outras.
Future<void> _carregarRoboto() async {
  // <flutter>/bin/cache/artifacts/engine/<plataforma>/flutter_tester
  final artefactos = File(Platform.resolvedExecutable).parent.parent.parent;
  final pasta = Directory('${artefactos.path}/material_fonts');
  if (!pasta.existsSync()) fail('A Roboto do Flutter não está em ${pasta.path}');
  for (final familia in ['Roboto', 'FlutterTest']) {
    final f = FontLoader(familia);
    for (final n in ['roboto-light', 'roboto-regular', 'roboto-medium', 'roboto-bold', 'roboto-black']) {
      f.addFont(Future.value(ByteData.sublistView(File('${pasta.path}/$n.ttf').readAsBytesSync())));
    }
    await f.load();
  }
}

/// A app como no telemóvel: o fundo do design e a Roboto também nos chips (o rótulo deles não
/// diz a família: no telemóvel é a do sistema, a Roboto; no teste seria a letra quadrada).
Widget _app(Widget home) => MaterialApp(
  theme: temaApp(),
  builder: (_, w) => TemaConformeRealce(
    child: Builder(
      builder: (c) {
        final tema = Theme.of(c);
        final chips = tema.chipTheme;
        return Theme(
          data: tema.copyWith(
            chipTheme: chips.copyWith(
              labelStyle: (chips.labelStyle ?? const TextStyle()).copyWith(fontFamily: 'Roboto'),
            ),
          ),
          child: FundoCinema(child: w!),
        );
      },
    ),
  ),
  home: home,
);

const _configs = [(360.0, 800.0, 1.0), (360.0, 800.0, 1.3), (412.0, 915.0, 1.0), (412.0, 915.0, 1.3)];

/// Corre [corpo] em cada telemóvel de [configs]; no fim, nenhum erro (overflow incluído).
void _noTelemovel(
  String nome,
  Future<void> Function(WidgetTester t, Size ecra) corpo, {
  List<(double, double, double)> configs = _configs,
}) {
  for (final (l, a, e) in configs) {
    testWidgets('$nome · ${l.toInt()}×${a.toInt()} · letra $e', (t) async {
      t.view.physicalSize = Size(l, a);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = e;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final erros = <String>[];
      final antes = FlutterError.onError;
      FlutterError.onError = (d) => erros.add(d.exceptionAsString().split('\n').first);
      try {
        await corpo(t, Size(l, a));
      } finally {
        FlutterError.onError = antes;
      }
      expect(erros, isEmpty, reason: 'sem overflow nem outros erros');
      expect(t.takeException(), isNull);
    });
  }
}

/// O texto não foi cortado (nem com reticências, nem por faltarem linhas).
void _inteiro(WidgetTester t, Finder texto) {
  final p = _paragrafo(t, texto);
  expect(p.didExceedMaxLines, isFalse, reason: '«${p.text.toPlainText()}» cortado');
}

/// O parágrafo de um `Text` (também com `semanticsLabel`, que o embrulha num `Semantics`).
RenderParagraph _paragrafo(WidgetTester t, Finder texto) =>
    t.renderObject<RenderParagraph>(find.descendant(of: texto, matching: find.byType(RichText), matchRoot: true).first);

/// O texto cabe todo na caixa que o desenha (sem reticências nem corte).
void _semReticencias(WidgetTester t, Finder texto) {
  final p = _paragrafo(t, texto);
  final s = p.text.toPlainText();
  expect(p.didExceedMaxLines, isFalse, reason: '«$s» cortado');
  final fim = p.getOffsetForCaret(TextPosition(offset: s.length), Rect.zero);
  expect(fim.dx, lessThanOrEqualTo(p.size.width + .5), reason: '«$s» passa a largura');
  expect(
    p.getMaxIntrinsicWidth(double.infinity),
    lessThanOrEqualTo(p.size.width + .5),
    reason: '«$s» não cabe numa linha mas não parte',
  );
}

/// Nenhuma palavra do texto partida entre duas linhas («.t xt»).
void _semPalavrasPartidas(WidgetTester t, Finder texto) {
  final p = _paragrafo(t, texto);
  final s = p.text.toPlainText();
  for (final m in RegExp(r'\S+').allMatches(s)) {
    final caixas = p.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end));
    expect({for (final c in caixas) c.top.round()}.length, lessThanOrEqualTo(1), reason: '«${m[0]}» partida em «$s»');
  }
}

/// O alvo de toque tem pelo menos 48×48.
void _alvo48(WidgetTester t, Finder f, {String? motivo}) {
  final s = t.getSize(f);
  expect(s.width, greaterThanOrEqualTo(48), reason: motivo);
  expect(s.height, greaterThanOrEqualTo(48), reason: motivo);
}

/// Todo dentro do ecrã (sem deslizar nada).
void _noEcra(WidgetTester t, Finder f, Size ecra, {String? motivo}) {
  final r = t.getRect(f);
  expect(r.left, greaterThanOrEqualTo(0), reason: motivo);
  expect(r.top, greaterThanOrEqualTo(0), reason: motivo);
  expect(r.right, lessThanOrEqualTo(ecra.width + .5), reason: motivo);
  expect(r.bottom, lessThanOrEqualTo(ecra.height + .5), reason: motivo);
}

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;
  late ServicoTarefas tarefas;

  setUpAll(_carregarRoboto);

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('gestor_telemovel');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
    await area.adicionar(_importadas(20));
    tarefas = ServicoTarefas();
  });
  tearDown(() {
    tarefas.dispose();
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {
      /* Windows */
    }
  });

  Widget casca([ServicoVerificacao? s]) {
    final serv = s ?? ServicoVerificacao(bib, colecao: area);
    return _app(
      TelaPrincipal(
        inicial: Seccao.gestor,
        tarefas: tarefas,
        verificacao: serv,
        verTv: const SizedBox(),
        gestor: TelaGestor(biblioteca: bib, area: area, servico: serv, tarefas: tarefas),
        definicoes: const SizedBox(),
      ),
    );
  }

  Future<void> abrirPasso(WidgetTester t, String cartao) async {
    await t.tap(find.text(cartao).hitTestable().first);
    await t.pumpAndSettle();
  }

  Finder noPasso2(Finder f) => find.descendant(of: find.byType(PassoVerificar), matching: f);
  Finder noPasso3(Finder f) => find.descendant(of: find.byType(PassoEnviar), matching: f);

  /// O que desliza no passo 2 (a pesquisa e os estados, e as listas).
  Finder listaPasso2() =>
      find.descendant(of: noPasso2(find.byType(CustomScrollView)), matching: find.byType(Scrollable)).first;
  Finder linha(Finder pai, String nome) => find.ancestor(
    of: find.descendant(of: pai, matching: find.text(nome)),
    matching: find.byType(CheckboxListTile),
  );

  _noTelemovel('resumo: o título inteiro, o indicador só com o ícone e sem «OK: abrir →»', (t, ecra) async {
    final sem = t.ensureSemantics();
    await t.pumpWidget(casca());
    await t.pumpAndSettle();
    expect(find.byTooltip('Voltar'), findsNothing, reason: 'no resumo não há Voltar');
    _inteiro(t, find.text('Gestor de listas'));
    expect(find.text('OK: abrir →'), findsNothing);
    final ind = find.byType(IndicadorAtividade);
    expect(
      find.descendant(of: ind, matching: find.byType(Text)),
      findsNothing,
      reason: 'só o ícone',
    );
    expect(find.bySemanticsLabel(RegExp('^Nada a decorrer')), findsOneWidget);
    _alvo48(t, ind);
    _noEcra(t, ind, ecra);
    sem.dispose();
  });

  _noTelemovel('passos: ← só com o ícone, sem título e a faixa com os nomes inteiros', (t, ecra) async {
    final sem = t.ensureSemantics();
    await t.pumpWidget(casca());
    await t.pumpAndSettle();
    for (final cartao in ['Importar', 'Verificar', 'Enviar ou exportar']) {
      await abrirPasso(t, cartao);
      final voltar = find.byTooltip('Voltar');
      expect(voltar, findsOneWidget, reason: cartao);
      expect(find.widgetWithText(TextButton, 'Voltar'), findsNothing, reason: 'só o ícone');
      expect(find.bySemanticsLabel('Voltar'), findsOneWidget);
      _alvo48(t, find.ancestor(of: voltar, matching: find.byType(IconButton)));
      for (final titulo in ['Importar listas', 'Verificar listas', 'Enviar ou exportar listas']) {
        expect(find.text(titulo), findsNothing, reason: 'a faixa já diz o passo');
      }
      for (final (i, nome) in ['Importar', 'Verificar', 'Enviar'].indexed) {
        final item = find.byKey(ValueKey('faixa ${i + 1}'));
        final texto = find.descendant(of: item, matching: find.text(nome));
        expect(texto, findsOneWidget, reason: nome);
        _inteiro(t, texto);
        _alvo48(t, item, motivo: nome);
        final r = t.getRect(texto), caixa = t.getRect(item);
        expect(r.left >= caixa.left - .5 && r.right <= caixa.right + .5, isTrue, reason: '$nome dentro do item');
      }
      await t.tap(voltar);
      await t.pumpAndSettle();
      expect(find.text('Gestor de listas'), findsOneWidget);
    }
    sem.dispose();
  });

  _noTelemovel('indicador a decorrer: o ícone e «0/8»; a dica e a leitura dizem o texto todo', (t, ecra) async {
    final ver = _VerificadorPreso();
    final s = ServicoVerificacao(bib, colecao: area, verificador: ver, workers: 3);
    final sem = t.ensureSemantics();
    try {
      await t.pumpWidget(casca(s));
      await t.pump();
      unawaited(s.verificarVarias(area.listas.take(8).toList()));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      final ind = find.byType(IndicadorAtividade);
      expect(find.descendant(of: ind, matching: find.text('0/8')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^A verificar 0/8')), findsWidgets);
      _alvo48(t, ind);
      // (a barra do progresso, no resumo, também o diz)
      final antes = find.text('A verificar 0/8').evaluate().length;
      await t.longPress(ind);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('A verificar 0/8').evaluate().length, antes + 1, reason: 'o toque longo mostra o texto todo');
      await t.pump(const Duration(seconds: 5));
      // no passo 2, o da verificação
      await abrirPasso(t, 'Verificar');
      expect(find.descendant(of: ind, matching: find.text('0/8')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^A verificar 0/8')), findsWidgets);
    } finally {
      s.parar();
      ver.soltar();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      sem.dispose();
    }
  });

  _noTelemovel('passo 2: cada lista em duas linhas, sem cabeçalho de colunas, seleção na barra de cima', (
    t,
    ecra,
  ) async {
    final sem = t.ensureSemantics();
    await t.pumpWidget(casca());
    await t.pumpAndSettle();
    await abrirPasso(t, 'Verificar');
    for (final c in ['LISTA', 'ESTADO', 'MOTIVO', 'TESTE']) {
      expect(find.text(c), findsNothing, reason: 'sem cabeçalho de colunas');
    }
    // os estados todos à vista
    for (final e in ['Funcionam', 'Inconclusivas', 'Não funcionam', 'Por verificar']) {
      final chip = noPasso2(find.textContaining(e)).hitTestable();
      expect(chip, findsOneWidget, reason: e);
      _noEcra(t, chip, ecra, motivo: e);
    }
    // as primeiras listas: nome inteiro, a pílula por baixo do nome, linha ≥ 56, caixa ≥ 48
    final vistas = [
      for (final l in area.listas)
        if (noPasso2(find.text(l.nomeMostrado)).hitTestable().evaluate().isNotEmpty) l,
    ];
    expect(vistas.length, greaterThanOrEqualTo(2), reason: 'listas à vista logo ao abrir');
    for (final l in vistas.take(4)) {
      final nome = noPasso2(find.text(l.nomeMostrado));
      final ln = linha(find.byType(PassoVerificar), l.nomeMostrado);
      _inteiro(t, nome);
      expect(t.getSize(ln).height, greaterThanOrEqualTo(56), reason: l.nomeMostrado);
      _alvo48(
        t,
        find.descendant(of: ln, matching: find.byType(Checkbox)),
        motivo: 'a caixa de ${l.nomeMostrado}',
      );
      final pilula = find.descendant(of: ln, matching: find.byType(PilulaEstado));
      expect(pilula, findsOneWidget);
      expect(t.getRect(pilula).top, greaterThanOrEqualTo(t.getRect(nome).bottom - .5), reason: 'o estado em baixo');
      if (l.ultima?.motivo case final m?) {
        expect(find.descendant(of: ln, matching: find.textContaining(m.substring(0, 8))), findsOneWidget);
      }
    }
    // «selecionar visíveis» na barra de cima, junto de Ações, com 48
    final caixa = find.byKey(const ValueKey('caixaCabecalho'));
    final acoes = find.byKey(const ValueKey('botaoAcoes'));
    expect(caixa.hitTestable(), findsOneWidget);
    _alvo48(
      t,
      find.descendant(of: caixa, matching: find.byType(Checkbox)),
      motivo: 'selecionar visíveis',
    );
    _alvo48(t, acoes, motivo: 'Ações');
    expect((t.getCenter(caixa).dy - t.getCenter(acoes).dy).abs(), lessThan(24), reason: 'na mesma linha');
    _noEcra(t, acoes, ecra);
    expect(find.bySemanticsLabel(RegExp('Selecionar todas as visíveis')), findsOneWidget);
    final todas = find.descendant(of: caixa, matching: find.text('Todas'));
    _inteiro(t, todas);
    _semReticencias(t, todas);
    await t.tap(caixa);
    await t.pump();
    expect(find.text('Ações (20)'), findsOneWidget);
    // uma linha à mão
    await t.tap(caixa);
    await t.pump();
    await t.tap(linha(find.byType(PassoVerificar), vistas.first.nomeMostrado));
    await t.pump();
    expect(find.text('Ações (1)'), findsOneWidget);
    await t.tap(acoes);
    await t.pumpAndSettle();
    expect(find.text('Verificar selecionadas'), findsOneWidget);
    await t.tapAt(const Offset(4, 4));
    await t.pumpAndSettle();
    // a deslizar, a pesquisa e os estados saem; a barra da seleção e de Ações fica presa em cima
    final antes = t.getRect(acoes);
    await t.drag(listaPasso2(), const Offset(0, -400));
    await t.pumpAndSettle();
    expect(acoes.hitTestable(), findsOneWidget, reason: 'Ações continua à mão');
    expect(caixa.hitTestable(), findsOneWidget);
    expect(t.getRect(acoes).top, lessThan(antes.top), reason: 'subiu e ficou presa');
    final vistasDepois = [
      for (final l in area.listas)
        if (noPasso2(find.text(l.nomeMostrado)).hitTestable().evaluate().isNotEmpty) l,
    ];
    expect(vistasDepois.length, greaterThanOrEqualTo(4), reason: 'sem a pesquisa à vista cabem mais listas');
    for (final l in vistasDepois) {
      expect(
        t.getRect(noPasso2(find.text(l.nomeMostrado))).top,
        greaterThanOrEqualTo(t.getRect(acoes).top),
        reason: '${l.nomeMostrado} passa por baixo da barra',
      );
    }
    sem.dispose();
  });

  _noTelemovel('passo 2 a verificar: «A verificar · canal 2/3» e «Na fila» inteiros', (t, ecra) async {
    final ver = _VerificadorPreso();
    final s = ServicoVerificacao(bib, colecao: area, verificador: ver, workers: 3);
    try {
      await t.pumpWidget(casca(s));
      await t.pumpAndSettle();
      await abrirPasso(t, 'Verificar');
      unawaited(s.verificarVarias(area.listas.take(5).toList()));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      final aVerificar = noPasso2(find.text('A verificar · canal 2/3')).hitTestable();
      expect(aVerificar, findsWidgets);
      _inteiro(t, aVerificar.first);
      _semReticencias(t, aVerificar.first);
      final naFila = noPasso2(find.text('Na fila'));
      for (var i = 0; i < 10 && naFila.hitTestable().evaluate().isEmpty; i++) {
        await t.drag(listaPasso2(), const Offset(0, -150));
        await t.pump();
      }
      _inteiro(t, naFila.first);
      _semReticencias(t, naFila.first);
    } finally {
      s.parar();
      ver.soltar();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }
  });

  _noTelemovel('passo 3: os 6 chips à vista, linhas de 48 e sem «OK marca/desmarca»', (t, ecra) async {
    await t.pumpWidget(casca());
    await t.pumpAndSettle();
    await abrirPasso(t, 'Enviar ou exportar');
    for (final c in ['Funcionam (', 'Inconclusivas (', 'Não funcionam (', 'Por verificar (', 'Todas (', 'Nenhuma']) {
      final chip = noPasso3(find.textContaining(c)).hitTestable();
      expect(chip, findsOneWidget, reason: c);
      _noEcra(t, chip, ecra, motivo: c);
      _alvo48(
        t,
        find.ancestor(of: chip, matching: find.byType(RawChip)),
        motivo: c,
      );
    }
    expect(find.textContaining('OK marca'), findsNothing);
    final vistas = [
      for (final l in area.listas)
        if (noPasso3(find.text(l.nomeMostrado)).hitTestable().evaluate().isNotEmpty) l,
    ];
    expect(vistas, isNotEmpty);
    for (final l in vistas.take(3)) {
      final ln = linha(find.byType(PassoEnviar), l.nomeMostrado);
      _inteiro(t, noPasso3(find.text(l.nomeMostrado)));
      expect(t.getSize(ln).height, greaterThanOrEqualTo(48));
      _alvo48(
        t,
        find.descendant(of: ln, matching: find.byType(Checkbox)),
        motivo: l.nomeMostrado,
      );
    }
    // marcar uma linha à mão
    await t.tap(linha(find.byType(PassoEnviar), vistas.first.nomeMostrado));
    await t.pump();
    expect(find.text('Enviar 1 lista'), findsOneWidget);
  });

  _noTelemovel('diálogo de envio em ecrã inteiro, com os «manter» à vista sem deslizar', (t, ecra) async {
    await t.pumpWidget(casca());
    await t.pumpAndSettle();
    await abrirPasso(t, 'Enviar ou exportar');
    await t.tap(noPasso3(find.textContaining('Funcionam (')));
    await t.pump();
    await t.tap(find.text('Enviar 10 listas'));
    await t.pumpAndSettle();
    final dialogo = find.byType(Dialog);
    expect(t.getRect(dialogo), Offset.zero & ecra, reason: 'ecrã inteiro');
    await t.tap(find.descendant(of: dialogo, matching: find.text('Substituir as listas de Ver TV')));
    await t.pumpAndSettle();
    for (final m in ['Nenhuma', 'Favoritas', 'As que funcionam', 'As inconclusivas']) {
      final f = find.descendant(of: dialogo, matching: find.text(m)).hitTestable();
      expect(f, findsOneWidget, reason: m);
      _noEcra(t, f, ecra, motivo: m);
    }
    final enviar = find.descendant(of: dialogo, matching: find.widgetWithText(FilledButton, 'Enviar 10 listas'));
    expect(enviar.hitTestable(), findsOneWidget);
    _noEcra(t, enviar, ecra);
    _alvo48(t, enviar);
    final fechar = find.ancestor(
      of: find.descendant(of: dialogo, matching: find.byTooltip('Cancelar')),
      matching: find.byType(IconButton),
    );
    _alvo48(t, fechar);
    await t.tap(fechar);
    await t.pumpAndSettle();
    expect(dialogo, findsNothing);
  });

  _noTelemovel('importar: sem palavras partidas e «Limpar o Gestor» em vermelho, no fim', (t, ecra) async {
    await t.pumpWidget(casca());
    await t.pumpAndSettle();
    await abrirPasso(t, 'Importar');
    for (final o in [
      'Ficheiros',
      'Accounts.json, .ini, .m3u, .txt',
      'Colar texto',
      'Uma lista por linha',
      'Listas do stbstalker',
      'Publicadas entre duas datas',
      'De Ver TV',
      'Ainda não há listas em Ver TV',
    ]) {
      final f = find.text(o).hitTestable();
      expect(f, findsWidgets, reason: o);
      _semPalavrasPartidas(t, f.first);
    }
    final limpar = find.text('Limpar o Gestor');
    await t.ensureVisible(limpar);
    await t.pumpAndSettle();
    expect(t.renderObject<RenderParagraph>(limpar).text.style?.color, Tokens.mau);
    expect(
      find.ancestor(of: limpar, matching: find.byType(FilledButton)),
      findsNothing,
      reason: 'ação secundária',
    );
    _alvo48(t, find.ancestor(of: limpar, matching: find.byType(TextButton)));
    expect(t.getRect(limpar).top, greaterThan(t.getRect(find.text('Escolher ficheiros')).bottom), reason: 'no fim');
  });

  _noTelemovel('passo 2 com 300 listas: chega-se à última, seleciona-se e «Ações» continua à mão', (t, ecra) async {
    await t.runAsync(() => area.adicionar(_importadas(280, desde: 20)));
    await t.pumpWidget(casca());
    await t.pumpAndSettle();
    await abrirPasso(t, 'Verificar');
    final ultima = area.listas.last.nomeMostrado;
    await t.scrollUntilVisible(noPasso2(find.text(ultima)), 2000, scrollable: listaPasso2());
    await t.pumpAndSettle();
    _inteiro(t, noPasso2(find.text(ultima)));
    await t.tap(linha(find.byType(PassoVerificar), ultima));
    await t.pump();
    expect(find.text('Ações (1)').hitTestable(), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('botaoAcoes')));
    await t.pumpAndSettle();
    expect(find.text('Remover do gestor'), findsOneWidget);
    await t.tapAt(const Offset(4, 4));
    await t.pumpAndSettle();
  }, configs: const [(360.0, 800.0, 1.3)]);

  testWidgets('Android sem TV a 800 dp (tablet): sem as dicas do comando', (t) async {
    t.view.physicalSize = const Size(800, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await t.pumpWidget(casca());
      await t.pumpAndSettle();
      expect(find.text('Verificar').hitTestable(), findsWidgets, reason: 'o resumo à vista');
      expect(find.text('OK: abrir →'), findsNothing);
      await abrirPasso(t, 'Enviar ou exportar');
      expect(find.textContaining('OK marca'), findsNothing);
      expect(find.text('0 marcadas'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('no computador (Windows) a 800 dp: com as dicas do comando', (t) async {
    t.view.physicalSize = const Size(800, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await t.pumpWidget(casca());
      await t.pumpAndSettle();
      expect(find.text('OK: abrir →'), findsNWidgets(3));
      await abrirPasso(t, 'Enviar ou exportar');
      expect(find.text('0 marcadas · OK marca/desmarca uma lista'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
