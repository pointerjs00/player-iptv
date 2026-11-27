import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/desporto/servico_jogos.dart';
import 'package:player_iptv/ui/jogos/linha_jogo.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';

import 'ajuda_dpad.dart';
import 'jogos_apoio.dart';

/// O ecrã «Jogos» num ecrã largo (computador): a lista, a coluna à direita, os estados vazios,
/// o «Onde ver» e o «▶ Ver».
void main() {
  late Montagem m;
  tearDown(() => arrumarJogos(m));

  Future<void> montar(WidgetTester t, {List<JogoComCanais>? jogos, FontesFalsas? fontes, EstadoJogos? estado}) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    m = (await t.runAsync(() => prepararJogos(jogos: jogos, fontes: fontes, estado: estado)))!;
    await t.pumpWidget(appTeste(Scaffold(body: m.tela())));
    await t.pump();
  }

  testWidgets('os jogos com canal, pela hora, com a coluna do jogo à direita', (t) async {
    await montar(t);
    expect(find.byType(LinhaJogo), findsNWidgets(7), reason: 'o jogo sem canal fica de fora');
    expect(find.text('Moreirense'), findsNothing);
    // a coluna à direita mostra o primeiro jogo
    expect(find.text('Onde dá'), findsOneWidget);
    expect(find.text('Marítimo'), findsNWidgets(2), reason: 'na linha e na coluna');
    expect(m.servico.cargas, isEmpty, reason: 'o dia já estava carregado');
  });

  testWidgets('um jogo sem canal só aparece com «Mostrar jogos sem canal»', (t) async {
    await montar(t);
    expect(find.text('Moreirense'), findsNothing);
    await t.tap(find.widgetWithText(FilterChip, 'Mostrar jogos sem canal'));
    await t.pump();
    expect(find.text('Moreirense'), findsOneWidget);
    expect(find.text('Ainda sem canal anunciado'), findsOneWidget);
    expect(m.prefs.mostrarSemCanal, isTrue);
  });

  testWidgets('filtros: «Em direto» e uma competição', (t) async {
    await montar(t);
    await t.tap(find.widgetWithText(FilterChip, 'Em direto'));
    await t.pump();
    expect(find.byType(LinhaJogo), findsOneWidget);
    await t.tap(find.widgetWithText(FilterChip, 'Em direto'));
    await t.pump();
    final premier = find.widgetWithText(FilterChip, 'Premier League');
    await t.scrollUntilVisible(premier, 150,
        scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first);
    await t.ensureVisible(premier);
    await t.pumpAndSettle();
    await t.tap(premier);
    await t.pump();
    expect(find.byType(LinhaJogo), findsOneWidget);
    expect(find.text('Arsenal'), findsWidgets);
  });

  testWidgets('estado vazio: nenhum jogo das competições seguidas', (t) async {
    await montar(t, jogos: const []);
    expect(find.text('Nenhum jogo das tuas competições neste dia'), findsOneWidget);
  });

  testWidgets('estado vazio: só jogos sem canal, com o botão para os mostrar', (t) async {
    await montar(t, jogos: [jogoTeste(3, 'Moreirense', 'Santa Clara', [])]);
    expect(find.text('Ainda sem canal anunciado'), findsOneWidget);
    await t.tap(find.widgetWithText(OutlinedButton, 'Mostrar jogos sem canal'));
    await t.pump();
    expect(find.text('Moreirense'), findsWidgets);
  });

  testWidgets('sem rede: diz de quando são os dados; uma fonte em falta diz-se no topo', (t) async {
    await montar(t,
        estado: EstadoJogos(
            carga: Carga.pronto,
            falhas: const {FonteJogos.meo},
            velhoDesde: DateTime.now().toUtc().subtract(const Duration(hours: 2))));
    expect(find.textContaining('Sem rede: a mostrar os dados de há 2 h'), findsOneWidget);
    expect(find.textContaining('MEO indisponível'), findsOneWidget);
  });

  testWidgets('«Onde ver»: as fontes do canal; escolher a 2.ª abre-a e deixa a 1.ª para a troca', (t) async {
    await montar(t);
    await t.tap(find.widgetWithText(Etiquetas, 'Sport TV 1').first);
    await t.pumpAndSettle();
    expect(find.text('Onde ver: Sport TV 1'), findsOneWidget);
    expect(find.text('Lista 1'), findsOneWidget);
    expect(find.text('Lista 2'), findsOneWidget);
    await t.tap(find.text('Lista 2'));
    await t.pumpAndSettle();
    expect(m.abertas.single.map((f) => f.lista.id), ['2', '1']);
    // o êxito fica como «funcionou da última vez»
    m.aoFuncionar!(m.abertas.single.first);
    expect(m.prefs.ultimaFonte('sporttv1')?.listaId, '2');
  });

  testWidgets('«Onde ver» de um canal que nenhuma lista tem', (t) async {
    await montar(t);
    await t.tap(find.widgetWithText(Etiquetas, 'Sport TV 3'));
    await t.pumpAndSettle();
    expect(find.text('Nenhuma das tuas listas tem este canal'), findsOneWidget);
  });

  testWidgets('«▶ Ver» junta as fontes de todos os canais do jogo', (t) async {
    await montar(t);
    await t.tap(find.widgetWithText(FilledButton, 'Ver'));
    await t.pump();
    expect(m.abertas.single.map((f) => f.canalTv), ['sporttv1', 'sporttv1', 'sporttv2']);
  });

  testWidgets('a casca mostra «Jogos» na barra só quando recebe o ecrã', (t) async {
    await montar(t);
    await t.pumpWidget(appTeste(TelaPrincipal(
        verTv: const SizedBox(), jogos: m.tela(), gestor: const SizedBox(), definicoes: const SizedBox())));
    await t.pump();
    expect(find.text('Jogos'), findsWidgets);
    await t.tap(find.text('Jogos').first);
    await t.pump();
    expect(find.byType(LinhaJogo), findsWidgets);
    await t.pumpWidget(appTeste(
        const TelaPrincipal(verTv: SizedBox(), gestor: SizedBox(), definicoes: SizedBox())));
    await t.pump();
    expect(find.text('Jogos'), findsNothing);
  });
}

/// As etiquetas dos canais (para encontrar a de um canal pelo nome).
typedef Etiquetas = EtiquetaCanal;
