import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/desporto/servico_jogos.dart';
import 'package:player_iptv/ui/conteudo/painel_canal.dart' show LogoCanal;
import 'package:player_iptv/ui/jogos/linha_jogo.dart';
import 'package:player_iptv/desporto/modelo.dart';
import 'package:player_iptv/ui/jogos/tela_competicoes.dart';
import 'package:player_iptv/ui/jogos/tela_jogos_competicao.dart';
import 'package:player_iptv/ui/jogos/tela_jogos.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/ui/definicoes/secao_jogos.dart';
import 'package:player_iptv/ui/definicoes/tela_definicoes.dart';
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

  testWidgets('os jogos por competição (a Liga Portugal primeiro), com a coluna do jogo à direita', (t) async {
    await montar(t);
    expect(find.byType(LinhaJogo), findsNWidgets(8), reason: 'por omissão também os jogos sem canal');
    final blocos = [for (final e in find.byType(CabecalhoCompeticao).evaluate()) (e.widget as CabecalhoCompeticao).grupo.competicao.nome];
    expect(blocos, ['Liga Portugal Betclic', 'Premier League', 'Eredivisie']);
    expect(find.text('6 jogos'), findsOneWidget);
    // a coluna à direita mostra o primeiro jogo
    expect(find.text('Onde dá'), findsOneWidget);
    expect(find.text('Marítimo'), findsNWidgets(2), reason: 'na linha e na coluna');
    expect(m.servico.cargas, isEmpty, reason: 'o dia já estava carregado');
  });

  testWidgets('«Competições» abre as seguidas; a ordem escolhida lá muda a ordem dos blocos', (t) async {
    await montar(t);
    await t.tap(find.byTooltip('Competições'));
    await t.pumpAndSettle();
    expect(find.byType(TelaCompeticoes), findsOneWidget);
    // como se tivesse reordenado: a Eredivisie para o topo
    m.prefs.moverCompeticao('eredivisie', 0);
    await t.pump();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(TelaCompeticoes), findsNothing);
    final blocos = [for (final e in find.byType(CabecalhoCompeticao).evaluate()) (e.widget as CabecalhoCompeticao).grupo.competicao.nome];
    expect(blocos, ['Eredivisie', 'Liga Portugal Betclic', 'Premier League']);
  });

  testWidgets('ao vivo: com o ecrã à vista pede a cada 60 s, só no dia de hoje; sai e pára', (t) async {
    await montar(t);
    await t.pump(const Duration(seconds: 61));
    expect(m.servico.aoVivo, [hojeJogos]);
    await t.pump(const Duration(seconds: 60));
    expect(m.servico.aoVivo, hasLength(2));
    // outro dia: não há ao vivo
    await t.tap(find.byTooltip('Dia seguinte'));
    await t.pump(const Duration(seconds: 61));
    expect(m.servico.aoVivo, hasLength(2));
    await t.tap(find.byTooltip('Dia anterior'));
    await t.pump(const Duration(seconds: 61));
    expect(m.servico.aoVivo, hasLength(3));
    // sai do ecrã (outra secção da casca à vista)
    await t.pumpWidget(appTeste(Scaffold(
        body: SeccaoAtual(seccao: Seccao.verTv, irPara: (_) {}, child: m.tela()))));
    await t.pump(const Duration(seconds: 61));
    expect(m.servico.aoVivo, hasLength(3), reason: 'com o ecrã escondido não pede');
  });

  testWidgets('o detalhe mostra o logótipo de cada canal, tirado das listas (as iniciais sem ele)', (t) async {
    await montar(t,
        fontes: FontesFalsas({
          'sporttv1': [
            fonteJogos('1', 'sporttv1', 'PT: SPORT TV 1'),
            fonteJogos('2', 'sporttv1', 'SPORT TV 1 FHD', logo: 'http://logos.invalido/stv1.png'),
          ],
          'sporttv2': [fonteJogos('2', 'sporttv2', 'SPORT TV 2 FHD')],
        }));
    final logos = {
      for (final e in find.byType(LogoCanal).evaluate()) (e.widget as LogoCanal).nome: (e.widget as LogoCanal).url,
    };
    expect(logos['Sport TV 1'], 'http://logos.invalido/stv1.png', reason: 'o primeiro logótipo das fontes');
    expect(logos['Sport TV 2'], '', reason: 'sem logótipo nas listas: as iniciais');
  });

  testWidgets('«Ordenar: Por hora» nos Filtros: uma só lista pela hora, com a competição em cada jogo', (t) async {
    await montar(t);
    await t.tap(find.widgetWithIcon(FilterChip, Icons.tune_rounded));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'Por hora'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Fechar'));
    await t.pumpAndSettle();
    expect(m.prefs.ordenarPorHora, isTrue);
    expect(find.byType(CabecalhoCompeticao), findsNothing);
    final casas = [for (final e in find.byType(LinhaJogo).evaluate()) (e.widget as LinhaJogo).item.jogo.casa];
    expect(casas, ['Marítimo', 'Benfica', 'Feyenoord', 'Moreirense', 'Arsenal', 'Braga', 'Gil Vicente', 'Famalicão']);
    expect(find.byType(LinhaJogo).evaluate().every((e) => (e.widget as LinhaJogo).mostrarCompeticao), isTrue);
  });

  testWidgets('em «Competições», tocar numa abre todos os jogos dela, de todos os dias, por dia', (t) async {
    await montar(t);
    m.servico.definir(DateTime(2026, 11, 28), [
      JogoComCanais(
          Jogo(id: 'fotmob:99', desporto: Desporto.futebol, competicaoId: 'premier-league', casa: 'Chelsea',
              fora: 'Liverpool', inicio: DateTime.utc(2026, 11, 28, 17, 30)),
          [transmissao('fotmob:99', 'sporttv2')]),
    ]);
    await t.tap(find.byTooltip('Competições'));
    await t.pumpAndSettle();
    await t.tap(find.text('Premier League'));
    await t.pumpAndSettle();
    expect(find.byType(TelaJogosCompeticao), findsOneWidget);
    expect(find.text('Hoje, 27 nov'), findsOneWidget);
    expect(find.text('Amanhã, 28 nov'), findsOneWidget);
    final casas = [for (final e in find.byType(LinhaJogo).evaluate()) (e.widget as LinhaJogo).item.jogo.casa];
    expect(casas, ['Arsenal', 'Chelsea']);
    expect(t.getRect(find.text('Hoje, 27 nov')).top, lessThan(t.getRect(find.text('Amanhã, 28 nov')).top));
    // os dias que faltavam pedem-se (de ontem a daqui a 6 dias)
    expect(m.servico.cargas, containsAll([DateTime(2026, 11, 26), DateTime(2026, 12, 3)]));
    await t.tap(find.byTooltip('Voltar'));
    await t.pumpAndSettle();
    expect(find.byType(TelaJogosCompeticao), findsNothing);
    expect(find.byType(TelaCompeticoes), findsOneWidget);
  });

  Future<void> abrirFiltros(WidgetTester t) async {
    await t.tap(find.widgetWithIcon(FilterChip, Icons.tune_rounded));
    await t.pumpAndSettle();
  }

  Future<void> fecharFiltros(WidgetTester t) async {
    await t.tap(find.widgetWithText(FilledButton, 'Fechar'));
    await t.pumpAndSettle();
  }

  testWidgets('Filtros › «Só jogos com canal» esconde os que ainda não têm canal', (t) async {
    await montar(t);
    expect(find.text('Moreirense'), findsOneWidget);
    await abrirFiltros(t);
    await t.tap(find.text('Só jogos com canal'));
    await t.pump();
    await fecharFiltros(t);
    expect(find.text('Moreirense'), findsNothing);
    expect(find.widgetWithText(FilterChip, 'Filtros (1)'), findsOneWidget, reason: 'diz quantos filtros estão ligados');
    expect(m.prefs.mostrarSemCanal, isFalse);
  });

  testWidgets('«Ao vivo» e as competições nos Filtros', (t) async {
    await montar(t);
    expect(find.widgetWithText(FilterChip, 'Ao vivo (1)'), findsOneWidget);
    await t.tap(find.widgetWithText(FilterChip, 'Ao vivo (1)'));
    await t.pump();
    expect(find.byType(LinhaJogo), findsOneWidget);
    await t.tap(find.widgetWithText(FilterChip, 'Ao vivo (1)'));
    await t.pump();
    await abrirFiltros(t);
    await t.tap(find.widgetWithText(FilterChip, 'Premier League (1)'));
    await t.pump();
    await fecharFiltros(t);
    expect(find.byType(LinhaJogo), findsOneWidget);
    expect(find.text('Arsenal'), findsWidgets);
    // «Limpar filtros» volta a mostrar tudo
    await abrirFiltros(t);
    await t.tap(find.text('Limpar filtros'));
    await t.pump();
    await fecharFiltros(t);
    expect(find.byType(LinhaJogo), findsNWidgets(8));
  });

  testWidgets('pesquisa por equipa: parte do nome, sem acentos; sem resultados diz qual', (t) async {
    await montar(t);
    // como no aparelho: tocar no campo começa a escrever (o foco sozinho não)
    await t.tap(find.byType(TextField));
    await t.pump();
    await t.enterText(find.byType(TextField), 'famalicao');
    await t.pump();
    expect(find.byType(LinhaJogo), findsOneWidget);
    expect(find.text('Famalicão'), findsWidgets);
    await t.enterText(find.byType(TextField), 'zzz');
    await t.pump();
    expect(find.text('Nenhum jogo de «zzz» neste dia'), findsOneWidget);
    await t.tap(find.widgetWithText(OutlinedButton, 'Limpar a pesquisa'));
    await t.pump();
    expect(find.byType(LinhaJogo), findsNWidgets(8));
  });

  testWidgets('o dia muda com as setas, e «Hoje» volta ao dia de hoje', (t) async {
    await montar(t);
    expect(find.text('Hoje, 27 nov'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Hoje'), findsNothing);
    await t.tap(find.byTooltip('Dia seguinte'));
    await t.pump();
    expect(find.text('Amanhã, 28 nov'), findsOneWidget);
    await t.tap(find.byTooltip('Dia seguinte'));
    await t.tap(find.byTooltip('Dia seguinte'));
    await t.pump();
    expect(find.text('Seg, 30 nov'), findsOneWidget);
    expect(m.servico.cargas, [DateTime(2026, 11, 28), DateTime(2026, 11, 29), DateTime(2026, 11, 30)]);
    await t.tap(find.widgetWithText(ActionChip, 'Hoje'));
    await t.pump();
    expect(find.text('Hoje, 27 nov'), findsOneWidget);
    expect(find.byType(LinhaJogo), findsNWidgets(8));
  });

  testWidgets('estado vazio: nenhum jogo das competições seguidas', (t) async {
    await montar(t, jogos: const []);
    expect(find.text('Nenhum jogo das tuas competições neste dia'), findsOneWidget);
  });

  testWidgets('estado vazio: só jogos sem canal, com o botão para os mostrar', (t) async {
    await montar(t, jogos: [jogoTeste(3, 'Moreirense', 'Santa Clara', [])]);
    m.prefs.mostrarSemCanal = false;
    await t.pump();
    expect(find.text('Ainda sem canal anunciado'), findsOneWidget);
    await t.tap(find.widgetWithText(OutlinedButton, 'Mostrar jogos sem canal'));
    await t.pump();
    expect(find.text('Moreirense'), findsWidgets);
  });

  testWidgets('sem rede: diz de quando são os dados; uma fonte em falta diz-se no topo', (t) async {
    await montar(t,
        estado: EstadoJogos(
            carga: Carga.pronto,
            falhas: const {FonteJogos.sportTv},
            velhoDesde: DateTime.now().toUtc().subtract(const Duration(hours: 2))));
    expect(find.textContaining('Sem rede: a mostrar os dados de há 2 h'), findsOneWidget);
    expect(find.textContaining('Sport TV indisponível'), findsOneWidget);
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

  testWidgets('os jogos das equipas favoritas ficam em destaque', (t) async {
    await montar(t);
    m.prefs.equipasFavoritas = ['SL Benfica'];
    await t.pump();
    final destaque = {
      for (final e in find.byType(LinhaJogo).evaluate()) (e.widget as LinhaJogo).item.jogo.casa: (e.widget as LinhaJogo).destaque,
    };
    expect(destaque['Benfica'], isTrue);
    expect(destaque['Marítimo'], isFalse);
  });

  testWidgets('Definições › Jogos: as competições e a qualidade preferida', (t) async {
    await montar(t);
    final (bib, area, prefs) = (await t.runAsync(() async =>
        (await Biblioteca.abrir(m.pasta), await AreaGestor.abrir(m.pasta), await Preferencias.abrir(m.pasta))))!;
    await t.pumpWidget(appTeste(Scaffold(
        body: TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs, jogos: m.prefs))));
    await t.pump();
    await t.tap(find.text('Jogos'));
    await t.pumpAndSettle();
    expect(find.byType(SecaoJogos), findsOneWidget);
    expect(m.prefs.competicoes, contains('liga-portugal'));
    await t.tap(find.widgetWithText(FilterChip, 'Liga Portugal Betclic'));
    await t.pump();
    expect(m.prefs.competicoes, isNot(contains('liga-portugal')));
    await t.tap(find.widgetWithText(ChoiceChip, '4K'));
    await t.pump();
    expect(m.prefs.qualidade.name, 'uhd');
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
