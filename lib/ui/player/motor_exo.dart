import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/preferencias.dart';
import '../../rede/http.dart';
import '../design/componentes.dart';
import '../design/ecra.dart';
import 'motor_reproducao.dart';

/// A fábrica do [MotorExo] do ecrã do player (o `CriarMotorExo` dele).
MotorReproducao novoMotorExo({required bool tunel, required bool memoria}) => MotorExo(tunel: tunel, memoria: memoria);

/// Como o vídeo do ExoPlayer mostra cada formato de imagem: o ajuste vai para o nativo (a
/// `SurfaceView` fica com o tamanho certo dentro da caixa), por isso não há aumento no Flutter. O
/// nativo não tem "Zoom": fica "Preencher" (também tira as barras, cortando as pontas).
({BoxFit fit, double? aspecto, double escala}) ajusteVideoExo(FormatoImagem f) => switch (f) {
      FormatoImagem.ajustar => (fit: BoxFit.contain, aspecto: null, escala: 1.0),
      FormatoImagem.preencher || FormatoImagem.zoom => (fit: BoxFit.cover, aspecto: null, escala: 1.0),
      FormatoImagem.esticar => (fit: BoxFit.fill, aspecto: null, escala: 1.0),
      FormatoImagem.r16x9 => (fit: BoxFit.contain, aspecto: 16 / 9, escala: 1.0),
      FormatoImagem.r4x3 => (fit: BoxFit.contain, aspecto: 4 / 3, escala: 1.0),
    };

/// O [MotorReproducao] do ExoPlayer (Media3) do Android: fala com o `ReprodutorExo` nativo pelo
/// canal `player_iptv/exo` (métodos) e `player_iptv/exo/eventos` (eventos `{id, tipo, …}`).
///
/// O vídeo vai do MediaCodec para uma `SurfaceView` por baixo da interface: [video] é uma área
/// transparente (o "buraco" por onde se vê) com as legendas por cima, desenhadas aqui.
///
/// Um player nativo por motor: `criar` uma vez (no construtor); o zapping é `abrir` no mesmo `id`.
/// Os eventos de outro `id` (um player antigo) não contam.
class MotorExo implements MotorReproducao, MotorComProcura {
  /// Pede logo o player nativo (`criar`, uma vez por motor). `fonteEventos`: só para testes de
  /// widgets (no lugar do [EventChannel], cujo `cancel` lá nunca acaba).
  MotorExo(
      {this.tunel = false,
      this.memoria = false,
      this.canal = canalPadrao,
      EventChannel eventos = eventosPadrao,
      @visibleForTesting Stream<Object?>? fonteEventos}) {
    _subEventos = (fonteEventos ?? _eventosDe(eventos)).listen(_aoEvento, onError: (Object e) {
      debugPrint('exoplayer: erro no canal de eventos (${e.runtimeType})');
    });
    _id = _criar();
  }

  static const canalPadrao = MethodChannel('player_iptv/exo');
  static const eventosPadrao = EventChannel('player_iptv/exo/eventos');

  /// O nativo tem um só destino de eventos: um `listen` novo cala o anterior e um `cancel` cala o
  /// atual. Por isso os motores partilham uma só escuta por canal (o motor novo começa a ouvir
  /// antes de o antigo ser largado, ao recriar o player).
  static final _escutas = <String, Stream<Object?>>{};
  static Stream<Object?> _eventosDe(EventChannel c) => _escutas[c.name] ??= c.receiveBroadcastStream();

  /// Túnel de vídeo (decidido ao criar o player).
  final bool tunel;

  /// O modo Memória do recuo: o nativo guarda um back buffer (~128 MiB) para recuar sem
  /// gravar (decidido ao criar o player).
  final bool memoria;
  /// O canal dos métodos (nos testes, um falso).
  final MethodChannel canal;
  late final StreamSubscription<Object?> _subEventos;

  /// O id do player nativo (null: o ExoPlayer não existe neste aparelho).
  late final Future<int?> _id;
  int? _idConhecido;
  bool _descartado = false;

  /// O motor com o player nativo agora: um `criar` novo (outro ecrã) tira-o ao anterior.
  static MotorExo? _vivo;

  /// Outro motor criou o seu player: o nativo ignora os pedidos deste (id antigo).
  bool _substituido = false;

