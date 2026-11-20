import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/design/ecra.dart';
import 'package:player_iptv/ui/design/escala_interface.dart';
import 'package:player_iptv/ui/player/motor_exo.dart';
import 'package:player_iptv/ui/player/motor_reproducao.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';
import 'package:player_iptv/ui/player/player_canais.dart';
import 'package:player_iptv/ui/player/taxa_ecra.dart';
import 'package:player_iptv/ui/tema.dart';

const _metodos = MethodChannel('player_iptv/exo');
const _eventos = EventChannel('player_iptv/exo/eventos');

/// O lado nativo a fingir: regista os pedidos (`criar` devolve [id]) e deixa o teste mandar eventos.
class _ExoFalso {
  _ExoFalso({this.estatisticas, this.falharCriar = false, this.falharAbrir}) {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_metodos, (c) async {
      chamadas.add(c);
      switch (c.method) {
        case 'criar':
          if (falharCriar) throw MissingPluginException();
          return id;
        case 'abrir' when falharAbrir != null:
          throw PlatformException(code: 'argumentos', message: falharAbrir);
        case 'estatisticas':
          return estatisticas;
      }
      return null;
    });
    m.setMockStreamHandler(
        _eventos,
        MockStreamHandler.inline(
          onListen: (_, sink) {
            this.sink = sink;
            aEscutar++;
          },
          onCancel: (_) {
            sink = null;
            cancelados++;
          },
        ));
    addTearDown(() {
      m.setMockMethodCallHandler(_metodos, null);
      m.setMockStreamHandler(_eventos, null);
    });
  }

  final int id = 7;
  final Map<String, Object?>? estatisticas;
  final bool falharCriar;
  final String? falharAbrir;
  final chamadas = <MethodCall>[];
  MockStreamHandlerEventSink? sink;

  /// Os eventos nos testes de widgets (lá o EventChannel nunca deixa o teste acabar).
  final fonte = StreamController<Object?>.broadcast();
  int aEscutar = 0;
  int cancelados = 0;

  List<String> get metodos => [for (final c in chamadas) c.method];
  List<MethodCall> de(String metodo) => [for (final c in chamadas) if (c.method == metodo) c];
  Map<Object?, Object?> args(MethodCall c) => c.arguments as Map<Object?, Object?>;

  /// A sessão do último `abrir` que chegou (0 antes do primeiro), como o nativo a guarda.
  int get sessao {
    final a = de('abrir');
    return a.isEmpty ? 0 : args(a.last)['sessao']! as int;
  }

  /// Um evento do player [deId] (por omissão o atual), da [sessao] dada (por omissão a atual).
  void evento(String tipo, [Map<String, Object?> dados = const {}, int? deId, int? daSessao]) {
    final e = {...dados, 'id': deId ?? id, 'sessao': daSessao ?? sessao, 'tipo': tipo};
    if (fonte.hasListener) {
      fonte.add(e);
    } else {
      sink!.success(e);
    }
  }

  /// Um motor para os testes de widgets, com os eventos de [fonte].
  MotorExo motor() {
    final m = MotorExo(fonteEventos: fonte.stream);
    addTearDown(m.descartar);
    return m;
  }
}

/// O canal do modo de ecrã (`player_iptv/ecra`) a fingir: um ecrã a 60 Hz que também faz 50.
class _EcraFalso {
  _EcraFalso() {
    const canal = MethodChannel('player_iptv/ecra');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    TaxaEcra.reiniciarGlobal();
    final antes = TaxaEcra.aoIrParaSegundoPlano;
    TaxaEcra.aoIrParaSegundoPlano = (_) {};
    m.setMockMethodCallHandler(canal, (c) async {
      switch (c.method) {
        case 'taxas':
          return {'atual': hz, 'suportadas': [50.0, 60.0]};
        case 'pedir':
          final v = ((c.arguments as Map)['hz'] as num).toDouble();
          pedidos.add(v);
          hz = v;
      }
      return null;
    });
    addTearDown(() {
      m.setMockMethodCallHandler(canal, null);
      TaxaEcra.aoIrParaSegundoPlano = antes;
      TaxaEcra.reiniciarGlobal();
    });
  }

  double hz = 60;
  final pedidos = <double>[];
}

Future<void> _esperar() => pumpEventQueue();

