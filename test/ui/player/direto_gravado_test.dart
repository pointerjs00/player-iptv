import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/direto/gravador.dart';
import 'package:player_iptv/direto/sessao_direto.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/ui/player/barra_progresso.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';
import 'package:player_iptv/ui/player/motor_na_sessao.dart';
import 'package:player_iptv/ui/player/motor_reproducao.dart';
import 'package:player_iptv/ui/player/player_canais.dart';
import 'package:player_iptv/ui/tema.dart';

import '../motor_falso.dart';

final _canais = [
  for (var i = 1; i <= 5; i++) Canal(id: '$i', nome: 'Canal $i', grupo: 'G'),
];

String _origem(Canal c) => 'http://exemplo.invalid/live/utilizador/segredo/${c.id}.ts';

/// Uma sessão sem rede nem servidor: o gravado cresce 1000 bytes por segundo do relógio do teste
/// (10 min já gravados ao abrir) e o "URL local" diz o `desde`.
class _SessaoFalsa implements SessaoDireto {
  _SessaoFalsa(this.agora, this.registo, this.n, {this.pasta});

  final DateTime Function() agora;
  final List<String> registo;
  final int n;
  final Directory? pasta;
  late final DateTime _t0 = agora().subtract(const Duration(minutes: 10));
  final fontes = <FonteVideo>[];
  final recuos = <Duration>[];
  bool fechada = false;
  final _erros = StreamController<ErroGravador>.broadcast();
  final _crescimento = StreamController<int>.broadcast();

  int get fim => agora().difference(_t0).inMilliseconds;

  void erro(ErroGravador e) => _erros.add(e);
  void crescer() => _crescimento.add(fim);

  @override
  Future<Uri?> abrir(FonteVideo fonte) async {
    registo.add('sessao$n: abrir');
    fontes.add(fonte);
    pasta?.createSync(recursive: true);
    return urlDireto;
  }

  @override
  Uri urlDesde(int posicao) => Uri.parse('http://127.0.0.1:4567/codigo$n/direto?desde=$posicao');

  @override
  Uri get urlDireto => urlDesde(posicaoDireto);

  @override
  int get posicaoDireto => posicaoHa(atrasoDireto);

  @override
  int posicaoHa(Duration recuo) {
    recuos.add(recuo);
    return math.max(0, fim - recuo.inMilliseconds);
  }

  @override
  Duration recuoDe(int posicao) => Duration(milliseconds: math.max(0, fim - posicao));

  @override
  Duration get janela => recuoDe(0);

  @override
  Stream<ErroGravador> get erros => _erros.stream;

  @override
  Stream<int> get crescimento => _crescimento.stream;

  @override
  Future<void> fechar() async {
    if (fechada) return;
    fechada = true;
    registo.add('sessao$n: fechar');
    final p = pasta;
    if (p != null && p.existsSync()) p.deleteSync(recursive: true);
    await _erros.close();
    await _crescimento.close();
  }
}

/// O ExoPlayer falso com a janela do HLS.
class _MotorProcura extends MotorFalso implements MotorComProcura {
  _MotorProcura({super.nome, super.registo});

  JanelaMotor? janelaAgora = const JanelaMotor(
      posicao: Duration(seconds: 50), duracao: Duration(seconds: 60), procuravel: true, direto: true);
  final seeks = <Duration>[];

  @override
  Future<JanelaMotor?> janela() async => janelaAgora;

  @override
  Future<void> seekTo(Duration posicao) async => seeks.add(posicao);
}

class _Montagem {
  final registo = <String>[];
  final motores = <MotorFalso>[];
  final sessoes = <_SessaoFalsa>[];
  Directory? pastas;
  String Function(Canal c) url = _origem;

  MotorFalso get motor => motores.last;
  _SessaoFalsa get sessao => sessoes.last;

  Future<void> montar(WidgetTester t, {bool comSessao = true, MotorAndroid motor = MotorAndroid.exoplayer}) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final antes = Preferencias.atual;
    Preferencias.atual = Preferencias.omissao()..motorAndroid = motor;
    addTearDown(() => Preferencias.atual = antes);
    MotorNaSessao.instancia.esquecer();
    addTearDown(MotorNaSessao.instancia.esquecer);
    DateTime agora() => t.binding.clock.now();
    MotorFalso novo(String nome) {
      registo.add('criar $nome');
      final m = _MotorProcura(nome: '$nome${motores.length + 1}', registo: registo);
      motores.add(m);
      return m;
    }