  /// O último `abrir` pedido: um mais antigo que ainda espera pelo `criar` já não vai. É também a
  /// `sessao` do carregamento: o nativo põe-na em todos os eventos e os de outra sessão (atrasados
  /// do canal anterior, no zapping, com o mesmo id) não contam.
  int _pedidoAbrir = 0;
  String? _url;

  /// As imagens por segundo medidas pelo nativo nesta sessão (null até haver imagens que cheguem).
  double? _fpsMedido;

  /// Quantas vezes o [video] está montado (mostra-se de 0 para 1, esconde-se de 1 para 0).
  int _montados = 0;
  bool? _visivelEnviado;
  ({String modo, double? proporcao})? _ajusteEnviado;

  /// As faixas como vieram no último evento (para a faixa atual ser a mesma da lista).
  final _porId = <String, FaixaMotor>{};

  /// O texto da legenda agora (vazio: nenhuma).
  final legenda = ValueNotifier<String>('');

  final _erros = StreamController<ErroMotor>.broadcast();
  final _aCarregar = StreamController<bool>.broadcast();
  final _percentagem = StreamController<double>.broadcast();
  final _tamanho = StreamController<Size?>.broadcast();
  final _posicao = StreamController<Duration>.broadcast();
  final _fim = StreamController<void>.broadcast();
  final _faixas = StreamController<FaixasMotor>.broadcast();
  final _faixaAtual = StreamController<FaixaAtual>.broadcast();
  final _fps = StreamController<double>.broadcast();
  final _primeiraImagem = StreamController<void>.broadcast();

  @override
  String get nome => 'exoplayer';

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
  Stream<double> get fps => _fps.stream;

  @override
  bool? get direto => _direto;

  @override
  Stream<void> get primeiraImagem => _primeiraImagem.stream;

  /// O que o nativo disse do canal aberto (no `pronto` e no `fim`); null até lá.
  bool? _direto;

  // ---------------------------------------------------------------- pedidos

  Future<int?> _criar() async {
    try {
      final id = await canal.invokeMethod<int>('criar', {'tunel': tunel, 'memoria': memoria});
      _idConhecido = id;
      // o player aberto duas vezes (toque duplo): o anterior perdeu o seu player no nativo; sem
      // aviso ficava "a carregar" para sempre
      final anterior = _vivo;
      _vivo = this;
      if (anterior != null && !identical(anterior, this)) anterior._perdeuPlayer();
      return id;
    } catch (e) {
      // sem o lado nativo (outra plataforma, versão antiga): o ecrã pode passar ao mpv
      debugPrint('exoplayer: não foi possível criar o player (${e.runtimeType})');
      _erro('o ExoPlayer não está disponível neste aparelho', formato: true);
      return null;
    }
  }

