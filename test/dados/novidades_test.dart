import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/novidades.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('novidades'));
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  test('a versão das novidades é a do pubspec.yaml (junte a entrada ao mudar a versão)', () {
    final linha = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    final versao = linha.split(':').last.trim().split('+').first;
    expect(versaoApp, versao);
    expect(historicoNovidades.map((n) => n.versao).toSet(), hasLength(historicoNovidades.length));
    for (final n in historicoNovidades) {
      expect(n.itens, isNotEmpty, reason: n.versao);
    }
  });

  test('instalação nova: não mostra; depois de atualizar: mostra uma vez', () async {
    expect(await novidadesPorVer(pasta, instalacaoNova: true), isFalse);
    expect(await novidadesPorVer(pasta, instalacaoNova: false), isFalse, reason: 'já registou esta versão');
    // uma versão antiga registada: mostra uma vez
    File('${pasta.path}/$ficheiroNovidadesVistas').writeAsStringSync('1.0.0');
    expect(await novidadesPorVer(pasta, instalacaoNova: true), isTrue);
    expect(await novidadesPorVer(pasta, instalacaoNova: false), isFalse);
  });

  test('quem já tinha listas e ainda não tem registo (atualizou de uma versão sem novidades): mostra', () async {
    expect(await novidadesPorVer(pasta, instalacaoNova: false), isTrue);
    expect(await novidadesPorVer(pasta, instalacaoNova: false), isFalse);
  });

  testWidgets('a casca mostra as novidades ao abrir; "Ver todas" abre o histórico', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Widget casca(bool novidades) => MaterialApp(
          theme: temaApp(),
          builder: (_, c) => TemaConformeRealce(child: c!),
          home: TelaPrincipal(
            novidades: novidades,
            verTv: const Scaffold(body: Text('ver tv')),
            gestor: const SizedBox(),
            definicoes: const SizedBox(),
          ),
        );
    await t.pumpWidget(casca(false));
    await t.pumpAndSettle();
    expect(find.text('Novidades da versão $versaoApp'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(casca(true));
    await t.pumpAndSettle();
    expect(find.text('Novidades da versão $versaoApp'), findsOneWidget);
    expect(find.text(historicoNovidades.first.itens.first), findsOneWidget);
    await t.tap(find.text('Ver todas'));
    await t.pumpAndSettle();
    expect(find.text('Novidades da versão $versaoApp'), findsNothing);
    expect(find.text('Versão $versaoApp'), findsOneWidget);
  });
}
