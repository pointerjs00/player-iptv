import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/inicio/acoes_lista.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';
import 'package:player_iptv/ui/tema.dart';

/// Task 8: o menu de ações dos cartões do Player.

Widget _app(Widget w) =>
    MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

void _tamanho(WidgetTester t, double l, double a) {
  t.view.physicalSize = Size(l, a);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

String _focado() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return '';
  final textos = <String>[];
  void visitar(Element e) {
    if (e.widget is Text) textos.add((e.widget as Text).data ?? '');
    e.visitChildren(visitar);
  }

  (ctx as Element).visitChildren(visitar);
  if (textos.isEmpty) textos.add(ctx.findAncestorWidgetOfExactType<Tooltip>()?.message ?? '');
  return textos.join(' | ');
}

const _acoes = ['Atualizar canais', 'Verificar agora', 'Editar lista', 'Copiar link', 'Enviar para o Gestor', 'Remover lista'];

/// Verificador que responde logo (sem rede).
class _Falso extends Verificador {
  _Falso() : super(pausaReteste: Duration.zero);

  @override
  Future<ResultadoVerificacao> verificarUmaVez(Conta conta, List<String> canaisTeste,
          {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso}) async =>
      const ResultadoVerificacao(EstadoV.funciona, 'ok', validade: '2030-01-01');
}

