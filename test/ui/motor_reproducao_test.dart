import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';
import 'package:player_iptv/ui/player/motor_reproducao.dart';
import 'package:player_iptv/ui/player/player_canais.dart';
import 'package:player_iptv/ui/tema.dart';

/// Um motor sem rede nem mpv: regista o que o player lhe pede e deixa o teste mandar eventos.
class MotorFalso implements MotorReproducao {
  final aberturas = <({String url, Map<String, String> cabecalhos, Duration? inicio})>[];
  final pedidos = <String>[];
  final audios = <FaixaMotor>[];
  bool descartado = false;

  final _erros = StreamController<ErroMotor>.broadcast();
  final _aCarregar = StreamController<bool>.broadcast();
  final _percentagem = StreamController<double>.broadcast();
  final _tamanho = StreamController<Size?>.broadcast();
  final _posicao = StreamController<Duration>.broadcast();
  final _fim = StreamController<void>.broadcast();
  final _faixas = StreamController<FaixasMotor>.broadcast();
  final _faixaAtual = StreamController<FaixaAtual>.broadcast();

  void erro(String e, {bool formato = false}) => _erros.add(ErroMotor(e, formato: formato));
  void carregar(bool b) => _aCarregar.add(b);
  void percentagem(double p) => _percentagem.add(p);
  void tamanho(Size? s) => _tamanho.add(s);
  void tempo(Duration p) => _posicao.add(p);
  void mudarFaixas(FaixasMotor f) => _faixas.add(f);
  void mudarFaixaAtual(FaixaAtual f) => _faixaAtual.add(f);

  @override
  String get nome => 'falso';
  @override
  bool get suportaDesentrelacamento => false;
  @override
  Stream<ErroMotor> get erros => _erros.stream;
  @override
  Stream<bool> get aCarregar => _aCarregar.stream;
  @override
  Stream<double> get percentagemCarga => _percentagem.stream;
  @override
  Stream<Size?> get tamanhoVideo => _tamanho.stream;
  @override
  Stream<Duration> get posicao => _posicao.stream;
  @override
  Stream<void> get fim => _fim.stream;
  @override
  Stream<FaixasMotor> get faixas => _faixas.stream;
  @override
  Stream<FaixaAtual> get faixaAtual => _faixaAtual.stream;

  @override
  Future<void> abrir(String url, Map<String, String> cabecalhos, {Duration? inicio}) async =>
      aberturas.add((url: url, cabecalhos: cabecalhos, inicio: inicio));
  @override
  Future<void> play() async => pedidos.add('play');
  @override
  Future<void> pausar() async => pedidos.add('pausar');
  @override
  Future<void> parar() async => pedidos.add('parar');
  @override
  Future<void> escolherAudio(FaixaMotor faixa) async => audios.add(faixa);
  @override
  Future<void> escolherLegenda(FaixaMotor? faixa) async => pedidos.add('legenda ${faixa?.id}');
  @override
  Future<void> velocidade(double v) async => pedidos.add('velocidade $v');
  @override
  Future<void> volume(double v) async => pedidos.add('volume $v');
  @override
  Future<EstatisticasMotor> estatisticas() async => const EstatisticasMotor();
  @override
  Widget video({required BoxFit ajuste, double? proporcao}) => const ColoredBox(color: Colors.black);
  @override
  Future<void> descartar() async => descartado = true;
}

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

  testWidgets('um erro de formato chega ao ecrã (por agora como um erro normal)', (t) async {
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
