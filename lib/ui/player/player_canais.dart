import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

import '../../dados/preferencias.dart';
import '../../modelo/canal.dart';
import '../../protocolos/protocolo.dart';
import '../../rede/http.dart';
import '../design/componentes.dart';
import 'aplicar_preferencias.dart';
import 'aviso_buffering.dart';
import 'cartao_erro.dart';
import 'compativel_sessao.dart';
import 'configuracao_mpv.dart';
import 'continuar_direto.dart';
import 'controlos_player.dart';
import 'desentrelacamento.dart';
import 'diagnostico.dart';
import 'estatisticas.dart';
import 'faixas.dart';
import 'filtro_desentrelacamento.dart';
import 'leitor_partilhado.dart';
import 'maquina_controlos.dart';
import 'mpv_fora_da_ui.dart';
import 'numero_canal.dart';
import 'painel_definicoes.dart';
import 'progresso.dart';
import 'relogio_direto.dart';
import 'saltos_direto.dart';
import 'taxa_ecra.dart';
import 'troca_player.dart';
import 'ultima_imagem.dart';
import 'vigia_abertura.dart';

/// A mensagem do leitor sem links: nas contas Xtream o link leva o utilizador e a password.
String mensagemErroPlayer(String e) {
  final limpo = semSegredos(e);
  final semPontuacao = limpo.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  return semPontuacao.isEmpty ? 'o canal não abriu' : 'o canal não abriu ($limpo)';
}

/// O erro do mpv faz o canal falhar? Não quando é só a queixa do seek que o media_kit faz ao
/// ligar a superfície de vídeo do Android (num direto não se pode recuar, mas continua a tocar),
/// nem um pacote que não se descodificou (no corte da ligação o último chega a meio; o mpv salta-o
/// e continua, e o fim do buffer trata-se em [ContinuarDireto]).
bool erroFatalPlayer(String e) =>
    !e.contains('force-seekable') && !e.startsWith('Cannot seek') && !e.startsWith('Error decoding');

/// Dá o link (e os headers) de um canal. No Android chama o protocolo; na janela do player
/// do Windows pede-o à janela principal. `continuar`: o mesmo canal outra vez porque o servidor
/// cortou a ligação (não é um canal "visto" de novo).
typedef ResolverFonte = Future<FonteVideo> Function(Canal canal, {bool continuar});

/// O player: toca o canal `indice` de `canais`, com a barra de controlos e o painel de
/// definições ([ControlosPlayer]). As preferências ([Preferencias.atual]) aplicam-se a cada canal.
class PlayerCanais extends StatefulWidget {
  const PlayerCanais({super.key, required this.canais, required this.indice, required this.resolver,
      required this.nomeLista, required this.aoSair, this.alternarEcraInteiro, this.aoMudarCanal});

  final List<Canal> canais;
  final int indice;
  final ResolverFonte resolver;
  final String nomeLista;
  final VoidCallback aoSair;

  /// Windows: F11 / duplo clique / botão.
  final VoidCallback? alternarEcraInteiro;

  /// O canal que está a tocar mudou (cima/baixo): ao sair, a lista foca este.
  final ValueChanged<int>? aoMudarCanal;

  @override
  State<PlayerCanais> createState() => PlayerCanaisState();
}

class PlayerCanaisState extends State<PlayerCanais> with WidgetsBindingObserver {
  static final _plataforma = PlataformaVideo.atual;
  static final _android = _plataforma == PlataformaVideo.android;

  final _prefs = Preferencias.atual;
  final _sessao = SessaoPlayer();
  final _relogio = RelogioDireto();
  final _controlos = GlobalKey<ControlosPlayerState>();

  // a configuração do mpv para direto (buffer, reconexão, descodificação por plataforma); no
  // Android o player é recriado para mudar a descodificação (o vo fixa-se ao criar)
  late ModoDescodificacao _modo = Preferencias.atual.modoAndroid;
  late bool _hardware = Preferencias.atual.hardware;
  late ConfiguracaoMpv _config;
  late Player _player;
  late MotorForaDaUi _motor;
  late SaltosDireto _saltos;

  /// As leituras do mpv da barra, da barra de progresso e das estatísticas: de uma vez (um
  /// isolate por leitura, nunca na thread da UI) e partilhadas entre elas.
  late final _leitor = LeitorPartilhado((ps) => _motor.getProperties(ps));
  late VideoController _video;
  late Future<void> _configurado;
  final _subsPlayer = <StreamSubscription>[];
  int _larguraVista = 0;
  final _taxa = TaxaEcra();
  double? _hzPedidos;
  double? _hzEcra;
  String? _aviso;
  Timer? _esconderAviso;
  bool _estatisticas = false;
  bool _buffering = false;
  double? _percentagemBuffer;
  bool _aTocar = true;
  double _velocidade = 1;

  /// O desentrelaçamento: decide-se com a imagem, depois da primeira e a cada
  /// [_intervaloEntrelacamento] (ver `desentrelacamento.dart`). null: ainda não se sabe.
  bool? _entrelacada;
  String _hwdecAtual = '';
  MeioDesentrelacamento _meio = MeioDesentrelacamento.nenhum;
  Timer? _vigiaEntrelacamento;
  Future<void> _filaDesentrelacamento = Future.value();
  static const _intervaloEntrelacamento = Duration(seconds: 10);

  /// O shader do Flutter (Android) e o ficheiro do shader do mpv (Windows), uma vez por processo.
  ui.FragmentProgram? _programaFlutter;
  static Future<String?>? _shaderMpv;

