import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/adicionar.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/ui/verificar/tela_verificar.dart';
import 'package:player_iptv/verificar/servico.dart';

Widget _app(Widget w) =>
    MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

void _tamanho(WidgetTester t, double l, double a) {
  t.view.physicalSize = Size(l, a);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Os textos dentro do widget com o foco (ou a dica, num botão só com ícone).
String _focado() {
  final no = FocusManager.instance.primaryFocus;
  final ctx = no?.context;
  if (ctx == null || no is FocusScopeNode) return '';
  final textos = <String>[];
  void visitar(Element e) {
    if (e.widget case Text(:final data?)) textos.add(data);
    e.visitChildren(visitar);
  }

  (ctx as Element).visitChildren(visitar);
  if (textos.isEmpty) {
    final dica = ctx.findAncestorWidgetOfExactType<Tooltip>()?.message;
    if (dica != null) textos.add(dica);
  }
  return textos.join(' | ');
}

Future<void> _tecla(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pump();
}

/// Tab até ao botão com `texto` (no máximo 60 vezes).
Future<void> _irPara(WidgetTester t, String texto) async {
  for (var i = 0; i < 60 && !_focado().startsWith(texto); i++) {
    await _tecla(t, LogicalKeyboardKey.tab);
  }
  expect(_focado(), startsWith(texto), reason: 'Tab até "$texto"');
}

/// Deixa acabar as escritas em disco (IO real), com um frame entre cada passo.
Future<void> _esperar(WidgetTester t, bool Function() feito) async {
  for (var i = 0; i < 100 && !feito(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
  await t.pumpAndSettle();
}

bool _ha(String texto) => find.textContaining(texto).evaluate().isNotEmpty;

UltimaVerificacao _u(String estado, {String motivo = ''}) =>
    UltimaVerificacao(estado: estado, data: DateTime(2026, 3, 1), validade: '2027-10-16', motivo: motivo);

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('gestor_ui');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
  });
  tearDown(() async {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Widget inicio() {
    final s = ServicoVerificacao(bib, colecao: area);
    return TelaInicio(
      biblioteca: bib,
      area: area,
      separadorGestor: TelaVerificar(biblioteca: bib, area: area, servico: s),
    );
  }

  Widget gestor() => Scaffold(
      body: TelaVerificar(biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area)));

  group('Estados no Gestor', () {
    testWidgets('a linha de uma lista inconclusiva diz "Inconclusiva"', (t) async {
      await t.runAsync(() => bib.adicionar([
            Importada(contaDeLinha('http://outro.com/c/ 00:1A:79:00:00:02')!, _u('inconclusivo', motivo: 'tempo esgotado')),
          ]));
      _tamanho(t, 1200, 900);
      await t.pumpWidget(_app(gestor()));
      await t.pump();
      expect(find.textContaining('Inconclusiva · tempo esgotado'), findsOneWidget);
      expect(find.textContaining('Inconclusivo'), findsNothing);
    });
  });

  group('Player', () {
    testWidgets('os separadores chamam-se Player e Gestor; o "+" só existe com o Gestor ativo', (t) async {
      _tamanho(t, 1200, 900);
      await t.pumpWidget(_app(inicio()));
      await t.pump();
      expect(find.text('Player'), findsOneWidget);
      expect(find.text('Gestor'), findsOneWidget);
      expect(find.text('Listas'), findsNothing);
      expect(find.text('Verificar'), findsNothing);
      expect(find.byTooltip('Adicionar listas'), findsNothing);
      await t.tap(find.text('Gestor'));
      await t.pumpAndSettle();
      expect(find.byTooltip('Adicionar listas'), findsOneWidget);
      await t.tap(find.text('Player'));
      await t.pumpAndSettle();
      expect(find.byTooltip('Adicionar listas'), findsNothing);
    });

    testWidgets('não gere nada (sem verificar), mas os cartões mostram o estado', (t) async {
      await t.runAsync(() => bib.adicionar([
            Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!, _u('funciona')),
            Importada(contaDeLinha('http://outro.com/c/ 00:1A:79:00:00:02')!,
                _u('inconclusivo', motivo: 'tempo esgotado')),
          ]));
      _tamanho(t, 1200, 900);
      await t.pumpWidget(_app(inicio()));
      await t.pump();
      expect(find.text('001NXTBOX 161027'), findsOneWidget);
      expect(find.text('Funciona'), findsWidgets);
      expect(find.text('até 16/10/2027'), findsNWidgets(2));
      expect(find.text('tempo esgotado'), findsOneWidget);
      expect(find.textContaining('Verificar'), findsNothing);
      expect(find.text('Verificar de novo'), findsNothing);
      expect(find.byTooltip('Adicionar listas'), findsNothing);
      expect(find.text('Adicionar listas'), findsNothing);
      // pesquisa e filtros ficam
      expect(find.widgetWithText(ChoiceChip, 'Funcionam'), findsOneWidget);
    });

    testWidgets('vazio: "Ir para o Gestor" muda de separador e o foco fica no "+"', (t) async {
      _tamanho(t, 960, 540);
      await t.pumpWidget(_app(inicio()));
      await t.pump();
      expect(find.text('Ainda não há listas no Player'), findsOneWidget);
      expect(_focado(), 'Ir para o Gestor');
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.text('Listas do stbstalker').hitTestable(), findsOneWidget);
      expect(_focado(), 'Adicionar listas');
      // e o "+" abre o diálogo de adicionar
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('Gestor', () {
    test('ficheiros/colar entram no Gestor e não no Player', () async {
      expect(await importarTexto(area, 'http://x.com/l.m3u\nhttp://y.com/l.m3u'), '2 listas novas.');
      expect(area.listas, hasLength(2));
      expect(bib.listas, isEmpty);
    });

    testWidgets('Importar do Player copia as listas do Player', (t) async {
      await t.runAsync(() => bib.adicionar([
            Importada(contaDeLinha('http://a.com/c/ 00:1A:79:00:00:01')!, _u('funciona')),
            Importada(contaDeLinha('http://b.com/l.m3u')!),
          ]));
      _tamanho(t, 1200, 1800);
      await t.pumpWidget(_app(gestor()));
      await t.pump();
      await t.runAsync(() async {
        await t.tap(find.text('Importar do Player'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await t.pump();
      expect(area.listas.map((l) => l.nomeMostrado), ['001A 161027', '002B']);
      expect(find.text('2 listas importadas do Player.'), findsOneWidget);
    });

    Future<void> preparar(WidgetTester t) async {
      await t.runAsync(() async {
        await bib.adicionar([
          Importada(contaDeLinha('http://velha.com/c/ 00:1A:79:00:00:01')!, _u('nao_funciona')),
          Importada(contaDeLinha('http://boa.com/c/ 00:1A:79:00:00:01')!, _u('funciona')),
        ]);
        await area.adicionar([
          Importada(contaDeLinha('http://nova.com/c/ 00:1A:79:00:00:01')!, _u('funciona')),
          Importada(contaDeLinha('http://outra.com/l.m3u')!),
        ]);
      });
      _tamanho(t, 1200, 1800);
      await t.pumpWidget(_app(gestor()));
      await t.pump();
    }

    List<String> player() => [for (final l in bib.listas) hostDe(l.conta.endereco)];

    testWidgets('Enviar para o Player pede sempre confirmação: cancelar não muda nada', (t) async {
      await preparar(t);
      await t.tap(find.widgetWithText(ActionChip, 'Todas'));
      await t.pump();
      await t.tap(find.textContaining('Enviar para o Player'));
      await t.pumpAndSettle();
      expect(find.text('Adicionar às listas do Player'), findsOneWidget);
      expect(find.text('Esmagar as listas do Player'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(player(), ['velha.com', 'boa.com']);
      // cancelar na segunda pergunta também não muda nada
      await t.tap(find.textContaining('Enviar para o Player'));
      await t.pumpAndSettle();
      await t.tap(find.text('Esmagar as listas do Player'));
      await t.pumpAndSettle();
      expect(find.text('Manter as que funcionam'), findsOneWidget);
      expect(find.text('Manter as que funcionam e as inconclusivas'), findsOneWidget);
      expect(find.text('Esmagar todas'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(player(), ['velha.com', 'boa.com']);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Enviar: adicionar às listas do Player e o resumo', (t) async {
      await preparar(t);
      await t.tap(find.widgetWithText(ActionChip, 'Funcionam'));
      await t.pump();
      await t.tap(find.textContaining('Enviar para o Player'));
      await t.pumpAndSettle();
      await t.tap(find.text('Adicionar às listas do Player'));
      await _esperar(t, () => _ha('Enviadas para o Player'));
      expect(player(), ['velha.com', 'boa.com', 'nova.com']);
      expect(find.text('Enviadas para o Player: 1 adicionada, 0 atualizadas, 0 removidas.'), findsOneWidget);
    });

    testWidgets('Enviar com o comando: esmagar mantendo as que funcionam (setas, OK e Voltar)', (t) async {
      await preparar(t);
      await _irPara(t, 'Todas');
      await _tecla(t, LogicalKeyboardKey.select);
      await _irPara(t, 'Enviar para o Player');
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(_focado(), contains('Adicionar às listas do Player'));
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      expect(_focado(), contains('Esmagar as listas do Player'));
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      // a 2.ª pergunta: Voltar cancela tudo
      expect(_focado(), contains('Manter as que funcionam'));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(player(), ['velha.com', 'boa.com']);
      expect(_focado(), startsWith('Enviar para o Player'), reason: 'o foco volta ao botão');
      // de novo, até ao fim
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      await _tecla(t, LogicalKeyboardKey.select); // "Manter as que funcionam"
      await _esperar(t, () => _ha('Enviadas para o Player'));
      expect(player(), ['boa.com', 'nova.com', 'outra.com']);
      expect(find.text('Enviadas para o Player: 2 adicionadas, 0 atualizadas, 1 removida.'), findsOneWidget);
      expect(_focado(), startsWith('Enviar para o Player'));
    });

    testWidgets('Enviar com o comando: esmagar todas', (t) async {
      await preparar(t);
      await _irPara(t, 'Todas');
      await _tecla(t, LogicalKeyboardKey.select);
      await _irPara(t, 'Enviar para o Player');
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      expect(_focado(), contains('Esmagar todas'));
      await _tecla(t, LogicalKeyboardKey.select);
      await _esperar(t, () => _ha('Enviadas para o Player'));
      expect(player(), ['nova.com', 'outra.com']);
    });

    testWidgets('na TV (960×540) as três opções da 2.ª pergunta cabem sem deslizar', (t) async {
      await preparar(t);
      await t.tap(find.widgetWithText(ActionChip, 'Todas'));
      await t.pump();
      await t.tap(find.textContaining('Enviar para o Player'));
      await t.pumpAndSettle();
      await t.tap(find.text('Esmagar as listas do Player'));
      await t.pumpAndSettle();
      _tamanho(t, 960, 540);
      await t.pumpAndSettle();
      final ecra = Offset.zero & const Size(960, 540);
      for (final o in ['Manter as que funcionam', 'Manter as que funcionam e as inconclusivas', 'Esmagar todas',
        'O Player fica só com as enviadas.', 'Cancelar']) {
        final r = t.getRect(find.text(o));
        expect(ecra.contains(r.topLeft) && ecra.contains(r.bottomRight), isTrue, reason: '$o em $r');
        // e não fica escondido por baixo do fim da área que desliza
        expect(find.text(o).hitTestable(), findsOneWidget, reason: o);
      }
      final pos = Scrollable.of(t.element(find.text('Esmagar todas'))).position;
      expect(pos.maxScrollExtent, 0, reason: 'sem nada escondido');
    });

    testWidgets('Remover do Gestor e Limpar o Gestor pedem confirmação', (t) async {
      await preparar(t);
      await t.tap(find.widgetWithText(ActionChip, 'Funcionam'));
      await t.pump();
      await t.tap(find.textContaining('Remover do Gestor'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(area.listas, hasLength(2));
      await t.tap(find.textContaining('Remover do Gestor'));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(find.widgetWithText(FilledButton, 'Remover'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(area.listas.map((l) => hostDe(l.conta.endereco)), ['outra.com']);

      await t.tap(find.text('Limpar o Gestor'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(area.listas, hasLength(1));
      await t.tap(find.text('Limpar o Gestor'));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(find.widgetWithText(FilledButton, 'Limpar'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(area.listas, isEmpty);
      expect(bib.listas, hasLength(2), reason: 'o Player não muda');
    });
  });
}
