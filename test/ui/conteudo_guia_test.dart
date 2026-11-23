import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/guia/programa.dart';
import 'package:player_iptv/guia/servico_guia.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/conteudo/painel_canal.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';

import '../guia/servico_guia_test.dart' show FonteFalsa, agora;
import 'ajuda_dpad.dart';
import 'apoio_telemovel.dart';

/// O guia (EPG) em Ver TV: a coluna dos detalhes do canal com o foco (TV e computador), a
/// pesquisa pelo programa a dar ou o seguinte, e no telemóvel o «Agora: …» e a folha dos detalhes.

final _conteudo = ConteudoLista(['Portugal', 'Desporto'], const [
  Canal(id: '1', nome: 'RTP 1', grupo: 'Portugal', numero: 1),
  Canal(id: '2', nome: 'SIC', grupo: 'Portugal', numero: 3),
  Canal(id: '3', nome: 'Sport TV 1', grupo: 'Desporto', numero: 20),
  Canal(id: '4', nome: 'Eleven', grupo: 'Desporto', numero: 21),
]);

Map<String, List<Programa>> _guia() => {
      '1': [
        const Programa(agora - 900, agora + 900, 'Telejornal', 'As notícias do dia, com o tempo.'),
        const Programa(agora + 900, agora + 4500, 'Novela da noite'),
        const Programa(agora + 4500, agora + 9000, 'Filme'),
      ],
      '3': [const Programa(agora - 600, agora + 6000, 'Futebol: Benfica x Porto')],
      '4': [
        const Programa(agora - 600, agora + 600, 'Ténis'),
        const Programa(agora + 600, agora + 6000, 'Resumo do Benfica'),
      ],
    };

final _pesquisa = find.byKey(const Key('pesquisa-canais'));
final _coluna = find.byKey(const Key('coluna-detalhes'));

