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
import 'package:player_iptv/ui/adicionar.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/principal/barra_seccoes.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';

import 'ajuda_dpad.dart';

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

/// Tab até ao botão com `texto` (no máximo 60 vezes); com `exato`, só o que tem esse texto
/// (o filtro "Todas · 2" não é o "Todas" de marcar).
Future<void> _irPara(WidgetTester t, String texto, {bool exato = false}) async {
  bool chegou() => exato ? _focado() == texto : _focado().startsWith(texto);
  for (var i = 0; i < 60 && !chegou(); i++) {
    await _tecla(t, LogicalKeyboardKey.tab);
  }
  expect(chegou(), isTrue, reason: 'Tab até "$texto"; foco em ${_focado()}');
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

/// Verificador que fica no "canal 2/3" de cada lista até ao fim do teste (sem relógios: o teste
/// acaba sem tempos pendentes).
class _Preso extends Verificador {
  final _nunca = Completer<void>();

  @override
  Future<ResultadoVerificacao> verificarComLimite(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso}) async {
    aviso?.call('canal 2/3');
    await _nunca.future;
    return const ResultadoVerificacao(EstadoV.funciona, 'ok');
  }
}

/// Os controlos à vista que estão desligados (o Gestor não tem nenhum "à espera").
List<String> _desligados() {
  final desligados = <String>[];
  var n = 0;
  for (final e in find.byWidgetPredicate((_) => true).evaluate()) {
    final w = e.widget;
    final ligado = switch (w) {
      ButtonStyleButton() => w.onPressed != null,
      IconButton() => w.onPressed != null,
      ChoiceChip() => w.onSelected != null,
      ActionChip() => w.onPressed != null,
      CheckboxListTile() => w.onChanged != null,
      CartaoModerno() => w.onTap != null,
      _ => null,
    };
    if (ligado == null) continue;
    n++;
    if (!ligado) {
      final textos = find.descendant(of: find.byWidget(w), matching: find.byType(Text)).evaluate();
      desligados.add('${w.runtimeType}: ${textos.map((t) => (t.widget as Text).data).join(' ')}');
    }
  }
  expect(n, greaterThanOrEqualTo(3), reason: 'há controlos à vista');
  return desligados;
}

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

  Widget telaGestor([ServicoVerificacao? s]) => TelaGestor(
      biblioteca: bib, area: area, servico: s ?? ServicoVerificacao(bib, colecao: area), tarefas: ServicoTarefas());

  Widget inicio({ServicoVerificacao? s, Seccao inicial = Seccao.verTv}) => TelaPrincipal(
        verTv: TelaInicio(biblioteca: bib, area: area),
        gestor: telaGestor(s),
        definicoes: const SizedBox(),
        inicial: inicial,
      );

  Widget gestor([ServicoVerificacao? s]) => Scaffold(body: telaGestor(s));

  /// Abre o sub-ecrã do passo com este nome (com um toque).
  Future<void> abrirPasso(WidgetTester t, String passo) async {
    await t.tap(find.descendant(of: find.byType(CartaoModerno), matching: find.text(passo)));
    await t.pumpAndSettle();
  }

  /// O botão "Voltar" de um sub-ecrã.
  Future<void> voltar(WidgetTester t) async {
    await t.tap(find.widgetWithText(TextButton, 'Voltar'));
    await t.pumpAndSettle();
  }

  Finder linha(String nome) => find.ancestor(of: find.textContaining(nome), matching: find.byType(CheckboxListTile));

  Future<void> marcar(WidgetTester t, String nome) async {
    await t.tap(linha(nome));
    await t.pump();
  }

  group('Estados no Gestor', () {
    testWidgets('a linha de uma lista inconclusiva diz "Inconclusiva" e o motivo', (t) async {
      await t.runAsync(() => area.adicionar([
            Importada(contaDeLinha('http://outro.com/c/ 00:1A:79:00:00:02')!, _u('inconclusivo', motivo: 'tempo esgotado')),
          ]));
      _tamanho(t, 1200, 2400);
      await t.pumpWidget(_app(gestor()));
      await t.pump();
      // a pílula do estado e o motivo, na mesma linha
      expect(find.descendant(of: linha('OUTRO'), matching: find.text('Inconclusiva')), findsOneWidget);
      expect(find.descendant(of: linha('OUTRO'), matching: find.text('tempo esgotado')), findsOneWidget);
      expect(find.textContaining('Inconclusivo'), findsNothing);
    });

    testWidgets('a tabela tem as colunas LISTA, ESTADO, CANAIS e VALIDADE, alinhadas com as linhas', (t) async {
      await t.runAsync(() => area.adicionar([
            Importada(
                contaDeLinha('http://boa.com/c/ 00:1A:79:00:00:01')!,
                UltimaVerificacao(estado: 'funciona', data: DateTime(2026, 3, 1), validade: '2027-10-16', canais: const [
                  {'id': 'a', 'nome': 'A', 'estado': 'funciona', 'motivo': ''},
                  {'id': 'b', 'nome': 'B', 'estado': 'funciona', 'motivo': ''},
                  {'id': 'c', 'nome': 'C', 'estado': 'nao_funciona', 'motivo': ''},
                ])),
          ]));
      _tamanho(t, 960 - BarraSeccoes.largura, 1200);
      await t.pumpWidget(_app(gestor()));
      await t.pump();
      for (final c in ['LISTA', 'ESTADO', 'CANAIS', 'VALIDADE']) {
        expect(find.text(c), findsOneWidget, reason: c);
      }
      expect(find.descendant(of: linha('001BOA'), matching: find.text('2/3')), findsOneWidget);
      expect(find.descendant(of: linha('001BOA'), matching: find.text('16/10/2027')), findsOneWidget);
      expect(find.descendant(of: linha('001BOA'), matching: find.text('Funciona')), findsOneWidget);
      // as colunas começam onde começa o cabeçalho
      expect((t.getRect(find.text('CANAIS')).left - t.getRect(find.text('2/3')).left).abs(), lessThan(2));
      expect((t.getRect(find.text('VALIDADE')).left - t.getRect(find.text('16/10/2027')).left).abs(), lessThan(2));
      expect((t.getRect(find.text('LISTA')).left - t.getRect(find.textContaining('001BOA')).left).abs(), lessThan(2));
    });
  });

  group('Player', () {
    testWidgets('as secções chamam-se Ver TV, Gestor e Definições; "Adicionar listas" só no Gestor', (t) async {
      _tamanho(t, 1200, 900);
      await t.pumpWidget(_app(inicio()));
      await t.pump();
      final barra = find.byType(BarraSeccoes);
      for (final r in ['Ver TV', 'Gestor', 'Definições']) {
        expect(find.descendant(of: barra, matching: find.text(r)), findsOneWidget, reason: r);
      }
      expect(find.text('Player'), findsNothing);
      expect(find.text('Listas'), findsNothing);
      // o Player não verifica: sem botão "Verificar"
      expect(find.widgetWithText(ButtonStyleButton, 'Verificar'), findsNothing);
      expect(find.text('Adicionar listas'), findsNothing);
      await t.tap(find.descendant(of: barra, matching: find.text('Gestor')));
      await t.pumpAndSettle();
      await abrirPasso(t, 'Importar');
      expect(find.text('Adicionar listas').hitTestable(), findsOneWidget);
      await t.tap(find.descendant(of: barra, matching: find.text('Ver TV')));
      await t.pumpAndSettle();
      expect(find.text('Adicionar listas'), findsNothing);
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
      expect(find.textContaining('Funciona'), findsWidgets);
      expect(find.text('até 16/10/2027'), findsNWidgets(2));
      expect(find.text('tempo esgotado'), findsOneWidget);
      expect(find.textContaining('Verificar'), findsNothing);
      expect(find.text('Verificar de novo'), findsNothing);
      expect(find.byTooltip('Adicionar listas'), findsNothing);
      expect(find.text('Adicionar listas'), findsNothing);
      // pesquisa e filtros ficam
      expect(find.widgetWithText(ChoiceChip, 'Funcionam'), findsOneWidget);
    });

    testWidgets('vazio: "Ir para o Gestor" muda de secção, o foco fica no passo 1 e OK leva a "Adicionar listas"',
        (t) async {
      _tamanho(t, 960, 540);
      await t.pumpWidget(_app(inicio()));
      await t.pump();
      expect(find.text('Ainda não há listas para ver'), findsOneWidget);
      expect(_focado(), 'Ir para o Gestor');
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(_focado(), '1 | Importar | O Gestor está vazio');
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
      await abrirPasso(t, 'Importar');
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
      await _irPara(t, 'Todas', exato: true);
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
      await _irPara(t, 'Todas', exato: true);
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

    testWidgets('Exportar pergunta o formato (Accounts.json ou .ini); sem seleção avisa', (t) async {
      await preparar(t);
      await t.tap(find.widgetWithText(OutlinedButton, 'Exportar'));
      await t.pump();
      expect(find.text('Selecione as listas a exportar.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await t.tap(find.widgetWithText(ActionChip, 'Todas'));
      await t.pump();
      await t.tap(find.widgetWithText(OutlinedButton, 'Exportar'));
      await t.pumpAndSettle();
      expect(find.text('Accounts.json (sfvip player)'), findsOneWidget);
      expect(find.text('Ficheiros .ini (Stalker Portal Player)'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Remover e Limpar o Gestor pedem confirmação', (t) async {
      await preparar(t);
      await t.tap(find.widgetWithText(ActionChip, 'Funcionam'));
      await t.pump();
      await t.tap(find.widgetWithText(OutlinedButton, 'Remover'));
      await t.pumpAndSettle();
      expect(find.text('Remover do Gestor?'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(area.listas, hasLength(2));
      await t.tap(find.widgetWithText(OutlinedButton, 'Remover'));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(find.widgetWithText(FilledButton, 'Remover'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(area.listas.map((l) => hostDe(l.conta.endereco)), ['outra.com']);

      await abrirPasso(t, 'Importar');
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

  group('Gestor sem esperas', () {
    late ServicoVerificacao s;

    Future<void> comTres(WidgetTester t, {int workers = 4}) async {
      await t.runAsync(() => area.adicionar([
            Importada(contaDeLinha('http://boa.com/c/ 00:1A:79:00:00:01')!, _u('funciona')),
            Importada(contaDeLinha('http://meia.com/l.m3u')!),
            Importada(contaDeLinha('http://morta.com/l.m3u')!, _u('nao_funciona')),
          ]));
      s = ServicoVerificacao(bib, colecao: area, verificador: _Preso(), workers: workers);
      _tamanho(t, 1200, 1800);
      await t.pumpWidget(_app(gestor(s)));
      await t.pump();
    }

    testWidgets('com uma verificação a decorrer, nenhum botão está desligado (no principal e nos sub-ecrãs)',
        (t) async {
      await comTres(t);
      s.verificar(area.listas.first);
      await t.pump();
      expect(s.ocupado, isTrue);
      expect(_desligados(), isEmpty);
      await abrirPasso(t, 'Importar');
      expect(find.text('Adicionar listas').hitTestable(), findsOneWidget);
      expect(_desligados(), isEmpty);
      await voltar(t);
      await abrirPasso(t, 'Verificar');
      expect(find.text('Parar').hitTestable(), findsOneWidget);
      expect(_desligados(), isEmpty);
      await voltar(t);
      // e sem nada selecionado nem a decorrer, os da barra também ficam ligados (avisam)
      s.parar();
      await t.pump();
      expect(_desligados(), isEmpty);
      await t.tap(find.text('Verificar (entra na fila)'));
      await t.pump();
      expect(find.text('Selecione as listas a verificar.'), findsOneWidget);
    });

    testWidgets('"Verificar (entra na fila)" com seleção junta à fila a meio de uma verificação', (t) async {
      await comTres(t);
      final [boa, meia, morta] = area.listas;
      s.verificar(boa);
      await t.pump();
      await marcar(t, '002MEIA');
      await marcar(t, '003MORTA');
      expect(find.text('Selecionadas: 2'), findsOneWidget);
      await t.tap(find.text('Verificar (entra na fila)'));
      await t.pump();
      expect([s.aVerificar(boa.id), s.aVerificar(meia.id), s.aVerificar(morta.id)], [true, true, true]);
      expect(s.total, 3, reason: 'juntaram-se à fila (não foi ignorado)');
      expect(find.text('2 listas entraram na fila.'), findsOneWidget);
      // outra vez: já lá estão
      await t.tap(find.text('Verificar (entra na fila)'));
      await t.pumpAndSettle();
      expect(find.text('As listas selecionadas já estão na fila.'), findsOneWidget);
      expect(s.total, 3);
    });

    testWidgets('uma lista a ser verificada mostra "A verificar · canal 2/3"; a da fila "Na fila"; '
        'o indicador e o passo 2 dizem quantas', (t) async {
      await comTres(t, workers: 1);
      expect(find.text('Nada a decorrer'), findsOneWidget);
      s.verificarVarias(area.listas.take(2));
      await t.pump();
      expect(find.descendant(of: linha('001BOA'), matching: find.text('A verificar · canal 2/3')), findsOneWidget);
      expect(find.descendant(of: linha('002MEIA'), matching: find.text('Na fila')), findsOneWidget);
      expect(find.descendant(of: linha('003MORTA'), matching: find.text('Não funciona')), findsOneWidget);
      // o indicador de atividade e o estado do passo 2
      expect(find.text('A verificar 0/2'), findsNWidgets(2));
      expect(find.text('Nada a decorrer'), findsNothing);
    });

    testWidgets('remover selecionadas com uma a ser verificada pede confirmação e cancela só essa', (t) async {
      await comTres(t);
      final [boa, meia, morta] = area.listas;
      s.verificarVarias([boa, morta]);
      await t.pump();
      await marcar(t, '001BOA');
      await marcar(t, '002MEIA');
      await t.tap(find.widgetWithText(OutlinedButton, 'Remover'));
      await t.pumpAndSettle();
      expect(find.textContaining('Uma delas está a ser verificada: essa verificação é cancelada.'), findsOneWidget);
      // cancelar não muda nada
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect([s.aVerificar(boa.id), s.aVerificar(morta.id)], [true, true]);
      expect(area.listas, hasLength(3));
      await t.tap(find.widgetWithText(OutlinedButton, 'Remover'));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(find.widgetWithText(FilledButton, 'Remover'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(s.aVerificar(boa.id), isFalse, reason: 'a removida deixou de ser verificada');
      expect(s.aVerificar(morta.id), isTrue, reason: 'a outra continua');
      expect(s.total, 1);
      expect(area.listas.map((l) => l.id), [morta.id]);
      expect(area.porId(meia.id), isNull);
      expect(t.takeException(), isNull);
    });

    testWidgets('trocar para importar (e para Ver TV) e voltar mantém o filtro, a seleção e o sub-ecrã', (t) async {
      await t.runAsync(() => area.adicionar([
            Importada(contaDeLinha('http://boa.com/c/ 00:1A:79:00:00:01')!, _u('funciona')),
            Importada(contaDeLinha('http://outra.com/c/ 00:1A:79:00:00:02')!, _u('funciona')),
            Importada(contaDeLinha('http://morta.com/l.m3u')!, _u('nao_funciona')),
          ]));
      _tamanho(t, 1200, 1800);
      await t.pumpWidget(_app(inicio(inicial: Seccao.gestor)));
      await t.pump();
      await t.tap(find.widgetWithText(ChoiceChip, 'Funcionam · 2'));
      await t.pump();
      await marcar(t, '002OUTRA');
      expect(find.textContaining('003MORTA'), findsNothing);
      await abrirPasso(t, 'Importar');
      expect(find.text('Adicionar listas').hitTestable(), findsOneWidget);
      // a Ver TV e de volta ao Gestor: continua no sub-ecrã de importar
      final barra = find.byType(BarraSeccoes);
      await t.tap(find.descendant(of: barra, matching: find.text('Ver TV')));
      await t.pumpAndSettle();
      expect(find.text('Adicionar listas'), findsNothing);
      await t.tap(find.descendant(of: barra, matching: find.text('Gestor')));
      await t.pumpAndSettle();
      expect(find.text('Adicionar listas').hitTestable(), findsOneWidget);
      await voltar(t);
      final filtro = t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Funcionam · 2'));
      expect(filtro.selected, isTrue, reason: 'o filtro fica');
      expect(find.textContaining('003MORTA'), findsNothing);
      expect(t.widget<CheckboxListTile>(linha('002OUTRA')).value, isTrue, reason: 'a seleção fica');
      expect(t.widget<CheckboxListTile>(linha('001BOA')).value, isFalse);
      expect(find.text('Selecionadas: 1'), findsOneWidget);
    });

    testWidgets('Voltar num sub-ecrã regressa ao principal (foco no passo); no principal vai para Ver TV',
        (t) async {
      ecraTvTeste(t);
      await t.runAsync(() => area.adicionar([Importada(contaDeLinha('http://boa.com/l.m3u')!)]));
      await t.pumpWidget(_app(inicio(inicial: Seccao.gestor)));
      await t.pump();
      await abrirPasso(t, 'Verificar');
      expect(_focado(), startsWith('Verificar todas'));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Verificar todas (1)'), findsNothing);
      expect(find.text('Gestor de listas'), findsOneWidget);
      expect(_focado(), startsWith('2 | Verificar'), reason: 'o foco volta ao passo 2');
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Gestor de listas'), findsNothing, reason: 'agora sim, Ver TV');
    });

    testWidgets('na TV (960 com a barra lateral) a barra das selecionadas cabe e tudo se alcança com as setas',
        (t) async {
      ecraTvTeste(t);
      await t.runAsync(() => area.adicionar([
            Importada(contaDeLinha('http://boa.com/c/ 00:1A:79:00:00:01')!, _u('funciona')),
            Importada(contaDeLinha('http://meia.com/l.m3u')!),
          ]));
      await t.pumpWidget(_app(inicio(inicial: Seccao.gestor)));
      await t.pump();
      const acoes = ['Verificar (entra na fila)', 'Enviar para o Player', 'Exportar', 'Remover'];
      for (final c in acoes) {
        final r = t.getRect(find.ancestor(of: find.text(c), matching: find.bySubtype<ButtonStyleButton>()).first);
        expect(r.left >= BarraSeccoes.largura && r.right <= 960, isTrue, reason: '$c em $r');
      }
      // da barra das secções para dentro; em cada linha: ao princípio (ESQUERDA), até ao fim
      // (DIREITA) e BAIXO para a linha seguinte
      for (var i = 0; i < 6 && textosFocados() != 'Gestor'; i++) {
        await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
      }
      expect(textosFocados(), 'Gestor');
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
      expect(textosFocados(), startsWith('1 | Importar'));
      final vistos = <String>{};
      for (var l = 0; l < 14 && !vistos.any((v) => v.contains('002MEIA')); l++) {
        for (var i = 0; i < 8; i++) {
          final antes = textosFocados();
          await teclaDpad(t, LogicalKeyboardKey.arrowLeft);
          if (textosFocados() == 'Gestor') {
            await teclaDpad(t, LogicalKeyboardKey.arrowRight);
            break;
          }
          if (textosFocados() == antes) break;
        }
        for (var i = 0; i < 8; i++) {
          final antes = textosFocados();
          vistos.add(antes);
          await teclaDpad(t, LogicalKeyboardKey.arrowRight);
          if (textosFocados() == antes) break;
        }
        await teclaDpad(t, LogicalKeyboardKey.arrowDown);
        vistos.add(textosFocados());
      }
      final caminho = vistos.join(' / ');
      for (final v in [
        '1 | Importar', '2 | Verificar', '3 | Enviar ou exportar',
        'Todas · 2', 'Funcionam · 1', 'Inconclusivas · 0', 'Não funcionam · 0', 'Por verificar · 1',
        'Funcionam + inconclusivas', 'Nenhuma', ...acoes, '001BOA', '002MEIA',
      ]) {
        expect(caminho, contains(v), reason: caminho);
      }
      expect(vistos, containsAll(['Funcionam', 'Todas']), reason: caminho);
    });
  });
}