/// Um motor que é sempre descartado no fim do teste (mesmo a falhar: senão a escuta partilhada
/// dos eventos ficava presa a ele).
MotorExo _motor({bool tunel = false}) {
  final m = MotorExo(tunel: tunel);
  addTearDown(m.descartar);
  return m;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MotorExo (canal)', () {
    test('é o exoplayer, sem desentrelaçamento da app', () async {
      _ExoFalso();
      final m = _motor();
      expect(m.nome, 'exoplayer');
      expect(m.suportaDesentrelacamento, isFalse);
      await m.descartar();
    });

    test('abrir manda criar uma vez e abrir com o link, os cabeçalhos e o início', () async {
      final exo = _ExoFalso();
      final m = _motor(tunel: true);
      await m.abrir('http://exemplo.invalid/canal.ts', {'User-Agent': 'Teste'});
      await m.abrir('http://exemplo.invalid/filme.mp4', const {}, inicio: const Duration(seconds: 90));
      expect(exo.de('criar'), hasLength(1));
      expect(exo.args(exo.de('criar').single), {'tunel': true});
      final abrir = exo.de('abrir');
      expect(abrir, hasLength(2));
      expect(exo.args(abrir[0]), {
        'id': 7,
        'url': 'http://exemplo.invalid/canal.ts',
        'cabecalhos': {'User-Agent': 'Teste'},
        'sessao': 1,
      });
      expect(exo.args(abrir[1])['inicioMs'], 90000);
      expect(exo.args(abrir[1])['sessao'], 2, reason: 'cada abrir é uma sessão nova');
      await m.descartar();
    });

    test('os comandos levam o id e os valores do protocolo', () async {
      final exo = _ExoFalso();
      final m = _motor();
      await m.play();
      await m.pausar();
      await m.parar();
      await m.volume(40);
      await m.velocidade(1.5);
      await m.escolherAudio(const FaixaMotor('2:1'));
      await m.escolherLegenda(const FaixaMotor('3:0'));
      await m.escolherLegenda(null);
      await m.escolherLegenda(FaixaMotor.nenhuma);
      final pedidos = [for (final c in exo.chamadas) if (c.method != 'criar') '${c.method} ${exo.args(c)}'];
      expect(pedidos, [
        'play {id: 7}',
        'pausar {id: 7}',
        'parar {id: 7}',
        'volume {id: 7, v: 0.4}',
        'velocidade {id: 7, v: 1.5}',
        'audio {id: 7, grupo: 2, faixa: 1}',
        'legenda {id: 7, grupo: 3, faixa: 0}',
        'legenda {id: 7}',
        'legenda {id: 7}',
      ]);
      await m.descartar();
    });

    test('"Automática" no áudio e nas legendas volta à escolha do ExoPlayer (sem grupo)', () async {
      final exo = _ExoFalso();
      final m = _motor();
      await m.escolherAudio(const FaixaMotor('2:1'));
      await m.escolherAudio(FaixaMotor.auto);
      await m.escolherLegenda(FaixaMotor.auto);
      final pedidos = [for (final c in exo.chamadas) if (c.method != 'criar') '${c.method} ${exo.args(c)}'];
      expect(pedidos, [
        'audio {id: 7, grupo: 2, faixa: 1}',
        'audio {id: 7}',
        'legenda {id: 7, auto: true}',
      ]);
      await m.descartar();
    });

    test('os eventos viram os streams do MotorReproducao', () async {
      final exo = _ExoFalso();
      final m = _motor();
      final carregar = <bool>[], percentagens = <double>[], tamanhos = <Size?>[], posicoes = <Duration>[];
      final erros = <ErroMotor>[], faixas = <FaixasMotor>[], atuais = <FaixaAtual>[];
      var fins = 0;
      m.aCarregar.listen(carregar.add);
      m.percentagemCarga.listen(percentagens.add);
      m.tamanhoVideo.listen(tamanhos.add);
      m.posicao.listen(posicoes.add);
      m.erros.listen(erros.add);
      m.faixas.listen(faixas.add);
      m.faixaAtual.listen(atuais.add);
      m.fim.listen((_) => fins++);
      await m.abrir('http://exemplo.invalid/canal.ts', const {});
      await _esperar();

      exo.evento('aCarregar', {'valor': true, 'percentagem': 40.0});
      exo.evento('aCarregar', {'valor': false, 'percentagem': 100.0});
      exo.evento('pronto');
      exo.evento('tamanho', {'largura': 1920, 'altura': 1080, 'proporcaoPixel': 1.0});
      exo.evento('posicao', {'ms': 1500});
      exo.evento('faixas', {
        'audio': [
          {'grupo': 1, 'faixa': 0, 'lingua': 'por', 'rotulo': 'Estéreo', 'suportada': true},
          {'grupo': 1, 'faixa': 1, 'lingua': 'eng', 'rotulo': null, 'suportada': true},
          {'grupo': 2, 'faixa': 0, 'lingua': 'eng', 'rotulo': 'DTS', 'suportada': false},
        ],
        'legendas': [
          {'grupo': 3, 'faixa': 0, 'lingua': 'por', 'rotulo': null, 'suportada': true},
        ],
      });
      exo.evento('faixaAtual', {
        'audio': {'grupo': 1, 'faixa': 1},
        'legenda': null,
      });
      exo.evento('erro', {'codigo': 'ERROR_CODE_DECODER_INIT_FAILED', 'numero': 4001, 'mensagem': 'Sem descodificador', 'formato': true});
      exo.evento('erro', {'codigo': 'ERROR_CODE_IO_BAD_HTTP_STATUS', 'numero': 2004, 'mensagem': 'HTTP 404', 'formato': false});
      exo.evento('fim');
      await _esperar();

      expect(carregar, [true, false]);
      expect(percentagens, [40.0], reason: 'o % só conta numa paragem');
      expect(tamanhos, [null, const Size(1920, 1080)], reason: 'ao abrir, a imagem do canal anterior deixa de contar');
      expect(posicoes, [const Duration(milliseconds: 1500)]);
      expect(faixas.single.video, isEmpty);
      expect(faixas.single.audio, const [
        FaixaMotor('1:0', titulo: 'Estéreo', lingua: 'por'),
        FaixaMotor('1:1', lingua: 'eng'),
      ], reason: 'as faixas que o aparelho não toca não se oferecem');
      expect(faixas.single.legendas, const [FaixaMotor('3:0', lingua: 'por')]);
      expect(atuais.single.audio, const FaixaMotor('1:1', lingua: 'eng'));
      expect(atuais.single.legenda, FaixaMotor.nenhuma);
      expect([for (final e in erros) (e.mensagem, e.formato)], [('Sem descodificador', true), ('HTTP 404', false)]);
      expect(fins, 1);
      await m.descartar();
    });

    test('zapping: 10 canais seguidos, um só criar e o último abrir ganha', () async {
      final exo = _ExoFalso();
      final m = _motor();
      final tamanhos = <Size?>[];
      m.tamanhoVideo.listen(tamanhos.add);
      // à pressa, sem esperar (o criar ainda não respondeu): só o último chega ao nativo
      final pedidos = [for (var i = 1; i <= 10; i++) m.abrir('http://exemplo.invalid/$i.ts', const {})];
      await Future.wait(pedidos);
      // e um a um, à espera de cada
      for (var i = 11; i <= 20; i++) {
        await m.abrir('http://exemplo.invalid/$i.ts', const {});
      }
      expect(exo.de('criar'), hasLength(1));
      final urls = [for (final c in exo.de('abrir')) exo.args(c)['url']];
      expect(urls.first, 'http://exemplo.invalid/10.ts');
      expect(urls.last, 'http://exemplo.invalid/20.ts');
      expect(urls, hasLength(11));
      expect({for (final c in exo.de('abrir')) exo.args(c)['id']}, {7});
      await _esperar();
      // os eventos de outro player (um id antigo) não contam
      exo.evento('tamanho', {'largura': 720, 'altura': 576, 'proporcaoPixel': 1.0}, 6);
      exo.evento('tamanho', {'largura': 1280, 'altura': 720, 'proporcaoPixel': 1.0});
      await _esperar();
      expect(tamanhos.whereType<Size>(), [const Size(1280, 720)]);
      await m.descartar();
    });

    test('zapping: os eventos atrasados do canal anterior (outra sessão) não contam', () async {
      final exo = _ExoFalso();
      final m = _motor();
      final erros = <ErroMotor>[], tamanhos = <Size?>[], posicoes = <Duration>[];
      var fins = 0;
      m.erros.listen(erros.add);
      m.tamanhoVideo.listen(tamanhos.add);
      m.posicao.listen(posicoes.add);
      m.fim.listen((_) => fins++);
      await m.abrir('http://exemplo.invalid/1.ts', const {});
      await m.abrir('http://exemplo.invalid/2.ts', const {});
      expect([for (final c in exo.de('abrir')) exo.args(c)['sessao']], [1, 2]);
      await _esperar();
      // chegam depois do abrir do canal 2, mas são do carregamento do canal 1
      exo.evento('erro', {'codigo': 'ERROR_CODE_IO_BAD_HTTP_STATUS', 'numero': 2004, 'mensagem': 'HTTP 404', 'formato': false}, null, 1);
      exo.evento('tamanho', {'largura': 720, 'altura': 576, 'proporcaoPixel': 1.0}, null, 1);
      exo.evento('posicao', {'ms': 9000}, null, 1);
      exo.evento('fim', const {}, null, 1);
      await _esperar();
      expect(erros, isEmpty);
      expect(tamanhos.whereType<Size>(), isEmpty);
      expect(posicoes, isEmpty);
      expect(fins, 0);
      // os da sessão atual contam
      exo.evento('erro', {'codigo': 'ERROR_CODE_IO_BAD_HTTP_STATUS', 'numero': 2004, 'mensagem': 'HTTP 404', 'formato': false}, null, 2);
      exo.evento('tamanho', {'largura': 1280, 'altura': 720, 'proporcaoPixel': 1.0}, null, 2);
      await _esperar();
      expect(erros.single.mensagem, 'HTTP 404');
      expect(tamanhos.whereType<Size>(), [const Size(1280, 720)]);
      await m.descartar();
    });

    test('o player aberto duas vezes: o 1.º motor recebe um erro e não fica a carregar', () async {
      final exo = _ExoFalso();
      final primeiro = _motor();
      final erros = <ErroMotor>[];
      primeiro.erros.listen(erros.add);
      await primeiro.abrir('http://exemplo.invalid/1.ts', const {});
      final segundo = _motor();
      await segundo.abrir('http://exemplo.invalid/2.ts', const {});
      await _esperar();
      expect(erros.single.mensagem, 'o player foi aberto noutro ecrã');
      expect(erros.single.formato, isFalse);
      // o 1.º já não pede nada (nem o descartar: o nativo é do 2.º)
      final antes = exo.chamadas.length;
      await primeiro.play();
      await primeiro.descartar();
      expect(exo.chamadas.length, antes);
      await segundo.descartar();
      expect(exo.metodos.last, 'descartar');
    });

    test('descartar manda mostrar(false) e descartar, e larga os eventos', () async {
      final exo = _ExoFalso();
      final m = _motor();
      await m.abrir('http://exemplo.invalid/canal.ts', const {});
      await _esperar();
      expect(exo.aEscutar, 1);
      await m.descartar();
      await _esperar();
      final depois = exo.chamadas.skipWhile((c) => c.method != 'mostrar').toList();
      expect([for (final c in depois) '${c.method} ${exo.args(c)}'], [
        'mostrar {id: 7, visivel: false}',
        'descartar {id: 7}',
      ]);
      expect(exo.cancelados, 1);
      // depois de descartar nada chega ao nativo
      await m.play();
      await m.abrir('http://exemplo.invalid/outro.ts', const {});
      expect(exo.metodos.last, 'descartar');
    });

    test('dois motores seguidos partilham os eventos: largar o antigo não cala o novo', () async {
      final exo = _ExoFalso();
      final antigo = _motor();
      await antigo.abrir('http://exemplo.invalid/a.ts', const {});
      final novo = _motor();
      final posicoes = <Duration>[];
      novo.posicao.listen(posicoes.add);
      await novo.abrir('http://exemplo.invalid/b.ts', const {});
      await antigo.descartar();
      await _esperar();
      exo.evento('posicao', {'ms': 2000});
      await _esperar();
      expect(posicoes, [const Duration(seconds: 2)]);
      await novo.descartar();
    });

    test('estatisticas mapeia perdidas, renderizadas, fps, codec e resolução', () async {
      _ExoFalso(estatisticas: {
        'perdidas': 3,
        'renderizadas': 1200,
        'saltadas': 0,
        'fps': 25.0,
        'codec': 'avc1.64002A',
        'mime': 'video/avc',
        'largura': 1920,
        'altura': 1080,
        'resolucao': '1920x1080',
        'bitrate': 6000000,
        'bufferMs': 4500,
        'tunel': false,
        'visivel': true,
      });
      final m = _motor();
      final e = await m.estatisticas();
      expect(e.perdidas, 3);
      expect(e.renderizadas, 1200);
      expect(e.fps, 25.0);
      expect(e.codec, 'avc1.64002A');
      expect(e.resolucao, const Size(1920, 1080));
      expect(e.bitrate, 6000000);
      expect(e.buffer, const Duration(milliseconds: 4500));
      await m.descartar();
    });

    test('M1: estatisticas traz o descodificador (hardware ou software) e se o túnel ficou ativo', () async {
      _ExoFalso(estatisticas: {
        'perdidas': 0,
        'renderizadas': 10,
        'descodificador': 'OMX.amlogic.avc.decoder.awesome',
        'hardware': true,
        'tunel': true,
        'tunelAtivo': false,
      });
      final m = _motor();
      final e = await m.estatisticas();
      expect(e.descodificador, 'OMX.amlogic.avc.decoder.awesome');
      expect(e.hardware, isTrue);
      expect(e.tunelPedido, isTrue);
      expect(e.tunelAtivo, isFalse);
      await m.descartar();
    });

    test('C1: o fps medido pelo nativo (evento fps) vale quando o formato não o diz, e recomeça a cada sessão', () async {
      final exo = _ExoFalso(estatisticas: {'perdidas': 0, 'renderizadas': 40, 'fps': null, 'largura': 1920, 'altura': 1080});
      final m = _motor();
      final medidos = <double>[];
      m.fps.listen(medidos.add);
      await m.abrir('http://exemplo.invalid/1.ts', const {});
      await _esperar();
      expect((await m.estatisticas()).fps, isNull, reason: 'TS sem fps no formato: ainda por medir');
      exo.evento('fps', {'valor': 50.0});
      await _esperar();
      expect(medidos, [50.0]);
      expect((await m.estatisticas()).fps, 50.0);
      // outro canal (sessão nova): a medição recomeça; um fps atrasado do anterior não conta
      await m.abrir('http://exemplo.invalid/2.ts', const {});
      await _esperar();
      exo.evento('fps', {'valor': 50.0}, null, 1);
      await _esperar();
      expect(medidos, [50.0]);
      expect((await m.estatisticas()).fps, isNull);
      exo.evento('fps', {'valor': 25.0});
      await _esperar();
      expect(medidos, [50.0, 25.0]);
      expect((await m.estatisticas()).fps, 25.0);
      await m.descartar();
    });

    test('C3: o nativo diz se é um direto (pronto e fim) e se um erro é de rede', () async {
      final exo = _ExoFalso();
      final m = _motor();
      final erros = <ErroMotor>[];
      m.erros.listen(erros.add);
      await m.abrir('http://exemplo.invalid/1.ts', const {});
      await _esperar();
      expect(m.direto, isNull, reason: 'ainda não se sabe');
      exo.evento('pronto', {'direto': false});
      await _esperar();
      expect(m.direto, isFalse);
      exo.evento('fim', {'direto': true});
      exo.evento('erro', {'codigo': 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED', 'numero': 2001, 'mensagem': 'Falha de rede ao abrir o canal', 'formato': false, 'rede': true});
      await _esperar();
      expect(m.direto, isTrue);
      expect(erros.single.rede, isTrue);
      await m.abrir('http://exemplo.invalid/2.ts', const {});
      expect(m.direto, isNull, reason: 'canal novo: por saber outra vez');
      await m.descartar();
    });

    test('M2: o evento primeiraImagem (da sessão atual) vira o stream primeiraImagem', () async {
      final exo = _ExoFalso();
      final m = _motor();
      var imagens = 0;
      m.primeiraImagem.listen((_) => imagens++);
      await m.abrir('http://exemplo.invalid/1.ts', const {});
      await m.abrir('http://exemplo.invalid/2.ts', const {});
      await _esperar();
      exo.evento('primeiraImagem', const {}, null, 1); // do canal anterior
      await _esperar();
      expect(imagens, 0);
      exo.evento('primeiraImagem');
      await _esperar();
      expect(imagens, 1);
      await m.descartar();
    });

    test('estatisticas sem vídeo: nulls, não lança', () async {
      _ExoFalso(estatisticas: {'perdidas': 0, 'renderizadas': 0, 'fps': null, 'codec': null, 'resolucao': null});
      final m = _motor();
      final e = await m.estatisticas();
      expect(e.resolucao, isNull);
      expect(e.fps, isNull);
      expect(e.codec, isNull);
      await m.descartar();
    });

    test('os erros mostrados não contêm o link', () async {
      final exo = _ExoFalso(falharAbrir: 'Falhou http://exemplo.invalid/live/utilizador/segredo/1.ts');
      final m = _motor();
      final erros = <ErroMotor>[];
      m.erros.listen(erros.add);
      // o pedido recusado não lança: vira um erro do motor
      await m.abrir('http://exemplo.invalid/live/utilizador/segredo/1.ts', const {});
      await _esperar();
      exo.evento('erro', {
        'codigo': 'ERROR_CODE_IO_UNSPECIFIED',
        'numero': 2000,
        'mensagem': 'Falha ao abrir http://exemplo.invalid/live/utilizador/segredo/1.ts',
        'formato': false,
      });
      await _esperar();
      expect(erros, hasLength(2));
      for (final e in erros) {
        expect(e.mensagem, isNot(contains('exemplo.invalid')));
        expect(e.mensagem, isNot(contains('segredo')));
        expect(e.mensagem, isNotEmpty);
      }
      await m.descartar();
    });

    test('sem ExoPlayer no aparelho (criar falha): um erro de formato, para passar ao mpv', () async {
      final exo = _ExoFalso(falharCriar: true);
      final m = _motor();
      final erros = <ErroMotor>[];
      m.erros.listen(erros.add);
      await m.abrir('http://exemplo.invalid/canal.ts', const {});
      await _esperar();
      expect(exo.de('abrir'), isEmpty);
      expect(erros.single.formato, isTrue);
      await m.descartar();
    });
  });

  group('MotorExo.video', () {
    Future<void> montar(WidgetTester t, Widget w) => t.pumpWidget(MaterialApp(home: w));

    testWidgets('mostra o vídeo ao montar, manda o ajuste quando muda e esconde ao desmontar', (t) async {
      final exo = _ExoFalso();
      final m = exo.motor();
      await montar(t, m.video(ajuste: BoxFit.contain));
      await t.pump();
      expect([for (final c in exo.chamadas) if (c.method != 'criar') '${c.method} ${exo.args(c)}'], [
        'mostrar {id: 7, visivel: true}',
        'ajuste {id: 7, modo: ajustar}',
      ]);
      exo.chamadas.clear();
      await montar(t, m.video(ajuste: BoxFit.contain));
      await t.pump();
      expect(exo.chamadas, isEmpty, reason: 'o mesmo ajuste não se manda outra vez');
      await montar(t, m.video(ajuste: BoxFit.cover));
      await montar(t, m.video(ajuste: BoxFit.fill));
      await montar(t, m.video(ajuste: BoxFit.contain, proporcao: 4 / 3));
      await t.pump();
      expect([for (final c in exo.chamadas) exo.args(c)], [
        {'id': 7, 'modo': 'preencher'},
        {'id': 7, 'modo': 'esticar'},
        {'id': 7, 'modo': 'ajustar', 'proporcao': 4 / 3},
      ]);
      exo.chamadas.clear();
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect([for (final c in exo.chamadas) '${c.method} ${exo.args(c)}'], [
        'mostrar {id: 7, visivel: false}',
      ]);
      await m.descartar();
    });

    testWidgets('mudar o vídeo de sítio na árvore não pisca o mostrar', (t) async {
      final exo = _ExoFalso();
      final m = exo.motor();
      await montar(t, m.video(ajuste: BoxFit.contain));
      await t.pump();
      exo.chamadas.clear();
      // outro pai: o antigo é desmontado depois de o novo montar
      await montar(t, Center(child: m.video(ajuste: BoxFit.contain)));
      await t.pump();
      expect(exo.de('mostrar'), isEmpty);
      await m.descartar();
    });

    testWidgets('a área é transparente e desenha o texto das legendas', (t) async {
      final exo = _ExoFalso();
      final m = exo.motor();
      await montar(t, m.video(ajuste: BoxFit.contain));
      await t.pump();
      final opacos = find.descendant(
          of: find.byKey(ObjectKey(m)),
          matching: find.byWidgetPredicate((w) => (w is ColoredBox && w.color.a > 0) ||
              (w is Container && w.color != null && w.color!.a > 0) ||
              (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color != null)));
      expect(opacos, findsNothing);
      exo.evento('legendaTexto', {'texto': 'Olá\nmundo'});
      await t.pump();
      await t.pump();
      expect(find.text('Olá\nmundo'), findsOneWidget);
      exo.evento('legendaTexto', {'texto': ''});
      await t.pump();
      await t.pump();
      expect(find.text('Olá\nmundo'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await m.descartar();
    });

    testWidgets('enquanto o vídeo nativo está montado, o FundoCinema não pinta', (t) async {
      final m = _ExoFalso().motor();
      final mostrar = ValueNotifier(false);
      addTearDown(mostrar.dispose);
      // sem MaterialApp: a faixa "debug" e a transição da rota também pintam retângulos
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(1920, 1080)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FundoCinema(
            child: ValueListenableBuilder<bool>(
              valueListenable: mostrar,
              builder: (_, v, _) => v ? m.video(ajuste: BoxFit.contain) : const SizedBox.expand(),
            ),
          ),
        ),
      ));
      final fundo = t.renderObject<RenderBox>(find.byType(FundoCinema));
      expect(fundo, paints..rect(), reason: 'fora do player o fundo é opaco');
      mostrar.value = true;
      await t.pump();
      expect(fundo, isNot(paints..rect()));
      mostrar.value = false;
      await t.pump();
      expect(fundo, paints..rect(), reason: 'ao sair do player o fundo volta no mesmo frame');
      await m.descartar();
    });
  });

  group('PlayerCanais com o MotorExo', () {
    const canal = Canal(id: '1', nome: 'RTP 1', grupo: 'Generalistas');
    const canal2 = Canal(id: '2', nome: 'RTP 2', grupo: 'Generalistas');

    /// [escala]: como no main.dart, a escala da interface (Compacto) por dentro do [FundoCinema].
    Future<void> montarPlayer(WidgetTester t, _ExoFalso exo,
        {FormatoImagem formato = FormatoImagem.ajustar, bool android = false, bool escala = false}) async {
      t.view.physicalSize = const Size(1920, 1080);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final antes = Preferencias.atual;
      Preferencias.atual = Preferencias.omissao()
        ..formato = formato
        ..motorAndroid = MotorAndroid.exoplayer
        ..ajustarTaxaEcra = true;
      addTearDown(() => Preferencias.atual = antes);
      await t.pumpWidget(MaterialApp(
        theme: temaApp(),
        builder: (_, w) => FundoCinema(
            child: escala ? EscalaConformePreferencias(preferencias: Preferencias.atual, child: w!) : w!),
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: PlayerCanais(
            canais: const [canal, canal2],
            indice: 0,
            nomeLista: 'Lista A',
            aoSair: () {},
            resolver: (c, {continuar = false}) async =>
                FonteVideo('http://exemplo.invalid/${c.id}.ts', const {'User-Agent': 'Teste'}),
            criarMotor: (_, _) => exo.motor(),
            criarMotorExo: ({required bool tunel}) => exo.motor(),
            plataforma: android ? PlataformaVideo.android : null,
            agora: () => t.binding.clock.now(),
          ),
        ),
      ));
      await t.pump();
      await t.pump();
    }

    testWidgets('mostra o vídeo antes de abrir, abre o canal e ao sair descarta', (t) async {
      final exo = _ExoFalso();
      await montarPlayer(t, exo);
      expect(exo.de('criar'), hasLength(1));
      final m = exo.metodos;
      expect(m.indexOf('mostrar'), lessThan(m.indexOf('abrir')), reason: 'a faixa de vídeo liga-se antes de preparar');
      expect(exo.args(exo.de('abrir').single), {
        'id': 7,
        'url': 'http://exemplo.invalid/1.ts',
        'cabecalhos': {'User-Agent': 'Teste'},
        'sessao': 1,
      });
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      expect(exo.metodos.sublist(exo.metodos.length - 2), ['mostrar', 'descartar']);
      expect(exo.args(exo.de('mostrar').last)['visivel'], isFalse);
    });

    testWidgets('zapping no ecrã: o mesmo player, sem mexer no mostrar', (t) async {
      final exo = _ExoFalso();
      await montarPlayer(t, exo);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      final urls = [for (final c in exo.de('abrir')) exo.args(c)['url']];
      expect(urls, hasLength(2));
      expect(urls.last, isNot(urls.first));
      expect(exo.de('criar'), hasLength(1));
      expect(exo.de('mostrar'), hasLength(1));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('nenhum fundo opaco por cima do vídeo nativo', (t) async {
      final exo = _ExoFalso();
      await montarPlayer(t, exo);
      final video = find.byWidgetPredicate((w) => w.key is ObjectKey && (w.key! as ObjectKey).value is MotorExo);
      expect(video, findsOneWidget);
      final opacosPorCima = find.ancestor(
          of: video,
          matching: find.byWidgetPredicate((w) =>
              (w is ColoredBox && w.color.a > 0) ||
              (w is Material && w.type != MaterialType.transparency && (w.color?.a ?? 0) > 0)));
      expect(opacosPorCima, findsNothing);
      expect(FundoCinema.videoPorBaixo.value, 1, reason: 'o fundo da app não se pinta por baixo do vídeo');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('na TV a 80 % (Compacto): o vídeo é transparente, enche o ecrã e o fundo não se pinta', (t) async {
      EcraTv.nativo = true;
      addTearDown(() => EcraTv.nativo = false);
      final exo = _ExoFalso();
      await montarPlayer(t, exo, escala: true);
      expect(Preferencias.atual.tamanhoInterface, TamanhoInterface.compacto);
      expect(
          find.byWidgetPredicate((w) => w is Transform && (w.transform.storage[0] - escalaCompacto).abs() < .001),
          findsOneWidget,
          reason: 'a interface está a 80 %');
      final video = find.byWidgetPredicate((w) => w.key is ObjectKey && (w.key! as ObjectKey).value is MotorExo);
      expect(video, findsOneWidget);
      // a área transparente (no ecrã, depois da redução) cobre a janela toda: a SurfaceView vê-se toda
      expect(t.getRect(video), const Rect.fromLTWH(0, 0, 1920, 1080));
      final opacosPorCima = find.ancestor(
          of: video,
          matching: find.byWidgetPredicate((w) =>
              (w is ColoredBox && w.color.a > 0) ||
              (w is Material && w.type != MaterialType.transparency && (w.color?.a ?? 0) > 0)));
      expect(opacosPorCima, findsNothing);
      expect(FundoCinema.videoPorBaixo.value, 1, reason: 'o fundo da app não se pinta por baixo do vídeo');
      expect(find.byType(FundoCinema), isNot(paints..rect(rect: const Rect.fromLTWH(0, 0, 1920, 1080))),
          reason: 'o gradiente do fundo não se pinta');

      // mudar para Normal com o vídeo a tocar: o mesmo player, o fundo continua sem pintar
      Preferencias.atual.tamanhoInterface = TamanhoInterface.normal;
      await t.pump();
      await t.pump();
      expect(t.getRect(video), const Rect.fromLTWH(0, 0, 1920, 1080));
      expect(FundoCinema.videoPorBaixo.value, 1);
      expect(exo.de('criar'), hasLength(1), reason: 'a escala não recria o player');
      expect(exo.args(exo.de('mostrar').last)['visivel'], isTrue, reason: 'o vídeo não se esconde');

      // ao sair, o fundo volta
      await t.pumpWidget(FundoCinema(child: const SizedBox.expand()));
      expect(FundoCinema.videoPorBaixo.value, 0);
      expect(find.byType(FundoCinema), paints..rect(rect: const Rect.fromLTWH(0, 0, 1920, 1080)));
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('o zoom passa a preencher (o ExoPlayer não tem zoom)', (t) async {
      final exo = _ExoFalso();
      await montarPlayer(t, exo, formato: FormatoImagem.zoom);
      expect(exo.args(exo.de('ajuste').last)['modo'], 'preencher');
      final video = find.byWidgetPredicate((w) => w.key is ObjectKey && (w.key! as ObjectKey).value is MotorExo);
      expect(
          find.ancestor(
              of: video,
              matching: find.byWidgetPredicate((w) => w is Transform && w.transform.getMaxScaleOnAxis() > 1.01)),
          findsNothing,
          reason: 'o aumento do Flutter não mexe na SurfaceView');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('C1: sem fps no formato (TS/HLS), o fps medido pelo nativo pede os 50 Hz e aparece nas estatísticas',
        (t) async {
      final exo = _ExoFalso(estatisticas: {'perdidas': 0, 'renderizadas': 40, 'fps': null, 'largura': 1920, 'altura': 1080});
      final ecra = _EcraFalso();
      await montarPlayer(t, exo, android: true);
      // as tentativas de ler o fps do formato passam sem nada (o TS não o diz)
      await t.pump(const Duration(seconds: 6));
      expect(ecra.pedidos, isEmpty, reason: 'sem fps não se pede modo');
      exo.evento('fps', {'valor': 50.0});
      await t.pump();
      await t.pump();
      expect(ecra.pedidos, [50.0]);
      await t.pump(const Duration(seconds: 4)); // a TV a mudar de modo
      t.state<PlayerCanaisState>(find.byType(PlayerCanais)).alternarEstatisticas();
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Imagens/s'), findsOneWidget);
      expect(find.text('50.00'), findsOneWidget);
      // o mesmo fps outra vez não volta a pedir
      exo.evento('fps', {'valor': 50.0});
      await t.pump(const Duration(seconds: 1));
      expect(ecra.pedidos, [50.0]);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('16:9 e 4:3 vão como proporção do ajuste', (t) async {
      final exo = _ExoFalso();
      await montarPlayer(t, exo, formato: FormatoImagem.r4x3);
      expect(exo.args(exo.de('ajuste').last), {'id': 7, 'modo': 'ajustar', 'proporcao': 4 / 3});
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });
}