  /// A imagem que estava no ecrã quando o servidor cortou: fica por baixo do "A carregar…" até à
  /// primeira imagem do canal reaberto (em vez do preto).
  final _ultima = UltimaImagem();
  Tracks _faixas = const Tracks();
  Track _faixa = const Track();
  late List<Canal> _canais = widget.canais;
  late int _i = widget.indice;
  late final _historico = HistoricoCanais(widget.indice);
  String? _erro;
  bool _aAbrir = true;
  int _pedido = 0;

  /// A reabrir o canal porque o buffer acabou (o servidor fechou a ligação): em vez do indicador
  /// de abertura mostra-se "A carregar…" (ver [ContinuarDireto]).
  bool _aRetomar = false;
  final _continuar = ContinuarDireto();

  /// Quando o canal deu imagem pela última vez (para saber se uma reabertura valeu a pena).
  DateTime? _abriuEm;

  /// Num ficheiro com fim cortado pelo servidor, onde reabrir (null num direto: vai para o direto).
  Duration? _retomarEm;

  /// Num direto cortado: os PTS do que se viu por último (`demuxer-start-time` e `time-pos` no
  /// corte). Depois de reabrir salta-se para lá, para não repetir o que já se viu (quem foi até ao
  /// fim do buffer está à frente do bloco com que o servidor responde a uma ligação nova).
  ({double? inicio, double? posicao})? _continuarDe;

  /// A reabrir com um salto por decidir ([_saltarParaOndeEstava]): sem som e com a última imagem
  /// por cima, para não se ver nem ouvir o bocado repetido.
  bool _saltoPendente = false;

  /// A faixa de áudio escolhida pelo utilizador neste canal (volta a pôr-se depois de reabrir).
  AudioTrack? _audioEscolhido;

  // nunca ecrã preto mudo: o "a abrir" só sai com imagem; sem ela em 20 s, erro
  /// Um stop que não acaba neste tempo é de um mpv que deixou de responder.
  static const _limiteStop = Duration(seconds: 5);

  late final _vigia = VigiaAbertura(
    aoAbrir: () {
      if (!mounted) return;
      final retomou = _aRetomar;
      _abriuEm = DateTime.now();
      _continuar.abriu();
      setState(() {
        _aAbrir = false;
        _erro = null;
        // à espera do salto para onde se estava: a última imagem e o "A carregar…" ficam até lá
        if (!_saltoPendente) {
          _aRetomar = false;
          _ultima.largar();
        }
      });
      _vigiarImagem(_pedido);
      _verEntrelacamento(_pedido);
      if (retomou) _reporFaixaAudio(_pedido);
    },
    aoFalhar: (motivo) {
      if (!mounted) return;
      _player.stop();
      _taxa.repor();
      setState(() { _erro = motivo; _aAbrir = false; _aRetomar = false; _ultima.largar(); });
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_android && FiltroDesentrelacamento.suportado) {
      FiltroDesentrelacamento.programa().then((p) {
        if (mounted) setState(() => _programaFlutter = p);
      });
    }
    if (!_android) {
      _shaderMpv ??= getApplicationSupportDirectory().then(escreverShaderMpv, onError: (Object e) {
        debugPrint('desentrelaçamento: sem pasta para o shader ($e)');
        return null;
      });
    }
    _criarPlayer();
    _abrir();
  }

  void _criarPlayer() {
    _config = ConfiguracaoMpv.para(_plataforma, modo: _modo, hardware: _hardware);
    _player = Player(configuration: _config.configuracaoPlayer);
    _motor = MotorForaDaUi.doPlayer(_player);
    _saltos = SaltosDireto(_motor, _relogio);
    _leitor.esquecer();
    _subsPlayer.add(_player.stream.error.listen((e) {
      if (mounted && e.isNotEmpty && erroFatalPlayer(e)) {
        // a reabrir depois de um corte: uma falha passageira (rede, 401) tenta-se outra vez
        if (_aRetomar && _tentarContinuarDepois(_pedido)) return;
        _vigia.parar();
        _taxa.repor();
        setState(() { _erro = mensagemErroPlayer(e); _aAbrir = false; _aRetomar = false; _ultima.largar(); });
      }
    }));
    _subsPlayer.add(_player.stream.completed.listen(_fimDoBuffer));
    _subsPlayer.add(_player.stream.buffering.listen((b) {
      _vigia.buffering(b);
      if (!mounted) return;
      if (b != _buffering || (!b && _percentagemBuffer != null)) {
        // o % de uma paragem não passa para a seguinte
        setState(() { _buffering = b; if (!b) _percentagemBuffer = null; });
      }
    }));
    _subsPlayer.add(_player.stream.bufferingPercentage.listen((p) {
      // guarda-se sempre: o mpv pode mandar o % antes do "buffering"
      _percentagemBuffer = p;
      if (mounted && _buffering) setState(() {});
    }));
    _subsPlayer.add(_player.stream.width.listen((w) {
      if ((w ?? 0) > 0) _larguraVista = w!;
      _vigia.largura(w);
    }));
    _subsPlayer.add(_player.stream.position.listen(_vigia.tempo));
    _subsPlayer.add(_player.stream.tracks.listen((t) {
      if (mounted) setState(() => _faixas = t);
    }));
    _subsPlayer.add(_player.stream.track.listen((t) {
      if (mounted) setState(() => _faixa = t);
    }));
    // o controlador de vídeo antes de configurar o mpv (as propriedades esperam por ele)
    _video = VideoController(_player, configuration: _config.configuracaoVideo);
    _configurado = aplicarConfiguracao(_motor, _config);
  }

