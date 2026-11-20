import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/ui/player/barra_progresso.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';
import 'package:player_iptv/ui/player/motor_na_sessao.dart';
import 'package:player_iptv/ui/player/motor_reproducao.dart';
import 'package:player_iptv/ui/player/painel_definicoes.dart';
import 'package:player_iptv/ui/player/player_canais.dart';
import 'package:player_iptv/ui/tema.dart';

import 'motor_falso.dart';

const _canais = [
  Canal(id: '1', nome: 'RTP 1', grupo: 'Generalistas'),
  Canal(id: '2', nome: 'RTP 2', grupo: 'Generalistas'),
];

/// O player com as duas fábricas a fingir: regista os motores criados (os do ExoPlayer chamam-se
/// `exo1`, `exo2`…, os do mpv `mpv1`, …) e os pedidos de todos, por ordem.
class _Montagem {
  final registo = <String>[];
  final exos = <MotorFalso>[];
  final mpvs = <MotorFalso>[];
  final tuneis = <bool>[];
  EstatisticasMotor estatisticas = const EstatisticasMotor();

  /// Se dado, o link só chega quando isto acabar (o canal fica "a ser pedido").
  Future<void>? resolverEspera;

  MotorFalso get atual => registo.lastWhere((r) => r.startsWith('criar ')).endsWith('exo')
      ? exos.last
      : mpvs.last;

  Future<void> montar(WidgetTester t,
      {PlataformaVideo plataforma = PlataformaVideo.android,
      MotorAndroid motor = MotorAndroid.exoplayer,
      bool tunel = false}) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final antes = Preferencias.atual;
    Preferencias.atual = Preferencias.omissao()
      ..motorAndroid = motor
      ..modoTunel = tunel;
    addTearDown(() => Preferencias.atual = antes);
    MotorNaSessao.instancia.esquecer();
    addTearDown(MotorNaSessao.instancia.esquecer);
    await t.pumpWidget(MaterialApp(
      theme: temaApp(),
      home: Scaffold(
        body: PlayerCanais(
          canais: _canais,
          indice: 0,
          nomeLista: 'Lista A',
          aoSair: () {},
          plataforma: plataforma,
          // o relógio do teste (anda com os pump), nunca o de parede
          agora: () => t.binding.clock.now(),
          resolver: (c, {continuar = false}) async {
            final espera = resolverEspera;
            if (espera != null) await espera;
            return FonteVideo('http://exemplo.invalid/${c.id}.ts', const {'User-Agent': 'Teste'});
          },
          criarMotor: (ModoDescodificacao modo, bool hardware) {
            registo.add('criar mpv');
            final m = MotorFalso(nome: 'mpv${mpvs.length + 1}', registo: registo, estatisticasFalsas: estatisticas);
            mpvs.add(m);
            return m;
          },
          criarMotorExo: ({required bool tunel}) {
            registo.add('criar exo');
            tuneis.add(tunel);
            final m = MotorFalso(nome: 'exo${exos.length + 1}', registo: registo, estatisticasFalsas: estatisticas);
            exos.add(m);
            return m;
          },
        ),
      ),
    ));
    await t.pump();
    await t.pump();
  }
}

Future<void> _abrirComImagem(WidgetTester t, MotorFalso m) async {
  m.tamanho(const Size(1920, 1080));
  await t.pump();
  m.tempo(Duration.zero);
  await t.pump();
  m.tempo(const Duration(milliseconds: 500));
  await t.pump();
}

/// Deixa o canal reabrir (descartar o motor antigo, resolver o link, abrir).
Future<void> _reabrir(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump();
  }
}

Future<void> _sair(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 5));
}

Future<void> _abrirPainel(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.select);
  await t.pumpAndSettle();
  await t.tap(find.byTooltip('Definições'));
  await t.pumpAndSettle();
}

ItemDefinicao _item(WidgetTester t, String titulo) =>
    t.widget<LinhaDefinicao>(find.byKey(ValueKey(titulo))).item;