  /// Manda [metodo] ao player deste motor (nada depois de [descartar] ou sem player). Um pedido
  /// recusado vira um erro do motor (sem o link), nunca uma exceção.
  Future<T?> _pedir<T>(String metodo, [Map<String, Object?> args = const {}, bool Function()? aindaVale]) async {
    if (_descartado) return null;
    final id = await _id;
    if (id == null || _descartado || _substituido) return null;
    if (aindaVale != null && !aindaVale()) return null;
    try {
      return await canal.invokeMethod<T>(metodo, {'id': id, ...args});
    } on PlatformException catch (e) {
      debugPrint('exoplayer: $metodo recusado (${e.code})');
      _erro(e.message ?? 'o ExoPlayer recusou o pedido');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> abrir(String url, Map<String, String> cabecalhos, {Duration? inicio}) async {
    if (_descartado) return;
    final pedido = ++_pedidoAbrir;
    _url = url;
    // a medição do fps recomeça com o canal
    _fpsMedido = null;
    _direto = null;
    // a imagem do canal anterior deixa de contar (como o stop do mpv)
    _tamanho.add(null);
    legenda.value = '';
    await _pedir<void>(
      'abrir',
      {
        'url': url,
        'cabecalhos': cabecalhos,
        'sessao': pedido,
        if (inicio != null) 'inicioMs': inicio.inMilliseconds,
      },
      () => pedido == _pedidoAbrir,
    );
  }

  @override
  Future<JanelaMotor?> janela() async {
    final m = await _pedir<Map<Object?, Object?>>('janela');
    if (m == null) return null;
    Duration? ms(String k) => switch (m[k]) { final num v when v >= 0 => Duration(milliseconds: v.round()), _ => null };
    final posicao = ms('posicaoMs');
    if (posicao == null) return null;
    return JanelaMotor(
      posicao: posicao,
      duracao: ms('duracaoMs'),
      bufferAte: ms('bufferAteMs'),
      procuravel: m['procuravel'] == true,
      direto: m['direto'] != false,
    );
  }

  @override
  Future<void> seekTo(Duration posicao) =>
      _pedir<void>('seekTo', {'ms': posicao.isNegative ? 0 : posicao.inMilliseconds});

  @override
  Future<void> play() => _pedir<void>('play');

  @override
  Future<void> pausar() => _pedir<void>('pausar');

  @override
  Future<void> parar() async {
    if (_descartado) return;
    _tamanho.add(null);
    legenda.value = '';
    return _pedir<void>('parar');
  }

  /// Uma faixa concreta (`grupo:faixa`) ou a "Automática" (sem grupo: o nativo tira a escolha e
  /// volta à do ExoPlayer).
  @override
  Future<void> escolherAudio(FaixaMotor faixa) async {
    final gf = _grupoFaixa(faixa.id);
    if (gf == null && faixa.id != FaixaMotor.auto.id) return;
    await _pedir<void>('audio', {if (gf != null) 'grupo': gf.$1, if (gf != null) 'faixa': gf.$2});
  }

  /// null ou "nenhuma": desliga; "auto": a escolha do ExoPlayer; senão a faixa `grupo:faixa`.
  @override
  Future<void> escolherLegenda(FaixaMotor? faixa) async {
    final gf = faixa == null ? null : _grupoFaixa(faixa.id);
    final auto = faixa?.id == FaixaMotor.auto.id;
    if (faixa != null && faixa.id != FaixaMotor.nenhuma.id && gf == null && !auto) return;
    await _pedir<void>('legenda', {
      if (gf != null) 'grupo': gf.$1,
      if (gf != null) 'faixa': gf.$2,
      if (auto) 'auto': true,
    });
    if (gf == null) legenda.value = '';
  }

  static (int, int)? _grupoFaixa(String id) {
    final partes = id.split(':');
    if (partes.length != 2) return null;
    final g = int.tryParse(partes[0]), f = int.tryParse(partes[1]);
    return g == null || f == null ? null : (g, f);
  }

  @override
  Future<void> velocidade(double v) => _pedir<void>('velocidade', {'v': v});

  @override
  Future<void> volume(double v) => _pedir<void>('volume', {'v': (v / 100).clamp(0.0, 1.0)});

  @override
  Future<EstatisticasMotor> estatisticas() async {
    final m = await _pedir<Map<Object?, Object?>>('estatisticas');
    if (m == null) return const EstatisticasMotor();
    double? n(String k) => switch (m[k]) { final num v => v.toDouble(), _ => null };
    bool? b(String k) => switch (m[k]) { final bool v => v, _ => null };
    int? i(String k) => n(k)?.round();
    String? s(String k) => switch (m[k]) { final String v when v.trim().isNotEmpty => v.trim(), _ => null };
    Size? resolucao;
    final w = n('largura'), h = n('altura');
    if (w != null && h != null && w > 0 && h > 0) {
      resolucao = Size(w, h);
    } else {
      final r = s('resolucao')?.split('x');
      final rw = r?.length == 2 ? double.tryParse(r![0]) : null, rh = r?.length == 2 ? double.tryParse(r![1]) : null;
      if (rw != null && rh != null && rw > 0 && rh > 0) resolucao = Size(rw, rh);
    }
    // o fps do formato, ou o medido nas imagens (o TS e o HLS sem FRAME-RATE não o dizem)
    final fps = n('fps') ?? _fpsMedido, buffer = i('bufferMs'), bitrate = n('bitrate');
    return EstatisticasMotor(
      resolucao: resolucao,
      fps: fps != null && fps > 0 ? fps : null,
      codec: s('codec') ?? s('mime'),
      perdidas: i('perdidas'),
      renderizadas: i('renderizadas'),
      bitrate: bitrate != null && bitrate > 0 ? bitrate : null,
      buffer: buffer == null ? null : Duration(milliseconds: buffer),
      descodificador: s('descodificador'),
      hardware: b('hardware'),
      tunelPedido: b('tunel'),
      tunelAtivo: b('tunelAtivo'),
    );
  }

  /// Mostra ou esconde a `SurfaceView` (escondida, o nativo larga o descodificador de vídeo).
  void _mostrar(bool visivel) {
    if (_visivelEnviado == visivel) return;
    _visivelEnviado = visivel;
    unawaited(_pedir<void>('mostrar', {'visivel': visivel}));
  }

  void _ajustar(BoxFit fit, double? proporcao) {
    final a = (
      modo: switch (fit) {
        BoxFit.cover => 'preencher',
        BoxFit.fill => 'esticar',
        _ => 'ajustar',
      },
      proporcao: proporcao != null && proporcao > 0 ? proporcao : null,
    );
    if (a == _ajusteEnviado) return;
    _ajusteEnviado = a;
    unawaited(_pedir<void>('ajuste', {'modo': a.modo, if (a.proporcao != null) 'proporcao': a.proporcao}));
  }

  @override
  Widget video({required BoxFit ajuste, double? proporcao}) =>
      _VideoExo(key: ObjectKey(this), motor: this, ajuste: ajuste, proporcao: proporcao);

  /// Esconde o vídeo e larga o player nativo (só o deste motor: um `id` antigo é ignorado lá).
  @override
  Future<void> descartar() async {
    if (_descartado) return;
    // os pedidos que ainda esperam pelo criar já não vão
    _pedidoAbrir++;
    final id = await _id;
    if (_descartado) return;
    _descartado = true;
    if (identical(_vivo, this)) _vivo = null;
    if (id != null && !_substituido) {
      try {
        if (_visivelEnviado != false) await canal.invokeMethod<void>('mostrar', {'id': id, 'visivel': false});
        _visivelEnviado = false;
        await canal.invokeMethod<void>('descartar', {'id': id});
      } catch (e) {
        debugPrint('exoplayer: descartar falhou (${e.runtimeType})');
      }
    }
    // sem esperar: o cancel de uma subscrição pode devolver um futuro de outra zona (nos testes de
    // widgets nunca acabava) e nada depende dele
    unawaited(_subEventos.cancel());
    for (final c in [_erros, _aCarregar, _percentagem, _tamanho, _posicao, _fim, _faixas, _faixaAtual, _fps, _primeiraImagem]) {
      unawaited(c.close());
    }
    legenda.value = '';
  }

  /// Outro motor criou o seu player: este já não toca nada (o ecrã mostra o erro e pode tentar de
  /// novo, com um motor novo, ou sair).
  void _perdeuPlayer() {
    if (_descartado || _substituido) return;
    _substituido = true;
    _erro('o player foi aberto noutro ecrã');
  }

  // ---------------------------------------------------------------- eventos

  /// A mensagem nunca leva o link (nem o deste canal, nem outro qualquer).
  void _erro(String mensagem, {bool formato = false, bool rede = false}) {
    if (_descartado || _erros.isClosed) return;
    var m = mensagem;
    final url = _url;
    if (url != null && url.isNotEmpty) m = m.replaceAll(url, '');
    m = semSegredos(m);
    if (m.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').isEmpty) m = 'o ExoPlayer não conseguiu tocar o canal';
    _erros.add(ErroMotor(m, formato: formato, rede: rede));
  }

  void _aoEvento(Object? e) {
    if (_descartado || e is! Map) return;
    final id = _idConhecido;
    if (id == null || e['id'] != id || _substituido) return; // outro player (ou o criar ainda não respondeu)
    // outro carregamento: um evento atrasado do canal anterior (o nativo põe 0 antes do 1.º abrir)
    if ((e['sessao'] ?? 0) != _pedidoAbrir) return;
    switch (e['tipo']) {
      case 'aCarregar':
        final valor = e['valor'] == true;
        // o % só conta numa paragem (o 100 do fim apagava o "A carregar…" da paragem seguinte)
        final p = e['percentagem'];
        if (valor && p is num) _percentagem.add(p.toDouble());
        _aCarregar.add(valor);
      case 'tamanho':
        if (e['largura'] case final num w when w > 0) {
          if (e['altura'] case final num h when h > 0) _tamanho.add(Size(w.toDouble(), h.toDouble()));
        }
      case 'posicao':
        if (e['ms'] case final num ms) _posicao.add(Duration(milliseconds: ms.round()));
      case 'fim':
        if (e['direto'] case final bool d) _direto = d;
        _fim.add(null);
      case 'fps':
        if (e['valor'] case final num v when v > 0) {
          _fpsMedido = v.toDouble();
          _fps.add(v.toDouble());
        }
      case 'erro':
        if (e['codigo'] case final String codigo) debugPrint('exoplayer: erro $codigo (${e['numero']})');
        _erro(e['mensagem'] is String ? e['mensagem'] as String : '',
            formato: e['formato'] == true, rede: e['rede'] == true);
      case 'faixas':
        _porId.clear();
        List<FaixaMotor> lista(Object? l) => [
              if (l is List)
                for (final f in l)
                  if (f is Map && f['suportada'] != false && f['grupo'] is int && f['faixa'] is int)
                    _porId['${f['grupo']}:${f['faixa']}'] = FaixaMotor(
                      '${f['grupo']}:${f['faixa']}',
                      titulo: f['rotulo'] is String ? f['rotulo'] as String : null,
                      lingua: f['lingua'] is String ? f['lingua'] as String : null,
                    ),
            ];
        _faixas.add(FaixasMotor(audio: lista(e['audio']), legendas: lista(e['legendas'])));
      case 'faixaAtual':
        FaixaMotor? de(Object? f) {
          if (f is! Map || f['grupo'] is! int || f['faixa'] is! int) return null;
          final k = '${f['grupo']}:${f['faixa']}';
          return _porId[k] ?? FaixaMotor(k);
        }
        _faixaAtual.add(FaixaAtual(
          audio: de(e['audio']) ?? FaixaMotor.auto,
          legenda: de(e['legenda']) ?? FaixaMotor.nenhuma,
        ));
      case 'legendaTexto':
        legenda.value = e['texto'] is String ? e['texto'] as String : '';
      case 'primeiraImagem':
        _primeiraImagem.add(null);
      case 'pronto':
        // o ecrã sabe que abriu pela imagem e pela posição; aqui só se é um direto
        if (e['direto'] case final bool d) _direto = d;
    }
  }
}

/// A área do vídeo nativo: transparente (vê-se a `SurfaceView` por baixo da interface) com o texto
/// das legendas. Montada, mostra o vídeo e tira o fundo da app ([FundoCinema.videoPorBaixo]);
/// desmontada, esconde-o.
class _VideoExo extends StatefulWidget {
  const _VideoExo({super.key, required this.motor, required this.ajuste, this.proporcao});
  final MotorExo motor;
  final BoxFit ajuste;
  final double? proporcao;

  @override
  State<_VideoExo> createState() => _VideoExoState();
}

class _VideoExoState extends State<_VideoExo> {
  bool _semFundo = false;

  void _tirarFundo(bool sim) {
    if (_semFundo == sim) return;
    _semFundo = sim;
    FundoCinema.videoPorBaixo.value += sim ? 1 : -1;
  }

  @override
  void initState() {
    super.initState();
    _tirarFundo(true);
    final m = widget.motor;
    if (m._montados++ == 0) m._mostrar(true);
    m._ajustar(widget.ajuste, widget.proporcao);
  }

  @override
  void didUpdateWidget(_VideoExo antigo) {
    super.didUpdateWidget(antigo);
    widget.motor._ajustar(widget.ajuste, widget.proporcao);
  }

  // o fundo volta no mesmo frame em que o vídeo sai da árvore (o dispose só vem depois de pintar)
  @override
  void activate() {
    super.activate();
    _tirarFundo(true);
  }

  @override
  void deactivate() {
    _tirarFundo(false);
    super.deactivate();
  }

  @override
  void dispose() {
    _tirarFundo(false);
    final m = widget.motor;
    if (--m._montados == 0 && !m._descartado) m._mostrar(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    return Stack(fit: StackFit.expand, children: [
      const SizedBox.expand(), // transparente: o vídeo está por baixo
      ValueListenableBuilder<String>(
        valueListenable: widget.motor.legenda,
        builder: (_, texto, _) => texto.trim().isEmpty
            ? const SizedBox.shrink()
            : Align(
                alignment: const Alignment(0, .92),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    texto,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: tv ? 34 : 22,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 4),
                        Shadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 2),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    ]);
  }
}
