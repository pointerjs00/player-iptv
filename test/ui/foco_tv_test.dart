import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/protocolo.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/tarefas/servico_tarefas.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/design/ecra.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';

/// I6: tudo só com as setas, OK e Voltar (sem requestFocus nem toques).

// como a app (main.dart): o tema segue o modo de realce do foco
Widget _app(Widget w) =>
    MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

void _tamanho(WidgetTester t, double l, double a) {
  t.view.physicalSize = Size(l, a);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Os textos dentro do widget com o foco ('' se nada tem foco).
String _focado() => _textosFocados().join(' | ');

List<String> _textosFocados() {
  final no = FocusManager.instance.primaryFocus;
  final ctx = no?.context;
  // o foco na página inteira (FocusScope) é o mesmo que nada focado
  if (ctx == null || no is FocusScopeNode) return const [];
  final textos = <String>[];
  void visitar(Element e) {
    final w = e.widget;
    if (w is Text) textos.add(w.data ?? '');
    if (w is EditableText) textos.add('[campo ${w.controller.text}]');
    e.visitChildren(visitar);
  }

  (ctx as Element).visitChildren(visitar);
  final campo = ctx.findAncestorWidgetOfExactType<EditableText>();
  if (campo != null) textos.add('[campo ${campo.controller.text}]');
  if (textos.isEmpty) {
    final dica = ctx.findAncestorWidgetOfExactType<Tooltip>()?.message;
    if (dica != null) textos.add(dica);
  }
  return textos;
}

/// Fecha o ecrã e deixa acabar os pedidos (e os seus tempos limite) que ficaram a meio.
Future<void> _fechar(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await t.pump(const Duration(minutes: 10));
}

Future<void> _tecla(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pump();
}

/// Carrega em Tab até o foco estar no widget com `texto` (no máximo 40 vezes).
/// (só um botão: um cartão inteiro, que também contém o texto, não conta)
Future<void> _irPara(WidgetTester t, String texto) async {
  bool chegou() {
    final ts = _textosFocados();
    return ts.length == 1 && ts.single.contains(texto);
  }

  for (var i = 0; i < 40 && !chegou(); i++) {
    await _tecla(t, LogicalKeyboardKey.tab);
  }
  expect(chegou(), isTrue, reason: 'Tab até "$texto"; foco em: ${_focado()}');
}

/// Porque é que o widget com o foco não tem realce visível (null = tem). O realce é uma borda
/// de pelo menos 2 px (acento ou clara) no próprio widget ou num antepassado próximo.
String? _semRealce() {
  final no = FocusManager.instance.primaryFocus;
  final ctx = no?.context;
  if (ctx == null || no is FocusScopeNode) return 'nada focado';
  bool forte(BorderSide s) =>
      s.width >= 2 && s.style != BorderStyle.none && (s.color == Realce.borda.color || s.color == Cores.texto);
  bool caixa(Decoration? d) => d is BoxDecoration && d.border is Border && forte((d.border! as Border).top);
  var ok = false;
  void ver(Widget w) {
    if (w is Material && w.shape is OutlinedBorder && forte((w.shape! as OutlinedBorder).side)) ok = true;
    if (w is DecoratedBox && caixa(w.decoration)) ok = true;
    if (w is InputDecorator && w.isFocused) {
      final b = w.decoration.focusedBorder;
      if (b is OutlineInputBorder && forte(b.borderSide)) ok = true;
    }
  }

  var n = 0;
  ver(ctx.widget);
  (ctx as Element).visitAncestorElements((e) {
    ver(e.widget);
    return !ok && ++n < 45;
  });
  // ou dentro dele (o realce das abas fica no conteúdo da aba)
  void descer(Element e, int nivel) {
    if (ok || nivel > 40) return;
    ver(e.widget);
    e.visitChildren((f) => descer(f, nivel + 1));
  }

  ctx.visitChildren((f) => descer(f, 0));
  return ok ? null : 'sem realce: ${_focado()} (${ctx.widget.runtimeType})';
}

/// Carrega em Tab `n` vezes e devolve os elementos focados sem realce visível.
Future<Set<String>> _semRealceAoPercorrer(WidgetTester t, int n, {Set<String>? vistos}) async {
  final falhas = <String>{};
  await t.pump(); // o realce do foco inicial (autofocus) chega um frame depois
  for (var i = 0; i < n; i++) {
    final f = _semRealce();
    if (f != null && f != 'nada focado') falhas.add(f);
    vistos?.add(_focado());
    await _tecla(t, LogicalKeyboardKey.tab);
    await t.pump(); // o estado "focado" dos botões chega um frame depois
  }
  return falhas;
}

/// O realce como no comando da TV (nos testes o FocusManager começa em modo "toque").
void _realceTv() {
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
}

/// Verificador que espera até `soltar`.
class _Lento extends Verificador {
  final soltar = Completer<void>();
  @override
  Future<ResultadoVerificacao> verificarUmaVez(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso}) async {
    await soltar.future;
    return const ResultadoVerificacao(EstadoV.funciona, 'ok');
  }
}

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('foco');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
  });

  TelaGestor telaGestor({ServicoVerificacao? s, String? baseStb}) => baseStb == null
      ? TelaGestor(biblioteca: bib, area: area, servico: s ?? ServicoVerificacao(bib, colecao: area), tarefas: ServicoTarefas())
      : TelaGestor(
          biblioteca: bib,
          area: area,
          servico: s ?? ServicoVerificacao(bib, colecao: area),
          tarefas: ServicoTarefas(),
          baseStb: baseStb);

  /// Abre o sub-ecrã do passo com este nome (com um toque).
  Future<void> abrirPasso(WidgetTester t, String passo) async {
    await t.tap(find.descendant(of: find.byType(CartaoModerno), matching: find.text(passo)));
    await t.pumpAndSettle();
  }

  /// A app (a casca): Ver TV e, por omissão, o Gestor verdadeiro.
  Widget casca({Widget? gestor}) => TelaPrincipal(
        verTv: TelaInicio(biblioteca: bib, area: area),
        gestor: gestor ?? telaGestor(),
        definicoes: const SizedBox(),
      );

  /// Ver TV vazio: "Ir para o Gestor" (OK), o passo 1 do Gestor (OK) e a origem "Colar texto"
  /// (DIREITA e OK) abrem o painel de colar (só com o comando).
  Future<void> abrirAdicionar(WidgetTester t) async {
    await t.pumpWidget(_app(casca()));
    await t.pump();
    expect(_focado(), 'Ir para o Gestor');
    await _tecla(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(_focado(), startsWith('1 | Importar'));
    await _tecla(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(_focado(), startsWith('Ficheiros'));
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    await _tecla(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(_focado(), startsWith('Colar texto'));
  }
  tearDown(() async {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Future<Lista> comCache(WidgetTester t, ConteudoLista c) async {
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
      await bib.guardarCanais(bib.listas.single.id, c);
    });
    return bib.listas.single;
  }

  Future<void> mostrar(WidgetTester t, Lista l, {FutureOr<int?> Function(List<Canal>, int)? abrir}) async {
    await t.runAsync(() async {
      await t.pumpWidget(_app(TelaConteudo(biblioteca: bib, lista: l, abrir: abrir)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump();
  }

  final pequena = ConteudoLista(['Portugal', 'UK'], const [
    Canal(id: '1', nome: 'PT: RTP 1 HD', grupo: 'Portugal', url: 'u1'),
    Canal(id: '2', nome: 'PT: SIC', grupo: 'Portugal', url: 'u2'),
    Canal(id: '3', nome: 'BBC One', grupo: 'UK', url: 'u3'),
  ]);

  testWidgets('I6: Conteúdo começa com o foco no grupo; setas até um canal e OK abre-o', (t) async {
    _tamanho(t, 1200, 800);
    final l = await comCache(t, pequena);
    (List<Canal>, int)? aberto;
    await mostrar(t, l, abrir: (c, i) {
      aberto = (c, i);
      return null;
    });
    expect(_focado(), contains('Portugal'));
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    expect(_focado(), contains('PT: '), reason: 'a seta para a direita vai para os canais do grupo');
    // cima/baixo até ao 1.º canal e de volta ao 2.º
    for (var i = 0; i < 3 && !_focado().contains('PT: RTP 1 HD'); i++) {
      await _tecla(t, LogicalKeyboardKey.arrowUp);
    }
    expect(_focado(), contains('PT: RTP 1 HD'));
    await _tecla(t, LogicalKeyboardKey.arrowDown);
    expect(_focado(), contains('PT: SIC'));
    await _tecla(t, LogicalKeyboardKey.select);
    expect(aberto?.$2, 1);
  });

  testWidgets('I6: no telemóvel/TV estreita o foco começa no 1.º canal', (t) async {
    _tamanho(t, 500, 800);
    final l = await comCache(t, pequena);
    await mostrar(t, l);
    expect(_focado(), contains('PT: RTP 1 HD'));
  });

  testWidgets('I6: Voltar do player devolve o foco ao canal que estava a tocar (depois de zapping)', (t) async {
    _tamanho(t, 1200, 800);
    final l = await comCache(t, ConteudoLista(['G'], [
      for (var i = 0; i < 60; i++) Canal(id: '$i', nome: 'Canal $i', grupo: 'G', url: 'u$i'),
    ]));
    await mostrar(t, l, abrir: (c, i) async => 37); // o utilizador mudou para o canal 37
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    expect(_focado(), startsWith('Canal '));
    await _tecla(t, LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    expect(_focado(), contains('Canal 37'));
    expect(find.text('Canal 37').hitTestable(), findsOneWidget, reason: 'o canal fica visível');
  });

  testWidgets('I6: o campo de pesquisa não abre o teclado nem prende as setas; OK escreve', (t) async {
    _tamanho(t, 1200, 800);
    final l = await comCache(t, pequena);
    await mostrar(t, l);
    expect(_focado(), contains('Portugal'));
    // a pesquisa está no topo: CIMA no primeiro grupo vai direto ao campo
    await _tecla(t, LogicalKeyboardKey.arrowUp);
    expect(_focado(), contains('[campo'));
    expect(t.testTextInput.isVisible, isFalse, reason: 'o foco sozinho não abre o teclado no ecrã');
    // as setas saem do campo (não ficam presas)
    await _tecla(t, LogicalKeyboardKey.arrowDown);
    expect(_focado(), isNot(contains('[campo')));
    await _tecla(t, LogicalKeyboardKey.arrowUp);
    expect(_focado(), contains('[campo'));
    await _tecla(t, LogicalKeyboardKey.select);
    expect(t.testTextInput.isVisible, isTrue);
  });

  testWidgets('I6: Cancelar o carregamento (sem cache) deixa o foco em "Tentar de novo"', (t) async {
    _tamanho(t, 1200, 800);
    HttpOverrides.global = null;
    late ServerSocket calado;
    await t.runAsync(() async {
      calado = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      calado.listen((_) {}); // aceita e nunca responde
      await bib.adicionar([Importada(Conta('x', Tipo.m3u, 'http://127.0.0.1:${calado.port}/l.m3u'))]);
    });
    addTearDown(() => t.runAsync(calado.close));
    await t.pumpWidget(_app(TelaConteudo(biblioteca: bib, lista: bib.listas.single)));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(_focado(), contains('Cancelar'));
    await _tecla(t, LogicalKeyboardKey.select);
    expect(_focado(), contains('Tentar de novo'));
    await _tecla(t, LogicalKeyboardKey.select);
    expect(_focado(), contains('Cancelar'));
    await _fechar(t);
  });

  testWidgets('I6/Task 8: "Atualizar" abre o loader com o foco em "Cancelar"; Cancelar devolve o foco ao '
      '"Atualizar"', (t) async {
    _tamanho(t, 1200, 800);
    final l = await comCache(t, pequena);
    await mostrar(t, l);
    await _irPara(t, 'Atualizar');
    await _tecla(t, LogicalKeyboardKey.select);
    await t.pump();
    expect(_focado(), contains('Cancelar'));
    await _tecla(t, LogicalKeyboardKey.select);
    await t.pump();
    expect(_focado(), contains('Atualizar'));
    expect(find.text('PT: RTP 1 HD'), findsOneWidget, reason: 'os canais da cache continuam');
    await _fechar(t);
  });

  testWidgets('I6: Voltar do Conteúdo regressa ao Início com o cartão focado', (t) async {
    _tamanho(t, 1200, 800);
    await t.runAsync(() async {
      await bib.adicionar([
        Importada(contaDeLinha('http://a.com/l.m3u')!),
        Importada(contaDeLinha('http://b.com/l.m3u')!),
      ]);
      for (final l in bib.listas) {
        await bib.guardarCanais(l.id, pequena);
      }
    });
    await t.pumpWidget(_app(TelaInicio(biblioteca: bib)));
    await t.pump();
    expect(_focado(), contains('001A'));
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    expect(_focado(), contains('002B'));
    await t.runAsync(() async {
      await _tecla(t, LogicalKeyboardKey.select);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpAndSettle();
    expect(find.byType(TelaConteudo), findsOneWidget);
    await t.binding.handlePopRoute(); // Voltar do comando
    await t.pumpAndSettle();
    expect(find.byType(TelaConteudo), findsNothing);
    expect(_focado(), contains('002B'));
  });

  group('I6: Gestor', () {
    Future<(ServicoVerificacao, _Lento)> abrirVerificar(WidgetTester t) async {
      _tamanho(t, 1200, 1600);
      await t.runAsync(() => area.adicionar([Importada(contaDeLinha('http://x.com/c/ 00:1A:79:00:00:01')!)]));
      final f = _Lento();
      final s = ServicoVerificacao(bib, colecao: area, verificador: f, ritmo: RitmoHost(intervalo: Duration.zero));
      await t.pumpWidget(_app(Scaffold(body: telaGestor(s: s))));
      await t.pump();
      await abrirPasso(t, 'Verificar');
      return (s, f);
    }

    testWidgets('I6: "Verificar mais (fila)" é o primeiro foco; "Parar" devolve-lhe o foco', (t) async {
      final (s, f) = await abrirVerificar(t);
      expect(_focado(), contains('Verificar mais (fila)'));
      s.verificarVarias(area.listas);
      await t.pump();
      expect(s.ocupado, isTrue);
      expect(_focado(), contains('Verificar mais (fila)'));
      await _irPara(t, 'Parar');
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pump();
      expect(_focado(), contains('Verificar mais (fila)'));
      f.soltar.complete();
      for (var i = 0; i < 10 && s.ocupado; i++) {
        await t.pump();
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      }
      await t.pump();
      expect(s.ocupado, isFalse);
      expect(_focado(), contains('Verificar mais (fila)'));
    });

    testWidgets('I6: "Procurar e juntar" (stbstalker) mantém o foco e inicia a pesquisa em segundo plano', (t) async {
      HttpOverrides.global = null;
      late ServerSocket calado;
      final ligacoes = <Socket>[];
      await t.runAsync(() async {
        calado = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        calado.listen(ligacoes.add);
      });
      addTearDown(() => t.runAsync(() async {
            for (final c in ligacoes) {
              c.destroy();
            }
            await calado.close();
          }));
      _tamanho(t, 1200, 1600);
      await t.pumpWidget(_app(Scaffold(body: telaGestor(baseStb: 'http://127.0.0.1:${calado.port}/'))));
      await t.pump();
      await abrirPasso(t, 'Importar');
      await t.tap(find.text('Listas do stbstalker'));
      await t.pump();
      await _irPara(t, 'Procurar e juntar');
      await t.runAsync(() async {
        await _tecla(t, LogicalKeyboardKey.select);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(_focado(), contains('Procurar e juntar'));
      await _fechar(t);
    });
  });

  group('Tarefa C', () {
    // Android TV a 1080p: 960×540 lógicos (densidade 2)
    Future<void> inicioComGestor(WidgetTester t, {Widget? gestor}) async {
      _tamanho(t, 960, 540);
      await t.runAsync(() => bib.adicionar([
            Importada(contaDeLinha('http://a.com/l.m3u')!),
            Importada(contaDeLinha('http://b.com/l.m3u')!),
          ]));
      await t.pumpWidget(_app(casca(gestor: gestor ?? const Center(child: Text('ECRÃ GESTOR')))));
      await t.pump();
    }

    Widget gestorVerdadeiro() => telaGestor();

    testWidgets('T3: do 1.º cartão, ESQUERDA chega à barra e BAIXO+OK mostra o Gestor', (t) async {
      await inicioComGestor(t);
      expect(_focado(), contains('001A'));
      // CIMA a mais a partir dos cartões não passa da barra (fica na secção ativa)
      final caminho = <String>[];
      for (var i = 0; i < 6; i++) {
        await _tecla(t, LogicalKeyboardKey.arrowUp);
        caminho.add(_focado());
      }
      expect(_focado(), 'Ver TV', reason: 'CIMA a partir dos cartões: $caminho');
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      expect(_focado(), startsWith('[campo'), reason: 'DIREITA volta à pesquisa, de onde se subiu');
      for (var i = 0; i < 4 && !_focado().contains('001A'); i++) {
        await _tecla(t, LogicalKeyboardKey.arrowDown);
      }
      expect(_focado(), contains('001A'));
      // ESQUERDA no 1.º cartão: a secção ativa na barra
      await _tecla(t, LogicalKeyboardKey.arrowLeft);
      expect(_focado(), 'Ver TV');
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      expect(_focado(), 'Gestor');
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.text('ECRÃ GESTOR').hitTestable(), findsOneWidget);
      // e de volta a Ver TV com CIMA+OK
      await _tecla(t, LogicalKeyboardKey.arrowUp);
      expect(_focado(), 'Ver TV');
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.text('ECRÃ GESTOR').hitTestable(), findsNothing);
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      expect(_focado(), contains('001A'), reason: 'DIREITA volta ao cartão onde se estava');
    });

    testWidgets('T3: as secções cabem no telemóvel (em baixo) e as origens da importação no Gestor', (t) async {
      await inicioComGestor(t, gestor: gestorVerdadeiro());
      _tamanho(t, 360, 740);
      await t.pump();
      expect(t.takeException(), isNull);
      final nav = find.byType(NavigationBar);
      expect(find.descendant(of: nav, matching: find.text('Gestor')).hitTestable(), findsOneWidget);
      expect(find.text('Colar texto'), findsNothing, reason: 'Ver TV não adiciona');
      await t.tap(find.descendant(of: nav, matching: find.text('Gestor')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await abrirPasso(t, 'Importar');
      expect(t.takeException(), isNull);
      expect(find.text('Colar texto').hitTestable(), findsOneWidget);
    });

    testWidgets('T3: a importação continua alcançável no Gestor: o passo 1 é o 1.º controlo, à direita da '
        'barra, e OK nele leva às origens',
        (t) async {
      await inicioComGestor(t, gestor: gestorVerdadeiro());
      await _tecla(t, LogicalKeyboardKey.arrowLeft);
      expect(_focado(), 'Ver TV');
      // em Ver TV não há origens de importação: DIREITA volta ao cartão
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      expect(_focado(), contains('001A'));
      await _tecla(t, LogicalKeyboardKey.arrowLeft);
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      expect(_focado(), startsWith('1 | Importar'));
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(_focado(), startsWith('Ficheiros'));
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.text('Escolher ficheiros'), findsOneWidget);
    });

    testWidgets('T2: "Colar texto": o campo não abre o teclado com o foco, Voltar sai da '
        'edição e chega-se a "Juntar ao Gestor" só com setas e OK', (t) async {
      _tamanho(t, 960, 540);
      await abrirAdicionar(t);
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      expect(_focado(), contains('[campo'));
      expect(t.testTextInput.isVisible, isFalse, reason: 'o foco sozinho não abre o teclado no ecrã');
      // sem escrever, as setas saem do campo (e voltam)
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      expect(_focado(), 'Juntar ao Gestor');
      await _tecla(t, LogicalKeyboardKey.arrowUp);
      expect(_focado(), contains('[campo'));
      // OK escreve
      await _tecla(t, LogicalKeyboardKey.select);
      expect(t.testTextInput.isVisible, isTrue);
      t.testTextInput.enterText('http://x.com/l.m3u');
      await t.pump();
      // Voltar fecha o teclado (e não o diálogo); as setas voltam a mudar o foco
      // Voltar do comando (o simulador não tem tecla física para o goBack: usa-se a do Esc)
      await t.sendKeyEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.escape);
      await t.pump();
      expect(t.testTextInput.isVisible, isFalse);
      expect(find.text('Juntar ao Gestor'), findsOneWidget, reason: 'o painel continua aberto');
      expect(_focado(), contains('[campo http://x.com/l.m3u'));
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      expect(_focado(), 'Juntar ao Gestor');
      await t.runAsync(() async {
        await _tecla(t, LogicalKeyboardKey.select);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pumpAndSettle();
      expect(area.listas, hasLength(1));
      expect(bib.listas, isEmpty, reason: 'entra no Gestor, não no Player');
      expect(find.text('Novas no Gestor'), findsOneWidget);
      expect(find.text('Verificar a 1 nova'), findsOneWidget);
    });

    testWidgets('T2 (emulador): o Voltar do sistema a escrever acaba a edição sem sair do ecrã; '
        'depois as setas chegam a "Juntar ao Gestor" e OK importa', (t) async {
      _tamanho(t, 960, 540);
      await abrirAdicionar(t);
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      expect(_focado(), contains('[campo'));
      await _tecla(t, LogicalKeyboardKey.select);
      expect(t.testTextInput.isVisible, isTrue);
      t.testTextInput.enterText('http://x.com/l.m3u');
      await t.pump();
      // no Android TV o IME come a tecla BACK e o Flutter só recebe o "voltar" do sistema (popRoute)
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Juntar ao Gestor'), findsOneWidget, reason: 'o ecrã de importar continua aberto');
      expect(t.testTextInput.isVisible, isFalse);
      expect(_focado(), contains('[campo http://x.com/l.m3u'), reason: 'o texto fica');
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      expect(_focado(), 'Juntar ao Gestor');
      await t.runAsync(() async {
        await _tecla(t, LogicalKeyboardKey.select);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pumpAndSettle();
      expect(area.listas, hasLength(1));
    });

    testWidgets('T2: sem estar a escrever, o Voltar do sistema volta ao ecrã principal do Gestor', (t) async {
      _tamanho(t, 960, 540);
      await abrirAdicionar(t);
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      expect(_focado(), contains('[campo'));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Juntar ao Gestor'), findsNothing);
    });

    testWidgets('T1 (I1): no telemóvel/rato (modo toque) o foco automático não desenha a borda; '
        'com o comando desenha', (t) async {
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      Future<void> mostrarBotao(Widget w) async {
        await t.pumpWidget(_app(Scaffold(body: Center(child: w))));
        await t.pump();
        await t.pump();
      }

      for (final w in <Widget>[
        FilledButton(autofocus: true, onPressed: () {}, child: const Text('Cheio')),
        OutlinedButton(autofocus: true, onPressed: () {}, child: const Text('Contorno')),
        IconButton(autofocus: true, tooltip: 'Ícone', onPressed: () {}, icon: const Icon(Icons.add)),
        ChoiceChip(autofocus: true, label: const Text('Chip'), selected: false, onSelected: (_) {}),
      ]) {
        FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
        await mostrarBotao(w);
        expect(FocusManager.instance.primaryFocus?.context, isNotNull);
        expect(_semRealce(), isNotNull, reason: 'modo toque: ${w.runtimeType} sem borda');
        FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
        await t.pump();
        await t.pump();
        expect(_semRealce(), isNull, reason: 'modo comando: ${w.runtimeType} com borda');
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('T1: no Android TV o realce do foco fica sempre ligado (mesmo depois de um toque)', (t) async {
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      await configurarRealceFoco(eTv: () async => true);
      expect(FocusManager.instance.highlightStrategy, FocusHighlightStrategy.alwaysTraditional);
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
      await configurarRealceFoco(eTv: () async => false);
      expect(FocusManager.instance.highlightStrategy, FocusHighlightStrategy.automatic);
      await configurarRealceFoco(eTv: () async => throw Exception('sem canal'));
      expect(FocusManager.instance.highlightStrategy, FocusHighlightStrategy.automatic);
    });

    testWidgets('T1: Início — tudo o que tem foco tem realce; o cartão focado cresce', (t) async {
      _realceTv();
      _tamanho(t, 1920, 1080);
      await t.runAsync(() => bib.adicionar([
            Importada(contaDeLinha('http://a.com/c/ 00:1A:79:00:00:01')!),
            Importada(contaDeLinha('http://b.com/l.m3u')!),
          ]));
      await t.runAsync(() => area.adicionar([Importada(contaDeLinha('http://g.com/l.m3u')!)]));
      final s = ServicoVerificacao(bib, colecao: area);
      await t.pumpWidget(_app(casca(gestor: telaGestor(s: s))));
      await t.pump();
      expect(_focado(), contains('001A'));
      expect(_semRealce(), isNull);
      var escala = 1.0;
      (FocusManager.instance.primaryFocus!.context! as Element).visitAncestorElements((e) {
        final w = e.widget;
        if (w is AnimatedScale) escala = w.scale;
        return w is! GridView;
      });
      expect(escala, greaterThan(1), reason: 'o cartão focado aumenta um pouco');
      final vistos = <String>{};
      final falhas = await _semRealceAoPercorrer(t, 30, vistos: vistos);
      expect(falhas, isEmpty);
      for (final v in ['Ver TV', 'Gestor', 'Definições', 'Todas', '[campo ]']) {
        expect(vistos, isNot(contains('Mais opções')), reason: 'o menu é só com pressão longa');
        expect(vistos, contains(v), reason: 'percorreu: $vistos');
      }
      // o Player não gere nada
      expect(vistos, isNot(contains('Adicionar listas')));
      expect(vistos.where((v) => v.contains('Verificar')), isEmpty, reason: '$vistos');
      // o Gestor: os passos e a barra das selecionadas; nos sub-ecrãs, "Adicionar listas" e "Verificar mais (fila)"
      await t.tap(find.text('Gestor'));
      await t.pumpAndSettle();
      final noGestor = <String>{};
      expect(await _semRealceAoPercorrer(t, 40, vistos: noGestor), isEmpty);
      expect(noGestor.join(' / '), allOf(contains('Importar'), contains('Enviar ou exportar'),
          contains('Verificar (entra na fila)'), contains('Enviar para o Player'), contains('Remover')));
      await abrirPasso(t, 'Importar');
      expect(await _semRealceAoPercorrer(t, 8, vistos: noGestor), isEmpty);
      await t.tap(find.widgetWithText(TextButton, 'Voltar'));
      await t.pumpAndSettle();
      await abrirPasso(t, 'Verificar');
      expect(await _semRealceAoPercorrer(t, 4, vistos: noGestor), isEmpty);
      expect(noGestor.join(' / '), allOf(contains('Ficheiros'), contains('Escolher ficheiros'),
          contains('Limpar o Gestor'), contains('Verificar mais (fila)')));
    });

    testWidgets('T1: Conteúdo — grupos, canais, pesquisa e Atualizar com realce (a estrela não é paragem)',
        (t) async {
      _realceTv();
      _tamanho(t, 1200, 800);
      final l = await comCache(t, pequena);
      await mostrar(t, l);
      final vistos = <String>{};
      final falhas = await _semRealceAoPercorrer(t, 14, vistos: vistos);
      expect(falhas, isEmpty);
      expect(vistos, containsAll(['Portugal | 2', 'PT: RTP 1 HD', 'Atualizar a lista de canais']), reason: '$vistos');
      expect(vistos, isNot(contains('Pôr nos favoritos')));
    });

    testWidgets('T1: Conteúdo estreito — os grupos em chips têm realce', (t) async {
      _realceTv();
      _tamanho(t, 500, 800);
      final l = await comCache(t, pequena);
      await mostrar(t, l);
      final vistos = <String>{};
      final falhas = await _semRealceAoPercorrer(t, 12, vistos: vistos);
      expect(falhas, isEmpty);
      expect(vistos, contains('UK'), reason: '$vistos');
    });

    testWidgets('T1: Gestor — botões, chips, caixas e formato com realce', (t) async {
      _realceTv();
      _tamanho(t, 1200, 1600);
      await t.runAsync(() => area.adicionar([Importada(contaDeLinha('http://x.com/c/ 00:1A:79:00:00:01')!)]));
      await t.pumpWidget(_app(Scaffold(body: telaGestor())));
      await t.pump();
      final vistos = <String>{};
      // o principal: passos, marcar, a barra das selecionadas, filtros e as linhas
      final falhas = await _semRealceAoPercorrer(t, 20, vistos: vistos);
      expect(falhas, isEmpty);
      expect(vistos.join(' / '), allOf(contains('Verificar (entra na fila)'), contains('Todas'), contains('001X'),
          contains('Enviar para o Player'), contains('Exportar'), contains('Remover')));
      // os sub-ecrãs
      await abrirPasso(t, 'Importar');
      expect(await _semRealceAoPercorrer(t, 8, vistos: vistos), isEmpty);
      await t.tap(find.widgetWithText(TextButton, 'Voltar'));
      await t.pumpAndSettle();
      await abrirPasso(t, 'Verificar');
      expect(await _semRealceAoPercorrer(t, 4, vistos: vistos), isEmpty);
      await t.tap(find.widgetWithText(TextButton, 'Voltar'));
      await t.pumpAndSettle();
      // o formato da exportação (as opções do diálogo)
      await t.tap(find.widgetWithText(ActionChip, 'Todas'));
      await t.pump();
      await t.tap(find.widgetWithText(OutlinedButton, 'Exportar'));
      await t.pumpAndSettle();
      expect(await _semRealceAoPercorrer(t, 3, vistos: vistos), isEmpty);
      expect(vistos.join(' / '), allOf(contains('Escolher ficheiros'), contains('Verificar mais (fila)'),
          contains('Accounts.json'), contains('Ficheiros .ini')));
      expect(vistos.join(' / '), allOf(contains('Colar texto'), contains('Limpar o Gestor')));
    });

    testWidgets('T1: ecrã de importar — origens, painel e campo com realce', (t) async {
      _realceTv();
      _tamanho(t, 960, 540);
      await t.pumpWidget(_app(casca()));
      await t.pump();
      await t.pump();
      expect(_semRealce(), isNull, reason: '"Ir para o Gestor" com realce');
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(_focado(), startsWith('1 | Importar'));
      expect(_semRealce(), isNull, reason: 'o passo 1 com realce');
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(_focado(), startsWith('Ficheiros'));
      expect(_semRealce(), isNull, reason: 'a origem "Ficheiros" com realce');
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      await _tecla(t, LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      final vistos = <String>{};
      final falhas = await _semRealceAoPercorrer(t, 5, vistos: vistos);
      expect(falhas, isEmpty);
      expect(vistos.join(' / '), allOf(contains('Colar texto'), contains('[campo'), contains('Juntar ao Gestor')));
    });

    testWidgets('D1: DIREITA do 1.º cartão foca o 2.º cartão e só há um realce; o cartão é uma só '
        'paragem (sem botões de dentro)', (t) async {
      // como no emulador da Android TV: 960×540 lógicos e tamanhos de TV
      _realceTv();
      _tamanho(t, 960, 540);
      EcraTv.nativo = true;
      addTearDown(() => EcraTv.nativo = false);
      await t.runAsync(() => bib.adicionar([
            Importada(contaDeLinha('http://a.com/l.m3u')!),
            Importada(contaDeLinha('http://b.com/l.m3u')!),
          ]));
      await t.pumpWidget(_app(TelaInicio(biblioteca: bib)));
      await t.pump();
      await t.pump();
      int realces() => find
          .byWidgetPredicate((w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).border == Border.fromBorderSide(Realce.borda))
          .evaluate()
          .length;
      // o cartão inteiro tem o foco: os textos de dentro (nome, estado...) são todos do foco
      bool cartaoFocado(String nome) => _textosFocados().length > 1 && _focado().contains(nome);
      expect(cartaoFocado('001A'), isTrue, reason: _focado());
      expect(realces(), 1);
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(cartaoFocado('002B'), isTrue, reason: 'foco em: ${_focado()}');
      expect(realces(), 1, reason: 'um só realce visível');
      // sem linha por baixo, BAIXO não entra em nada de dentro: o foco fica no cartão
      await _tecla(t, LogicalKeyboardKey.arrowDown);
      await t.pump();
      expect(cartaoFocado('002B'), isTrue, reason: 'foco em: ${_focado()}');
      await _tecla(t, LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(cartaoFocado('001A'), isTrue, reason: 'foco em: ${_focado()}');
      expect(realces(), 1);
    });
  });
}
