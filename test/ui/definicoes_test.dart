import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/copia_seguranca.dart';
import 'package:player_iptv/dados/guardar_ficheiro.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/definicoes/linha_opcao.dart';
import 'package:player_iptv/ui/definicoes/tela_definicoes.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/protocolos/protocolo.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';

Widget _app(Widget w) => MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

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
  return textos.join(' | ');
}

/// O foco está dentro do widget que o [finder] encontra?
bool _focoEm(WidgetTester t, Finder finder) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null || finder.evaluate().isEmpty) return false;
  final alvo = t.element(finder.first);
  var dentro = false;
  ctx.visitAncestorElements((a) {
    if (a == alvo) dentro = true;
    return !dentro;
  });
  return dentro;
}

/// O chip `rotulo` da linha `linha` (há "Desligado" em mais de uma linha).
Finder _chip(String linha, String rotulo) => find.descendant(
    of: find.widgetWithText(LinhaOpcao, linha), matching: find.widgetWithText(ChoiceChip, rotulo));

/// Fica preso até ao fim do teste: o serviço continua ocupado.
class _Preso extends Verificador {
  final _nunca = Completer<void>();

  @override
  Future<ResultadoVerificacao> verificarComLimite(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso, Duration? limite}) async {
    await _nunca.future;
    return const ResultadoVerificacao(EstadoV.funciona, 'ok');
  }
}

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;
  late Preferencias prefs;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('defs');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
    prefs = await Preferencias.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Future<void> abrir(WidgetTester t,
      {EscolherCopia? escolher, Future<ResultadoGuardar> Function(String, List<int>)? guardar}) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(TelaDefinicoes(
        biblioteca: bib, area: area, preferencias: prefs, escolherCopia: escolher, guardarCopia: guardar)));
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> categoria(WidgetTester t, String nome) async {
    await t.tap(find.text(nome));
    await t.pump();
  }

  testWidgets('as 5 categorias existem e cada opção está numa delas', (t) async {
    await abrir(t);
    for (final s in ['Imagem e som', 'Verificação', 'Ligação', 'Cópia de segurança', 'Sobre e licenças']) {
      expect(find.text(s), findsOneWidget);
    }
    final opcoes = {
      'Imagem e som': ['Desentrelaçamento', 'Descodificação por hardware', 'Formato da imagem', 'Volume ao abrir'],
      'Verificação': ['Listas ao mesmo tempo', 'Tempo limite por lista', 'Tempo por canal', 'Canais de teste'],
      'Ligação': ['User-agent'],
      'Cópia de segurança': ['Exportar cópia', 'Importar cópia'],
      'Sobre e licenças': ['Ver licenças'],
    };
    for (final e in opcoes.entries) {
      await categoria(t, e.key);
      for (final o in e.value) {
        expect(find.text(o), findsOneWidget, reason: '${e.key}: $o');
      }
    }
  });

  testWidgets('Imagem e som: explica cada opção e a taxa do ecrã só aparece no Android', (t) async {
    await abrir(t);
    expect(find.text('Evita riscas nos canais entrelaçados. Automático só o liga quando é preciso.'), findsOneWidget);
    expect(find.text('Mais leve. Desliga se a imagem falhar.'), findsOneWidget);
    expect(find.text('Vale para todos os canais'), findsOneWidget);
    expect(find.text('Ajustar a taxa do ecrã ao canal'), findsNothing);
    for (final m in ['Automático', 'Ligado', 'Desligado']) {
      expect(_chip('Desentrelaçamento', m), findsOneWidget);
    }
    await t.pumpWidget(_app(TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs, android: true)));
    await t.pump();
    expect(find.text('Ajustar a taxa do ecrã ao canal'), findsOneWidget);
    expect(find.text('Evita soluços nas imagens (Android TV)'), findsOneWidget);
  });

  testWidgets('Android: "Motor do player" (ExoPlayer / mpv) e "Modo túnel"; no Windows não aparecem', (t) async {
    await abrir(t);
    expect(find.text('Motor do player'), findsNothing);
    expect(find.text('Modo túnel'), findsNothing);
    await t.pumpWidget(_app(TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs, android: true)));
    await t.pump();
    expect(find.text('Motor do player'), findsOneWidget);
    expect(find.text('Modo túnel'), findsOneWidget);
    expect(find.text('Só em aparelhos que o suportam. Pode ajudar a fluidez; se a imagem falhar, desliga.'),
        findsOneWidget);
    final exo = t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'ExoPlayer'));
    expect(exo.selected, isTrue, reason: 'o ExoPlayer é a omissão');
    expect(t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Modo túnel')).value, isFalse);
    await t.tap(find.widgetWithText(SwitchListTile, 'Modo túnel'));
    await t.pump();
    expect(prefs.modoTunel, isTrue);
    await t.tap(find.widgetWithText(ChoiceChip, 'mpv'));
    await t.pump();
    expect(prefs.motorAndroid, MotorAndroid.mpv);
    expect(find.text('Guardado · vale a partir do próximo canal'), findsOneWidget);
  });

  testWidgets('Android com o ExoPlayer: as opções só do mpv ficam desativadas, com "só no motor mpv"', (t) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs, android: true)));
    await t.pump();
    expect(find.text('só no motor mpv'), findsNWidgets(3));
    for (final m in ['Automático', 'Ligado', 'Desligado']) {
      expect(t.widget<ChoiceChip>(_chip('Desentrelaçamento', m)).onSelected, isNull, reason: m);
    }
    for (final m in ['Direta (recomendada)', 'Compatível']) {
      expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, m)).onSelected, isNull, reason: m);
    }
    expect(t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Descodificação por hardware')).onChanged,
        isNull);
    await t.tap(_chip('Desentrelaçamento', 'Desligado'));
    await t.pump();
    expect(prefs.modoDesentrelacamento, ModoDesentrelacamento.automatico, reason: 'desativada: não muda');
    // com o mpv voltam a estar ativas
    await t.tap(find.widgetWithText(ChoiceChip, 'mpv'));
    await t.pump();
    expect(find.text('só no motor mpv'), findsNothing);
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Compatível')).onSelected, isNotNull);
    expect(t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Descodificação por hardware')).onChanged,
        isNotNull);
  });

  testWidgets('Imagem e som: «Recuar no direto» e «Espaço reservado» (só com Armazenamento), em linhas', (t) async {
    await abrir(t);
    expect(find.widgetWithText(LinhaOpcao, 'Recuar no direto'), findsOneWidget);
    expect(find.text('Grava o canal para poderes recuar e pausar. Apagado ao mudar de canal.'), findsOneWidget);
    expect(find.widgetWithText(LinhaOpcao, 'Espaço reservado'), findsOneWidget);
    expect(find.text('Quanto do armazenamento interno se usa, no máximo.'), findsOneWidget);
    for (final r in ['Armazenamento', 'Memória', 'Desligado']) {
      expect(_chip('Recuar no direto', r), findsOneWidget, reason: r);
    }
    expect(t.widget<ChoiceChip>(_chip('Recuar no direto', 'Armazenamento')).selected, isTrue, reason: 'a omissão');
    for (final g in ['1 GB', '2 GB', '3 GB']) {
      expect(_chip('Espaço reservado', g), findsOneWidget, reason: g);
    }
    expect(t.widget<ChoiceChip>(_chip('Espaço reservado', '2 GB')).selected, isTrue, reason: 'a omissão');
    await t.tap(_chip('Espaço reservado', '3 GB'));
    await t.pump();
    expect(prefs.reservaDiretoGb, 3);
    expect(find.text('Guardado · vale a partir do próximo canal'), findsOneWidget);
    // Memória e Desligado não gravam: o espaço reservado sai
    await t.tap(_chip('Recuar no direto', 'Memória'));
    await t.pump();
    expect(prefs.recuoDireto, RecuoDireto.memoria);
    expect(find.text('Espaço reservado'), findsNothing);
    await t.tap(_chip('Recuar no direto', 'Desligado'));
    await t.pump();
    expect(prefs.recuoDireto, RecuoDireto.desligado);
    expect(find.text('Espaço reservado'), findsNothing);
    await t.tap(_chip('Recuar no direto', 'Armazenamento'));
    await t.pump();
    expect(find.text('Espaço reservado'), findsOneWidget);
    expect((prefs.recuoDireto, prefs.reservaDiretoGb), (RecuoDireto.armazenamento, 3));
  });

  testWidgets('mudar uma opção confirma: "Guardado" (e, no player, que vale a partir do próximo canal)', (t) async {
    await abrir(t);
    await t.tap(_chip('Desentrelaçamento', 'Desligado'));
    await t.pump();
    expect(prefs.modoDesentrelacamento, ModoDesentrelacamento.desligado);
    expect(find.text('Guardado · vale a partir do próximo canal'), findsOneWidget);
    await categoria(t, 'Verificação');
    await t.tap(find.text('DAZN 1'));
    await t.pump();
    expect(find.text('Guardado'), findsOneWidget, reason: 'fora do player: só "Guardado"');
    expect(bib.canaisTeste, containsAll(['rtp1', 'dazn1']));
    await categoria(t, 'Ligação');
    await t.enterText(find.byType(TextField), 'X/1');
    await t.pump();
    expect(find.text('Guardado'), findsOneWidget);
  });

  /// Só com o comando: TAB na primeira categoria e DIREITA para a primeira opção, o
  /// desentrelaçamento ("Automático"): no telemóvel o tamanho da interface não aparece.
  Future<void> entrarNasOpcoes(WidgetTester t) async {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(_focado(), 'Imagem e som');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(_focoEm(t, find.widgetWithText(ChoiceChip, 'Automático')), isTrue);
  }

  testWidgets('mudar uma opção não tira o foco do sítio', (t) async {
    await abrir(t);
    await entrarNasOpcoes(t);
    for (var i = 0; i < 2; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
    }
    await t.sendKeyEvent(LogicalKeyboardKey.select); // Desligado
    await t.pump();
    expect(prefs.modoDesentrelacamento, ModoDesentrelacamento.desligado);
    expect(find.text('Guardado · vale a partir do próximo canal'), findsOneWidget);
    expect(_focoEm(t, _chip('Desentrelaçamento', 'Desligado')), isTrue);
  });

  testWidgets('no telemóvel: uma lista de categorias e cada uma abre a sua página', (t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs)));
    await t.pump();
    for (final s in ['Imagem e som', 'Verificação', 'Ligação', 'Cópia de segurança', 'Sobre e licenças']) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text('Desentrelaçamento'), findsNothing);
    await t.tap(find.text('Verificação'));
    await t.pump();
    expect(find.text('Listas ao mesmo tempo'), findsOneWidget);
    expect(find.text('Verificação'), findsOneWidget, reason: 'o título da página');
    expect(find.text('Imagem e som'), findsNothing);
    await t.tap(find.byTooltip('Voltar'));
    await t.pump();
    expect(find.text('Listas ao mesmo tempo'), findsNothing);
    expect(find.text('Imagem e som'), findsOneWidget);
  });

  testWidgets('D-pad: ESQUERDA da opção vai à categoria e DIREITA volta à opção', (t) async {
    await abrir(t);
    await entrarNasOpcoes(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight); // "Ligado"
    await t.pump();
    expect(_focoEm(t, find.widgetWithText(ChoiceChip, 'Ligado')), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // volta ao "Automático"
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // o primeiro: sai para a categoria
    await t.pump();
    expect(_focado(), 'Imagem e som');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(_focoEm(t, find.widgetWithText(ChoiceChip, 'Automático')), isTrue, reason: 'volta à opção de onde saiu');
    // um interruptor (o cartão todo): ESQUERDA também vai à categoria
    for (var i = 0; i < 3 && !_focado().contains('Descodificação por hardware'); i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
    }
    expect(_focado(), contains('Descodificação por hardware'));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    expect(_focado(), 'Imagem e som');
  });

  testWidgets('o tempo limite muda com as setas e fica gravado', (t) async {
    await abrir(t);
    await categoria(t, 'Verificação');
    expect(find.text('8 s'), findsOneWidget);
    await t.tap(find.text('+').last);
    await t.pump();
    final v = prefs.timeoutVerificacao;
    expect(v, 9);
    // a gravação é IO real com continuações na zona do teste: alterna-se entre as duas
    for (var i = 0; i < 25; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump();
    }
    final m = jsonDecode(File('${pasta.path}${Platform.pathSeparator}preferencias.json').readAsStringSync()) as Map;
    expect(m['timeoutVerificacao'], v);
  });

  testWidgets('durante uma verificação os canais e o tempo limite mudam e dizem que valem para as próximas',
      (t) async {
    await t.runAsync(() => area.adicionar([Importada(contaDeLinha('http://a.com/c/ 00:1A:79:00:00:01')!)]));
    final s = ServicoVerificacao(bib, colecao: area, verificador: _Preso());
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
        _app(TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs, servico: s)));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Verificação'));
    await t.pump();
    // com a verificação a decorrer (o verificador fica preso: o serviço está ocupado)
    s.verificar(area.listas.first);
    await t.pump();
    expect(find.textContaining('Não se mudam'), findsNothing);
    await t.tap(find.text('DAZN 1'));
    await t.pump();
    expect(bib.canaisTeste, contains('dazn1'));
    final antes = prefs.timeoutVerificacao;
    await t.tap(find.text('+').last);
    await t.pump();
    expect(prefs.timeoutVerificacao, isNot(antes));
  });

  testWidgets('o user-agent escrito fica nas preferências', (t) async {
    await abrir(t);
    await categoria(t, 'Ligação');
    await t.ensureVisible(find.byType(TextField));
    await t.tap(find.byType(TextField));
    await t.pump();
    await t.enterText(find.byType(TextField), 'MeuPlayer/3');
    expect(prefs.userAgent, 'MeuPlayer/3');
  });

  testWidgets('exportar guarda um .json com a biblioteca', (t) async {
    await t.runAsync(() => bib.adicionar([Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!)]));
    String? nome;
    String? texto;
    await abrir(t, guardar: (n, b) async {
      nome = n;
      texto = utf8.decode(b);
      return const ResultadoGuardar('Transferências/x.json');
    });
    await categoria(t, 'Cópia de segurança');
    await t.ensureVisible(find.text('Exportar cópia'));
    await t.tap(find.text('Exportar cópia'));
    await t.pump();
    expect(nome, endsWith('.json'));
    expect(texto, contains('nxtbox.uk'));
    expect(find.textContaining('Cópia guardada em Transferências/x.json'), findsOneWidget);
  });

  testWidgets('importar um ficheiro inválido mostra o erro e não muda nada', (t) async {
    await t.runAsync(() => bib.adicionar([Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!)]));
    await abrir(t, escolher: () async => 'isto não é uma cópia');
    await categoria(t, 'Cópia de segurança');
    await t.ensureVisible(find.text('Importar cópia'));
    await t.tap(find.text('Importar cópia'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('Nada foi alterado'), findsOneWidget);
    expect(bib.listas, hasLength(1));
  });

  testWidgets('importar pede confirmação e Cancelar não muda nada', (t) async {
    final outra = (await t.runAsync(() async {
      final o = await Biblioteca.abrir(Directory.systemTemp.createTempSync('defs2'));
      await o.adicionar([Importada(contaDeLinha('http://outro.com/c/ 00:1A:79:00:00:02')!)]);
      return o;
    }))!;
    final texto = utf8.decode(codificarCopia(outra, area, prefs));
    await abrir(t, escolher: () async => texto);
    await categoria(t, 'Cópia de segurança');
    await t.ensureVisible(find.text('Importar cópia'));
    await t.tap(find.text('Importar cópia'));
    await t.pumpAndSettle();
    expect(find.text('Importar cópia de segurança'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(bib.listas, isEmpty);
    await t.tap(find.text('Importar cópia'));
    await t.pumpAndSettle();
    await t.tap(find.text('Juntar'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    expect(bib.listas, hasLength(1));
  });

  testWidgets('na TV: a secção Definições abre-se com o comando e o foco fica visível', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final textoCopia = (await t.runAsync(() async {
      final o = await Biblioteca.abrir(Directory.systemTemp.createTempSync('defs3'));
      await o.adicionar([Importada(contaDeLinha('http://outro.com/c/ 00:1A:79:00:00:02')!)]);
      return utf8.decode(codificarCopia(o, area, prefs));
    }))!;
    await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(1280, 800), navigationMode: NavigationMode.directional),
        child: _app(TelaPrincipal(
      verTv: TelaInicio(biblioteca: bib, area: area),
      gestor: const SizedBox(),
      definicoes: TelaDefinicoes(
          biblioteca: bib, area: area, preferencias: prefs, escolherCopia: () async => textoCopia),
    ))));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Desentrelaçamento'), findsNothing, reason: 'começa em Ver TV');
    // só com setas: ESQUERDA até à barra, BAIXO até "Definições" e OK
    expect(_focado(), 'Ir para o Gestor');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    for (var i = 0; i < 4 && _focado() != 'Definições'; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
    }
    expect(_focado(), 'Definições');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('Desentrelaçamento'), findsOneWidget);
    // DIREITA entra na secção
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    // o foco entra no ecrã, na primeira categoria
    expect(_focado(), 'Imagem e som');
    // só com setas: BAIXO até "Cópia de segurança", DIREITA para as opções, até "Importar cópia" e OK
    for (var i = 0; i < 4 && _focado() != 'Cópia de segurança'; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
    }
    expect(_focado(), 'Cópia de segurança');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    final botaoImportar = find.widgetWithText(OutlinedButton, 'Importar cópia');
    // "Exportar cópia" e "Importar cópia" estão lado a lado: DIREITA
    expect(_focoEm(t, find.widgetWithText(FilledButton, 'Exportar cópia')), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(_focoEm(t, botaoImportar), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    // o diálogo abre com o foco em "Cancelar" (o mais seguro)
    expect(find.text('Importar cópia de segurança'), findsOneWidget);
    expect(_focoEm(t, find.widgetWithText(TextButton, 'Cancelar')), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(_focoEm(t, find.widgetWithText(FilledButton, 'Juntar')), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(bib.listas, hasLength(1));
    // depois do diálogo o foco volta ao ecrã (não se perde)
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    expect(_focoEm(t, botaoImportar), isTrue);
    // Voltar: de volta a Ver TV
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Desentrelaçamento'), findsNothing);
    expect(find.textContaining('OUTRO'), findsOneWidget, reason: 'Ver TV com a lista importada');
  });
}