  /// Recria o player noutra descodificação (o vo do Android fixa-se ao criar) ou no lugar de um
  /// mpv que deixou de responder. Devolve a aposentação do antigo (quem abre não espera por ela:
  /// ver [prepararPlayer]).
  Future<void> _recriar(ModoDescodificacao modo, bool hardware) {
    for (final s in _subsPlayer) {
      s.cancel();
    }
    _subsPlayer.clear();
    final antigo = _player;
    final motorAntigo = _motor;
    _modo = modo;
    _hardware = hardware;
    _criarPlayer();
    if (mounted) setState(() {});
    // pára o antigo (nunca toca por trás); nenhum pedido ao mpv antigo depois de destruído
    return _aposentar(motorAntigo, antigo);
  }

  /// Larga um player: pausa e volume 0 pelo media_kit já (se o mpv estiver preso e o player
  /// ficar por destruir, nunca toca por trás), depois destrói-o quando for seguro.
  static Future<void> _aposentar(MotorForaDaUi motor, Player player) {
    // o próximo player só abre um canal depois de este fechar o áudio (ver VezDoAudio)
    final audioFechado = Completer<void>();
    VezDoAudio.instancia.largar(audioFechado.future);
    return motor.aposentar(
        // pelas funções assíncronas do libmpv (pause, mute): o pause()/setVolume() do
        // media_kit esperam pelo controlador de vídeo e pelo lock dele e, ao sair a meio de uma
        // abertura, nunca chegavam a parar nada (visto no emulador)
        pausar: () async {
          var h = motor.handleConhecido;
          final mpv = player.platform;
          if (h == null && mpv is NativePlayer) h = await mpv.handle.timeout(const Duration(seconds: 2));
          if (h != null) pararSemEsperar(h);
        },
        silenciar: () async {}, // o mute=yes vai com o pause
        destruir: () => player.dispose().whenComplete(audioFechado.complete),
      );
  }