    await t.pumpWidget(MaterialApp(
      theme: temaApp(),
      home: Scaffold(
        body: PlayerCanais(
          canais: _canais,
          indice: 0,
          nomeLista: 'Lista A',
          aoSair: () {},
          plataforma: PlataformaVideo.android,
          agora: agora,
          resolver: (c, {continuar = false}) async => FonteVideo(url(c), const {'User-Agent': 'Teste'}),
          criarMotor: (ModoDescodificacao modo, bool hardware) => novo('mpv'),
          criarMotorExo: ({required bool tunel}) => novo('exo'),
          criarSessao: comSessao
              ? () {
                  final n = sessoes.length + 1;
                  final p = pastas;
                  final s = _SessaoFalsa(agora, registo, n, pasta: p == null ? null : Directory('${p.path}/s$n'));
                  sessoes.add(s);
                  return s;
                }
              : null,
        ),
      ),
    ));
    await _reabrir(t);
  }
}

Future<void> _abrirComImagem(WidgetTester t, MotorFalso m) async {
  m.tamanho(const Size(1920, 1080));
  m.mostrouPrimeiraImagem();
  await t.pump();
}

Future<void> _reabrir(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump();
  }
}

Future<void> _sair(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 5));
}

int _desde(String url) => int.parse(Uri.parse(url).queryParameters['desde']!);

