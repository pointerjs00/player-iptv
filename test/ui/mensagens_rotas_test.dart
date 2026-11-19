import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/tarefas/servico_tarefas.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/design/mensagens.dart';
import 'package:player_iptv/ui/player/controlos_player.dart';
import 'package:player_iptv/ui/player/maquina_controlos.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

final _conteudo = ConteudoLista(['Portugal'], const [
  Canal(id: '1', nome: 'SIC', grupo: 'Portugal'),
  Canal(id: '2', nome: 'RTP 1', grupo: 'Portugal'),
]);

/// A app como no main.dart: com `anfitriao`, as mensagens vivem no `MaterialApp.builder` (por cima
/// de todas as rotas); sem ele, a TelaPrincipal tem as suas (só se veem na rota dela).
Widget _app(Widget casa, {bool anfitriao = true}) => MaterialApp(
      theme: temaApp(),
      builder: (_, c) => TemaConformeRealce(child: anfitriao ? AnfitriaoMensagens(child: c!) : c!),
      home: casa,
    );

/// Um player mínimo (só os controlos): regista as ações que pede.
class _Player extends StatelessWidget {
  const _Player(this.acoes);
  final List<AcaoPlayer> acoes;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: ControlosPlayer(
          estado: const EstadoControlos(canal: 'RTP 1', subtitulo: 'Lista A'),
          atraso: () => Duration.zero,
          aoAgir: acoes.add,
          aoMudarVelocidade: (_) {},
          definicoes: () => const [],
          child: const SizedBox.expand(),
        ),
      );
}

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late ServicoTarefas tarefas;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('mensagens_rotas');
    bib = await Biblioteca.abrir(pasta);
    tarefas = ServicoTarefas();
  });
  tearDown(() {
    tarefas.dispose();
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  void tamanho(WidgetTester t) {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
  }

  /// A casca com um botão em Ver TV que abre `rota` por cima (como a lista aberta e o player do
  /// Android, que são rotas empilhadas sobre a casca).
  Widget casca(Widget Function() rota) => TelaPrincipal(
        tarefas: tarefas,
        verTv: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => rota())),
              child: const Text('abrir'),
            ),
          ),
        ),
        gestor: const SizedBox(),
        definicoes: const SizedBox(),
      );

  Future<Lista> abrirLista(WidgetTester t, {bool anfitriao = true}) async {
    tamanho(t);
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
      await bib.guardarCanais(bib.listas.single.id, _conteudo);
    });
    final l = bib.listas.single;
    await t.pumpWidget(_app(casca(() => TelaConteudo(biblioteca: bib, lista: l)), anfitriao: anfitriao));
    await t.tap(find.text('abrir'));
    await t.runAsync(() async {
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpAndSettle();
    expect(find.text('RTP 1'), findsOneWidget, reason: 'a lista aberta está à vista');
    return l;
  }

  Future<void> tecla(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k);
    await t.pumpAndSettle();
  }

  /// Uma tarefa que acaba e dá à casca uma mensagem com ação ("Menu: Ir").
  Future<List<int>> mensagemDaCasca(WidgetTester t) async {
    final feitas = <int>[];
    tarefas.iniciar('Enviar', (p) async => 'Enviada', rotuloAcao: 'Ir', aoAcao: () => feitas.add(1));
    await t.pump();
    await t.pump();
    return feitas;
  }

  group('lista aberta', () {
    testWidgets('o "Desfazer" do favorito aparece no canto (sem SnackBar) e a tecla Menu desfaz', (t) async {
      final l = await abrirLista(t);
      await tecla(t, LogicalKeyboardKey.arrowRight);
      await tecla(t, LogicalKeyboardKey.arrowDown);
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      await t.pump(duracaoOkMantido + const Duration(milliseconds: 50));
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(l.favoritos, {'2'});
      expect(find.text('RTP 1 está nos favoritos'), findsOneWidget);
      expect(find.text('Menu: Desfazer'), findsOneWidget, reason: 'a mensagem do canto');
      expect(find.byType(SnackBar), findsNothing);
      await tecla(t, LogicalKeyboardKey.contextMenu);
      expect(l.favoritos, isEmpty, reason: 'Menu desfez');
      expect(find.text('Ordenar A–Z'), findsNothing, reason: 'Menu não abriu as opções dos canais');
      expect(find.text('RTP 1 está nos favoritos'), findsNothing);
    });

    testWidgets('sem mensagem à vista, Menu abre as opções dos canais', (t) async {
      await abrirLista(t);
      final feitas = await mensagemDaCasca(t);
      expect(find.text('Menu: Ir'), findsOneWidget, reason: 'a mensagem da casca vê-se por cima da lista');
      await t.pump(const Duration(seconds: 9));
      await t.pumpAndSettle();
      expect(find.text('Menu: Ir'), findsNothing);
      await tecla(t, LogicalKeyboardKey.contextMenu);
      expect(find.text('Ordenar A–Z'), findsOneWidget);
      expect(feitas, isEmpty);
    });

    testWidgets('a mensagem de uma casca tapada pela lista não apanha a tecla Menu', (t) async {
      // sem anfitrião na app (só a casca tem mensagens): a mensagem fica escondida por baixo
      await abrirLista(t, anfitriao: false);
      final feitas = await mensagemDaCasca(t);
      await tecla(t, LogicalKeyboardKey.contextMenu);
      expect(find.text('Ordenar A–Z'), findsOneWidget, reason: 'a tecla chegou à lista aberta');
      expect(feitas, isEmpty, reason: 'a ação escondida não correu');
    });
  });

  group('player (Android, rota por cima da casca)', () {
    Future<List<AcaoPlayer>> abrirPlayer(WidgetTester t, {bool anfitriao = true}) async {
      tamanho(t);
      final acoes = <AcaoPlayer>[];
      await t.pumpWidget(_app(casca(() => _Player(acoes)), anfitriao: anfitriao));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      return acoes;
    }

    testWidgets('a mensagem da casca vê-se por cima do player; sem mensagem, Menu abre as estatísticas',
        (t) async {
      final acoes = await abrirPlayer(t);
      final feitas = await mensagemDaCasca(t);
      expect(find.text('Menu: Ir'), findsOneWidget);
      await t.pump(const Duration(seconds: 9));
      await t.pumpAndSettle();
      await tecla(t, LogicalKeyboardKey.contextMenu);
      expect(acoes, contains(AcaoPlayer.estatisticas));
      expect(feitas, isEmpty);
    });

    testWidgets('a mensagem de uma casca tapada pelo player não apanha a tecla Menu', (t) async {
      final acoes = await abrirPlayer(t, anfitriao: false);
      final feitas = await mensagemDaCasca(t);
      await tecla(t, LogicalKeyboardKey.contextMenu);
      expect(acoes, contains(AcaoPlayer.estatisticas));
      expect(feitas, isEmpty);
    });

    testWidgets('Menu numa mensagem da casca com ação, por cima do player, volta à casca e faz a ação',
        (t) async {
      await abrirPlayer(t);
      final feitas = await mensagemDaCasca(t);
      await tecla(t, LogicalKeyboardKey.contextMenu);
      expect(feitas, [1]);
      expect(find.byType(ControlosPlayer), findsNothing, reason: 'a ação vê-se: o player fechou');
      expect(find.text('abrir'), findsOneWidget);
    });
  });
}
