import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/design/ecra.dart';
import 'package:player_iptv/ui/player/controlos_player.dart';
import 'package:player_iptv/ui/player/maquina_controlos.dart';
import 'package:player_iptv/ui/player/painel_definicoes.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

class _Ensaio {
  final acoes = <AcaoPlayer>[];
  final velocidades = <double>[];
  Duration atraso = Duration.zero;
  bool aTocar = true;
  double velocidade = 1;
  bool erro = false;
  bool ecraInteiro = false;
  var silencio = false;
  StateSetter? reconstruir;
  var leiturasInfo = 0;
  Map<String, String> infoStream = const {
    'width': '1280',
    'height': '720',
    'container-fps': '50.000000',
    'video-bitrate': '3100000',
  };
}

final _chave = GlobalKey<ControlosPlayerState>();

Future<_Ensaio> _montar(WidgetTester t, {bool ecraInteiro = false, bool semAnimacoes = false, bool tv = false}) async {
  EcraTv.nativo = tv;
  addTearDown(() => EcraTv.nativo = false);
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
  t.view.physicalSize = const Size(1920, 1080);
  t.view.devicePixelRatio = tv ? 2 : 1;
  addTearDown(t.view.reset);
  final e = _Ensaio()..ecraInteiro = ecraInteiro;
  await t.pumpWidget(
    MaterialApp(
      theme: temaApp(),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(disableAnimations: semAnimacoes),
        child: TemaConformeRealce(child: w!),
      ),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: StatefulBuilder(
          builder: (_, setState) {
            e.reconstruir = setState;
            return ControlosPlayer(
              key: _chave,
              estado: EstadoControlos(
                canal: 'RTP 1',
                subtitulo: 'Generalistas · 3/120 · Lista A',
                aTocar: e.aTocar,
                velocidade: e.velocidade,
                erro: e.erro,
              ),
              atraso: () => e.atraso,
              lerInfoStream: () async {
                e.leiturasInfo++;
                return e.infoStream;
              },
              aoAgir: (a) => setState(() => e.acoes.add(a)),
              aoMudarVelocidade: (v) => setState(() {
                e.velocidades.add(v);
                e.velocidade = v;
              }),
              comEcraInteiro: e.ecraInteiro,
              definicoes: () => [
                DefinicaoInterruptor('Silêncio', valor: e.silencio, aoMudar: (v) => setState(() => e.silencio = v)),
                DefinicaoEscolha('Formato de imagem', opcoes: const ['Ajustar', 'Zoom'], atual: 0, aoMudar: (_) {}),
              ],
              child: Center(
                child: TextButton(
                  onPressed: () => e.acoes.add(AcaoPlayer.tentarDeNovo),
                  child: const Text('Tentar de novo'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return e;
}

/// O "voltar" do sistema (Android: a tecla BACK, o gesto).
Future<void> _voltarSistema(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

Future<void> _tecla(WidgetTester t, LogicalKeyboardKey k) async {
  // o simulador não tem tecla física para o goBack: usa-se a do Esc
  await t.sendKeyEvent(k, physicalKey: k == LogicalKeyboardKey.goBack ? PhysicalKeyboardKey.escape : null);
  await t.pumpAndSettle();
}

/// O texto/tooltip do controlo com o foco.
String? _focado() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  final linha = ctx.findAncestorWidgetOfExactType<LinhaDefinicao>();
  if (linha != null) return linha.item.titulo;
  final t = ctx.findAncestorWidgetOfExactType<Tooltip>();
  return t?.message;
}

bool _barraVisivel(WidgetTester t) => find.byTooltip('Definições').hitTestable().evaluate().isNotEmpty;

void main() {
  testWidgets('escondidos: cima/baixo mudam de canal, esquerda/direita recuam/avançam; a barra não aparece', (t) async {
    final e = await _montar(t);
    expect(_barraVisivel(t), isFalse);
    await _tecla(t, LogicalKeyboardKey.arrowUp);
    await _tecla(t, LogicalKeyboardKey.arrowDown);
    await _tecla(t, LogicalKeyboardKey.arrowLeft);
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    expect(e.acoes, [AcaoPlayer.canalAnterior, AcaoPlayer.canalSeguinte, AcaoPlayer.recuar, AcaoPlayer.avancar]);
    expect(_barraVisivel(t), isFalse);
  });

  testWidgets('OK mostra a barra com o foco no play/pausa; as setas andam na barra (sem mudar de canal)', (t) async {
    final e = await _montar(t);
    await _tecla(t, LogicalKeyboardKey.select);
    expect(_barraVisivel(t), isTrue);
    expect(_focado(), 'Pausa');
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    expect(_focado(), 'Avançar 10 s');
    await _tecla(t, LogicalKeyboardKey.arrowLeft);
    await _tecla(t, LogicalKeyboardKey.arrowLeft);
    expect(_focado(), 'Recuar 10 s');
    await _tecla(t, LogicalKeyboardKey.arrowDown);
    expect(_focado(), 'Recuar 10 s');
    expect(e.acoes, isEmpty);
    // OK no botão focado carrega nele
    await _tecla(t, LogicalKeyboardKey.select);
    expect(e.acoes.last, AcaoPlayer.recuar);
  });

  testWidgets('os botões da barra fazem o que dizem', (t) async {
    final e = await _montar(t);
    await _tecla(t, LogicalKeyboardKey.select);
    for (final (dica, acao) in [
      ('Pausa', AcaoPlayer.playPausa),
      ('Canal anterior', AcaoPlayer.canalAnterior),
      ('Canal seguinte', AcaoPlayer.canalSeguinte),
      ('Recuar 10 s', AcaoPlayer.recuar),
      ('Avançar 10 s', AcaoPlayer.avancar),
    ]) {
      await t.tap(find.byTooltip(dica));
      await t.pumpAndSettle();
      expect(e.acoes.last, acao, reason: dica);
    }
  });

  testWidgets('teclas multimédia funcionam com a barra visível', (t) async {
    final e = await _montar(t);
    await _tecla(t, LogicalKeyboardKey.select);
    await _tecla(t, LogicalKeyboardKey.mediaPlayPause);
    await _tecla(t, LogicalKeyboardKey.channelDown);
    await _tecla(t, LogicalKeyboardKey.mediaRewind);
    expect(e.acoes, [AcaoPlayer.playPausa, AcaoPlayer.canalSeguinte, AcaoPlayer.recuar]);
  });

  testWidgets('esconde-se após 5 s sem atividade; uma tecla adia', (t) async {
    await _montar(t);
    await _tecla(t, LogicalKeyboardKey.select);
    await t.pump(const Duration(seconds: 4));
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    await t.pump(const Duration(seconds: 4));
    expect(_barraVisivel(t), isTrue);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(_barraVisivel(t), isFalse);
    // depois de esconder, as setas voltam a mudar de canal
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Tooltip>(), isNull);
  });

  testWidgets('o rato a mexer mostra a barra', (t) async {
    await _montar(t);
    final rato = await t.createGesture(kind: PointerDeviceKind.mouse);
    await rato.addPointer(location: const Offset(500, 500));
    addTearDown(rato.removePointer);
    await rato.moveTo(const Offset(600, 520));
    await t.pumpAndSettle();
    expect(_barraVisivel(t), isTrue);
  });

  testWidgets('um toque mostra a barra; outro toque no vídeo esconde-a', (t) async {
    await _montar(t);
    await t.tapAt(const Offset(960, 300));
    await t.pumpAndSettle();
    expect(_barraVisivel(t), isTrue);
    await t.tapAt(const Offset(960, 300));
    await t.pumpAndSettle();
    expect(_barraVisivel(t), isFalse);
  });

  testWidgets('Voltar (Esc) por camadas: painel → barra (foco em Definições) → escondida → sair', (t) async {
    final e = await _montar(t);
    await _tecla(t, LogicalKeyboardKey.select);
    await t.tap(find.byTooltip('Definições'));
    await t.pumpAndSettle();
    expect(find.text('Silêncio'), findsOneWidget);
    expect(_focado(), 'Silêncio');
    // as setas são do painel: não mudam de canal, nem saem para a barra
    await _tecla(t, LogicalKeyboardKey.arrowDown);
    expect(_focado(), 'Formato de imagem');
    await _tecla(t, LogicalKeyboardKey.arrowDown);
    expect(_focado(), 'Formato de imagem');
    await _tecla(t, LogicalKeyboardKey.escape);
    expect(find.text('Silêncio'), findsNothing);
    expect(_barraVisivel(t), isTrue);
    expect(_focado(), 'Definições');
    await _tecla(t, LogicalKeyboardKey.escape);
    expect(_barraVisivel(t), isFalse);
    expect(e.acoes, isEmpty);
    await _tecla(t, LogicalKeyboardKey.escape);
    expect(e.acoes.last, AcaoPlayer.sair);
  });

  testWidgets('Android: o Voltar do comando conta uma vez só (a tecla segue para o Voltar do sistema)', (t) async {
    // no Android a tecla BACK chega como tecla E como "voltar" do sistema: tratar as duas
    // fechava o painel e a barra de uma vez (e depois saía do player e da lista)
    final e = await _montar(t);
    await _tecla(t, LogicalKeyboardKey.select);
    await t.tap(find.byTooltip('Definições'));
    await t.pumpAndSettle();
    await _tecla(t, LogicalKeyboardKey.goBack);
    expect(find.text('Silêncio'), findsOneWidget, reason: 'a tecla sozinha não faz nada');
    await _voltarSistema(t);
    expect(find.text('Silêncio'), findsNothing);
    expect(_barraVisivel(t), isTrue);
    expect(_focado(), 'Definições');
    await _voltarSistema(t);
    expect(_barraVisivel(t), isFalse);
    // escondida: o Voltar do sistema já fecha a página do player
    expect(t.widget<PopScope<Object?>>(find.byWidgetPredicate((w) => w is PopScope)).canPop, isTrue);
    expect(e.acoes, isEmpty);
  });

  testWidgets('o painel não se esconde sozinho e muda as definições', (t) async {
    final e = await _montar(t);
    await _tecla(t, LogicalKeyboardKey.select);
    await t.tap(find.byTooltip('Definições'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 30));
    await _tecla(t, LogicalKeyboardKey.select);
    expect(e.silencio, isTrue);
    expect(find.text('Silêncio'), findsOneWidget);
  });

  testWidgets('o Voltar do sistema (PopScope) segue as mesmas camadas', (t) async {
    final e = await _montar(t);
    await _tecla(t, LogicalKeyboardKey.select);
    final nav = t.state<NavigatorState>(find.byType(Navigator));
    await nav.maybePop();
    await t.pumpAndSettle();
    expect(_barraVisivel(t), isFalse);
    expect(e.acoes, isEmpty);
  });

  testWidgets('velocidade: OK passa à seguinte (1× → 1,25× … 2× → 0,5×)', (t) async {
    final e = await _montar(t);
    await _tecla(t, LogicalKeyboardKey.select);
    await t.tap(find.byTooltip('Velocidade'));
    await t.pumpAndSettle();
    expect(e.velocidades, [1.25]);
    expect(find.text('1,25×'), findsOneWidget);
    e.reconstruir!(() => e.velocidade = 2);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Velocidade'));
    await t.pumpAndSettle();
    expect(e.velocidades.last, 0.5);
  });

  testWidgets('"Em direto" quando não há atraso; atrás do direto mostra o atraso e "Voltar ao direto"', (t) async {
    final e = await _montar(t);
    await _tecla(t, LogicalKeyboardKey.select);
    expect(find.text('Em direto'), findsOneWidget);
    expect(find.byTooltip('Voltar ao direto'), findsNothing);
    e.atraso = const Duration(seconds: 20);
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('−0:20'), findsOneWidget);
    await t.tap(find.byTooltip('Voltar ao direto'));
    await t.pumpAndSettle();
    expect(e.acoes.last, AcaoPlayer.voltarAoDireto);
  });

  testWidgets('o botão Voltar (fechar) está à vista com a barra; ecrã inteiro só quando há', (t) async {
    final e = await _montar(t, ecraInteiro: true);
    await _tecla(t, LogicalKeyboardKey.select);
    await t.tap(find.byTooltip('Voltar'));
    await t.pumpAndSettle();
    expect(e.acoes.last, AcaoPlayer.sair);
    await _tecla(t, LogicalKeyboardKey.select);
    await t.tap(find.byTooltip('Ecrã inteiro (F11)'));
    await t.pumpAndSettle();
    expect(e.acoes.last, AcaoPlayer.ecraInteiro);
  });

  testWidgets('sem ecrã inteiro (Android) não há esse botão', (t) async {
    await _montar(t);
    await _tecla(t, LogicalKeyboardKey.select);
    expect(find.byTooltip('Ecrã inteiro (F11)'), findsNothing);
    expect(find.byTooltip('Voltar'), findsOneWidget);
  });

  testWidgets('com o cartão de erro, OK tenta de novo', (t) async {
    final e = await _montar(t);
    e.reconstruir!(() => e.erro = true);
    await t.pumpAndSettle();
    await _tecla(t, LogicalKeyboardKey.select);
    expect(e.acoes.last, AcaoPlayer.tentarDeNovo);
  });

  testWidgets('reduzir movimento: a barra aparece sem animação', (t) async {
    await _montar(t, semAnimacoes: true);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    final o = t.widget<AnimatedOpacity>(find.byKey(const ValueKey('barra')));
    expect(o.duration, Duration.zero);
    expect(o.opacity, 1);
  });

  testWidgets('a mudar de canal escondido, aparece o nome do canal (sem tirar as setas ao zapping)', (t) async {
    final e = await _montar(t);
    _chave.currentState!.mostrarInfoCanal();
    await t.pumpAndSettle();
    double opacidade() => t.widget<AnimatedOpacity>(find.byKey(const ValueKey('infoCanal'))).opacity;
    expect(opacidade(), 1);
    await _tecla(t, LogicalKeyboardKey.arrowDown);
    expect(e.acoes, [AcaoPlayer.canalSeguinte]);
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(opacidade(), 0);
  });

  testWidgets('os botões do vídeo (cartão de erro) recebem o toque; não mostra a barra', (t) async {
    final e = await _montar(t);
    await t.tap(find.text('Tentar de novo'));
    await t.pumpAndSettle();
    expect(e.acoes, [AcaoPlayer.tentarDeNovo]);
    expect(_barraVisivel(t), isFalse);
  });

  for (final tv in [false, true]) {
    testWidgets('com o direto atrasado, as setas chegam a "Voltar ao direto" e às Definições (TV: $tv)', (t) async {
      final e = await _montar(t, tv: tv);
      await _tecla(t, LogicalKeyboardKey.select);
      e.reconstruir!(() => e.atraso = const Duration(seconds: 20));
      await t.pumpAndSettle();
      final vistos = <String?>[];
      for (var i = 0; i < 5; i++) {
        await _tecla(t, LogicalKeyboardKey.arrowRight);
        vistos.add(_focado());
      }
      expect(vistos, ['Avançar 10 s', 'Canal seguinte', 'Velocidade', 'Voltar ao direto', 'Definições']);
      await _tecla(t, LogicalKeyboardKey.arrowLeft);
      await _tecla(t, LogicalKeyboardKey.select);
      expect(e.acoes.last, AcaoPlayer.voltarAoDireto);
    });
  }

  testWidgets('a barra mostra resolução, imagens/s e débito; escondida não lê o player', (t) async {
    final e = await _montar(t);
    await t.pump(const Duration(seconds: 3));
    expect(e.leiturasInfo, 0, reason: 'escondida não lê');
    await _tecla(t, LogicalKeyboardKey.select);
    expect(find.text('1280×720 · 50 fps · 3,1 Mb/s'), findsOneWidget);
    e.infoStream = const {
      'width': '',
      'height': '',
      'container-fps': '',
      'estimated-vf-fps': '29.97',
      'video-bitrate': '',
    };
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('— · 29,97 fps · —'), findsOneWidget);
    await _tecla(t, LogicalKeyboardKey.escape);
    final n = e.leiturasInfo;
    await t.pump(const Duration(seconds: 5));
    expect(e.leiturasInfo, n, reason: 'deixa de ler quando a barra se esconde');
  });

  test('texto da informação do stream (vírgula decimal, "—" sem valor)', () {
    expect(
      textoInfoStream(const {'width': '1920', 'height': '1080', 'container-fps': '25', 'video-bitrate': '8000000'}),
      '1920×1080 · 25 fps · 8 Mb/s',
    );
    expect(
      textoInfoStream(const {'width': '720', 'height': '576', 'container-fps': '23.976', 'video-bitrate': '860000'}),
      '720×576 · 23,98 fps · 0,9 Mb/s',
    );
    expect(textoInfoStream(const {}), '— · — · —');
  });
}
