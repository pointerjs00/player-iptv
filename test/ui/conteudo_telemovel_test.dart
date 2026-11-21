import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';

import 'ajuda_dpad.dart';
import 'apoio_telemovel.dart';

/// A lista aberta num telemóvel ao alto (360×800 e 412×915, letra a 1 e a 1,3, com a Roboto): o
/// topo com o nome em duas linhas, ⟳ e um menu ⋮; os grupos num botão que abre um bottom sheet
/// com pesquisa; o nome do canal em duas linhas; e nada transborda. A TV fica com as duas colunas.

const _nomeLista = '001ALFA 070927 A lista com um nome bem comprido';
const _canalLongo = '|PT| SPORT TV 1 FHD (DIRETO)';

final _grupos = [for (var i = 1; i <= 12; i++) 'Grupo $i'];

final _conteudo = ConteudoLista(_grupos, [
  const Canal(id: 'longo', nome: _canalLongo, grupo: 'Grupo 1', numero: 1),
  for (final (i, g) in _grupos.indexed)
    for (var j = 1; j <= i + 1; j++) Canal(id: '$g-$j', nome: '$g canal $j', grupo: g, numero: 100 * (i + 1) + j),
]);

final _botaoGrupo = find.byKey(const Key('botao-grupo'));
final _folha = find.byKey(const Key('folha-grupos'));
final _menu = find.byKey(const Key('menu-lista-aberta'));

