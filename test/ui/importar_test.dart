import 'dart:async';
import 'dart:io';

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
import 'package:player_iptv/ui/gestor/indicador_atividade.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/ui/tema.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';

import '../apoio/servidor_falso.dart';

/// Um verificador que nunca acaba: a fila vê-se, sem tocar na rede.
class _Preso extends Verificador {
  final _nunca = Completer<void>();

  @override
  Future<ResultadoVerificacao> verificarComLimite(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso}) async {
    await _nunca.future;
    return const ResultadoVerificacao(EstadoV.funciona, 'ok');
  }
}

void main() {
  late Directory pasta;
  late Biblioteca bib;
  late AreaGestor area;
  late ServicoTarefas tarefas;
  late ServicoVerificacao servico;
  ServidorFalso? srv;
  ServerSocket? calado;
  final ligacoes = <Socket>[];
  final hoje = DateTime.now();
  final slug = '${hoje.day}-${hoje.month}-${hoje.year}';

  setUp(() {
    pasta = Directory.systemTemp.createTempSync('importar');
    srv = null;
    calado = null;
  });

  tearDown(() async {
    await srv?.parar();
    for (final c in ligacoes) {
      c.destroy();
    }
    ligacoes.clear();
    await calado?.close();
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  /// O Gestor aberto no sub-ecrã de importar. `base` é o blog falso.
  Future<void> abrir(WidgetTester t, {required String Function() base}) async {
    HttpOverrides.global = null; // o binding de testes bloqueia a rede (só o servidor local)
    t.view.physicalSize = const Size(1200, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      bib = await Biblioteca.abrir(pasta);
      area = await AreaGestor.abrir(pasta);
    });
    tarefas = ServicoTarefas();
    servico = ServicoVerificacao(bib, colecao: area, verificador: _Preso());
    addTearDown(tarefas.dispose);
    await t.pumpWidget(MaterialApp(
        theme: temaApp(),
        home: Scaffold(
            body: TelaGestor(
                biblioteca: bib, area: area, servico: servico, tarefas: tarefas, baseStb: base()))));
    await t.pump();
    await abrirImportar(t);
  }

  Future<void> blogFalso(WidgetTester t) async {
    srv = ServidorFalso((p) => switch (p.uri.path) {
          '/' => (200, '<a href="/${hoje.year}/01/stb-$slug.html">a</a>'),
          _ => (200, '<p>http://portal.exemplo/c/</p><p>00:1A:79:00:00:01<br/>00:1A:79:00:00:02</p>'),
        });
    await t.runAsync(srv!.iniciar);
  }

  /// Um blog que aceita a ligação e nunca responde: a pesquisa fica a decorrer.
  Future<void> blogCalado(WidgetTester t) async {
    await t.runAsync(() async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      s.listen(ligacoes.add); // guarda-as: uma ligação sem dono é fechada
      calado = s;
    });
  }

  Future<void> esperar(WidgetTester t, [int ms = 800]) async {
    await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await t.pump();
    await t.pump();
  }

  Future<void> procurar(WidgetTester t) async {
    await t.runAsync(() async {
      await t.tap(find.text('Procurar e juntar'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await t.pump();
  }

  /// O campo é só de leitura até se carregar nele (comando da TV): toca-se e depois escreve-se.
  Future<void> colar(WidgetTester t, String texto) async {
    await t.tap(find.byType(TextField));
    await t.pump();
    await t.pump();
    await t.enterText(find.byType(TextField), texto);
  }

  Future<void> escolherStb(WidgetTester t) async {
    await t.tap(find.text('Listas do stbstalker'));
    await t.pump();
  }

  group('ecrã de importar', () {
    testWidgets('mostra as 4 origens com os subtítulos aprovados e o painel da escolhida', (t) async {
      await abrir(t, base: () => 'http://127.0.0.1:1/');
      await t.runAsync(() => bib.adicionar([
            Importada(contaDeLinha('http://a.com/l.m3u')!),
            Importada(contaDeLinha('http://b.com/l.m3u')!),
          ]));
      await t.pump();
      for (final x in [
        'Ficheiros',
        'Accounts.json, .ini, .m3u, .txt',
        'Colar texto',
        'Uma lista por linha',
        'Listas do stbstalker',
        'Publicadas entre duas datas',
        'Do Player',
        'As 2 listas que já tens',
      ]) {
        // "Ficheiros" também é o título do painel da origem escolhida por omissão
        expect(find.text(x), x == 'Ficheiros' ? findsNWidgets(2) : findsOneWidget, reason: x);
      }
      expect(find.text('Resultado'), findsNothing, reason: 'sem importações ainda');
      await escolherStb(t);
      expect(find.text('Junta as listas publicadas no blog entre duas datas, sem duplicar.'), findsOneWidget);
    });

    testWidgets('Colar texto: cria uma tarefa e o resultado mostra os números', (t) async {
      await abrir(t, base: () => 'http://127.0.0.1:1/');
      await t.tap(find.text('Colar texto'));
      await t.pump();
      await colar(t, 'http://x.com/l.m3u\nhttp://y.com/l.m3u\nhttp://x.com/l.m3u');
      await t.runAsync(() async {
        await t.tap(find.text('Juntar ao Gestor'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await t.pump();
      await t.pump();
      expect(area.listas, hasLength(2));
      final tarefa = tarefas.recentes.single;
      expect(tarefa.estado, EstadoTarefa.terminada);
      expect(tarefa.titulo, 'Importar texto colado');
      expect(tarefa.resultado, '2 listas novas, 1 já existia.');
      expect(find.text('Encontradas'), findsOneWidget);
      expect(find.text('Novas no Gestor'), findsOneWidget);
      expect(find.text('Já estavam no Gestor'), findsOneWidget);
      expect(find.text('Verificar as 2 novas'), findsOneWidget);
    });

    testWidgets('Do Player: só as listas que o Gestor ainda não tinha contam como novas', (t) async {
      await abrir(t, base: () => 'http://127.0.0.1:1/');
      await t.runAsync(() async {
        await bib.adicionar([
          Importada(contaDeLinha('http://a.com/l.m3u')!),
          Importada(contaDeLinha('http://b.com/l.m3u')!),
        ]);
        await area.adicionar([Importada(contaDeLinha('http://a.com/l.m3u')!)]);
      });
      await t.pump();
      await t.tap(find.text('Do Player'));
      await t.pump();
      await t.runAsync(() async {
        await t.tap(find.text('Importar do Player'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await t.pump();
      await t.pump();
      expect(area.listas, hasLength(2));
      expect(find.text('Verificar a 1 nova'), findsOneWidget);
    });

    testWidgets('Verificar as n novas junta só as novas à fila', (t) async {
      await abrir(t, base: () => 'http://127.0.0.1:1/');
      await t.runAsync(() => area.adicionar([Importada(contaDeLinha('http://antiga.com/l.m3u')!)]));
      await t.pump();
      await t.tap(find.text('Colar texto'));
      await t.pump();
      await colar(t, 'http://antiga.com/l.m3u\nhttp://nova1.com/l.m3u\nhttp://nova2.com/l.m3u');
      await t.runAsync(() async {
        await t.tap(find.text('Juntar ao Gestor'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await t.pump();
      await t.pump();
      final novas = [for (final l in area.listas) if (!l.conta.endereco.contains('antiga')) l];
      expect(novas, hasLength(2));
      expect(find.text('Verificar as 2 novas'), findsOneWidget);
      await t.runAsync(() async {
        await t.tap(find.text('Verificar as 2 novas'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pump();
      expect(servico.passos.keys.toSet(), {for (final l in novas) l.id});
      expect(servico.total, 2, reason: 'a antiga não entrou na fila');
    });
  });

  group('stbstalker em segundo plano', () {
    testWidgets('Procurar e juntar cria uma tarefa, devolve logo o foco e no fim mostra os números', (t) async {
      await blogFalso(t);
      await abrir(t, base: () => '${srv!.url}/');
      await escolherStb(t);
      await procurar(t);
      await esperar(t);
      expect(area.listas, hasLength(2));
      expect(bib.listas, isEmpty);
      final tarefa = tarefas.recentes.single;
      expect(tarefa.estado, EstadoTarefa.terminada);
      expect(tarefa.titulo, startsWith(tituloTarefaStb));
      expect(tarefa.resultado, '2 listas novas.');
      expect(find.text('Novas no Gestor'), findsOneWidget);
      expect(find.text('Verificar as 2 novas'), findsOneWidget);
      // o botão ficou sempre ligado
      expect((t.widget(find.widgetWithText(FilledButton, 'Procurar e juntar')) as FilledButton).onPressed,
          isNotNull);
    });

    testWidgets('sair e voltar com a pesquisa a decorrer: o painel mostra o progresso; outro clique inicia '
        'outra tarefa', (t) async {
      await blogCalado(t);
      await abrir(t, base: () => 'http://127.0.0.1:${calado!.port}/');
      await escolherStb(t);
      await procurar(t);
      expect(tarefas.emCurso, hasLength(1));
      expect(find.text('Resultado'), findsOneWidget);
      expect(find.textContaining('A importar'), findsOneWidget);
      expect(find.text('stbstalker: a procurar os posts · 1 tarefa a decorrer'), findsOneWidget);
      // sai para o ecrã principal do Gestor e volta
      await t.tap(find.widgetWithText(TextButton, 'Voltar'));
      await t.pumpAndSettle();
      expect(find.text('Resultado'), findsNothing);
      // (o progresso sem fim anima sempre: sem pumpAndSettle)
      await t.tap(find.descendant(of: find.byType(CartaoModerno), matching: find.text('Importar')));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Resultado'), findsOneWidget);
      expect(find.textContaining('A importar'), findsOneWidget);
      // carregar outra vez não é ignorado
      await procurar(t);
      expect(tarefas.emCurso, hasLength(2));
      expect(find.text('stbstalker: a procurar os posts · 2 tarefas a decorrer'), findsOneWidget);
    });

    testWidgets('Parar a meio da pesquisa: não junta mais listas e a tarefa acaba cancelada', (t) async {
      // o blog tem 2 posts; o 1.º só responde quando o teste deixar
      final pedidos = <String>[];
      final porta = Completer<void>();
      late HttpServer blog;
      await t.runAsync(() async {
        blog = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        blog.listen((p) async {
          pedidos.add(p.uri.path);
          if (p.uri.path == '/') {
            p.response.write('<a href="/${hoje.year}/01/a-$slug.html">a</a> <a href="/${hoje.year}/01/b-$slug.html">b</a>');
          } else {
            if (p.uri.path.contains('/a-')) await porta.future;
            p.response.write('<p>http://portal.exemplo/c/</p><p>00:1A:79:00:00:0${p.uri.path.contains('/a-') ? 1 : 2}</p>');
          }
          await p.response.close();
        });
      });
      addTearDown(() => blog.close(force: true));
      await abrir(t, base: () => 'http://127.0.0.1:${blog.port}/');
      await escolherStb(t);
      await procurar(t);
      for (var i = 0; i < 50 && pedidos.length < 2; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      expect(pedidos, hasLength(2), reason: 'a página e o 1.º post');
      final tarefa = tarefas.emCurso.single;
      expect(tarefa.cancelavel, isTrue);
      tarefas.cancelar(tarefa.id); // o "Parar" do painel
      await t.runAsync(() async => porta.complete());
      await esperar(t);
      expect(tarefa.estado, EstadoTarefa.cancelada);
      expect(area.listas, isEmpty, reason: 'nenhuma lista entrou no Gestor');
      expect(pedidos, hasLength(2), reason: 'o 2.º post já não foi lido');
      expect(tarefa.resultado, 'Pesquisa parada. Nenhuma lista foi junta ao Gestor.');
    });

    testWidgets('blog que corta a ligação: a tarefa falha e o painel diz o motivo em português, sem o link',
        (t) async {
      await t.runAsync(() async {
        final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        s.listen((c) => c.destroy());
        calado = s;
      });
      await abrir(t, base: () => 'http://127.0.0.1:${calado!.port}/');
      await escolherStb(t);
      await procurar(t);
      await esperar(t);
      final tarefa = tarefas.recentes.single;
      expect(tarefa.estado, EstadoTarefa.falhou);
      expect(find.text('Com erro (Não foi possível pesquisar: a ligação foi cortada pelo servidor)'),
          findsOneWidget);
      expect(find.textContaining('http'), findsNothing);
    });

    testWidgets('sem posts nessas datas: terminada, com o motivo no painel', (t) async {
      srv = ServidorFalso((p) => (200, '<html></html>'));
      await t.runAsync(srv!.iniciar);
      await abrir(t, base: () => '${srv!.url}/');
      await escolherStb(t);
      await procurar(t);
      await esperar(t);
      expect(tarefas.recentes.single.estado, EstadoTarefa.terminada);
      expect(find.textContaining('Com erro (Nenhum post publicado'), findsOneWidget);
      expect(find.textContaining('Verificar a'), findsNothing);
      expect(find.textContaining('novas'), findsNothing);
    });
  });

  group('ResumoImportacao e indicador', () {
    test('texto do resumo', () {
      expect(ResumoImportacao(encontradas: 3, novas: 2, repetidas: 1).texto, '2 listas novas, 1 já existia.');
      expect(ResumoImportacao(encontradas: 1, novas: 1).texto, '1 lista nova.');
      expect(ResumoImportacao(erros: const ['x']).texto, 'x');
    });

    test('importarTexto devolve os ids das novas', () async {
      final b = await AreaGestor.abrir(pasta);
      await b.adicionar([Importada(contaDeLinha('http://a.com/l.m3u')!)]);
      final r = await importarTexto(b, 'http://a.com/l.m3u\nhttp://b.com/l.m3u');
      expect((r.encontradas, r.novas, r.repetidas), (2, 1, 1));
      expect(r.idsNovas, [b.listas.last.id]);
    });

    testWidgets('o indicador junta a pesquisa do stbstalker', (t) async {
      final ts = ServicoTarefas();
      addTearDown(ts.dispose);
      final fim = Completer<String>();
      Progresso? prog;
      ts.iniciar('$tituloTarefaStb · hoje', (p) {
        prog = p;
        p(0.5, '24 encontradas');
        return fim.future;
      });
      final b = await t.runAsync(() => Biblioteca.abrir(pasta));
      final s = ServicoVerificacao(b!);
      expect(IndicadorAtividade.texto(s, ts), 'stbstalker: 24 encontradas · 1 tarefa a decorrer');
      expect(prog, isNotNull);
      fim.complete('ok');
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      expect(IndicadorAtividade.texto(s, ts), '');
    });
  });
}

/// Abre o passo 1 do Gestor.
Future<void> abrirImportar(WidgetTester t) async {
  await t.tap(find.descendant(of: find.byType(CartaoModerno), matching: find.text('Importar')));
  await t.pumpAndSettle();
}
