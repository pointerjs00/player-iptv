import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';
import 'package:player_iptv/ui/player/motor_reproducao.dart';
import 'package:player_iptv/ui/player/player_canais.dart';
import 'package:player_iptv/ui/tema.dart';

import 'motor_falso.dart';

const _canal = Canal(id: '1', nome: 'RTP 1', grupo: 'Generalistas');

Future<MotorFalso> _montar(WidgetTester t) async {
  t.view.physicalSize = const Size(1920, 1080);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final motor = MotorFalso();
  final criados = <MotorFalso>[];
  await t.pumpWidget(MaterialApp(
    theme: temaApp(),
    home: Scaffold(
      body: PlayerCanais(
        canais: const [_canal],
        indice: 0,
        nomeLista: 'Lista A',
        aoSair: () {},
        resolver: (c, {continuar = false}) async =>
            const FonteVideo('http://exemplo.invalido/canal.ts', {'User-Agent': 'Teste'}),
        criarMotor: (ModoDescodificacao modo, bool hardware) {
          criados.add(motor);
          return motor;
        },
      ),
    ),
  ));
  await t.pump();
  await t.pump();
  expect(criados, hasLength(1), reason: 'o player cria o motor pela fábrica injetada');
  return motor;
}

/// O canal dá imagem e a posição anda: o vigia conta-o como aberto.
Future<void> _abrirComImagem(WidgetTester t, MotorFalso m) async {
  m.tamanho(const Size(1920, 1080));
  await t.pump();
  m.tempo(Duration.zero);
  await t.pump();
  m.tempo(const Duration(milliseconds: 500));
  await t.pump();
}

Future<void> _sair(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('abre o canal pelo motor injetado, com o link e os cabeçalhos', (t) async {
    final m = await _montar(t);
    expect(m.aberturas, hasLength(1));
    expect(m.aberturas.single.url, 'http://exemplo.invalido/canal.ts');
    expect(m.aberturas.single.cabecalhos, {'User-Agent': 'Teste'});
    expect(m.aberturas.single.inicio, isNull);
    // o indicador de abertura fica até à primeira imagem
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _abrirComImagem(t, m);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await _sair(t);
    expect(m.descartado, isTrue, reason: 'ao sair o motor é largado');
  });

  testWidgets('um erro do motor mostra o cartão de erro, sem o link', (t) async {
    final m = await _montar(t);
    m.erro('Failed to open http://exemplo.invalido/canal.ts');
    await t.pump();
    expect(find.textContaining('RTP 1: o canal não abriu'), findsOneWidget);
    expect(find.textContaining('exemplo.invalido'), findsNothing);
    expect(find.text('Tentar de novo'), findsOneWidget);
    await _sair(t);
  });

  testWidgets('no mpv um erro de formato é um erro como os outros (não há outro motor)', (t) async {
    final m = await _montar(t);
    m.erro('Unsupported codec', formato: true);
    await t.pump();
    expect(find.text('RTP 1: o canal não abriu (Unsupported codec)'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await _sair(t);
  });

  testWidgets('aCarregar a meio do canal mostra "A carregar…" com a percentagem', (t) async {
    final m = await _montar(t);
    await _abrirComImagem(t, m);
    m.percentagem(45);
    m.carregar(true);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('A carregar… 45%'), findsOneWidget);
    m.carregar(false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('A carregar'), findsNothing);
    await _sair(t);
  });

  testWidgets('as faixas do motor chegam ao painel e a escolha volta ao motor', (t) async {
    final m = await _montar(t);
    await _abrirComImagem(t, m);
    m.mudarFaixas(const FaixasMotor(audio: [
      FaixaMotor.auto,
      FaixaMotor('1', lingua: 'por', codec: 'aac'),
      FaixaMotor('2', lingua: 'eng', codec: 'ac3'),
    ]));
    m.mudarFaixaAtual(const FaixaAtual(audio: FaixaMotor('2', lingua: 'eng', codec: 'ac3')));
    await t.pump();
    // a barra e o painel de definições
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Definições'));
    await t.pumpAndSettle();
    expect(find.text('Faixa de áudio'), findsOneWidget);
    expect(find.text('Inglês · AC3'), findsOneWidget);
    // carregar na faixa de áudio passa à opção seguinte (depois da última volta a "Automática")
    await t.tap(find.text('Inglês · AC3'));
    await t.pumpAndSettle();
    expect(m.audios.map((f) => f.id), ['auto']);
    await _sair(t);
  });
}