void main() {
  testWidgets('um direto TS abre pela sessão: o motor toca o URL local, sem os cabeçalhos da origem', (t) async {
    final m = _Montagem();
    await m.montar(t);
    expect(m.sessoes, hasLength(1));
    expect(m.sessao.fontes.single.url, _origem(_canais[0]));
    final a = m.motor.aberturas.single;
    expect(a.url, m.sessao.urlDireto.toString());
    expect(a.cabecalhos, isEmpty);
    await _sair(t);
    expect(m.sessao.fechada, isTrue, reason: 'sair fecha a sessão');
  });

  testWidgets('recuar 3 × 10 s reabre o motor no URL com o desde do índice (30 s atrás do direto)', (t) async {
    final m = _Montagem();
    await m.montar(t);
    await _abrirComImagem(t, m.motor);
    for (var i = 0; i < 3; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _reabrir(t);
    }
    final aberturas = m.motor.aberturas;
    expect(aberturas, hasLength(4), reason: 'cada salto é uma reabertura do motor');
    final desde = aberturas.map((a) => _desde(a.url)).toList();
    final fim = m.sessao.fim;
    // o direto local começa 2 s antes do fim; cada recuo põe mais 10 s
    expect(desde, [fim - 2000, fim - 12000, fim - 22000, fim - 32000]);
    for (final a in aberturas) {
      expect(a.url, startsWith('http://127.0.0.1:4567/'));
      expect(a.cabecalhos, isEmpty);
    }
    expect(m.motores, hasLength(1), reason: 'o mesmo motor; nunca o seek no URL local');
    expect(m.sessoes, hasLength(1), reason: 'a mesma sessão');
    await _sair(t);
  });

  testWidgets('voltar ao direto abre o urlDireto da sessão', (t) async {
    final m = _Montagem();
    await m.montar(t);
    await _abrirComImagem(t, m.motor);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _reabrir(t);
    await _abrirComImagem(t, m.motor);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    final voltar = find.text('Voltar ao direto');
    expect(voltar, findsOneWidget);
    expect(find.byType(BarraProgresso), findsOneWidget, reason: 'a barra mostra o gravado também no ExoPlayer');
    await t.tap(voltar);
    await _reabrir(t);
    expect(m.motor.aberturas.last.url, m.sessao.urlDireto.toString());
    expect(m.sessoes, hasLength(1));
    await _sair(t);
  });

  testWidgets('a pausa pausa o motor e não pára o gravador', (t) async {
    final m = _Montagem();
    await m.montar(t);
    await _abrirComImagem(t, m.motor);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Pausa'));
    await t.pump();
    for (var i = 0; i < 5; i++) {
      m.sessao.crescer();
      await t.pump(const Duration(seconds: 1));
    }
    expect(m.motor.pedidos, contains('pausar'));
    expect(m.sessao.fechada, isFalse);
    expect(m.motor.aberturas, hasLength(1), reason: 'a pausa não reabre');
    await _sair(t);
  });

  testWidgets('zapping por 5 canais: uma só sessão aberta e as pastas das outras apagadas', (t) async {
    final tmp = Directory.systemTemp.createTempSync('direto_gravado_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final m = _Montagem()..pastas = tmp;
    await m.montar(t);
    for (var i = 0; i < 4; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _reabrir(t);
    }
    expect(m.sessoes, hasLength(5));
    expect(m.sessoes.where((s) => !s.fechada), hasLength(1));
    expect(m.sessoes.last.fechada, isFalse);
    expect(tmp.listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last), ['s5']);
    // cada sessão fecha antes de a seguinte abrir: nunca duas
    final s = m.registo.where((r) => r.startsWith('sessao')).toList();
    expect(s, [
      'sessao1: abrir', 'sessao1: fechar', 'sessao2: abrir', 'sessao2: fechar', 'sessao3: abrir',
      'sessao3: fechar', 'sessao4: abrir', 'sessao4: fechar', 'sessao5: abrir',
    ]);
    await _sair(t);
    expect(tmp.listSync(), isEmpty);
  });

  testWidgets('HLS não cria sessão e recuar chama o seekTo do ExoPlayer', (t) async {
    final m = _Montagem()..url = (c) => 'https://exemplo.invalid/canal/${c.id}/index.m3u8';
    await m.montar(t);
    expect(m.sessoes, isEmpty);
    expect(m.motor.aberturas.single.url, 'https://exemplo.invalid/canal/1/index.m3u8');
    await _abrirComImagem(t, m.motor);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    await t.pump();
    expect((m.motor as _MotorProcura).seeks, [const Duration(seconds: 40)]);
    expect(m.motor.aberturas, hasLength(1), reason: 'sem reabrir');
    await _sair(t);
  });

  testWidgets('o URL de origem nunca aparece nos erros nem no que o motor abre', (t) async {
    final m = _Montagem();
    await m.montar(t);
    await _abrirComImagem(t, m.motor);
    // um erro de rede do motor no URL local: reabre no gravado (nunca na origem)
    m.motor.erro('Falha a ler ${m.motor.aberturas.single.url}', rede: true);
    await _reabrir(t);
    expect(m.motor.aberturas, hasLength(2));
    // a mensagem de um erro do motor sai sem o URL local (nem o código)
    expect(mensagemErroPlayer('Falha a ler ${m.motor.aberturas.last.url} (rede)'), 'o canal não abriu (Falha a ler (rede))');
    // o gravador desiste: cartão de erro e a sessão fecha
    m.sessao.erro(const ErroGravador(desistiu: true, mensagem: 'o servidor está sempre a cortar a ligação a este canal'));
    await _reabrir(t);
    for (final a in m.motor.aberturas) {
      expect(a.url, isNot(contains('exemplo.invalid')));
      expect(a.url, isNot(contains('segredo')));
    }
    final textos = find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').join('\n');
    expect(textos, isNot(contains('exemplo.invalid')));
    expect(textos, isNot(contains('segredo')));
    expect(textos, isNot(contains('127.0.0.1')));
    expect(textos, isNot(contains('codigo')));
    expect(find.textContaining('o servidor está sempre a cortar'), findsOneWidget);
    expect(m.sessoes.every((s) => s.fechada), isTrue, reason: 'o erro final fecha a sessão');
    expect(m.motor.pedidos, contains('parar'));
    await _sair(t);
  });

  testWidgets('15 s sem crescimento do gravado contam como corte: reabre no URL local', (t) async {
    final m = _Montagem();
    await m.montar(t);
    await _abrirComImagem(t, m.motor);
    m.sessao.crescer();
    await t.pump(const Duration(seconds: 10));
    expect(m.motor.aberturas, hasLength(1), reason: 'ainda dentro do limite');
    await t.pump(const Duration(seconds: 6));
    await _reabrir(t);
    expect(m.motor.aberturas, hasLength(2));
    expect(m.motor.aberturas.last.url, startsWith('http://127.0.0.1:4567/codigo1/'));
    expect(m.sessoes, hasLength(1), reason: 'o gravador religa sozinho: a mesma sessão');
    await _sair(t);
  });

  testWidgets('sem sessão (null) fica tudo como antes: a origem no motor', (t) async {
    final m = _Montagem();
    await m.montar(t, comSessao: false);
    expect(m.motor.aberturas.single.url, _origem(_canais[0]));
    expect(m.motor.aberturas.single.cabecalhos, {'User-Agent': 'Teste'});
    await _sair(t);
  });

  testWidgets('o recurso ao mpv continua a mesma sessão e o mpv abre o URL local', (t) async {
    final m = _Montagem();
    await m.montar(t);
    m.motor.erro('formato', formato: true);
    await _reabrir(t);
    expect(m.motores.map((e) => e.nome), ['exo1', 'mpv2']);
    expect(m.sessoes, hasLength(1));
    expect(m.sessao.fechada, isFalse);
    expect(m.motor.aberturas.single.url, startsWith('http://127.0.0.1:4567/codigo1/'));
    await _sair(t);
  });
}
