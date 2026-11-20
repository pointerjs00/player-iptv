import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

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
  _SessaoFalsa(this.agora, this.registo, this.n, {this.pasta, this.memoria = false});

  final DateTime Function() agora;
  final List<String> registo;
  final int n;
  final Directory? pasta;

  /// Criada para gravar em memória.
  final bool memoria;
  late final DateTime _t0 = agora().subtract(const Duration(minutes: 10));
  final fontes = <FonteVideo>[];
  Future<FonteVideo> Function()? renovar;

  /// Se dado, o `abrir` só acaba quando isto acabar (a sessão a meio do arranque).
  Future<void>? espera;

  /// O stream não é MPEG-TS: `abrir` dá null.
  bool naoServe = false;

  @override
  String? aviso;
  @override
  bool ligouOrigem = false;
  final recuos = <Duration>[];
  bool fechada = false;
  final _erros = StreamController<ErroGravador>.broadcast();
  final _crescimento = StreamController<int>.broadcast();

  int get fim => agora().difference(_t0).inMilliseconds;

  void erro(ErroGravador e) {
    if (!_erros.isClosed) _erros.add(e);
  }

  void crescer() {
    if (!_crescimento.isClosed) _crescimento.add(fim);
  }

  @override
  Future<Uri?> abrir(FonteVideo fonte, {Future<FonteVideo> Function()? renovar}) async {
    registo.add('sessao$n: abrir');
    fontes.add(fonte);
    this.renovar = renovar;
    pasta?.createSync(recursive: true);
    final e = espera;
    if (e != null) await e;
    ligouOrigem = true;
    if (fechada || naoServe) return null;
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

  /// Aplicado a cada sessão criada (antes de abrir).
  void Function(_SessaoFalsa s)? preparar;

  /// Os motores mandam a posição 0 ao parar (como o mpv).
  bool zeroAoParar = false;


  MotorFalso get motor => motores.last;
  _SessaoFalsa get sessao => sessoes.last;

  Future<void> montar(WidgetTester t,
      {bool comSessao = true,
      MotorAndroid motor = MotorAndroid.exoplayer,
      RecuoDireto recuo = RecuoDireto.armazenamento}) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final antes = Preferencias.atual;
    Preferencias.atual = Preferencias.omissao()
      ..motorAndroid = motor
      ..recuoDireto = recuo;
    addTearDown(() => Preferencias.atual = antes);
    MotorNaSessao.instancia.esquecer();
    addTearDown(MotorNaSessao.instancia.esquecer);
    DateTime agora() => t.binding.clock.now();
    MotorFalso novo(String nome) {
      registo.add('criar $nome');
      final m = _MotorProcura(nome: '$nome${motores.length + 1}', registo: registo)..zeroAoParar = zeroAoParar;
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
          resolver: (c, {continuar = false}) async {
            registo.add('resolver ${c.id} continuar=$continuar');
            return FonteVideo(url(c), const {'User-Agent': 'Teste'});
          },
          criarMotor: (ModoDescodificacao modo, bool hardware) => novo('mpv'),
          criarMotorExo: ({required bool tunel}) => novo('exo'),
          criarSessao: comSessao
              ? ({required bool memoria}) {
                  final n = sessoes.length + 1;
                  final p = pastas;
                  registo.add('criar sessao$n memoria=$memoria');
                  final s = _SessaoFalsa(agora, registo, n,
                      pasta: p == null ? null : Directory('${p.path}/s$n'), memoria: memoria);
                  preparar?.call(s);
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

/// A app vai para segundo plano (Home, ou a proteção de ecrã do Fire TV) e volta.
Future<void> _paraOFundo(WidgetTester t) async {
  addTearDown(() => t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  for (final e in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    t.binding.handleAppLifecycleStateChanged(e);
  }
  await _reabrir(t);
}

Future<void> _voltar(WidgetTester t) async {
  for (final e in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    t.binding.handleAppLifecycleStateChanged(e);
  }
  await _reabrir(t);
}

int _desde(String url) => int.parse(Uri.parse(url).queryParameters['desde']!);

/// Toca `segundos` com o gravado a crescer (o relógio do teste anda; a posição do motor também).
Future<void> _tocar(WidgetTester t, _Montagem m, int segundos) async {
  for (var i = 1; i <= segundos; i++) {
    await t.pump(const Duration(seconds: 1));
    m.sessao.crescer();
    m.motor.tempo(Duration(seconds: i));
  }
  await t.pump();
}

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

  testWidgets('o ExoPlayer encravado a carregar com o gravado a crescer: 15 s depois reabre no URL local',
      (t) async {
    final m = _Montagem();
    await m.montar(t);
    await _abrirComImagem(t, m.motor);
    m.motor.carregar(true);
    for (var i = 0; i < 14; i++) {
      await t.pump(const Duration(seconds: 1));
      m.sessao.crescer();
    }
    expect(m.motor.aberturas, hasLength(1), reason: 'ainda dentro do limite');
    for (var i = 0; i < 2; i++) {
      await t.pump(const Duration(seconds: 1));
      m.sessao.crescer();
    }
    await _reabrir(t);
    expect(m.motor.aberturas, hasLength(2), reason: 'a rodinha não fica para sempre');
    expect(m.motor.aberturas.last.url, startsWith('http://127.0.0.1:4567/codigo1/'));
    expect(m.sessoes, hasLength(1), reason: 'a mesma sessão');
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

  for (final zero in [false, true]) {
    final como = zero ? ' (a posição vai a 0 no parar, como no mpv)' : '';
    testWidgets('um corte aos 40 s de reprodução reabre no ponto dos 40 s$como', (t) async {
      final m = _Montagem()..zeroAoParar = zero;
      await m.montar(t);
      await _abrirComImagem(t, m.motor);
      await _tocar(t, m, 40);
      expect(m.motor.aberturas, hasLength(1));
      // a reprodução está 2 s atrás do fim (o direto local), como quando abriu
      final esperado = m.sessao.fim - 2000;
      m.motor.erro('a ligação caiu', rede: true);
      await _reabrir(t);
      expect(m.motor.aberturas, hasLength(2));
      expect(_desde(m.motor.aberturas.last.url), esperado);
      // e outro corte logo a seguir (sem nada tocado) fica no mesmo ponto
      await _abrirComImagem(t, m.motor);
      m.motor.erro('a ligação caiu outra vez', rede: true);
      await _reabrir(t);
      expect(_desde(m.motor.aberturas.last.url), esperado);
      await _sair(t);
    });

    testWidgets('dois «recuar 10 s» seguidos dão −20 s$como', (t) async {
      final m = _Montagem()..zeroAoParar = zero;
      await m.montar(t);
      await _abrirComImagem(t, m.motor);
      await _tocar(t, m, 30);
      final fim = m.sessao.fim;
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _reabrir(t);
      expect(_desde(m.motor.aberturas.last.url), fim - 22000, reason: '20 s atrás do direto local (2 s antes do fim)');
      // tocar 5 s não muda o atraso; um terceiro recuo dá −30 s
      await _abrirComImagem(t, m.motor);
      await _tocar(t, m, 5);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _reabrir(t);
      expect(_desde(m.motor.aberturas.last.url), m.sessao.fim - 32000);
      await _sair(t);
    });
  }

  testWidgets('no zapping, um erro atrasado do canal anterior não põe cartão no canal novo', (t) async {
    final m = _Montagem();
    await m.montar(t);
    await _abrirComImagem(t, m.motor);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    // o servidor local do canal 1 cortou a ligação ao motor: o erro chega já com o canal 2 a abrir
    // (depois de o motor abrir o canal 2, o MotorExo já larga os eventos da sessão anterior)
    m.motor.erro('Source error: HttpDataSourceException');
    m.motor.erro('Source error: HttpDataSourceException', rede: true);
    await _reabrir(t);
    expect(find.textContaining('o canal não abriu'), findsNothing);
    expect(m.sessoes, hasLength(2));
    expect(m.sessoes.first.fechada, isTrue);
    expect(m.sessoes.last.fechada, isFalse, reason: 'a sessão nova fica aberta');
    expect(m.motor.aberturas.last.url, startsWith('http://127.0.0.1:4567/codigo2/'));
    // o motor parou antes de a sessão anterior fechar
    expect(m.registo.indexOf('exo1: parou'), lessThan(m.registo.indexOf('sessao1: fechar')));
    await _sair(t);
  });

  testWidgets('zapping rápido com as sessões a meio do arranque: só a última fica aberta', (t) async {
    final m = _Montagem();
    await m.montar(t);
    final espera = Completer<void>();
    m.preparar = (s) => s.espera = espera.future;
    for (var i = 0; i < 3; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
    }
    espera.complete();
    await _reabrir(t);
    final abertas = m.sessoes.where((s) => !s.fechada).toList();
    expect(abertas, hasLength(1));
    expect(abertas.single, same(m.sessoes.last));
    expect(abertas.single.fontes.single.url, _origem(_canais[3]));
    expect(m.motor.aberturas.last.url, abertas.single.urlDireto.toString());
    await _sair(t);
    expect(m.sessoes.every((s) => s.fechada), isTrue);
  });

  testWidgets('quando a gravação não serve, a sessão fecha antes de o motor abrir a origem (link novo)', (t) async {
    final m = _Montagem()..preparar = (s) => s.naoServe = true;
    await m.montar(t);
    final fechou = m.registo.indexOf('sessao1: fechar');
    final pediu = m.registo.indexOf('resolver 1 continuar=true');
    final abriu = m.registo.lastIndexOf('exo1: abrir');
    expect(fechou, greaterThan(m.registo.indexOf('sessao1: abrir')));
    expect(pediu, greaterThan(fechou));
    expect(abriu, greaterThan(pediu));
    expect(m.motor.aberturas.single.url, _origem(_canais[0]));
    await _sair(t);
  });

  testWidgets('o gravador recebe como renovar o link: pede-o de novo ao resolver (Stalker)', (t) async {
    final m = _Montagem();
    await m.montar(t);
    final renovar = m.sessao.renovar;
    expect(renovar, isNotNull);
    final f = await renovar!();
    expect(f.url, _origem(_canais[0]));
    expect(m.registo.last, 'resolver 1 continuar=true');
    await _sair(t);
  });

  group('espaço e modos do recuo', () {
    testWidgets('a reserva baixou por falta de espaço: o player diz com quanto fica o recuo', (t) async {
      final m = _Montagem()..preparar = (s) => s.aviso = 'Pouco espaço: o recuo fica com 700 MB';
      await m.montar(t);
      expect(find.text('Pouco espaço: o recuo fica com 700 MB'), findsOneWidget);
      expect(m.motor.aberturas.single.url, startsWith('http://127.0.0.1:4567/codigo1/'), reason: 'grava na mesma');
      await t.pump(const Duration(seconds: 5));
      expect(find.text('Pouco espaço: o recuo fica com 700 MB'), findsNothing);
      await _sair(t);
    });

    testWidgets('o espaço acaba a meio: avisa e o canal passa a uma sessão em memória (uma só ligação)',
        (t) async {
      final m = _Montagem();
      await m.montar(t);
      await _abrirComImagem(t, m.motor);
      m.registo.clear();
      m.sessao.erro(const ErroGravador(
          desistiu: true, semEspaco: true, mensagem: 'não há espaço no armazenamento para continuar a gravar'));
      await _reabrir(t);
      expect(find.text('Pouco espaço: o recuo fica em memória (cerca de 2 min em HD)'), findsOneWidget);
      expect(find.textContaining('não há espaço'), findsNothing, reason: 'não é o cartão de erro');
      expect(m.sessoes, hasLength(2));
      expect(m.sessoes.first.fechada, isTrue);
      expect(m.sessao.memoria, isTrue);
      final r = m.registo;
      final parou = r.indexOf('exo1: parou');
      final fechou = r.indexOf('sessao1: fechar');
      final pediu = r.indexOf('resolver 1 continuar=true');
      final criou = r.indexOf('criar sessao2 memoria=true');
      final abriu = r.lastIndexOf('exo1: abrir');
      expect(parou, greaterThanOrEqualTo(0));
      expect(fechou, greaterThan(parou), reason: 'o motor larga o URL local antes de a sessão fechar');
      expect(pediu, greaterThan(fechou), reason: 'o gravador já largou a origem');
      expect(criou, greaterThan(pediu));
      expect(abriu, greaterThan(criou));
      expect(m.motor.aberturas.last.url, startsWith('http://127.0.0.1:4567/codigo2/'), reason: 'o recuo continua');
      // um corte do mesmo canal continua na sessão em memória
      m.motor.erro('Falha a ler', rede: true);
      await _reabrir(t);
      expect(m.sessoes, hasLength(2));
      // outro canal volta ao disco
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _reabrir(t);
      expect(m.sessoes, hasLength(3));
      expect(m.sessao.memoria, isFalse);
      await _sair(t);
    });

    testWidgets('o espaço acaba a meio de um zapping: não reabre o canal antigo nem estraga o novo', (t) async {
      final m = _Montagem();
      await m.montar(t);
      await _abrirComImagem(t, m.motor);
      final antiga = m.sessao;
      final solta = Completer<void>();
      m.motor.pararDemora = solta.future;
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp); // o _abrir do canal 2 espera pelo parar
      await t.pump();
      antiga.erro(const ErroGravador(desistiu: true, semEspaco: true, mensagem: 'sem espaço'));
      await t.pump();
      solta.complete();
      await _reabrir(t);
      expect(m.sessoes, hasLength(2));
      expect(m.sessao.fontes.single.url, _origem(_canais[1]), reason: 'o canal novo abriu');
      expect(m.sessao.memoria, isFalse, reason: 'o canal novo grava no disco');
      expect(m.registo.where((r) => r == 'resolver 2 continuar=false'), hasLength(1),
          reason: 'o zapping não passou a "repetido"');
      expect(m.registo.where((r) => r.startsWith('resolver 1')), hasLength(1), reason: 'o antigo não reabre');
      await _sair(t);
    });

    testWidgets('modo Memória num direto TS: a sessão grava em memória e recuar reabre no URL local', (t) async {
      final m = _Montagem();
      await m.montar(t, recuo: RecuoDireto.memoria);
      expect(m.sessoes, hasLength(1));
      expect(m.sessao.memoria, isTrue);
      expect(m.motor.aberturas.single.url, m.sessao.urlDireto.toString());
      await _abrirComImagem(t, m.motor);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _reabrir(t);
      expect(m.motor.aberturas, hasLength(2));
      expect(_desde(m.motor.aberturas.last.url), m.sessao.fim - 12000, reason: '10 s atrás do direto local');
      expect(m.motor.aberturas.last.url, startsWith('http://127.0.0.1:4567/codigo1/'));
      await _sair(t);
      expect(m.sessao.fechada, isTrue);
    });

    testWidgets('modo Memória no mpv: também pelo anel em RAM', (t) async {
      final m = _Montagem();
      await m.montar(t, recuo: RecuoDireto.memoria, motor: MotorAndroid.mpv);
      expect(m.motores.single.nome, startsWith('mpv'));
      expect(m.sessao.memoria, isTrue);
      expect(m.motor.aberturas.single.url, startsWith('http://127.0.0.1:4567/codigo1/'));
      await _sair(t);
    });

    testWidgets('modo Desligado: sem sessão, a origem no motor', (t) async {
      final m = _Montagem();
      await m.montar(t, recuo: RecuoDireto.desligado);
      expect(m.sessoes, isEmpty);
      expect(m.motor.aberturas.single.url, _origem(_canais[0]));
      await _sair(t);
    });

    testWidgets('modo Armazenamento: a sessão grava no disco', (t) async {
      final m = _Montagem();
      await m.montar(t);
      expect(m.sessoes, hasLength(1));
      expect(m.sessao.memoria, isFalse);
      await _sair(t);
    });
  });

  group('segundo plano', () {
    testWidgets('paused fecha a sessão (o motor pára antes) e não fica nenhuma pasta', (t) async {
      final tmp = Directory.systemTemp.createTempSync('direto_fundo_');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      final m = _Montagem()..pastas = tmp;
      await m.montar(t);
      await _abrirComImagem(t, m.motor);
      expect(tmp.listSync(), hasLength(1));
      await _paraOFundo(t);
      expect(m.sessao.fechada, isTrue, reason: 'o gravado apaga-se ao sair da app');
      expect(tmp.listSync(), isEmpty);
      final parou = m.registo.lastIndexOf('exo1: parou');
      expect(parou, greaterThanOrEqualTo(0));
      expect(parou, lessThan(m.registo.indexOf('sessao1: fechar')), reason: 'o motor larga o URL local antes');
      // em segundo plano nada volta a abrir
      await t.pump(const Duration(minutes: 1));
      expect(m.sessoes, hasLength(1));
      expect(m.motor.aberturas, hasLength(1));
      await _voltar(t);
      await _sair(t);
    });

    testWidgets('resumed reabre o canal no direto, numa sessão nova', (t) async {
      final m = _Montagem();
      await m.montar(t);
      await _abrirComImagem(t, m.motor);
      // estava 10 s atrás e em pausa
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _reabrir(t);
      await _abrirComImagem(t, m.motor);
      await _paraOFundo(t);
      await t.pump(const Duration(minutes: 2));
      await _voltar(t);
      expect(m.sessoes, hasLength(2));
      expect(m.sessoes.first.fechada, isTrue);
      expect(m.sessao.fechada, isFalse);
      expect(m.sessao.fontes.single.url, _origem(_canais[0]), reason: 'o mesmo canal');
      expect(m.motor.aberturas.last.url, m.sessao.urlDireto.toString(), reason: 'no direto');
      expect(m.motores, hasLength(1));
      await _sair(t);
    });

    testWidgets('a app vai para o fundo a meio do arranque da sessão: fecha-a e reabre ao voltar', (t) async {
      final m = _Montagem();
      final espera = Completer<void>();
      m.preparar = (s) => s.espera = espera.future;
      await m.montar(t);
      await _paraOFundo(t);
      espera.complete();
      await _reabrir(t);
      expect(m.sessoes.every((s) => s.fechada), isTrue);
      expect(m.motor.aberturas, isEmpty, reason: 'nada abre em segundo plano');
      m.preparar = null;
      await _voltar(t);
      expect(m.sessoes, hasLength(2));
      expect(m.sessao.fechada, isFalse);
      expect(m.motor.aberturas.single.url, m.sessao.urlDireto.toString());
      await _sair(t);
    });
  });

  testWidgets('Windows: pedir para sair (o X da janela) fecha a sessão antes de deixar sair', (t) async {
    final tmp = Directory.systemTemp.createTempSync('direto_sair_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final m = _Montagem()..pastas = tmp;
    await m.montar(t);
    await _abrirComImagem(t, m.motor);
    final resposta = await t.binding.handleRequestAppExit();
    expect(resposta, AppExitResponse.exit);
    expect(m.sessao.fechada, isTrue, reason: 'o gravado apaga-se antes do exit');
    expect(tmp.listSync(), isEmpty);
    expect(m.registo.lastIndexOf('exo1: parou'), lessThan(m.registo.indexOf('sessao1: fechar')));
    await _sair(t);
  });

  group('ecrã ligado na pausa do gravado', () {
    Future<void> pausar(WidgetTester t) async {
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Pausa'));
      await t.pump();
    }

    testWidgets('em pausa o ecrã fica ligado e solta-se aos 30 minutos', (t) async {
      final m = _Montagem();
      await m.montar(t);
      await _abrirComImagem(t, m.motor);
      expect(m.motor.ecraLigado, isFalse);
      await pausar(t);
      expect(m.motor.ecraLigado, isTrue, reason: 'a proteção de ecrã não põe a app em segundo plano');
      await t.pump(const Duration(minutes: 29, seconds: 59));
      expect(m.motor.ecraLigado, isTrue);
      await t.pump(const Duration(seconds: 2));
      expect(m.motor.ecraLigado, isFalse, reason: 'passados 30 min o ecrã pode apagar');
      expect(m.sessao.fechada, isFalse, reason: 'a pausa continua (só fecha se a app for para o fundo)');
      await _sair(t);
    });

    testWidgets('retomar solta o ecrã (a tocar, o motor já o mantém ligado)', (t) async {
      final m = _Montagem();
      await m.montar(t);
      await _abrirComImagem(t, m.motor);
      await pausar(t);
      expect(m.motor.ecraLigado, isTrue);
      await t.tap(find.byTooltip('Reproduzir'));
      await t.pump();
      expect(m.motor.ecraLigado, isFalse);
      // e não volta a mudar aos 30 min
      await t.pump(const Duration(minutes: 31));
      expect(m.motor.pedidos.where((p) => p.startsWith('ecraLigado')), ['ecraLigado true', 'ecraLigado false']);
      await _sair(t);
    });

    testWidgets('sem gravado a pausa não mexe no ecrã', (t) async {
      final m = _Montagem();
      await m.montar(t, comSessao: false);
      await _abrirComImagem(t, m.motor);
      await pausar(t);
      expect(m.motor.ecraLigado, isFalse);
      await _sair(t);
    });
  });
}
