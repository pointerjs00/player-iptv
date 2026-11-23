import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/novidades.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/idioma/idioma.dart';
import 'package:player_iptv/idioma/ingles.dart';
import 'package:player_iptv/main.dart';
import 'package:player_iptv/ui/adicionar.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/gestor/tela_verificacao.dart';
import 'package:player_iptv/ui/inicio/acoes_lista.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';

/// Os textos portugueses passados a `tr('…')` no código (com os pedaços adjacentes juntos).
List<String> _textosNoCodigo() {
  final textos = <String>[];
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.contains('idioma')) continue;
    final s = f.readAsStringSync();
    var i = 0;
    while ((i = s.indexOf(RegExp(r'\btr\('), i)) >= 0) {
      var j = i + 3;
      final b = StringBuffer();
      var achou = false;
      while (true) {
        while (j < s.length && ' \t\r\n'.contains(s[j])) {
          j++;
        }
        if (j >= s.length || s[j] != "'") break;
        achou = true;
        j++;
        while (s[j] != "'") {
          if (s[j] == r'\') {
            final c = s[j + 1];
            b.write(switch (c) { 'n' => '\n', 't' => '\t', _ => c });
            j += 2;
          } else {
            b.write(s[j]);
            j++;
          }
        }
        j++;
      }
      if (achou) textos.add(b.toString());
      i = j;
    }
  }
  return textos;
}

Set<String> _marcas(String s) => {for (final m in RegExp(r'\{\d+\}').allMatches(s)) m[0]!};

void main() {
  tearDown(() => idiomaApp.value = Idioma.pt);

  test('cada texto com tr() tem tradução inglesa', () {
    final textos = _textosNoCodigo();
    expect(textos.length, greaterThan(700));
    final semTraducao = {for (final t in textos) if (!textosIngles.containsKey(t)) t};
    expect(semTraducao, isEmpty);
  });

  test('as traduções têm as mesmas marcas {0}, {1}… que o português', () {
    for (final e in textosIngles.entries) {
      expect(_marcas(e.value), _marcas(e.key), reason: e.key);
    }
  });

  test('tr: português por omissão, inglês com Idioma.en, marcas trocadas pelos argumentos', () {
    expect(tr('Grupo: {0}', ['Desporto']), 'Grupo: Desporto');
    idiomaApp.value = Idioma.en;
    expect(tr('Grupo: {0}', ['Desporto']), 'Group: Desporto');
    expect(tr('um texto sem tradução'), 'um texto sem tradução');
  });

  test('em inglês, o progresso das páginas e dos canais de teste continua a ler-se', () {
    idiomaApp.value = Idioma.en;
    expect(passoCarregamento(tr('a pedir os canais · página {0}{1}', [3, '/12'])),
        ('Requesting the channels · page 3/12', .25));
    expect(TelaVerificacao.textoPasso('canal 2/3 · a começar'), 'Testing channel 2 of 3');
    expect(TelaVerificacao.detalhePasso('canal 2/3 · a começar'), 'starting');
    expect(TelaVerificacao.textoPasso('na fila'), 'Queued');
  });

  test('os rótulos das enumerações e das listas fixas também se traduzem', () {
    String em(Idioma i, String Function() f) {
      idiomaApp.value = i;
      return f();
    }

    final pt = <String>[], en = <String>[];
    for (final i in Idioma.values) {
      final l = i == Idioma.pt ? pt : en;
      l.addAll([
        for (final f in FormatoImagem.values) if (f != FormatoImagem.r16x9 && f != FormatoImagem.r4x3 && f != FormatoImagem.zoom) em(i, () => f.rotulo),
        for (final m in ModoDesentrelacamento.values) em(i, () => m.rotulo),
        em(i, () => TamanhoInterface.compacto.rotulo),
        for (final r in RecuoDireto.values) ...[em(i, () => r.rotulo), em(i, () => r.descricao)],
        for (final o in OrdemListas.values) em(i, () => o.explicacao),
        for (final m in ModoDescodificacao.values) em(i, () => m.rotulo),
        for (final a in AcaoLista.values) ...[em(i, () => a.rotulo), em(i, () => a.explicacao)],
        for (final f in FormaLista.values) if (f != FormaLista.xtreamLink) em(i, () => f.nome),
        for (final n in historicoNovidades) for (final t in n.itens) em(i, () => tr(t)),
      ]);
    }
    for (var k = 0; k < pt.length; k++) {
      expect(en[k], isNot(pt[k]), reason: 'sem tradução: ${pt[k]}');
    }
  });

  group('preferência', () {
    late Directory pasta;
    setUp(() => pasta = Directory.systemTemp.createTempSync('idioma'));
    tearDown(() {
      Preferencias.atual = Preferencias.omissao();
      pasta.deleteSync(recursive: true);
    });

    test('grava-se e lê-se; na preferência atual muda logo o idioma da app', () async {
      final p = await Preferencias.abrir(pasta);
      expect(p.idioma, Idioma.pt);
      Preferencias.atual = p;
      p.idioma = Idioma.en;
      expect(idiomaApp.value, Idioma.en);
      await p.guardar();
      final lida = await Preferencias.abrir(pasta);
      expect(lida.idioma, Idioma.en);
      expect(lida.paraJson()['idioma'], 'en');
    });

    test('um valor desconhecido dá o português', () async {
      File('${pasta.path}${Platform.pathSeparator}${Preferencias.nomeFicheiro}').writeAsStringSync('{"idioma":"xx"}');
      expect((await Preferencias.abrir(pasta)).idioma, Idioma.pt);
    });
  });

  testWidgets('nas Definições, «Idioma · Language» › English muda a app inteira sem sair do ecrã', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    late Directory pasta;
    late Biblioteca bib;
    late AreaGestor area;
    await t.runAsync(() async {
      pasta = Directory.systemTemp.createTempSync('idioma_app');
      bib = await Biblioteca.abrir(pasta);
      area = await AreaGestor.abrir(pasta);
      Preferencias.atual = await Preferencias.abrir(pasta);
    });
    addTearDown(() {
      Preferencias.atual = Preferencias.omissao();
      idiomaApp.value = Idioma.pt;
    });
    await t.pumpWidget(AppPlayerIptv(biblioteca: bib, area: area));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Definições').first);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Idioma · Language'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Idioma da aplicação'), findsOneWidget);

    await t.tap(find.text('English'));
    await t.pump(const Duration(milliseconds: 300));
    expect(idiomaApp.value, Idioma.en);
    // o ecrã fica onde estava, já em inglês (também a barra das secções)
    expect(find.text('App language'), findsOneWidget);
    expect(find.text('Language'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Watch TV'), findsWidgets);
    expect(find.text('Definições'), findsNothing);
    expect(find.text('Ver TV'), findsNothing);
    expect(t.widget<MaterialApp>(find.byType(MaterialApp)).locale, const Locale('en', 'US'));

    await t.tap(find.text('Português'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Idioma da aplicação'), findsOneWidget);
    expect(find.text('Ver TV'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });
}