  /// A chave do canal para lembrar, nesta sessão, que precisa do modo "Compatível".
  String _chave(Canal c) => '${widget.nomeLista}|${c.id}';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached:
        _taxa.repor(); // a TV volta ao modo normal fora do player
      case AppLifecycleState.resumed:
        if (!_aAbrir && _erro == null) _ajustarTaxa(_pedido);
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void didUpdateWidget(PlayerCanais oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.canais, widget.canais) || oldWidget.indice != widget.indice) {
      trocar(widget.canais, widget.indice);
    }
  }

  /// A janela principal mandou outro canal (Windows).
  void trocar(List<Canal> canais, int i) {
    _canais = canais;
    _i = i;
    _historico.novaLista(i);
    _abrir();
  }

  /// O buffer chegou ao fim a meio do canal (o servidor fechou a ligação e o mpv não reconecta):
  /// pede o canal de novo, com "A carregar…", nunca em ciclo.
  Future<void> _fimDoBuffer(bool fim) async {
    if (!fim || !mounted) return;
    final pedido = _pedido;
    // um ficheiro com fim (filme de uma lista M3U) acaba: só os diretos se pedem de novo
    final p = await _motor.getProperties(const ['seekable', 'partially-seekable', 'demuxer-start-time', 'time-pos']);
    final eDireto = ContinuarDireto.eDireto(p['seekable']!, partiallySeekable: p['partially-seekable']!);
    if (!mounted || pedido != _pedido) return;
    // ou um ficheiro que o servidor cortou muito antes do fim (fica-se parado na última imagem):
    // reabre-se no ponto onde parou
    final posicao = _player.state.position;
    final cortado = !eDireto && ContinuarDireto.cortadoAntesDoFim(posicao: posicao, duracao: _player.state.duration);
    final direto = eDireto || cortado;
    if (!ContinuarDireto.deve(
        fimDoBuffer: fim, aAbrir: _aAbrir, erro: _erro != null, aTocar: _aTocar, direto: direto)) {
      return;
    }
    final abriu = _abriuEm;
    final posCorte = double.tryParse(p['time-pos'] ?? '');
    // o que a ligação deu de imagem (com os saltos para o fim do buffer), não só a parede
    final tocou = ContinuarDireto.proveitoDaLigacao(
        parede: abriu == null ? Duration.zero : DateTime.now().difference(abriu), posicaoNoCorte: posCorte);
    if (!_continuar.permitir(tocou: tocou)) {
      _vigia.parar();
      _taxa.repor();
      setState(() {
        _erro = 'o servidor está sempre a cortar a ligação a este canal';
        _ultima.largar();
      });
      return;
    }
    _retomarEm = cortado ? posicao : null;
    _continuarDe = cortado ? null : (inicio: double.tryParse(p['demuxer-start-time'] ?? ''), posicao: posCorte);
    // a última imagem fica no ecrã enquanto se reabre (antes de o stop/open a tirarem)
    await _ultima.guardar(MediaQuery.devicePixelRatioOf(context));
    if (!mounted || pedido != _pedido) {
      _ultima.largar();
      return;
    }
    _abrir(continuar: true);
  }

  /// Uma reabertura (depois de um corte) falhou: tenta outra vez daqui a um pouco, com "A
  /// carregar…" à vista. Falso = já se tentou o suficiente (o cartão de erro aparece).
  /// Uma espera por tentativa: os vários erros da mesma falha (o `tcp` e o "Failed to open")
  /// não gastam as esperas seguintes.
  bool _tentarContinuarDepois(int pedido) {
    final r = _continuar.falhou(pedido, () {
      if (mounted && pedido == _pedido && _aRetomar) _abrir(continuar: true);
    });
    if (r == Retoma.desistir) return false;
    if (r == Retoma.agendada) _vigia.parar();
    return true;
  }

  /// Volta a pôr a faixa de áudio escolhida depois de o canal ser reaberto (se ainda existir).
  Future<void> _reporFaixaAudio(int pedido) async {
    final escolhido = _audioEscolhido;
    if (escolhido == null) return;
    // as faixas chegam com o canal; espera-se um pouco por elas
    for (var i = 0; i < 10 && mounted && pedido == _pedido; i++) {
      final igual = _faixas.audio.where((a) => a.id == escolhido.id).firstOrNull;
      if (igual != null) {
        if (_faixa.audio.id != igual.id) await _player.setAudioTrack(igual);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Abre o canal `_i`. `continuar`: o mesmo canal outra vez porque o buffer acabou.
  Future<void> _abrir({bool continuar = false}) async {
    final pedido = ++_pedido;
    final canal = _canais[_i];
    if (!continuar) {
      _continuar.reiniciar();
      _audioEscolhido = null;
      _abriuEm = null;
      _retomarEm = null;
      _continuarDe = null;
    }
    _saltoPendente = false;
    _vigiaEntrelacamento?.cancel();
    _entrelacada = null;
    // o aplicarAoAbrir põe deinterlace=no (o d3d11vpp volta a ligar-se com a imagem)
    if (_meio == MeioDesentrelacamento.d3d11vpp) _meio = MeioDesentrelacamento.nenhum;
    setState(() {
      if (!continuar) _ultima.largar();
      _aAbrir = true;
      _aRetomar = continuar;
      _erro = null;
      _aTocar = true;
      _velocidade = 1;
    });
    _relogio.reiniciar();
    _leitor.esquecer();
    // o nome do canal uns segundos (no primeiro canal a barra ainda não foi construída)
    final controlos = _controlos.currentState;
    if (continuar) {
      // o mesmo canal: sem o nome por cima
    } else if (controlos != null) {
      controlos.mostrarInfoCanal();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _controlos.currentState?.mostrarInfoCanal());
    }
    try {
      _vigia.comecar(); // o prazo conta desde o pedido do link
      // ao mudar de canal, o anterior para já: senão continuava a tocar (e a mandar imagem e
      // posição) enquanto o link novo se resolve
      final modo =
          _android ? CompativelNaSessao.instancia.modoPara(_chave(canal), _prefs.modoAndroid) : _prefs.modoAndroid;
      final hardware = _prefs.hardware;
      // um mpv que deixou de responder não se volta a usar: player novo
      await prepararPlayer(
        novo: (_android && (modo != _modo || hardware != _hardware)) || _motor.semResposta,
        zap: pedido > 1,
        parar: () => _player.stop(),
        trocar: () => _recriar(modo, hardware),
        limiteStop: _limiteStop,
      );
      if (!mounted || pedido != _pedido) return;
      final f = await widget.resolver(canal, continuar: continuar);
      if (!mounted || pedido != _pedido) return;
      await _configurado;
      if (!mounted || pedido != _pedido) return;
      // as preferências em cada canal: 1×, volume, silêncio, atraso do áudio, desentrelaçamento…
      await aplicarAoAbrir(_motor, _prefs, _sessao, plataforma: _plataforma, modo: _modo);
      if (!mounted || pedido != _pedido) return;
      _vigia.abrindo();
      _larguraVista = 0;
      await VezDoAudio.instancia.esperar();
      if (!mounted || pedido != _pedido) return;
      await _player.open(Media(f.url, httpHeaders: f.headers, start: continuar ? _retomarEm : null));
      // o modo de ecrã pede-se já (o fps sabe-se logo que o canal abre): a TV pisca a mudar de
      // modo enquanto o indicador de abertura ainda está à vista, não por cima da imagem
      if (mounted && pedido == _pedido) unawaited(_ajustarTaxa(pedido));
      final de = continuar ? _continuarDe : null;
      if (de != null && mounted && pedido == _pedido) {
        _saltoPendente = true;
        unawaited(_motor.setProperty('mute', 'yes').catchError((Object _) {}));
        unawaited(_saltarParaOndeEstava(pedido, de).whenComplete(() => _acabouSalto(pedido)));
      }
    } catch (e) {
      if (!mounted || pedido != _pedido) return;
      // a reabrir depois de um corte: uma falha passageira (rede, create_link, 401) tenta-se outra vez
      if (continuar && _tentarContinuarDepois(pedido)) return;
      _vigia.parar();
      _taxa.repor();
      setState(() {
        _erro = e is ErroLista ? e.mensagem : descreverErro(e);
        _aAbrir = false;
        _aRetomar = false;
        _ultima.largar();
      });
    }
  }

  /// As propriedades do mpv para as estatísticas (texto; "" quando não há).
  Future<Map<String, String>> _lerMpv() => _leitor.ler(propriedadesDiagnostico);

  /// A barra de progresso: num direto pelos saltos do cache ([SaltosDireto.irPara]: seek
  /// relativo, nunca reabre o canal, o relógio do direto fica certo); num filme, seek absoluto.
  Future<void> _procurar(JanelaProgresso janela, double alvo) async {
    final pedido = _pedido;
    String? aviso;
    if (janela.direto) {
      aviso = await _saltos.irPara(alvo);
    } else if (pedido == _pedido) {
      await _motor.command(['seek', alvo.toStringAsFixed(3), 'absolute']);
    }
    _leitor.esquecer(); // a posição mudou
    if (!mounted || pedido != _pedido) return;
    if (aviso != null) _mostrarAviso(aviso);
    setState(() {});
  }

  /// Android TV / Fire TV: pede o modo de ecrã que combina com o fps do canal (50 fps -> 50 Hz),
  /// para cada imagem ficar o mesmo tempo no ecrã (sem judder).
  Future<void> _ajustarTaxa(int pedido) async {
    if (!_android) return;
    await _lerHzEcra();
    if (!_prefs.ajustarTaxaEcra) return;
    final mpv = _motor;
    // o container-fps costuma vir logo; senão o medido, que demora uns segundos
    try {
      for (var tentativa = 0; tentativa < 5; tentativa++) {
        if (!mounted || pedido != _pedido) return;
        var fps = double.tryParse(await mpv.getProperty('container-fps')) ?? 0;
        if (fps <= 0) fps = double.tryParse(await mpv.getProperty('estimated-vf-fps')) ?? 0;
        if (fps > 0) {
          if (!mounted || pedido != _pedido) return;
          final hz = await _taxa.ajustarPara(fps);
          if (hz != null && mounted) {
            setState(() => _hzPedidos = hz);
            // a TV demora a mudar de modo: os Hz do sistema leem-se depois
            await Future<void>.delayed(const Duration(seconds: 3));
            await _lerHzEcra();
          }
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } catch (_) {
      // o player fechou entretanto
    }
  }

  /// Depois de reabrir um direto cortado: salta para o que se viu por último (pelos PTS:
  /// [ContinuarDireto.posicaoNoNovo]), para não o repetir. Espera (~6 s) que o cache do stream novo
  /// chegue lá; senão vai até onde dá. Nunca para trás. Leituras fora da UI.
  Future<void> _saltarParaOndeEstava(int pedido, ({double? inicio, double? posicao}) de) async {
    for (var i = 0; i < _tentativasRetoma; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted || pedido != _pedido) return;
      try {
        final m = await _motor.getProperties(const ['demuxer-start-time', 'time-pos', 'demuxer-cache-state']);
        if (!mounted || pedido != _pedido) return;
        final pos = double.tryParse(m['time-pos'] ?? '');
        final alvo = ContinuarDireto.posicaoNoNovo(
            inicioAntigo: de.inicio, posicaoAntiga: de.posicao, inicioNovo: double.tryParse(m['demuxer-start-time'] ?? ''));
        if (pos == null || alvo == null) continue; // o stream novo ainda não começou
        final fim = fimProcuravel(m['demuxer-cache-state'] ?? '', pos);
        final aFrente = fim == null ? null : fim - pos - SaltosDireto.margemFim.inMicroseconds / 1e6;
        final r = ContinuarDireto.saltoAoRetomar(
            alvo: alvo, posicao: pos, aFrente: aFrente, ultimaTentativa: i == _tentativasRetoma - 1);
        if (r.esperar) continue;
        final salto = r.salto;
        final texto = salto == null ? 'sem salto' : 'salta ${salto.toStringAsFixed(1)} s';
        debugPrint('player: reaberto; o que se viu por último fica a ${(alvo - pos).toStringAsFixed(1)} s; $texto');
        if (salto != null) {
          await _motor.command(['seek', salto.toStringAsFixed(3), 'relative']);
          _relogio.avancou(Duration(microseconds: (salto * 1e6).round()));
        }
        return;
      } catch (e) {
        debugPrint('player: salto depois de reabrir falhou ($e)');
        return;
      }
    }
  }

  static const _tentativasRetoma = 20; // ~6 s

  /// O salto depois de reabrir acabou (ou desistiu): volta o som e sai a última imagem, se o canal
  /// já deu imagem (senão o vigia trata disso).
  void _acabouSalto(int pedido) {
    if (!mounted || pedido != _pedido || !_saltoPendente) return;
    _saltoPendente = false;
    unawaited(_motor.setProperty('mute', _sessao.silencio ? 'yes' : 'no').catchError((Object _) {}));
    if (!_aAbrir && _aRetomar) {
      setState(() {
        _aRetomar = false;
        _ultima.largar();
      });
    }
  }

  /// Os Hz do ecrã segundo o Android (o mpv não os sabe com `mediacodec_embed`).
  Future<void> _lerHzEcra() async {
    final hz = await _taxa.hzAtual();
    if (mounted && hz != _hzEcra) setState(() => _hzEcra = hz);
  }

  /// Descodificação direta: se o canal abriu mas não há imagem (o descodificador recusou o
  /// stream e o mpv passou para software, que o mediacodec_embed não mostra), reabre este canal
  /// em "Compatível" nesta sessão. Só uma vez por canal (nunca em ciclo).
  Future<void> _vigiarImagem(int pedido) async {
    if (!_android || _modo != ModoDescodificacao.direto || !_hardware) return;
    final player = _player;
    final mpv = _motor;
    try {
      // duas leituras seguidas sem imagem (a saída de vídeo do media_kit troca de vo no arranque)
      for (final espera in const [Duration(seconds: 2), Duration(seconds: 1)]) {
        await Future<void>.delayed(espera);
        if (!mounted || pedido != _pedido || !identical(player, _player)) return;
        final m = {
          for (final p in const ['video-codec', 'hwdec-current', 'vo-configured']) p: await mpv.getProperty(p),
        };
        // um mpv que não respondeu não diz nada sobre a imagem (é trocado no próximo canal)
        if (mpv.semResposta || !semImagemDireta(larguraVista: _larguraVista, propriedades: m)) return;
      }
    } catch (_) {
      return; // o player fechou entretanto
    }
    if (!mounted || pedido != _pedido) return;
    if (!CompativelNaSessao.instancia.marcar(_chave(_canais[_i]))) return;
    _mostrarAviso('Modo compatível ativado para este canal');
    _abrir();
  }

  void _mostrarAviso(String texto) {
    _esconderAviso?.cancel();
    setState(() => _aviso = texto);
    _esconderAviso = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _aviso = null);
    });
  }

  /// Mostra/esconde a sobreposição "Estatísticas" (Menu/I, toque longo, ou no painel).
  void alternarEstatisticas() => setState(() => _estatisticas = !_estatisticas);

  void _mudar(int delta) {
    if (_canais.length < 2) return;
    final i = (_i + delta) % _canais.length;
    _irPara(i < 0 ? i + _canais.length : i);
  }

  /// Abre o canal `i` da lista (o atual fica como "canal visto antes").
  void _irPara(int i) {
    if (i < 0 || i >= _canais.length || _historico.irPara(i) == null) return;
    _i = i;
    widget.aoMudarCanal?.call(_i);
    _abrir();
  }

  /// O número escrito com os algarismos: o número do portal ou a posição na lista.
  void _irParaNumero(int n) {
    final i = indicePorNumero(_canais, n);
    if (i == null) {
      _mostrarAviso('Não há o canal $n nesta lista');
    } else {
      _irPara(i);
    }
  }

  Future<void> _tocar(bool tocar) async {
    if (tocar == _aTocar) return;
    setState(() => _aTocar = tocar);
    if (tocar) {
      _relogio.retomou();
      await _player.play();
    } else {
      _relogio.pausou(); // o direto continua: fica-se para trás
      await _player.pause();
    }
  }

  Future<void> _saltar(Future<String?> Function() salto) async {
    final aviso = await salto();
    if (!mounted) return;
    if (aviso != null) _mostrarAviso(aviso);
    setState(() {});
  }

  void _agir(AcaoPlayer a) {
    switch (a) {
      case AcaoPlayer.canalAnterior:
        _mudar(-1);
      case AcaoPlayer.canalSeguinte:
        _mudar(1);
      case AcaoPlayer.alternarCanal:
        final anterior = _historico.anterior;
        if (anterior != null) _irPara(anterior);
      case AcaoPlayer.recuar:
        _saltar(_saltos.recuar);
      case AcaoPlayer.avancar:
        _saltar(_saltos.avancar);
      case AcaoPlayer.voltarAoDireto:
        _saltar(() async {
          if (!_aTocar) await _tocar(true);
          // longe demais para o buffer: reabre o canal (link novo) — o seek ficava minutos atrás.
          // Se entretanto mudou de canal, não se mexe no canal novo.
          final pedido = _pedido;
          final saltos = _saltos;
          final r = await saltos.voltarAoDireto(aindaValido: () => mounted && pedido == _pedido);
          if (r == VoltaAoDireto.reabrir && mounted && pedido == _pedido) _abrir();
          return null;
        });
      case AcaoPlayer.playPausa:
        _tocar(!_aTocar);
      case AcaoPlayer.tocar:
        _tocar(true);
      case AcaoPlayer.pausar:
        _tocar(false);
      case AcaoPlayer.estatisticas:
        alternarEstatisticas();
      case AcaoPlayer.ecraInteiro:
        widget.alternarEcraInteiro?.call();
      case AcaoPlayer.tentarDeNovo:
        _abrir();
      case AcaoPlayer.sair:
        widget.aoSair();
      case AcaoPlayer.passar || AcaoPlayer.mostrarControlos || AcaoPlayer.esconderControlos ||
            AcaoPlayer.fecharPainel || AcaoPlayer.algarismo || AcaoPlayer.irParaNumero ||
            AcaoPlayer.cancelarNumero:
        break;
    }
  }

  void _mudarVelocidade(double v) {
    setState(() => _velocidade = v);
    _relogio.mudouVelocidade(v);
    _motor.setRate(v);
  }

  /// Muda uma preferência, guarda-a e aplica-a já.
  void _preferir(void Function(Preferencias p) mudar, [Future<void> Function()? aplicar]) {
    setState(() => mudar(_prefs));
    _prefs.guardar().catchError((Object e) => debugPrint('preferências não gravadas ($e)'));
    aplicar?.call();
  }

  bool get _shaderFlutterPronto => _programaFlutter != null && FiltroDesentrelacamento.suportado;

  /// No Windows há sempre o shader do mpv; no Android, o do Flutter se o aparelho o permitir.
  bool get _desentrelacamentoPossivel => !_android || _shaderFlutterPronto;

  /// Lê do mpv se a imagem é entrelaçada (de uma vez, fora da UI) e põe o meio certo; repete a cada
  /// [_intervaloEntrelacamento] (um canal pode passar de progressivo a entrelaçado).
  Future<void> _verEntrelacamento(int pedido) async {
    _vigiaEntrelacamento?.cancel();
    try {
      final m = await _motor.getProperties(propriedadesEntrelacamento(_plataforma));
      if (!mounted || pedido != _pedido) return;
      _entrelacada = imagemEntrelacada(m) ?? _entrelacada;
      final hwdec = (m['hwdec-current'] ?? '').trim();
      if (hwdec.isNotEmpty) _hwdecAtual = hwdec;
      await _aplicarDesentrelacamento();
    } catch (_) {
      return; // o player fechou entretanto
    }
    if (!mounted || pedido != _pedido) return;
    _vigiaEntrelacamento = Timer(_entrelacada == null ? const Duration(seconds: 1) : _intervaloEntrelacamento,
        () => _verEntrelacamento(pedido));
  }

  /// Põe o meio que serve agora (preferência, imagem, aparelho). Em fila: uma mudança da
  /// preferência a meio de uma verificação não fica trocada.
  Future<void> _aplicarDesentrelacamento() {
    return _filaDesentrelacamento = _filaDesentrelacamento.then((_) async {
      final meio = meioDesentrelacamento(_plataforma,
          ligado: _prefs.desentrelacar,
          entrelacada: _entrelacada,
          hwdec: _hwdecAtual,
          shaderFlutter: _shaderFlutterPronto);
      if (meio == _meio || !mounted) return;
      if (!_android) await aplicarMeioMpv(_motor, meio, caminhoShader: await (_shaderMpv ?? Future.value()));
      if (mounted) setState(() => _meio = meio);
    }).catchError((Object e) => debugPrint('desentrelaçamento: $e'));
  }

  /// O modo de descodificação do Android no painel: 0 direta, 1 compatível, 2 software.
  int get _descodificacaoAndroid =>
      !_prefs.hardware ? 2 : (_prefs.modoAndroid == ModoDescodificacao.direto ? 0 : 1);

  String get _rotuloModoAtual => !_hardware ? 'Software' : _modo.rotulo;

  List<ItemDefinicao> _definicoes() {
    final video = escolhaVideo(_faixas.video, _faixa.video);
    final audio = escolhaAudio(_faixas.audio, _faixa.audio);
    final legendas = escolhaLegendas(_faixas.subtitle, _faixa.subtitle);
    final possivel = _desentrelacamentoPossivel;
    return [
      DefinicaoInterruptor(
        'Desentrelaçamento',
        valor: possivel && _prefs.desentrelacar,
        aoMudar: possivel ? (v) => _preferir((p) => p.desentrelacar = v, _aplicarDesentrelacamento) : null,
        nota: possivel
            ? 'Só nas imagens entrelaçadas (canais 1080i/576i)'
            : 'Este aparelho não permite o desentrelaçamento do player',
      ),
      DefinicaoEscolha(
        'Formato de imagem',
        opcoes: [for (final f in FormatoImagem.values) f.rotulo],
        atual: _prefs.formato.index,
        aoMudar: (i) => _preferir((p) => p.formato = FormatoImagem.values[i]),
      ),
      DefinicaoEscolha(
        'Qualidade / faixa de vídeo',
        opcoes: video.opcoes,
        atual: video.atual,
        // só com mais de uma faixa (escolher entre "Automática" e a única não muda nada)
        aoMudar: video.opcoes.length > 2 ? (i) => _player.setVideoTrack(video.faixa(i)) : null,
        nota: video.opcoes.length <= 2 ? 'Este canal só tem uma' : null,
      ),
      DefinicaoEscolha(
        'Faixa de áudio',
        opcoes: audio.opcoes,
        atual: audio.atual,
        aoMudar: audio.opcoes.length > 2
            ? (i) {
                final faixa = audio.faixa(i);
                _audioEscolhido = faixa.id == 'auto' ? null : faixa;
                _player.setAudioTrack(faixa);
              }
            : null,
        nota: audio.opcoes.length <= 2 ? 'Este canal só tem uma' : null,
      ),
      DefinicaoEscolha(
        'Legendas',
        opcoes: legendas.opcoes,
        atual: legendas.atual,
        aoMudar: (i) => _player.setSubtitleTrack(legendas.faixa(i)),
        nota: legendas.opcoes.length < 2 ? 'Este canal não tem legendas' : null,
      ),
      DefinicaoPassos(
        'Volume',
        valor: '${_prefs.volume.round()} %',
        menos: _prefs.volume > 0 ? () => _mudarVolume(-5) : null,
        mais: _prefs.volume < 100 ? () => _mudarVolume(5) : null,
      ),
      DefinicaoInterruptor('Silêncio', valor: _sessao.silencio, aoMudar: (v) {
        setState(() => _sessao.silencio = v);
        _motor.setProperty('mute', v ? 'yes' : 'no');
      }),
      DefinicaoPassos(
        'Atraso do áudio',
        valor: textoAtrasoAudio(_sessao.atrasoAudio),
        nota: 'Positivo: o som chega mais tarde',
        menos: _sessao.atrasoAudio > -limiteAtrasoAudio ? () => _mudarAtrasoAudio(-1) : null,
        mais: _sessao.atrasoAudio < limiteAtrasoAudio ? () => _mudarAtrasoAudio(1) : null,
      ),
      if (_android)
        DefinicaoEscolha(
          'Descodificação',
          opcoes: [ModoDescodificacao.direto.rotulo, ModoDescodificacao.compativel.rotulo, 'Software (sem hardware)'],
          atual: _descodificacaoAndroid,
          aoMudar: (i) => _preferir((p) {
            p.hardware = i != 2;
            if (i != 2) p.modoAndroid = i == 0 ? ModoDescodificacao.direto : ModoDescodificacao.compativel;
          }, () async => _abrir()),
          nota: _rotuloModoAtual != [ModoDescodificacao.direto.rotulo, ModoDescodificacao.compativel.rotulo,
                  'Software'][_descodificacaoAndroid]
              ? 'Este canal está em $_rotuloModoAtual (não deu imagem na direta)'
              : 'Compatível: para imagem preta ou cores erradas',
        )
      else
        DefinicaoInterruptor(
          'Descodificação por hardware',
          valor: _prefs.hardware,
          aoMudar: (v) => _preferir((p) => p.hardware = v, () async {
            await _motor.setProperty('hwdec', hwdecEmTempoReal(_plataforma, hardware: v)!);
            await _aplicarDesentrelacamento();
          }),
          nota: 'Desligue se a imagem aparecer com defeitos',
        ),
      if (_android)
        DefinicaoInterruptor(
          'Ajustar a taxa do ecrã ao canal',
          valor: _prefs.ajustarTaxaEcra,
          aoMudar: (v) => _preferir((p) => p.ajustarTaxaEcra = v, () async {
            if (v) {
              await _ajustarTaxa(_pedido);
            } else {
              await _taxa.repor();
              if (mounted) setState(() => _hzPedidos = null);
            }
          }),
          nota: '50 Hz nos canais a 50 imagens/s (sem saltos)',
        ),
      DefinicaoAcao(
        'Informação do stream',
        valor: _estatisticas ? 'Esconder' : 'Mostrar',
        nota: 'Resolução, codec, débito e buffer',
        aoCarregar: alternarEstatisticas,
      ),
    ];
  }

  void _mudarVolume(int passo) {
    _preferir((p) => p.volume = p.volume + passo, () => _motor.setVolume(_prefs.volume));
  }

  void _mudarAtrasoAudio(int direcao) {
    setState(() => _sessao.atrasoAudio = passoAtrasoAudio(_sessao.atrasoAudio, direcao));
    aplicarAtrasoAudio(_motor, _sessao.atrasoAudio);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _continuar.reiniciar(); // nenhuma reabertura marcada depois de sair
    _esconderAviso?.cancel();
    _vigiaEntrelacamento?.cancel();
    _ultima.largar();
    _vigia.parar();
    _taxa.fechar();
    for (final s in _subsPlayer) {
      s.cancel();
    }
    // o mpv só se destrói depois dos pedidos que ainda lá estão
    unawaited(_aposentar(_motor, _player));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canal = _canais[_i];
    final ajuste = ajusteVideo(_prefs.formato);
    Widget video = Video(
      key: ObjectKey(_video),
      controller: _video,
      controls: NoVideoControls,
      fill: Colors.black,
      fit: ajuste.fit,
      aspectRatio: ajuste.aspecto,
      // Android: o shader de desentrelaçamento por cima da textura (o tamanho lê-se na hora: chega
      // depois de o Video ser construído)
      envolverTextura: _meio == MeioDesentrelacamento.shaderFlutter
          ? (t) => TexturaDesentrelacada(
              programa: _programaFlutter,
              colunas: _player.state.width ?? 0,
              linhas: _player.state.height ?? 0,
              child: t)
          : null,
    );
    if (ajuste.escala != 1) video = ClipRect(child: Transform.scale(scale: ajuste.escala, child: video));
    video = _ultima.envolver(video);

    return ColoredBox(
      color: Colors.black,
      child: ControlosPlayer(
        key: _controlos,
        estado: EstadoControlos(
          canal: canal.nome,
          subtitulo: '${canal.grupo} · ${_i + 1}/${_canais.length} · ${widget.nomeLista}',
          aTocar: _aTocar,
          velocidade: _velocidade,
          erro: _erro != null,
          podeAlternar: _historico.anterior != null,
        ),
        aoNumero: _irParaNumero,
        atraso: () => _relogio.atraso,
        lerInfoStream: () => _leitor.ler(propriedadesInfoStream),
        lerProgresso: () async => janelaDe(await _leitor.ler(propriedadesProgresso)),
        aoProcurar: _procurar,
        aoAgir: _agir,
        aoMudarVelocidade: _mudarVelocidade,
        definicoes: _definicoes,
        comEcraInteiro: widget.alternarEcraInteiro != null,
        child: Stack(fit: StackFit.expand, children: [
          video,
          // ao reabrir depois de um corte: a última imagem por baixo do "A carregar…"
          if (_aRetomar) ?_ultima.sobreposicao(),
          if (_aAbrir && !_aRetomar) const Center(child: CircularProgressIndicator()),
          if (_aviso != null)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: SuperficieVidro(
                  cor: const Color(0xD90B0F17),
                  raio: 14,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Text(_aviso!, style: const TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ),
          // a meio do canal, à espera de dados (o arranque tem o indicador de cima)
          // e ao pedir o canal de novo quando o buffer acabou (o vídeo fica parado)
          AvisoBuffering(
              aberto: _erro == null && (!_aAbrir || _aRetomar),
              buffering: _buffering || _aRetomar,
              percentagem: _aRetomar ? null : _percentagemBuffer),
          if (_estatisticas)
            Positioned(
              top: 88, // por baixo do botão Voltar da barra
              left: 24,
              child: PainelEstatisticas(
                ler: _lerMpv,
                geracao: _pedido,
                hzEcra: _hzEcra,
                extra: [
                  if (_android) ('Modo de descodificação', _rotuloModoAtual),
                  ('Saída · hwdec pedido', '${_config.vo} · ${_config.hwdec}'),
                  ('Desentrelaçamento',
                      textoDesentrelacamento(_meio, ligado: _prefs.desentrelacar, entrelacada: _entrelacada)),
                  if (_hzPedidos != null) ('Taxa do ecrã pedida', '${_hzPedidos!.toStringAsFixed(2)} Hz'),
                ],
              ),
            ),
          if (_erro != null)
            CartaoErroCanal(texto: '${canal.nome}: $_erro', aoTentar: _abrir, aoVoltar: widget.aoSair),
        ]),
      ),
    );
  }
}