/// Como `testWidgets`, no Windows (o `Copiar link` só existe aí); o valor volta a null no fim
/// (a verificação das variáveis de debug corre antes dos tearDown).
void testWidgetsWin(String nome, Future<void> Function(WidgetTester) corpo,
        {TargetPlatform plataforma = TargetPlatform.windows}) =>
    testWidgets(nome, (t) async {
      debugDefaultTargetPlatformOverride = plataforma;
      try {
        await corpo(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;
  final pedidos = <Conta>[];
  late ServicoVerificacao servico;

  Future<ConteudoLista> abrirFalso(Conta c, {Cancelamento? cancelamento, Aviso? aviso}) async {
    pedidos.add(c);
    return ConteudoLista(['G'], const [Canal(id: '1', nome: 'Canal novo', grupo: 'G', url: 'u')]);
  }

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('menu');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(Directory('${pasta.path}${Platform.pathSeparator}g'));
    pedidos.clear();
    servico = ServicoVerificacao(bib, verificador: _Falso());
  });
  tearDown(() async {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Future<void> montar(WidgetTester t) async {
    _tamanho(t, 1200, 800);
    await t.runAsync(() => bib.adicionar([
          Importada(Conta('', Tipo.xtream, 'http://srv.com:8080', utilizador: 'joao', password: 'segredo'),
              UltimaVerificacao(estado: 'funciona', data: DateTime.now(), validade: '2027-10-16')),
          Importada(contaDeLinha('http://b.com/l.m3u')!),
        ]));
    await t.pumpWidget(_app(TelaInicio(
        biblioteca: bib, area: area, servico: servico, abrirLista: abrirFalso)));
    await t.pump();
  }

  /// IO real (disco) com pumps pelo meio, até `feito` (ou ~2 s).
  Future<void> esperar(WidgetTester t, bool Function() feito) async {
    for (var i = 0; i < 40 && !feito(); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50)); // as animações também andam
    }
  }

  void verMenu() {
    for (final a in _acoes) {
      // "Copiar link" só no Windows (a plataforma do teste, não a do computador)
      final esperado = a != 'Copiar link' || defaultTargetPlatform == TargetPlatform.windows;
      expect(find.widgetWithText(ListTile, a), esperado ? findsOneWidget : findsNothing, reason: a);
    }
    expect(find.text('Verificar de novo'), findsNothing);
  }

  Future<void> fecharMenu(WidgetTester t) async {
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Atualizar canais'), findsNothing);
  }

  testWidgetsWin('toque longo e clique direito abrem o mesmo menu (sem "Verificar de novo" nem "Mais opções")',
      (t) async {
    await montar(t);
    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    verMenu();
    await fecharMenu(t);
    await t.tap(find.text('001SRV 161027'), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await t.pumpAndSettle();
    verMenu();
    await fecharMenu(t);
    expect(find.byTooltip('Mais opções'), findsNothing);
  });

  testWidgetsWin('OK mantido no cartão abre o menu; setas escolhem; Voltar devolve o foco ao cartão', (t) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await montar(t);
    expect(_focado(), contains('001SRV'));
    await t.sendKeyDownEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 50));
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    }
    await t.pumpAndSettle();
    verMenu();
    expect(_focado(), startsWith('Atualizar canais'), reason: 'o foco começa na 1.ª ação');
    // as repetições e o soltar do OK que abriu o menu não escolhem nada
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await t.sendKeyUpEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    verMenu();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(_focado(), startsWith('Verificar agora'));
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(_focado(), contains('001SRV'));
    // um OK curto continua a abrir a lista
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(TelaConteudo), findsOneWidget);
  }, plataforma: TargetPlatform.android);

  testWidgetsWin('o menu tem as 6 ações pela ordem, cada uma com a sua explicação', (t) async {
    await montar(t);
    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    final tops = [for (final a in _acoes) t.getTopLeft(find.text(a)).dy];
    expect(tops, orderedEquals([...tops]..sort()));
    for (final e in [
      'Pede a lista de canais outra vez ao servidor',
      'Testa 3 canais · cerca de 20 s',
      'Nome, endereço, MAC ou utilizador',
      'Só no Windows · leva os dados de acesso',
      'Para verificar ou exportar com as outras',
      'Pede confirmação · os favoritos desta lista saem',
    ]) {
      expect(find.text(e), findsOneWidget, reason: e);
    }
  });

  testWidgetsWin('em Android o menu não tem "Copiar link"; em Windows tem', (t) async {
    final lista = Lista(
        id: 'x', ordem: 1, conta: Conta('', Tipo.m3u, 'http://b.com/l.m3u'));
    Future<void> abrir(TargetPlatform plataforma) async {
      debugDefaultTargetPlatformOverride = plataforma;
      await t.pumpWidget(_app(Builder(
          builder: (c) => TextButton(
              onPressed: () => mostrarMenuLista(c, lista), child: const Text('menu')))));
      await t.tap(find.text('menu'));
      await t.pumpAndSettle();
    }

    await abrir(TargetPlatform.android);
    expect(find.text('Copiar link'), findsNothing);
    expect(find.text('Verificar agora'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await abrir(TargetPlatform.windows);
    expect(find.text('Copiar link'), findsOneWidget);
  });

  testWidgetsWin('Atualizar canais: mensagem de progresso, depois de fim, sem sair do Início', (t) async {
    await montar(t);
    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Atualizar canais'));
    await t.pump();
    expect(find.byType(TelaConteudo), findsNothing, reason: 'a navegação não é bloqueada');
    final fim = find.textContaining('atualizados');
    await esperar(t, () => fim.evaluate().isNotEmpty);
    expect(fim, findsOneWidget);
    expect(pedidos, hasLength(1));
    expect(find.byType(TelaConteudo), findsNothing);
    await t.pump(const Duration(seconds: 10));
    await t.pumpAndSettle();
  });

  testWidgetsWin('Verificar agora: o estado da lista muda no Início e aparece a mensagem de fim', (t) async {
    await montar(t);
    await t.longPress(find.text('002B'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Verificar agora'));
    await t.pump();
    final fim = find.textContaining(': Funciona');
    await esperar(t, () => fim.evaluate().isNotEmpty);
    expect(fim, findsOneWidget);
    expect(bib.listas.last.ultima?.estado, 'funciona');
    expect(find.byType(TelaConteudo), findsNothing);
    await t.pump(const Duration(seconds: 10));
    await t.pumpAndSettle();
  });

  testWidgetsWin('Editar: nome próprio e password mudam e persistem; endereço inválido não guarda', (t) async {
    await montar(t);
    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Editar lista'));
    await t.pumpAndSettle();
    expect(find.text('Editar lista'), findsOneWidget);
    // a password não se vê
    expect(
        t.widget<EditableText>(find.descendant(
            of: find.byKey(const Key('editar-password')), matching: find.byType(EditableText))).obscureText,
        isTrue);

    Future<void> escrever(String campo, String texto) async {
      final f = find.byKey(Key('editar-$campo'));
      await t.tap(f);
      await t.pump();
      await t.enterText(find.descendant(of: f, matching: find.byType(EditableText)), texto);
    }

    await escrever('endereco', 'srv.com');
    await t.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await t.pumpAndSettle();
    expect(find.textContaining('http://'), findsWidgets, reason: 'erro do endereço');
    expect(bib.listas.first.conta.endereco, 'http://srv.com:8080');

    await escrever('endereco', 'http://srv.com:8080');
    await escrever('nome', 'Sala');
    await escrever('password', 'nova');
    await t.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await t.pump();
    await esperar(t, () => find.text('Editar lista').evaluate().isEmpty);
    await t.pumpAndSettle();
    expect(find.text('Editar lista'), findsNothing);
    expect(find.text('Sala'), findsOneWidget);
    expect(bib.listas.first.conta.password, 'nova');
    final relida = await t.runAsync(() => Biblioteca.abrir(pasta));
    expect(relida!.listas.first.nome, 'Sala');
    expect(relida.listas.first.conta.password, 'nova');
  });

  testWidgetsWin('Copiar link: vai para a área de transferência sem aparecer no ecrã', (t) async {
    String? copiado;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'Clipboard.setData') copiado = (c.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await montar(t);
    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Copiar link'));
    await t.pumpAndSettle();
    expect(copiado, startsWith('http://srv.com:8080/get.php?username=joao&password=segredo'));
    expect(find.text('Link copiado'), findsOneWidget);
    expect(find.textContaining('segredo'), findsNothing);
    expect(find.textContaining('get.php'), findsNothing);
  });

  testWidgetsWin('Enviar para o Gestor: copia a conta e o último resultado, sem duplicar', (t) async {
    await montar(t);
    for (var vez = 0; vez < 2; vez++) {
      await t.longPress(find.text('001SRV 161027'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ListTile, 'Enviar para o Gestor'));
      await t.pump();
      final aviso = find.text(vez == 0 ? 'Enviada para o Gestor' : 'Já estava no Gestor');
      await esperar(t, () => aviso.evaluate().isNotEmpty);
      expect(aviso, findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      await t.pumpAndSettle();
    }
    expect(area.listas, hasLength(1));
    expect(area.listas.single.conta.utilizador, 'joao');
    expect(area.listas.single.ultima!.estado, 'funciona');
  });

  testWidgetsWin('Remover lista pede confirmação; Cancelar não apaga; Remover apaga e o foco fica num cartão',
      (t) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await montar(t);
    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Remover lista'));
    await t.pumpAndSettle();
    expect(find.text('Remover lista?'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(bib.listas, hasLength(2));

    await t.longPress(find.text('001SRV 161027'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Remover lista'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Remover'));
    await t.pump();
    await esperar(t, () => find.text('001SRV 161027').evaluate().isEmpty);
    await t.pumpAndSettle();
    expect(bib.listas, hasLength(1));
    expect(find.text('001SRV 161027'), findsNothing);
    expect(_focado(), contains('002B'));
  });
}