Finder _naColuna(Finder f) => find.descendant(of: _coluna, matching: f);

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late FonteFalsa fonte;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('conteudo_guia');
    bib = await Biblioteca.abrir(pasta);
    fonte = FonteFalsa(todosDa: _guia, canalDa: (_) => const []);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  ServicoGuia? criarGuia(Lista l) =>
      ServicoGuia(chave: l.id, conta: l.conta, fonte: fonte, agora: () => agora);

  Future<Lista> abrir(WidgetTester t, {Widget Function(Widget) app = appTeste, bool comGuia = true}) async {
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
      await bib.guardarCanais(bib.listas.single.id, _conteudo);
    });
    final l = bib.listas.single;
    await t.runAsync(() async {
      await t.pumpWidget(app(const Scaffold(body: Text('base'))));
      Navigator.of(t.element(find.text('base'))).push(MaterialPageRoute<void>(
          builder: (_) => TelaConteudo(biblioteca: bib, lista: l, abrir: (c, i) => null,
              guia: comGuia ? criarGuia : (_) => null)));
      await t.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpAndSettle();
    return l;
  }

  Future<void> tecla(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k);
    await t.pump();
  }

  Future<void> escrever(WidgetTester t, String texto) async {
    await t.tap(_pesquisa);
    await t.pump();
    await t.enterText(_pesquisa, texto);
    await t.pump(const Duration(milliseconds: 200));
    await t.pumpAndSettle();
  }

  group('TV (960×540): a coluna dos detalhes', () {
    testWidgets('o canal com o foco: nome, número, grupo, agora (com progresso e descrição), a seguir e depois',
        (t) async {
      ecraTvTeste(t);
      await abrir(t);
      expect(_coluna, findsOneWidget);
      expect(t.takeException(), isNull, reason: 'nada transborda a 960');
      // → dos grupos vai ao 1.º canal
      await tecla(t, LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(_naColuna(find.text('RTP 1', findRichText: true)), findsOneWidget);
      expect(_naColuna(find.text('Canal 1 · Portugal')), findsOneWidget);
      expect(_naColuna(find.text('Telejornal')), findsOneWidget);
      expect(_naColuna(find.text('As notícias do dia, com o tempo.')), findsOneWidget);
      expect(_naColuna(find.text('${intervaloPrograma(_guia()['1']![0])} · faltam 15 min')), findsOneWidget);
      expect(t.widget<LinearProgressIndicator>(find.byKey(const Key('detalhe-progresso'))).value, closeTo(.5, 1e-9));
      expect(_naColuna(find.text('Novela da noite')), findsOneWidget);
      expect(_naColuna(find.text('Filme')), findsOneWidget, reason: 'o que vem depois, numa linha');
      // ↓ passa ao seguinte: os detalhes acompanham
      await tecla(t, LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(_naColuna(find.text('SIC', findRichText: true)), findsOneWidget);
      expect(_naColuna(find.text('Sem programação disponível.')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('um canal sem programação pede só a dele, e só quando o foco pára lá', (t) async {
      ecraTvTeste(t);
      await abrir(t);
      fonte.pedidosCanal.clear();
      await tecla(t, LogicalKeyboardKey.arrowRight); // RTP 1 (tem guia)
      await tecla(t, LogicalKeyboardKey.arrowDown); // SIC (sem guia), de passagem
      await t.pump(const Duration(milliseconds: 100));
      await tecla(t, LogicalKeyboardKey.arrowDown); // Sport TV 1 (tem guia)
      await t.pump(const Duration(milliseconds: 100));
      await tecla(t, LogicalKeyboardKey.arrowUp); // de volta à SIC, e fica
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(fonte.pedidosCanal, ['2']);
    });

    testWidgets('uma lista sem guia (M3U): os detalhes do canal e «Esta lista não tem programação.»', (t) async {
      ecraTvTeste(t);
      await abrir(t, comGuia: false);
      expect(_naColuna(find.text('RTP 1', findRichText: true)), findsOneWidget);
      expect(_naColuna(find.byKey(const Key('sem-guia'))), findsOneWidget);
    });

    testWidgets('numa janela estreita (< 900) não há coluna dos detalhes', (t) async {
      ecraTvTeste(t, largura: 800, altura: 600);
      await abrir(t);
      expect(_coluna, findsNothing);
    });
  });

  group('pesquisar pelo programa', () {
    testWidgets('encontra pelo programa a dar e pelo seguinte, depois dos encontrados pelo nome', (t) async {
      ecraTvTeste(t);
      await abrir(t);
      await escrever(t, 'benfica');
      expect(find.text('A dar: Futebol: Benfica x Porto'), findsOneWidget);
      expect(find.text('A seguir: Resumo do Benfica'), findsOneWidget);
      expect(find.text('Canais · 2 · 2 pelo programa'), findsOneWidget);
      // pelo nome primeiro: «sic» encontra a SIC pelo nome e nada pelo programa
      await escrever(t, 'telejornal');
      expect(find.text('A dar: Telejornal'), findsOneWidget);
      expect(find.text('Canais · 1 · 1 pelo programa'), findsOneWidget);
      await escrever(t, 'novela');
      expect(find.text('A seguir: Novela da noite'), findsOneWidget);
      await escrever(t, 'filme');
      expect(find.text('Nenhum canal.'), findsOneWidget, reason: 'só o a dar e o seguinte contam');
    });

    testWidgets('a pesquisa num grupo procura o programa só nesse grupo', (t) async {
      ecraTvTeste(t);
      await abrir(t);
      await t.tap(find.text('Portugal'));
      await t.pumpAndSettle();
      await escrever(t, 'benfica');
      expect(find.text('Nenhum canal.'), findsOneWidget);
    });

    testWidgets('sem o guia de todos os canais, uma nota explica que a pesquisa é só pelo nome', (t) async {
      ecraTvTeste(t);
      fonte.todosDa = null; // o servidor não dá o guia de todos
      await abrir(t);
      await escrever(t, 'benfica');
      expect(find.byKey(const Key('nota-guia-pesquisa')), findsOneWidget);
      expect(find.text('Esta lista não tem a programação de todos os canais: a pesquisa é só pelo nome.'),
          findsOneWidget);
    });
  });

  group('telemóvel', () {
    void noAndroid(String nome, Future<void> Function(WidgetTester t, Size ecra) corpo) =>
        noTelemovel(nome, (t, ecra) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          try {
            await corpo(t, ecra);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });

    noAndroid('«Agora: …» por baixo do nome; o toque longo abre os detalhes, com Ver e os favoritos', (t, ecra) async {
      final l = await abrir(t, app: appTelemovel);
      expect(_coluna, findsNothing);
      expect(find.text('Agora: Telejornal'), findsOneWidget);
      expect(find.text('Agora: Futebol: Benfica x Porto'), findsOneWidget);
      await t.longPress(find.widgetWithText(ListTile, 'RTP 1'));
      await t.pumpAndSettle();
      final folha = find.byKey(const Key('folha-detalhes'));
      expect(find.descendant(of: folha, matching: find.text('Telejornal')), findsOneWidget);
      expect(find.descendant(of: folha, matching: find.text('Novela da noite')), findsOneWidget);
      expect(l.favoritos, isEmpty, reason: 'o toque longo já não põe nos favoritos sozinho');
      await t.tap(find.text('Pôr nos favoritos'));
      await t.pumpAndSettle();
      expect(l.favoritos, {'1'});
      expect(t.takeException(), isNull);
    });
  });
}