void main() {
  late Directory pasta;
  late Biblioteca bib;

  setUpAll(carregarRoboto);
  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('conteudo_telemovel');
    bib = await Biblioteca.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {
      /* Windows */
    }
  });

  /// Android (não TV) e, no fim do corpo, o repor (antes das verificações do teste).
  void noAndroid(String nome, Future<void> Function(WidgetTester t, Size ecra) corpo) =>
      noTelemovel(nome, (t, ecra) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await corpo(t, ecra);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

  /// A lista aberta (com um grupo escondido, um favorito e um visto) por cima de um ecrã base.
  Future<Lista> abrir(WidgetTester t, {Widget Function(Widget)? app}) async {
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://servidor-alfa.exemplo.invalid/lista.m3u')!)]);
      final id = bib.listas.single.id;
      await bib.guardarCanais(id, _conteudo);
      await bib.esconderGrupo(id, 'Grupo 12', true);
      await bib.alternarFavorito(id, 'Grupo 2-1');
      await bib.registarVisto(id, _conteudo.canais[3]);
    });
    final l = bib.listas.single..nomeProprio = _nomeLista;
    await t.runAsync(() async {
      await t.pumpWidget((app ?? appTelemovel)(const Scaffold(body: Text('base'))));
      Navigator.of(t.element(find.text('base'))).push(MaterialPageRoute<void>(
          builder: (_) => TelaConteudo(biblioteca: bib, lista: l, abrir: (c, i) => null)));
      await t.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpAndSettle();
    return l;
  }

  Future<void> abrirFolha(WidgetTester t) async {
    await t.tap(_botaoGrupo);
    await t.pumpAndSettle();
    expect(_folha, findsOneWidget);
  }

  /// O IconButton com esta dica (a dica embrulha só o botão de 40; o alvo é o IconButton).
  Finder botao(String dica) => find.ancestor(of: find.byTooltip(dica), matching: find.byType(IconButton));

  /// A linha (ListTile) de um canal.
  Finder linhaDoCanal(Finder texto) => find.ancestor(of: texto, matching: find.byType(ListTile)).first;

  /// O texto cabe na altura da linha do canal (a linha tem altura fixa: não pode ficar cortado).
  void dentroDaLinha(WidgetTester t, Finder texto) {
    final linha = t.getRect(linhaDoCanal(texto));
    final r = t.getRect(texto);
    expect(r.top, greaterThanOrEqualTo(linha.top));
    expect(r.bottom, lessThanOrEqualTo(linha.bottom), reason: 'o texto passa o fundo da linha');
  }

  /// A linha de um grupo na folha.
  Finder linhaDaFolha(String texto) =>
      find.ancestor(of: find.descendant(of: _folha, matching: find.text(texto)), matching: find.byType(ListTile));

  noAndroid('topo: ← , o nome em até 2 linhas, «N canais», ⟳ e ⋮', (t, ecra) async {
    await abrir(t);
    final nome = find.text(_nomeLista);
    expect(nome, findsOneWidget);
    expect(t.widget<Text>(nome).maxLines, 2);
    expect(find.text('${_conteudo.canais.length} canais'), findsOneWidget);
    alvo48(t, botao('Voltar ao Início'));
    alvo48(t, botao('Atualizar a lista de canais'));
    alvo48(t, find.descendant(of: _menu, matching: find.byType(IconButton)));
    noEcra(t, _menu, ecra);
    // os botões «Ordem» e «Grupos escondidos» saíram do topo (estão no ⋮)
    expect(find.textContaining('Ordem:'), findsNothing);
    expect(find.textContaining('Grupos escondidos:'), findsNothing);
    // e o ← volta ao Início
    await t.tap(find.byTooltip('Voltar ao Início'));
    await t.pumpAndSettle();
    expect(find.byType(TelaConteudo), findsNothing);
  });

  noAndroid('o ⋮ tem a ordem, os grupos escondidos e «Atualizar»', (t, ecra) async {
    final l = await abrir(t);
    await t.tap(_menu);
    await t.pumpAndSettle();
    expect(find.text('Ordem: da lista'), findsOneWidget);
    expect(find.text('Ordem: A–Z'), findsOneWidget);
    expect(find.text('Mostrar grupos escondidos (1)'), findsOneWidget);
    expect(find.text('Atualizar canais'), findsOneWidget);
    // A–Z: os canais passam a estar por ordem alfabética
    await t.tap(find.text('Ordem: A–Z'));
    await t.pumpAndSettle();
    expect(l.ordemCanais, OrdemCanais.az);
    // os grupos escondidos à vista: o «Grupo 12» aparece na folha
    await t.tap(_menu);
    await t.pumpAndSettle();
    await t.tap(find.text('Mostrar grupos escondidos (1)'));
    await t.pumpAndSettle();
    await abrirFolha(t);
    // o último da lista: desliza-se até ele
    await t.dragUntilVisible(linhaDaFolha('Grupo 12'), find.descendant(of: _folha, matching: find.byType(ListView)),
        const Offset(0, -200));
    expect(linhaDaFolha('Grupo 12'), findsOneWidget);
    Navigator.of(t.element(_folha)).pop();
    await t.pumpAndSettle();
    await t.tap(_menu);
    await t.pumpAndSettle();
    expect(find.text('Ocultar grupos escondidos'), findsOneWidget);
    await t.tap(find.text('Ocultar grupos escondidos'));
    await t.pumpAndSettle();
    await abrirFolha(t);
    await t.dragUntilVisible(linhaDaFolha('Grupo 11'), find.descendant(of: _folha, matching: find.byType(ListView)),
        const Offset(0, -200));
    expect(linhaDaFolha('Grupo 12'), findsNothing);
  });

  noAndroid('os grupos: um botão «Grupo: …» abre a folha com pesquisa e contagens; escolher fecha-a',
      (t, ecra) async {
    await abrir(t);
    expect(find.byType(ChoiceChip), findsNothing, reason: 'sem a fila de chips');
    expect(find.descendant(of: _botaoGrupo, matching: find.text('Grupo: Todos os canais')), findsOneWidget);
    alvo48(t, _botaoGrupo);
    await abrirFolha(t);
    // pesquisa, «Todos os canais», Favoritos, Vistos e cada grupo com a contagem
    expect(find.descendant(of: _folha, matching: find.byType(TextField)), findsOneWidget);
    final total = _conteudo.canais.length - 12; // sem os do Grupo 12 (escondido)
    expect(find.descendant(of: linhaDaFolha('Todos os canais'), matching: find.text('$total')), findsOneWidget);
    expect(find.descendant(of: linhaDaFolha(grupoFavoritos), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: linhaDaFolha(grupoVistos), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: linhaDaFolha('Grupo 3'), matching: find.text('3')), findsOneWidget);
    expect(linhaDaFolha('Grupo 12'), findsNothing, reason: 'escondido');
    // a pesquisa nos grupos (sem acentos nem maiúsculas)
    await t.tap(find.descendant(of: _folha, matching: find.byType(TextField)));
    await t.pump();
    await t.enterText(find.descendant(of: _folha, matching: find.byType(TextField)), 'grupo 1');
    await t.pumpAndSettle();
    expect(linhaDaFolha('Grupo 10'), findsOneWidget);
    expect(linhaDaFolha('Grupo 3'), findsNothing);
    expect(linhaDaFolha('Todos os canais'), findsOneWidget, reason: 'nunca é filtrada');
    // escolher fecha a folha e mostra os canais do grupo
    await t.tap(linhaDaFolha('Grupo 10'));
    await t.pumpAndSettle();
    expect(_folha, findsNothing);
    expect(find.descendant(of: _botaoGrupo, matching: find.text('Grupo: Grupo 10')), findsOneWidget);
    expect(find.text('Grupo 10 canal 1'), findsOneWidget);
    expect(find.text('Grupo 3 canal 1'), findsNothing);
    // e «Todos os canais» volta a mostrar todos
    await abrirFolha(t);
    await t.tap(linhaDaFolha('Todos os canais'));
    await t.pumpAndSettle();
    expect(_folha, findsNothing);
    expect(find.descendant(of: _botaoGrupo, matching: find.text('Grupo: Todos os canais')), findsOneWidget);
    expect(find.text(_canalLongo), findsOneWidget);
  });

  noAndroid('arrastar a folha para baixo fecha-a, sem mudar o grupo', (t, ecra) async {
    await abrir(t);
    await abrirFolha(t);
    // pela pega, como no Android
    final pega = t.getRect(find.byType(BottomSheet)).topCenter + const Offset(0, 12);
    await t.flingFrom(pega, const Offset(0, 600), 2000);
    await t.pumpAndSettle();
    expect(_folha, findsNothing);
    expect(find.descendant(of: _botaoGrupo, matching: find.text('Grupo: Todos os canais')), findsOneWidget);
  });

  noAndroid('os canais: o nome em até 2 linhas, inteiro; sem o contador «1 de N»', (t, ecra) async {
    await abrir(t);
    final nome = find.text(_canalLongo);
    expect(t.widget<Text>(nome).maxLines, 2);
    inteiro(t, nome);
    dentroDaLinha(t, nome);
    expect(find.byKey(const Key('contador-canais')), findsNothing);
    // a estrela dos favoritos continua a responder ao toque
    expect(find.byTooltip('Pôr nos favoritos').first, findsOneWidget);
    // e com pesquisa (o grupo por baixo do nome) também cabe
    await t.tap(find.byKey(const Key('pesquisa-canais')));
    await t.pump();
    await t.enterText(find.byKey(const Key('pesquisa-canais')), 'sport');
    await t.pump(const Duration(milliseconds: 200));
    await t.pumpAndSettle();
    inteiro(t, find.text(_canalLongo));
    dentroDaLinha(t, find.text(_canalLongo));
    dentroDaLinha(t, find.descendant(of: linhaDoCanal(find.text(_canalLongo)), matching: find.text('Grupo 1')));
  });

  testWidgets('na TV continuam as duas colunas, os botões do topo e o contador', (t) async {
    ecraTvTeste(t, largura: 960, altura: 540);
    await abrir(t, app: appTeste);
    expect(find.byKey(const Key('lista-grupos')), findsOneWidget);
    expect(find.byKey(const Key('filtro-grupos')), findsOneWidget);
    expect(_botaoGrupo, findsNothing);
    expect(_menu, findsNothing);
    expect(find.text('Ordem: da lista'), findsOneWidget);
    expect(find.byKey(const Key('contador-canais')), findsOneWidget);
    expect(find.text('‹ Início'), findsOneWidget);
  });

  testWidgets('no Windows (largo, sem TV) também fica tudo igual', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await abrir(t, app: appTeste);
    expect(find.byKey(const Key('lista-grupos')), findsOneWidget);
    expect(_botaoGrupo, findsNothing);
    expect(_menu, findsNothing);
    expect(find.byKey(const Key('contador-canais')), findsOneWidget);
  });
}