void main() {
  group('escolha do motor', () {
    testWidgets('no Android com o ExoPlayer nas preferências o player cria o ExoPlayer (com o túnel)', (t) async {
      final m = _Montagem();
      await m.montar(t, tunel: true);
      expect(m.registo, ['criar exo', 'exo1: abrir']);
      expect(m.tuneis, [true]);
      expect(m.exos.single.aberturas.single.url, 'http://exemplo.invalid/1.ts');
      await _sair(t);
      expect(m.exos.single.descartado, isTrue);
    });

    testWidgets('no Android com o mpv nas preferências o player cria o mpv', (t) async {
      final m = _Montagem();
      await m.montar(t, motor: MotorAndroid.mpv);
      expect(m.registo, ['criar mpv', 'mpv1: abrir']);
      await _sair(t);
    });

    testWidgets('no Windows é sempre o mpv (mesmo com o ExoPlayer nas preferências)', (t) async {
      final m = _Montagem();
      await m.montar(t, plataforma: PlataformaVideo.windows);
      expect(m.registo, ['criar mpv', 'mpv1: abrir']);
      expect(m.exos, isEmpty);
      await _sair(t);
    });
  });

  group('recurso ao mpv', () {
    testWidgets('um erro de formato larga o ExoPlayer, reabre o mesmo canal no mpv e avisa', (t) async {
      final m = _Montagem();
      await m.montar(t);
      m.exos.single.erro('O aparelho não descodifica o áudio deste canal', formato: true);
      await _reabrir(t);
      expect(m.registo, ['criar exo', 'exo1: abrir', 'exo1: descartar', 'criar mpv', 'mpv1: abrir'],
          reason: 'o ExoPlayer é largado antes de o mpv existir: nunca dois motores');
      expect(m.mpvs.single.aberturas.single.url, 'http://exemplo.invalid/1.ts');
      expect(find.textContaining('o canal não abriu'), findsNothing, reason: 'sem cartão de erro');
      expect(find.text('Este canal abriu com o motor mpv'), findsNothing, reason: 'só quando abrir');
      await _abrirComImagem(t, m.mpvs.single);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Este canal abriu com o motor mpv'), findsOneWidget);
      await _sair(t);
      expect(m.mpvs.single.descartado, isTrue);
    });

    testWidgets('um 2.º erro de formato no mesmo canal não volta a trocar: mostra o erro', (t) async {
      final m = _Montagem();
      await m.montar(t);
      m.exos.single.erro('formato', formato: true);
      await _reabrir(t);
      m.mpvs.single.erro('Unsupported codec', formato: true);
      await _reabrir(t);
      expect(m.exos, hasLength(1));
      expect(m.mpvs, hasLength(1));
      expect(find.text('RTP 1: o canal não abriu (Unsupported codec)'), findsOneWidget);
      await _sair(t);
    });

    testWidgets('um erro de rede não troca de motor', (t) async {
      final m = _Montagem();
      await m.montar(t);
      m.exos.single.erro('A ligação ao servidor falhou');
      await _reabrir(t);
      expect(m.mpvs, isEmpty);
      expect(m.exos.single.descartado, isFalse);
      expect(find.text('RTP 1: o canal não abriu (A ligação ao servidor falhou)'), findsOneWidget);
      expect(find.text('Este canal abriu com o motor mpv'), findsNothing);
      await _sair(t);
    });

    testWidgets('o canal fica no mpv nesta sessão; os outros canais voltam ao ExoPlayer', (t) async {
      final m = _Montagem();
      await m.montar(t);
      m.exos.single.erro('formato', formato: true);
      await _reabrir(t);
      await _abrirComImagem(t, m.mpvs.single);
      // zapping para o canal 2: volta ao ExoPlayer (e o mpv é largado)
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _reabrir(t);
      expect(m.exos, hasLength(2));
      expect(m.mpvs.single.descartado, isTrue);
      expect(m.exos.last.aberturas.single.url, 'http://exemplo.invalid/2.ts');
      await _abrirComImagem(t, m.exos.last);
      // de volta ao canal 1: abre logo no mpv, sem tentar o ExoPlayer
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _reabrir(t);
      expect(m.exos, hasLength(2), reason: 'nenhum ExoPlayer novo para o canal 1');
      expect(m.mpvs, hasLength(2));
      expect(m.exos.last.descartado, isTrue);
      expect(m.mpvs.last.aberturas.single.url, 'http://exemplo.invalid/1.ts');
      final i = m.registo.lastIndexOf('exo2: descartar');
      expect(i, lessThan(m.registo.lastIndexOf('criar mpv')), reason: 'nunca dois motores');
      await _sair(t);
    });

    testWidgets('outra abertura do player (sessão da app) lembra-se do canal', (t) async {
      final m = _Montagem();
      await m.montar(t);
      m.exos.single.erro('formato', formato: true);
      await _reabrir(t);
      await _sair(t);
      // o mesmo canal noutro player, sem esquecer a sessão
      final n = _Montagem();
      t.view.physicalSize = const Size(1920, 1080);
      await t.pumpWidget(MaterialApp(
        theme: temaApp(),
        home: Scaffold(
          body: PlayerCanais(
            canais: _canais,
            indice: 0,
            nomeLista: 'Lista A',
            aoSair: () {},
            plataforma: PlataformaVideo.android,
            resolver: (c, {continuar = false}) async => FonteVideo('http://exemplo.invalid/${c.id}.ts', const {}),
            criarMotor: (_, _) {
              n.registo.add('criar mpv');
              return MotorFalso(nome: 'mpv', registo: n.registo);
            },
            criarMotorExo: ({required bool tunel}) {
              n.registo.add('criar exo');
              return MotorFalso(nome: 'exo', registo: n.registo);
            },
          ),
        ),
      ));
      await _reabrir(t);
      expect(n.registo, ['criar mpv', 'mpv: abrir']);
      await _sair(t);
    });
  });

  group('zapping e recurso', () {
    testWidgets('um erro de formato atrasado do canal anterior não marca o canal novo', (t) async {
      final m = _Montagem();
      await m.montar(t);
      await _abrirComImagem(t, m.exos.single);
      // seta para cima: o canal 2 está a ser pedido (ainda sem abrir) quando chega o erro do canal 1
      final link = Completer<void>();
      m.resolverEspera = link.future;
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      expect(m.exos.single.aberturas, hasLength(1), reason: 'o canal 2 ainda não abriu');
      m.exos.single.erro('formato do canal 1', formato: true);
      await _reabrir(t);
      m.resolverEspera = null;
      link.complete();
      await _reabrir(t);
      expect(m.mpvs, isEmpty, reason: 'nada passa ao mpv');
      expect(m.exos, hasLength(1));
      expect(m.exos.single.aberturas.map((a) => a.url), ['http://exemplo.invalid/1.ts', 'http://exemplo.invalid/2.ts']);
      await _abrirComImagem(t, m.exos.single);
      expect(find.text('Este canal abriu com o motor mpv'), findsNothing);
      // nenhum dos dois canais ficou marcado: voltar ao 1 continua no ExoPlayer
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _reabrir(t);
      expect(m.mpvs, isEmpty);
      expect(m.exos.single.aberturas.last.url, 'http://exemplo.invalid/1.ts');
      await _sair(t);
    });

    testWidgets('do mpv para o ExoPlayer: o ExoPlayer só é criado depois de o mpv parar', (t) async {
      final m = _Montagem();
      await m.montar(t);
      m.exos.single.erro('formato', formato: true);
      await _reabrir(t);
      await _abrirComImagem(t, m.mpvs.single);
      final lento = Completer<void>();
      m.mpvs.single.pararDemora = lento.future;
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp); // o canal 2 volta ao ExoPlayer
      await t.pump(const Duration(seconds: 1));
      expect(m.exos, hasLength(1), reason: 'à espera de o mpv largar o descodificador');
      lento.complete();
      await _reabrir(t);
      expect(m.exos, hasLength(2));
      expect(m.registo.indexOf('mpv1: parou'), lessThan(m.registo.lastIndexOf('criar exo')));
      expect(m.exos.last.aberturas.single.url, 'http://exemplo.invalid/2.ts');
      await _sair(t);
    });

    testWidgets('do mpv para o ExoPlayer: um mpv que não pára não prende (limite)', (t) async {
      final m = _Montagem();
      await m.montar(t);
      m.exos.single.erro('formato', formato: true);
      await _reabrir(t);
      await _abrirComImagem(t, m.mpvs.single);
      m.mpvs.single.pararDemora = Completer<void>().future; // nunca acaba
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump(const Duration(seconds: 4));
      expect(m.exos, hasLength(1));
      await t.pump(const Duration(seconds: 2));
      await _reabrir(t);
      expect(m.exos, hasLength(2), reason: 'ao fim do limite segue-se em frente');
      expect(m.mpvs.single.descartado, isTrue);
      expect(m.exos.last.aberturas.single.url, 'http://exemplo.invalid/2.ts');
      await _sair(t);
    });
  });

  group('C3: corte do servidor com o ExoPlayer', () {
    const sempreACortar = 'RTP 1: o servidor está sempre a cortar a ligação a este canal';

    testWidgets('o fim de um direto reabre o mesmo canal, com "A carregar…" e sem cartão de erro', (t) async {
      final m = _Montagem();
      await m.montar(t);
      final exo = m.exos.single;
      await _abrirComImagem(t, exo);
      await t.pump(const Duration(seconds: 30)); // um bom bocado de canal
      exo.acabar();
      await _reabrir(t);
      expect(exo.aberturas, hasLength(2), reason: 'o mesmo canal outra vez, no mesmo motor');
      expect(exo.aberturas.last.url, 'http://exemplo.invalid/1.ts');
      expect(exo.aberturas.last.inicio, isNull, reason: 'num direto vai para o direto');
      expect(m.exos, hasLength(1));
      expect(m.mpvs, isEmpty);
      await t.pump(const Duration(milliseconds: 400)); // o aviso só aparece passado um pouco
      expect(find.text('A carregar…'), findsOneWidget);
      expect(find.textContaining('o canal não abriu'), findsNothing);
      await _abrirComImagem(t, exo);
      expect(find.text('A carregar…'), findsNothing);
      await _sair(t);
    });

    testWidgets('cortes seguidos sem proveito: desiste com a mensagem do mpv', (t) async {
      final m = _Montagem();
      await m.montar(t);
      final exo = m.exos.single;
      // cada ligação dá menos do que o proveito (5 s): ao fim de 3 reaberturas, o cartão
      for (var i = 0; i < 4; i++) {
        await _abrirComImagem(t, exo);
        await t.pump(const Duration(seconds: 1));
        exo.acabar();
        await _reabrir(t);
      }
      expect(exo.aberturas, hasLength(4), reason: 'três reaberturas, a quarta já não');
      expect(find.text(sempreACortar), findsOneWidget);
      await _sair(t);
    });

    testWidgets('o fim de um ficheiro (não direto) não reabre', (t) async {
      final m = _Montagem();
      await m.montar(t);
      final exo = m.exos.single..direto = false;
      await _abrirComImagem(t, exo);
      exo.acabar();
      await _reabrir(t);
      expect(exo.aberturas, hasLength(1));
      expect(find.textContaining('o servidor'), findsNothing);
      await _sair(t);
    });

    testWidgets('parado à espera de dados mais do que o network-timeout do mpv (15 s): reabre', (t) async {
      final m = _Montagem();
      await m.montar(t);
      final exo = m.exos.single;
      await _abrirComImagem(t, exo);
      await t.pump(const Duration(seconds: 20));
      // uma paragem curta não reabre
      exo.carregar(true);
      await t.pump(const Duration(seconds: 10));
      exo.carregar(false);
      await t.pump(const Duration(seconds: 10));
      expect(exo.aberturas, hasLength(1));
      // uma que não acaba, sim
      exo.carregar(true);
      await t.pump(const Duration(seconds: 14));
      expect(exo.aberturas, hasLength(1));
      await t.pump(const Duration(seconds: 2));
      await _reabrir(t);
      expect(exo.aberturas, hasLength(2));
      expect(find.textContaining('o canal não abriu'), findsNothing);
      await _sair(t);
    });

    testWidgets('um erro de rede com o canal já aberto reabre-o (como o fim do buffer no mpv)', (t) async {
      final m = _Montagem();
      await m.montar(t);
      final exo = m.exos.single;
      await _abrirComImagem(t, exo);
      await t.pump(const Duration(seconds: 30));
      exo.erro('Falha de rede ao abrir o canal', rede: true);
      await _reabrir(t);
      expect(exo.aberturas, hasLength(2));
      expect(find.textContaining('o canal não abriu'), findsNothing);
      // a reabrir, uma falha de rede passageira tenta-se outra vez (a recuperação que já existe)
      exo.erro('Falha de rede ao abrir o canal', rede: true);
      await t.pump(const Duration(seconds: 1));
      await _reabrir(t);
      expect(exo.aberturas, hasLength(3));
      expect(find.textContaining('o canal não abriu'), findsNothing);
      await _sair(t);
    });
  });

  group('N1: corte com a app em segundo plano', () {
    Future<void> paraFundo(WidgetTester t) async {
      for (final e in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        t.binding.handleAppLifecycleStateChanged(e);
        await t.pump();
      }
    }

    Future<void> deVolta(WidgetTester t) async {
      for (final e in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        t.binding.handleAppLifecycleStateChanged(e);
        await t.pump();
      }
    }

    testWidgets('um erro de rede em segundo plano não reabre; reabre ao voltar à app', (t) async {
      final m = _Montagem();
      await m.montar(t);
      final exo = m.exos.single;
      await _abrirComImagem(t, exo);
      await t.pump(const Duration(seconds: 30));
      await paraFundo(t);
      exo.erro('Falha de rede ao abrir o canal', rede: true);
      await _reabrir(t);
      await t.pump(const Duration(seconds: 5));
      expect(exo.aberturas, hasLength(1), reason: 'nada toca com a app escondida');
      expect(find.textContaining('o canal não abriu'), findsNothing);
      await deVolta(t);
      await _reabrir(t);
      expect(exo.aberturas, hasLength(2), reason: 'ao voltar, o canal reabre');
      await _sair(t);
    });

    testWidgets('uma paragem em segundo plano não arma os 15 s; ao voltar volta a contar', (t) async {
      final m = _Montagem();
      await m.montar(t);
      final exo = m.exos.single;
      await _abrirComImagem(t, exo);
      await t.pump(const Duration(seconds: 30));
      exo.carregar(true);
      await t.pump(const Duration(seconds: 5));
      await paraFundo(t);
      await t.pump(const Duration(seconds: 30));
      expect(exo.aberturas, hasLength(1));
      await deVolta(t);
      await t.pump(const Duration(seconds: 16));
      await _reabrir(t);
      expect(exo.aberturas, hasLength(2));
      await _sair(t);
    });
  });

  group('com o ExoPlayer', () {
    testWidgets('o painel: as opções só do mpv aparecem desativadas com "só no motor mpv"', (t) async {
      final m = _Montagem();
      await m.montar(t);
      await _abrirComImagem(t, m.exos.single);
      await _abrirPainel(t);
      for (final titulo in ['Desentrelaçamento', 'Atraso do áudio', 'Descodificação']) {
        final item = _item(t, titulo);
        expect(item.ativo, isFalse, reason: titulo);
        expect(item.nota, 'só no motor mpv', reason: titulo);
      }
      expect(_item(t, 'Faixa de áudio').nota, isNot('só no motor mpv'));
      expect(_item(t, 'Formato de imagem').ativo, isTrue);
      await _sair(t);
    });

    testWidgets('o painel com o mpv no Android: as opções do mpv continuam ativas', (t) async {
      final m = _Montagem();
      await m.montar(t, motor: MotorAndroid.mpv);
      await _abrirComImagem(t, m.mpvs.single);
      await _abrirPainel(t);
      expect(_item(t, 'Descodificação').ativo, isTrue);
      expect(_item(t, 'Atraso do áudio').ativo, isTrue);
      expect(_item(t, 'Descodificação').nota, isNot('só no motor mpv'));
      await _sair(t);
    });

    testWidgets('sem os botões e as teclas que só o mpv sabe fazer (saltos, barra de progresso)', (t) async {
      final m = _Montagem();
      await m.montar(t);
      await _abrirComImagem(t, m.exos.single);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.byTooltip('Pausa'), findsOneWidget, reason: 'a barra está à vista');
      expect(find.byTooltip('Recuar 10 s'), findsNothing);
      expect(find.byTooltip('Avançar 10 s'), findsNothing);
      expect(find.byType(BarraProgresso), findsNothing);
      await _sair(t);
    });

    testWidgets('pausar e voltar ao direto reabre o canal (sem saltos no ExoPlayer)', (t) async {
      final m = _Montagem();
      await m.montar(t);
      await _abrirComImagem(t, m.exos.single);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Pausa'));
      await t.pump();
      // o relógio do direto é o do teste: passa mais do que o limiar (2 s) sem tempo de parede
      await t.pump(const Duration(milliseconds: 2200));
      await t.pump(const Duration(seconds: 1));
      expect(m.exos.single.pedidos, contains('pausar'));
      final voltar = find.text('Voltar ao direto');
      expect(voltar, findsOneWidget);
      await t.tap(voltar);
      await _reabrir(t);
      expect(m.exos.single.aberturas, hasLength(2), reason: 'o mesmo canal outra vez, no mesmo motor');
      expect(m.exos, hasLength(1));
      await _sair(t);
    });

    testWidgets('as estatísticas e a informação do stream vêm do motor (nunca vazias)', (t) async {
      final m = _Montagem()
        ..estatisticas = const EstatisticasMotor(
          resolucao: Size(1920, 1080),
          fps: 50,
          codec: 'avc1.640028',
          perdidas: 3,
          renderizadas: 1200,
          bitrate: 4200000,
          buffer: Duration(milliseconds: 2500),
        );
      await m.montar(t);
      await _abrirComImagem(t, m.exos.single);
      final estado = t.state<PlayerCanaisState>(find.byType(PlayerCanais));
      estado.alternarEstatisticas();
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Estatísticas'), findsOneWidget);
      for (final v in ['1920×1080', 'avc1.640028', '50.00', '3 · 1200', '2.5 s', '4.2 Mb/s']) {
        expect(find.textContaining(v), findsWidgets, reason: v);
      }
      // a informação da barra (resolução · imagens/s · débito)
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('1920×1080 · 50 fps · 4,2 Mb/s'), findsOneWidget);
      estado.alternarEstatisticas();
      await _sair(t);
    });

    testWidgets('o silêncio no ExoPlayer é o volume a 0 (e volta ao volume da preferência)', (t) async {
      final m = _Montagem();
      await m.montar(t);
      await _abrirComImagem(t, m.exos.single);
      await _abrirPainel(t);
      await t.tap(find.text('Silêncio'));
      await t.pump();
      expect(m.exos.single.pedidos.last, 'volume 0.0');
      await t.tap(find.text('Silêncio'));
      await t.pump();
      expect(m.exos.single.pedidos.last, 'volume 100.0');
      await _sair(t);
    });

    testWidgets('I4: mostrar um erro pára o motor (nada toca por baixo do cartão, nem ao voltar à app)', (t) async {
      final m = _Montagem();
      await m.montar(t);
      final exo = m.exos.single;
      await _abrirComImagem(t, exo);
      exo.pedidos.clear();
      // o que o nativo manda num ERROR_CODE_DECODING_FAILED depois da 1.ª imagem: nem formato nem rede
      exo.erro('O ExoPlayer não conseguiu tocar o canal', formato: false, rede: false);
      await t.pump();
      await t.pump();
      expect(find.text('RTP 1: o canal não abriu (O ExoPlayer não conseguiu tocar o canal)'), findsOneWidget);
      expect(exo.pedidos, contains('parar'));
      await _sair(t);
    });

    testWidgets('I4: desistir de um canal que o servidor está sempre a cortar também pára o motor', (t) async {
      final m = _Montagem();
      await m.montar(t);
      final exo = m.exos.single;
      for (var i = 0; i < 4; i++) {
        await _abrirComImagem(t, exo);
        exo.pedidos.clear();
        exo.acabar();
        await _reabrir(t);
      }
      expect(find.text('RTP 1: o servidor está sempre a cortar a ligação a este canal'), findsOneWidget);
      expect(exo.pedidos, contains('parar'));
      await _sair(t);
    });

    testWidgets('M2: o "A abrir…" sai logo com a primeira imagem do ExoPlayer, sem esperar pela posição', (t) async {
      final m = _Montagem();
      await m.montar(t);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      m.exos.single.mostrouPrimeiraImagem();
      await t.pump();
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await _sair(t);
    });

    testWidgets('"Abrir em modo compatível" no cartão de erro abre o canal no mpv', (t) async {
      final m = _Montagem();
      await m.montar(t);
      m.exos.single.erro('A ligação ao servidor falhou');
      await _reabrir(t);
      await t.tap(find.text('Abrir em modo compatível'));
      await _reabrir(t);
      expect(m.exos.single.descartado, isTrue);
      expect(m.mpvs.single.aberturas.single.url, 'http://exemplo.invalid/1.ts');
      await _sair(t);
    });
  });
}
