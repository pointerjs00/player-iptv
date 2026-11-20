import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
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
import 'controlo_desentrelacamento.dart';
import 'controlos_player.dart';
import 'desentrelacamento.dart';
import 'diagnostico.dart';
import 'estatisticas.dart';
import 'faixas.dart';
import 'filtro_desentrelacamento.dart';
import 'leitor_partilhado.dart';
import '../design/mensagens.dart';
import 'maquina_controlos.dart';
import 'motor_exo.dart';
import 'motor_mpv.dart';
import 'motor_na_sessao.dart';
import 'motor_reproducao.dart';
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

/// Cria o motor de um player (no Android o player é recriado para mudar a descodificação do mpv:
/// o vo fixa-se ao criar). Os testes dão um motor falso.
typedef CriarMotor = MotorReproducao Function(ModoDescodificacao modo, bool hardware);

/// O motor por omissão: o mpv do media_kit com a configuração do direto desta plataforma.
MotorReproducao criarMotorMpv(ModoDescodificacao modo, bool hardware) =>
    MotorMediaKit(ConfiguracaoMpv.para(PlataformaVideo.atual, modo: modo, hardware: hardware));

/// Cria o ExoPlayer de um player (Android; `tunel`: o modo túnel das preferências). Os testes dão
/// um motor falso.
typedef CriarMotorExo = MotorReproducao Function({required bool tunel});

/// O aviso quando o ExoPlayer não conseguiu tocar um canal e ele abriu no mpv.
const avisoMotorMpv = 'Este canal abriu com o motor mpv';

/// A nota das opções que só existem no mpv, com o ExoPlayer.
const soNoMpv = 'só no motor mpv';

/// O player: toca o canal `indice` de `canais`, com a barra de controlos e o painel de
/// definições ([ControlosPlayer]). As preferências ([Preferencias.atual]) aplicam-se a cada canal.
class PlayerCanais extends StatefulWidget {
  const PlayerCanais({super.key, required this.canais, required this.indice, required this.resolver,
      required this.nomeLista, required this.aoSair, this.alternarEcraInteiro, this.aoMudarCanal,
      this.criarMotor = criarMotorMpv, this.criarMotorExo = novoMotorExo, @visibleForTesting this.plataforma,
      @visibleForTesting this.agora});

  final List<Canal> canais;
  final int indice;
  final ResolverFonte resolver;
  final String nomeLista;
  final VoidCallback aoSair;

  /// Windows: F11 / duplo clique / botão.
  final VoidCallback? alternarEcraInteiro;

  /// O canal que está a tocar mudou (cima/baixo): ao sair, a lista foca este.
  final ValueChanged<int>? aoMudarCanal;

  /// O mpv: o motor no Windows, no Android quando é o das preferências, e o recurso quando o
  /// ExoPlayer não consegue tocar um canal.
  final CriarMotor criarMotor;

  /// O ExoPlayer (Android, quando é o motor das preferências: [Preferencias.motorAndroid]).
  final CriarMotorExo criarMotorExo;

  /// Só para os testes: a plataforma (por omissão a deste aparelho).
  final PlataformaVideo? plataforma;

  /// Só para os testes: o relógio (por omissão o de parede). O do direto, o do proveito de uma
  /// ligação e o das paragens a meio do canal.
  final DateTime Function()? agora;

  @override
  State<PlayerCanais> createState() => PlayerCanaisState();
}

class PlayerCanaisState extends State<PlayerCanais> with WidgetsBindingObserver {
  late final _plataforma = widget.plataforma ?? PlataformaVideo.atual;
  late final _android = _plataforma == PlataformaVideo.android;

  final _prefs = Preferencias.atual;
  final _sessao = SessaoPlayer();
  late final DateTime Function() _agora = widget.agora ?? DateTime.now;
  late final _relogio = RelogioDireto(agora: _agora);
  final _controlos = GlobalKey<ControlosPlayerState>();

  // a configuração do mpv para direto (buffer, reconexão, descodificação por plataforma); no
  // Android o player é recriado para mudar a descodificação (o vo fixa-se ao criar)
  late ModoDescodificacao _modo = Preferencias.atual.modoAndroid;
  late bool _hardware = Preferencias.atual.hardware;
  late MotorReproducao _motor;

  /// O motor que está por trás agora (o do canal: [MotorNaSessao]).
  late TipoMotor _tipo;

  /// O ExoPlayer a ser largado antes de o mpv o substituir (quem abre a seguir espera por ele).
  Future<void>? _largando;

  /// Ao abrir no mpv um canal que o ExoPlayer não tocou: diz-se quando abrir.
  bool _avisarMpv = false;

  /// O canal ([_chave]) de que são os erros do motor agora: o que o motor abriu (ou para que foi
  /// criado). null entre a tecla do zapping e o `abrir` do canal novo: nesse intervalo o mesmo
  /// ExoPlayer ainda pode mandar um erro atrasado do canal anterior, que não é do novo.
  String? _chaveDoMotor;
  SaltosDireto? _saltos;

  /// O motor do mpv (media_kit), quando é ele que está por trás: as propriedades do mpv para o
  /// desentrelaçamento, o modo Compatível, as estatísticas, a taxa do ecrã e os saltos no cache.
  /// null noutro motor (essas funções ficam desligadas).
  MotorMediaKit? get _mk => switch (_motor) { final MotorMediaKit m => m, _ => null };
  MotorForaDaUi? get _mpv => _mk?.mpv;

  /// As leituras do mpv da barra, da barra de progresso e das estatísticas: de uma vez (um
  /// isolate por leitura, nunca na thread da UI) e partilhadas entre elas. Sem mpv: nada ("").
  late final _leitor = LeitorPartilhado((ps) => _mpv?.getProperties(ps) ?? Future.value(const <String, String>{}));
  final _subsPlayer = <StreamSubscription>[];
  int _larguraVista = 0;

  /// O tamanho da imagem e a posição, segundo os eventos do motor.
  Size? _tamanho;
  Duration _posicao = Duration.zero;

  /// O tamanho da imagem agora (no mpv lê-se na hora: chega depois de o vídeo ser construído).
  Size? get _tamanhoAgora => _mk?.tamanhoAtual ?? _tamanho;
  final _taxa = TaxaEcra();

  /// O fps do canal aberto no pedido `pedido` (do motor ou medido): sabido uma vez por abertura.
  ({int pedido, double fps})? _fpsConhecido;

  /// Cada pedido de modo de ecrã ([_ajustarTaxa]) leva um número: um mais novo cala os anteriores.
  int _ajusteTaxa = 0;
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
  /// [_intervaloEntrelacamento] (ver `controlo_desentrelacamento.dart`). [_playerDoDesentrelacamento]:
  /// o player para que o meio foi posto (um player recriado não tem o vf do antigo).
  late final _deint = ControloDesentrelacamento(_plataforma);
  MotorReproducao? _playerDoDesentrelacamento;
  Timer? _vigiaEntrelacamento;
  static const _intervaloEntrelacamento = Duration(seconds: 10);

  /// O shader do Flutter (Android) e o ficheiro do shader do mpv (Windows), uma vez por processo.
  ui.FragmentProgram? _programaFlutter;
  static Future<String?>? _shaderMpv;

  /// A imagem que estava no ecrã quando o servidor cortou: fica por baixo do "A carregar…" até à
  /// primeira imagem do canal reaberto (em vez do preto).
  final _ultima = UltimaImagem();
  FaixasMotor _faixas = const FaixasMotor();
  FaixaAtual _faixa = const FaixaAtual();
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
  ({double inicio, double posicao})? _continuarDe;

  /// O que a ligação atual deu de imagem nova (sem o ponto do filme nem o salto automático).
  var _ligacao = LigacaoDireto();

  /// O som enquanto se espera pelo salto depois de reabrir.
  final _mudo = MudoDuranteSalto();

  /// A reabrir com um salto por decidir ([_saltarParaOndeEstava]): sem som e com a última imagem
  /// por cima, para não se ver nem ouvir o bocado repetido.
  bool _saltoPendente = false;

  /// As linhas do ecrã que o vídeo ocupa (para o shader do Android; nas estatísticas). Medidas depois
  /// de cada layout ([MedidorLinhas]): redimensionar reconstrói quem depende delas.
  final _linhasNoEcra = ValueNotifier<double?>(null);

  /// A faixa de áudio escolhida pelo utilizador neste canal (volta a pôr-se depois de reabrir).
  FaixaMotor? _audioEscolhido;

  // nunca ecrã preto mudo: o "a abrir" só sai com imagem; sem ela em 20 s, erro
  /// Um stop que não acaba neste tempo é de um mpv que deixou de responder.
  static const _limiteStop = Duration(seconds: 5);

  late final _vigia = VigiaAbertura(
    aoAbrir: () {
      if (!mounted) return;
      final retomou = _aRetomar;
      _abriuEm = _agora();
      _continuar.abriu();
      _ligacao.abriu((_mk?.player.state.position ?? _posicao).inMicroseconds / 1e6);
      _porMudo(_mudo.primeiraImagem(silencio: _sessao.silencio));
      setState(() {
        _aAbrir = false;
        _erro = null;
        // à espera do salto para onde se estava: a última imagem e o "A carregar…" ficam até lá
        if (!_saltoPendente) {
          _aRetomar = false;
          _ultima.largar();
        }
      });
      if (_avisarMpv) {
        _avisarMpv = false;
        mostrarMensagem(context, avisoMotorMpv);
      }
      _vigiarImagem(_pedido);
      _verEntrelacamento(_pedido);
      if (retomou) _reporFaixaAudio(_pedido);
    },
    aoFalhar: (motivo) {
      if (!mounted) return;
      _motor.parar();
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
    _criarPlayer(_tipoPara(_canais[_i]));
    _abrir();
  }

  /// O motor com que o canal abre: no Android o das preferências (o mpv para os canais que o
  /// ExoPlayer não tocou nesta sessão); nas outras plataformas o mpv.
  TipoMotor _tipoPara(Canal c) =>
      MotorNaSessao.instancia.para(_chave(c), plataforma: _plataforma, preferido: _prefs.motorAndroid);

  /// O ExoPlayer está por trás (também um [MotorExo] dado pela fábrica do mpv, nos testes).
  bool get _exo => _tipo == TipoMotor.exoplayer || _motor is MotorExo;

  /// O volume que vai para o motor: sem mpv não há "mute", o silêncio é o volume a 0.
  double get _volumeMotor => _mpv == null && _sessao.silencio ? 0 : _prefs.volume;

  void _criarPlayer(TipoMotor tipo) {
    _tipo = tipo;
    // um motor novo só tem erros do canal para que foi criado
    _chaveDoMotor = _chave(_canais[_i]);
    _motor = tipo == TipoMotor.exoplayer
        ? widget.criarMotorExo(tunel: _prefs.modoTunel)
        : widget.criarMotor(_modo, _hardware);
    final mpv = _mpv;
    _saltos = mpv == null ? null : SaltosDireto(mpv, _relogio);
    _tamanho = null;
    _leitor.esquecer();
    _subsPlayer.add(_motor.erros.listen((erro) {
      if (!mounted) return;
      // o ExoPlayer não toca este canal (formato ou descodificador): abre no mpv, que fica com ele
      // nesta sessão (um 2.º erro já é do mpv: nunca há ciclos)
      if (erro.formato && _tipo == TipoMotor.exoplayer) {
        final chave = _chaveDoMotor;
        // um erro atrasado do canal anterior (zapping no mesmo ExoPlayer): não é deste canal
        if (chave == null || chave != _chave(_canais[_i])) return;
        _passarAoMpv(chave, aviso: true);
        return;
      }
      final e = erro.mensagem;
      if (e.isNotEmpty && erroFatalPlayer(e)) {
        // a reabrir depois de um corte: uma falha passageira (rede, 401) tenta-se outra vez
        if (_aRetomar && _tentarContinuarDepois(_pedido)) return;
        _vigia.parar();
        _taxa.repor();
        setState(() { _erro = mensagemErroPlayer(e); _aAbrir = false; _aRetomar = false; _ultima.largar(); });
      }
    }));
    _subsPlayer.add(_motor.fim.listen((_) => _fimDoBuffer()));
    _subsPlayer.add(_motor.aCarregar.listen((b) {
      _vigia.buffering(b);
      if (!mounted) return;
      if (b != _buffering || (!b && _percentagemBuffer != null)) {
        // o % de uma paragem não passa para a seguinte
        setState(() { _buffering = b; if (!b) _percentagemBuffer = null; });
      }
    }));
    _subsPlayer.add(_motor.percentagemCarga.listen((p) {
      // guarda-se sempre: o mpv pode mandar o % antes do "buffering"
      _percentagemBuffer = p;
      if (mounted && _buffering) setState(() {});
    }));
    _subsPlayer.add(_motor.tamanhoVideo.listen((t) {
      _tamanho = t;
      final w = t?.width.round();
      if ((w ?? 0) > 0) _larguraVista = w!;
      _vigia.largura(w);
    }));
    _subsPlayer.add(_motor.posicao.listen((p) {
      _posicao = p;
      _vigia.tempo(p);
    }));
    _subsPlayer.add(_motor.faixas.listen((t) {
      if (mounted) setState(() => _faixas = t);
    }));
    _subsPlayer.add(_motor.faixaAtual.listen((t) {
      if (mounted) setState(() => _faixa = t);
    }));
    _subsPlayer.add(_motor.fps.listen((fps) {
      // o fps que o motor mediu (TS e HLS no ExoPlayer não o dizem no formato): pede o modo de
      // ecrã, se este canal ainda não tinha fps
      if (!mounted || _fpsConhecido?.pedido == _pedido) return;
      _fpsConhecido = (pedido: _pedido, fps: fps);
      unawaited(_ajustarTaxa(_pedido));
    }));
  }

  /// Recria o player noutro motor ([tipo]), noutra descodificação (o vo do Android fixa-se ao
  /// criar) ou no lugar de um mpv que deixou de responder. Devolve a aposentação do antigo (quem
  /// abre não espera por ela: ver [prepararPlayer]).
  Future<void> _recriar(TipoMotor tipo, ModoDescodificacao modo, bool hardware) {
    _largarSubscricoes();
    final antigo = _motor;
    _modo = modo;
    _hardware = hardware;
    _criarPlayer(tipo);
    if (mounted) setState(() {});
    // pára o antigo (nunca toca por trás); nenhum pedido ao mpv antigo depois de destruído
    return antigo.descartar();
  }

  /// Do ExoPlayer para o mpv: o ExoPlayer é largado primeiro e só depois se cria o mpv (nunca dois
  /// motores ao mesmo tempo).
  Future<void> _largarExoECriar(TipoMotor tipo, ModoDescodificacao modo, bool hardware) async {
    _largarSubscricoes();
    final antigo = _motor;
    try {
      await antigo.descartar().timeout(_limiteStop);
    } catch (e) {
      debugPrint('exoplayer: não foi largado a tempo (${e.runtimeType})');
    }
    // saiu do player entretanto (o dispose já largou o antigo)
    if (!mounted) return;
    _modo = modo;
    _hardware = hardware;
    _criarPlayer(tipo);
    setState(() {});
  }

  void _largarSubscricoes() {
    for (final s in _subsPlayer) {
      s.cancel();
    }
    _subsPlayer.clear();
  }

  /// O ExoPlayer não tocou o canal (ou o utilizador pediu o modo compatível): o canal passa ao mpv
  /// nesta sessão e reabre já lá (no mesmo ponto, se se estava a reabrir depois de um corte).
  void _passarAoMpv(String chave, {required bool aviso}) {
    MotorNaSessao.instancia.passarAoMpv(chave);
    _vigia.parar();
    _avisarMpv = aviso;
    _abrir(continuar: _aRetomar, mesmoCanal: true);
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
  Future<void> _fimDoBuffer() async {
    final mk = _mk;
    // sem mpv não se sabe se é um direto nem onde parou (o motor trata do fim)
    if (!mounted || mk == null) return;
    final pedido = _pedido;
    // um ficheiro com fim (filme de uma lista M3U) acaba: só os diretos se pedem de novo
    final p = await mk.mpv.getProperties(const ['seekable', 'partially-seekable', 'demuxer-start-time', 'time-pos']);
    final eDireto = ContinuarDireto.eDireto(p['seekable']!, partiallySeekable: p['partially-seekable']!);
    if (!mounted || pedido != _pedido) return;
    // ou um ficheiro que o servidor cortou muito antes do fim (fica-se parado na última imagem):
    // reabre-se no ponto onde parou
    final posicao = mk.player.state.position;
    final cortado = !eDireto && ContinuarDireto.cortadoAntesDoFim(posicao: posicao, duracao: mk.duracao);
    final direto = eDireto || cortado;
    if (!ContinuarDireto.deve(
        fimDoBuffer: true, aAbrir: _aAbrir, erro: _erro != null, aTocar: _aTocar, direto: direto)) {
      return;
    }
    final abriu = _abriuEm;
    final posCorte = double.tryParse(p['time-pos'] ?? '');
    // o que a ligação deu de imagem nova (com os saltos à mão para o fim do buffer; sem o ponto do
    // filme nem o salto automático depois de reabrir), ou a parede
    final tocou = _ligacao.proveito(
        parede: abriu == null ? Duration.zero : _agora().difference(abriu), posicaoNoCorte: posCorte);
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
    // sem os dois PTS não há salto por que esperar (nada de ~6 s sem som)
    _continuarDe = cortado
        ? null
        : ContinuarDireto.pontoDoCorte(inicio: p['demuxer-start-time'] ?? '', posicao: p['time-pos'] ?? '');
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
        if (_faixa.audio.id != igual.id) await _motor.escolherAudio(igual);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Abre o canal `_i`. `continuar`: o mesmo canal outra vez porque o buffer acabou. `mesmoCanal`:
  /// o mesmo canal outra vez noutro motor ou de volta ao direto (não é "visto" de novo nem mostra
  /// o nome).
  Future<void> _abrir({bool continuar = false, bool mesmoCanal = false}) async {
    final pedido = ++_pedido;
    final canal = _canais[_i];
    final repetido = continuar || mesmoCanal;
    // o aviso do mpv é só do recurso, quando for ele a abrir
    if (!repetido) {
      _avisarMpv = false;
      // os erros que o motor mandar até abrir o canal novo são do anterior
      _chaveDoMotor = null;
    }
    if (!continuar) {
      _continuar.reiniciar();
      _audioEscolhido = null;
      _abriuEm = null;
      _retomarEm = null;
      _continuarDe = null;
    }
    _saltoPendente = false;
    _mudo.reiniciar();
    _ligacao = LigacaoDireto();
    _vigiaEntrelacamento?.cancel();
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
    if (repetido) {
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
      // Windows: "Abrir em modo compatível" (cartão de erro) põe este canal por software
      final hardwareCanal = hardware && (_android || !CompativelNaSessao.instancia.software(_chave(canal)));
      // o ExoPlayer de um canal anterior ainda a ser largado: espera-se (senão eram dois motores)
      final largando = _largando;
      if (largando != null) await largando;
      if (!mounted || pedido != _pedido) return;
      final tipo = _tipoPara(canal);
      if (tipo != _tipo && _tipo == TipoMotor.exoplayer) {
        final l = _largando = _largarExoECriar(tipo, modo, hardware);
        await l;
        if (identical(_largando, l)) _largando = null;
        if (!mounted || pedido != _pedido) return;
      } else {
        if (tipo == TipoMotor.exoplayer && _tipo == TipoMotor.mpv) {
          // do mpv para o ExoPlayer: o mpv larga primeiro o descodificador (num aparelho com poucos
          // descodificadores, o ExoPlayer falhava ao criar o seu e o canal passava ao mpv sem razão);
          // um mpv que não pára a tempo não prende
          try {
            await _motor.parar().timeout(_limiteStop);
          } catch (e) {
            debugPrint('mpv: não parou a tempo antes do ExoPlayer (${e.runtimeType})');
          }
          if (!mounted || pedido != _pedido) return;
        }
        // um mpv que deixou de responder não se volta a usar: player novo
        final mpvNovo = tipo == TipoMotor.mpv &&
            ((_android && (modo != _modo || hardware != _hardware)) || (_mpv?.semResposta ?? false));
        await prepararPlayer(
          novo: tipo != _tipo || mpvNovo,
          zap: pedido > 1,
          parar: () => _motor.parar(),
          trocar: () => _recriar(tipo, modo, hardware),
          limiteStop: _limiteStop,
        );
      }
      // o desentrelaçamento: no mesmo canal (corte do servidor) e no mesmo mpv fica tudo como estava;
      // noutro canal tira-se o filtro do anterior e decide-se de novo com a imagem
      final playerNovo = !identical(_playerDoDesentrelacamento, _motor);
      _playerDoDesentrelacamento = _motor;
      final desentrelacamento = _deint.abrir(continuar: continuar, playerNovo: playerNovo);
      if (!mounted || pedido != _pedido) return;
      final f = await widget.resolver(canal, continuar: repetido);
      if (!mounted || pedido != _pedido) return;
      final mk = _mk;
      if (mk != null) {
        await mk.configurado;
        if (!mounted || pedido != _pedido) return;
        // as preferências em cada canal: 1×, volume, silêncio, atraso do áudio, desentrelaçamento…
        await aplicarAoAbrir(mk.mpv, _prefs, _sessao,
            plataforma: _plataforma,
            modo: _modo,
            hardware: hardwareCanal,
            limparFiltro: desentrelacamento.limpar,
            manterDesentrelacamento: desentrelacamento.manter);
      } else {
        // outro motor: só o que a interface tem (1× e o volume; o silêncio é o volume a 0)
        await _motor.velocidade(1);
        await _motor.volume(_volumeMotor);
      }
      if (!mounted || pedido != _pedido) return;
      _vigia.abrindo();
      _larguraVista = 0;
      await VezDoAudio.instancia.esperar();
      if (!mounted || pedido != _pedido) return;
      _chaveDoMotor = _chave(canal);
      await _motor.abrir(f.url, f.headers, inicio: continuar ? _retomarEm : null);
      // o modo de ecrã pede-se já (o fps sabe-se logo que o canal abre): a TV pisca a mudar de
      // modo enquanto o indicador de abertura ainda está à vista, não por cima da imagem
      if (mounted && pedido == _pedido) unawaited(_ajustarTaxa(pedido));
      final de = continuar ? _continuarDe : null;
      if (de != null && mounted && pedido == _pedido) {
        _saltoPendente = true;
        _porMudo(_mudo.comecar());
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

  /// A informação da barra (resolução, imagens/s, débito) num motor sem mpv: das estatísticas
  /// dele, com os nomes do mpv ([textoInfoStream]).
  Future<Map<String, String>> _infoDoMotor() async {
    final e = await _motor.estatisticas();
    final r = e.resolucao, fps = e.fps, br = e.bitrate;
    return {
      if (r != null) 'width': '${r.width}',
      if (r != null) 'height': '${r.height}',
      if (fps != null) 'container-fps': '$fps',
      if (br != null) 'video-bitrate': '$br',
    };
  }

  /// A barra de progresso: num direto pelos saltos do cache ([SaltosDireto.irPara]: seek
  /// relativo, nunca reabre o canal, o relógio do direto fica certo); num filme, seek absoluto.
  Future<void> _procurar(JanelaProgresso janela, double alvo) async {
    final pedido = _pedido;
    final mpv = _mpv, saltos = _saltos;
    if (mpv == null || saltos == null) return;
    String? aviso;
    if (janela.direto) {
      aviso = await saltos.irPara(alvo);
    } else if (pedido == _pedido) {
      await mpv.command(['seek', alvo.toStringAsFixed(3), 'absolute']);
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
    // o fps do canal lê-se do mpv, ou das estatísticas do ExoPlayer: sem ele não se pede modo
    final mpv = _mpv;
    final motor = _motor;
    if (mpv == null && !_exo) return;
    final minha = ++_ajusteTaxa;
    // o container-fps costuma vir logo; senão o medido, que demora uns segundos (no ExoPlayer o
    // medido também chega pelo motor: [MotorReproducao.fps])
    try {
      for (var tentativa = 0; tentativa < 5; tentativa++) {
        if (!mounted || pedido != _pedido || !identical(motor, _motor) || minha != _ajusteTaxa) return;
        final conhecido = _fpsConhecido;
        double fps;
        if (conhecido != null && conhecido.pedido == pedido) {
          fps = conhecido.fps;
        } else if (mpv != null) {
          fps = double.tryParse(await mpv.getProperty('container-fps')) ?? 0;
          if (fps <= 0) fps = double.tryParse(await mpv.getProperty('estimated-vf-fps')) ?? 0;
        } else {
          fps = (await motor.estatisticas()).fps ?? 0;
        }
        if (fps > 0) {
          if (!mounted || pedido != _pedido || minha != _ajusteTaxa) return;
          _fpsConhecido = (pedido: pedido, fps: fps);
          final hz = await _taxa.ajustarPara(fps);
          final ecra = _hzEcra?.toStringAsFixed(2) ?? '?';
          final pedidoTexto = hz == null ? 'nada pedido (já certo ou nenhum modo serve)' : 'pedido ${hz.toStringAsFixed(2)} Hz';
          debugPrint('taxa do ecrã: canal a ${fps.toStringAsFixed(2)} imagens/s; ecrã a $ecra Hz; $pedidoTexto');
          if (hz != null && mounted) {
            setState(() => _hzPedidos = hz);
            // a TV demora a mudar de modo: os Hz do sistema leem-se depois
            await Future<void>.delayed(const Duration(seconds: 3));
            await _lerHzEcra();
            debugPrint('taxa do ecrã: depois do pedido o ecrã está a ${_hzEcra?.toStringAsFixed(2) ?? '?'} Hz');
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
  Future<void> _saltarParaOndeEstava(int pedido, ({double inicio, double posicao}) de) async {
    for (var i = 0; i < _tentativasRetoma; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted || pedido != _pedido) return;
      final mpv = _mpv;
      if (mpv == null) return;
      try {
        final m = await mpv.getProperties(const ['demuxer-start-time', 'time-pos', 'demuxer-cache-state']);
        if (!mounted || pedido != _pedido) return;
        final pos = double.tryParse(m['time-pos'] ?? '');
        final inicioNovo = double.tryParse(m['demuxer-start-time'] ?? '');
        if (pos == null || inicioNovo == null) continue; // o stream novo ainda não começou
        final alvo = ContinuarDireto.posicaoNoNovo(inicioAntigo: de.inicio, posicaoAntiga: de.posicao, inicioNovo: inicioNovo);
        if (alvo == null) return;
        final fim = fimProcuravel(m['demuxer-cache-state'] ?? '', pos);
        final aFrente = fim == null ? null : fim - pos - SaltosDireto.margemFim.inMicroseconds / 1e6;
        final r = ContinuarDireto.saltoAoRetomar(
            alvo: alvo,
            posicao: pos,
            aFrente: aFrente,
            // o servidor já fechou: o cache não cresce mais, decide-se já (nada de esperar ~6 s)
            ultimaTentativa: i == _tentativasRetoma - 1 || cacheNoFim(m['demuxer-cache-state'] ?? ''));
        if (r.esperar) continue;
        final salto = r.salto;
        final texto = salto == null ? 'sem salto' : 'salta ${salto.toStringAsFixed(1)} s';
        debugPrint('player: reaberto; o que se viu por último fica a ${(alvo - pos).toStringAsFixed(1)} s; $texto');
        if (salto != null) {
          await mpv.command(['seek', salto.toStringAsFixed(3), 'relative']);
          _relogio.avancou(Duration(microseconds: (salto * 1e6).round()));
          // o salto não é imagem nova desta ligação (o proveito conta a partir daqui)
          _ligacao.saltou(pos + salto);
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
    // o som só volta com imagem à vista (senão volta na primeira imagem, no aoAbrir)
    _porMudo(_mudo.acabouSalto(silencio: _sessao.silencio, temImagem: !_aAbrir));
    if (!_aAbrir && _aRetomar) {
      setState(() {
        _aRetomar = false;
        _ultima.largar();
      });
    }
  }

  void _porMudo(String? valor) {
    final mpv = _mpv;
    if (valor != null && mpv != null) unawaited(mpv.setProperty('mute', valor).catchError((Object _) => null));
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
    final mpv = _mpv;
    if (!_android || _modo != ModoDescodificacao.direto || !_hardware || mpv == null) return;
    final player = _motor;
    try {
      // duas leituras seguidas sem imagem (a saída de vídeo do media_kit troca de vo no arranque)
      for (final espera in const [Duration(seconds: 2), Duration(seconds: 1)]) {
        await Future<void>.delayed(espera);
        if (!mounted || pedido != _pedido || !identical(player, _motor)) return;
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
      await _motor.play();
    } else {
      _relogio.pausou(); // o direto continua: fica-se para trás
      await _motor.pausar();
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
        final saltos = _saltos;
        if (saltos != null) _saltar(saltos.recuar);
      case AcaoPlayer.avancar:
        final saltos = _saltos;
        if (saltos != null) _saltar(saltos.avancar);
      case AcaoPlayer.voltarAoDireto:
        _saltar(() async {
          if (!_aTocar) await _tocar(true);
          // longe demais para o buffer: reabre o canal (link novo) — o seek ficava minutos atrás.
          // Se entretanto mudou de canal, não se mexe no canal novo.
          final pedido = _pedido;
          final saltos = _saltos;
          if (saltos == null) {
            // sem saltos (ExoPlayer): o canal outra vez, no direto
            if (mounted && pedido == _pedido) _abrir(mesmoCanal: true);
            return null;
          }
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
    _motor.velocidade(v);
  }

  /// Muda uma preferência, guarda-a e aplica-a já.
  void _preferir(void Function(Preferencias p) mudar, [Future<void> Function()? aplicar]) {
    setState(() => mudar(_prefs));
    _prefs.guardar().catchError((Object e) => debugPrint('preferências não gravadas ($e)'));
    aplicar?.call();
  }

  String get _textoDesentrelacamento {
    final l = _tamanhoAgora?.height.round() ?? 0, n = _linhasNoEcra.value;
    if (_deint.meio == MeioDesentrelacamento.shaderFlutter && n != null && n > 0 && !shaderCabe(linhasVideo: l, linhasNoEcra: n)) {
      return 'desligado (imagem reduzida no ecrã)';
    }
    return textoDesentrelacamento(_deint.meio,
        ligado: _prefs.desentrelacar, entrelacada: _deint.entrelacada, confirmado: _deint.confirmado);
  }

  /// O modo Ligado: também nas imagens que o mpv vê como progressivas.
  bool get _forcarDesentrelacamento => _prefs.modoDesentrelacamento == ModoDesentrelacamento.ligado;

  /// "Abrir em modo compatível" (cartão de erro): só este canal, nesta sessão (Compatível no
  /// Android, software no Windows).
  void _abrirCompativel() {
    // no ExoPlayer não há modo compatível: o mais compatível é o mpv
    if (_tipo == TipoMotor.exoplayer) return _passarAoMpv(_chave(_canais[_i]), aviso: false);
    CompativelNaSessao.instancia.pedir(_chave(_canais[_i]));
    _abrir();
  }

  bool get _shaderFlutterPronto => _programaFlutter != null && FiltroDesentrelacamento.suportado;

  /// O desentrelaçamento da app só no motor que o suporta e que expõe o mpv.
  bool get _comDesentrelacamento => _motor.suportaDesentrelacamento && _mpv != null;

  /// No Windows há sempre o shader do mpv; no Android, o do Flutter se o aparelho o permitir.
  bool get _desentrelacamentoPossivel =>
      _comDesentrelacamento && (!_android || _shaderFlutterPronto || _deint.filtros);

  /// O Android no modo direto (o mpv não vê as imagens: o filtro não se aplica).
  bool get _diretoAndroid => _android && _modo == ModoDescodificacao.direto && _hardware;

  /// O que o painel diz do desentrelaçamento (conforme o que há mesmo neste aparelho). As 50 imagens/s
  /// só quando o filtro existe; antes da primeira leitura do mpv não se promete nem se nega.
  /// Ligado: em todas as imagens (as que o mpv vê como progressivas também).
  String get _notaDesentrelacamento {
    if (_exo) return soNoMpv;
    if (!_desentrelacamentoPossivel) return 'Este aparelho não permite o desentrelaçamento do player';
    final forcar = _forcarDesentrelacamento;
    if (_deint.filtrosPorSaber) {
      return forcar ? 'Em todas as imagens, também nas que parecem progressivas' : 'Só nas imagens entrelaçadas (1080i/576i/480i)';
    }
    if (_deint.filtros) {
      return _diretoAndroid
          ? 'Por campo (50 imagens/s; 60 nos 480i); na descodificação Direta um direto entrelaçado reabre em Compatível'
          : 'Por campo (50 imagens/s; 60 nos 480i), ${forcar ? 'em todas as imagens' : 'só nas imagens entrelaçadas'}';
    }
    return forcar
        ? 'Em todas as imagens; limpa as linhas sem dobrar as imagens/s'
        : 'Só nas imagens entrelaçadas (1080i/576i/480i); limpa as linhas sem dobrar as imagens/s';
  }

  /// Lê do mpv se a imagem é entrelaçada e se o filtro posto funciona (de uma vez, fora da UI) e põe
  /// o meio certo; repete a cada [_intervaloEntrelacamento] (um canal pode passar de progressivo a
  /// entrelaçado), ou a cada segundo enquanto a imagem ou o filtro estão por medir.
  Future<void> _verEntrelacamento(int pedido) async {
    _vigiaEntrelacamento?.cancel();
    final mpv = _mpv;
    if (!_comDesentrelacamento || mpv == null) return;
    try {
      final m = await mpv.getProperties(propriedadesEntrelacamento(_plataforma));
      if (!mounted || pedido != _pedido) return;
      // Android direto: o filtro não se aplica, o canal reabre em Compatível (uma vez por canal); e
      // um Compatível com o filtro que perde imagens volta ao direto
      if (_deint.ler(m, ligado: _prefs.desentrelacar, direto: _diretoAndroid, chave: _chave(_canais[_i]))) {
        _mostrarAviso(_deint.avisoReabrir ?? 'Modo compatível ativado para desentrelaçar este canal');
        _abrir();
        return;
      }
      await _aplicarDesentrelacamento(pedido);
    } catch (e) {
      // o player fechou entretanto, ou o mpv falhou: tenta-se na próxima verificação
      debugPrint('desentrelaçamento: verificação falhou ($e)');
    }
    if (!mounted || pedido != _pedido) return;
    _vigiaEntrelacamento = Timer(_deint.verificarCedo ? const Duration(seconds: 1) : _intervaloEntrelacamento,
        () => _verEntrelacamento(pedido));
  }

  /// Põe o meio que serve agora (preferência, imagem, aparelho). Em fila (no controlo); um pedido de
  /// um canal que entretanto mudou ([pedido]) já não toca no mpv.
  Future<void> _aplicarDesentrelacamento([int? pedido]) async {
    final p = pedido ?? _pedido;
    final mpv = _mpv;
    if (!_comDesentrelacamento || mpv == null) return;
    final mudou = await _deint.aplicar(mpv,
        ligado: _prefs.desentrelacar,
        forcar: _forcarDesentrelacamento,
        shaderFlutter: _shaderFlutterPronto,
        direto: _diretoAndroid,
        caminhoShader: _shaderMpv ?? Future.value(),
        valido: () => mounted && p == _pedido);
    if (mudou && mounted) setState(() {});
  }

  /// O modo de descodificação do Android no painel: 0 direta, 1 compatível, 2 software.
  int get _descodificacaoAndroid =>
      !_prefs.hardware ? 2 : (_prefs.modoAndroid == ModoDescodificacao.direto ? 0 : 1);

  String get _rotuloModoAtual => !_hardware ? 'Software' : _modo.rotulo;

  List<ItemDefinicao> _definicoes() {
    final video = escolhaVideo(_faixas.video, _faixa.video);
    final audio = escolhaAudio(_faixas.audio, _faixa.audio);
    final legendas = escolhaLegendas(_faixas.legendas, _faixa.legenda);
    final possivel = _desentrelacamentoPossivel;
    final exo = _exo;
    return [
      DefinicaoEscolha(
        'Desentrelaçamento',
        opcoes: [for (final m in ModoDesentrelacamento.values) m.rotulo],
        atual: (possivel ? _prefs.modoDesentrelacamento : ModoDesentrelacamento.desligado).index,
        aoMudar: possivel
            ? (i) => _preferir((p) => p.modoDesentrelacamento = ModoDesentrelacamento.values[i], _aplicarDesentrelacamento)
            : null,
        nota: _notaDesentrelacamento,
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
        aoMudar: video.opcoes.length > 2 && _mk != null ? (i) => _mk?.escolherVideo(video.faixa(i)) : null,
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
                _motor.escolherAudio(faixa);
              }
            : null,
        nota: audio.opcoes.length <= 2 ? 'Este canal só tem uma' : null,
      ),
      DefinicaoEscolha(
        'Legendas',
        opcoes: legendas.opcoes,
        atual: legendas.atual,
        aoMudar: (i) {
          final faixa = legendas.faixa(i);
          _motor.escolherLegenda(faixa.id == FaixaMotor.nenhuma.id ? null : faixa);
        },
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
        // durante a espera do salto o som fica desligado; o silêncio aplica-se no fim dela
        _porMudo(_mudo.mudouSilencio(v));
        if (_mpv == null) _motor.volume(_volumeMotor);
      }),
      DefinicaoPassos(
        'Atraso do áudio',
        valor: textoAtrasoAudio(_sessao.atrasoAudio),
        nota: exo ? soNoMpv : 'Positivo: o som chega mais tarde',
        menos: !exo && _sessao.atrasoAudio > -limiteAtrasoAudio ? () => _mudarAtrasoAudio(-1) : null,
        mais: !exo && _sessao.atrasoAudio < limiteAtrasoAudio ? () => _mudarAtrasoAudio(1) : null,
      ),
      if (_android)
        DefinicaoEscolha(
          'Descodificação',
          opcoes: [ModoDescodificacao.direto.rotulo, ModoDescodificacao.compativel.rotulo, 'Software (sem hardware)'],
          atual: _descodificacaoAndroid,
          aoMudar: exo
              ? null
              : (i) => _preferir((p) {
                    p.hardware = i != 2;
                    if (i != 2) p.modoAndroid = i == 0 ? ModoDescodificacao.direto : ModoDescodificacao.compativel;
                  }, () async => _abrir()),
          nota: exo
              ? soNoMpv
              : _rotuloModoAtual != [ModoDescodificacao.direto.rotulo, ModoDescodificacao.compativel.rotulo,
                  'Software'][_descodificacaoAndroid]
              ? 'Este canal está em $_rotuloModoAtual (sem imagem na direta, ou entrelaçado)'
              : 'Compatível: para imagem preta ou cores erradas',
        )
      else
        DefinicaoInterruptor(
          'Descodificação por hardware',
          valor: _prefs.hardware,
          aoMudar: (v) => _preferir((p) => p.hardware = v, () async {
            await _mpv?.setProperty('hwdec', hwdecEmTempoReal(_plataforma, hardware: v)!);
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
    _preferir((p) => p.volume = p.volume + passo, () => _motor.volume(_volumeMotor));
  }

  void _mudarAtrasoAudio(int direcao) {
    setState(() => _sessao.atrasoAudio = passoAtrasoAudio(_sessao.atrasoAudio, direcao));
    final mpv = _mpv;
    if (mpv != null) aplicarAtrasoAudio(mpv, _sessao.atrasoAudio);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _continuar.reiniciar(); // nenhuma reabertura marcada depois de sair
    _esconderAviso?.cancel();
    _vigiaEntrelacamento?.cancel();
    _ultima.largar();
    _linhasNoEcra.dispose();
    _vigia.parar();
    _taxa.fechar();
    for (final s in _subsPlayer) {
      s.cancel();
    }
    // o mpv só se destrói depois dos pedidos que ainda lá estão
    unawaited(_motor.descartar());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canal = _canais[_i];
    // o ExoPlayer ajusta a SurfaceView no nativo (sem aumento no Flutter: o zoom fica preencher)
    final exo = _exo;
    final ajuste = exo ? ajusteVideoExo(_prefs.formato) : ajusteVideo(_prefs.formato);
    final mk = _mk;
    Widget video = mk == null
        ? _motor.video(ajuste: ajuste.fit, proporcao: ajuste.aspecto)
        : mk.videoMpv(
            ajuste: ajuste.fit,
            proporcao: ajuste.aspecto,
            // Android: o shader de desentrelaçamento por cima da textura (o tamanho lê-se na hora:
            // chega depois de o Video ser construído)
            envolverTextura: _deint.meio == MeioDesentrelacamento.shaderFlutter && _comDesentrelacamento
                ? (t) => ValueListenableBuilder<double?>(
                    valueListenable: _linhasNoEcra,
                    builder: (_, _, _) => TexturaDesentrelacada(
                        programa: _programaFlutter,
                        colunas: mk.tamanhoAtual?.width.round() ?? 0,
                        linhas: mk.tamanhoAtual?.height.round() ?? 0,
                        linhasNoEcra: _linhasNoEcra.value,
                        child: t))
                : null,
          );
    if (ajuste.escala != 1) video = ClipRect(child: Transform.scale(scale: ajuste.escala, child: video));
    if (_android) {
      // as linhas do ecrã que o vídeo ocupa: reduzido, o shader não serve (os campos já vêm misturados)
      video = MedidorLinhas(
          linhas: _linhasNoEcra,
          medir: (caixa, dpr) => linhasMostradas(
              caixa: caixa,
              dpr: dpr,
              colunas: _tamanhoAgora?.width.round() ?? 0,
              linhas: _tamanhoAgora?.height.round() ?? 0,
              fit: ajuste.fit,
              aspecto: ajuste.aspecto,
              escala: ajuste.escala),
          child: video);
    }
    video = _ultima.envolver(video);

    return ColoredBox(
      // o vídeo do ExoPlayer está por baixo da interface: nada opaco por cima dele (as barras são a
      // caixa preta do nativo)
      color: exo ? Colors.transparent : Colors.black,
      child: ControlosPlayer(
        key: _controlos,
        estado: EstadoControlos(
          numero: numeroMostrado(_canais, _i),
          canal: canal.nome,
          subtitulo: subtituloCanal(lista: widget.nomeLista, grupo: canal.grupo),
          aTocar: _aTocar,
          velocidade: _velocidade,
          erro: _erro != null,
          podeAlternar: _historico.anterior != null,
        ),
        aoNumero: _irParaNumero,
        atraso: () => _relogio.atraso,
        // sem mpv: a informação vem das estatísticas do motor e não há barra de progresso nem
        // saltos (só o mpv salta no que já recebeu)
        lerInfoStream: exo ? _infoDoMotor : () => _leitor.ler(propriedadesInfoStream),
        lerProgresso: exo ? null : () async => janelaDe(await _leitor.ler(propriedadesProgresso)),
        aoProcurar: _procurar,
        comSaltos: !exo,
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
                // o ExoPlayer: imagens perdidas e mostradas, fps, codec, resolução, débito e buffer
                ler: exo ? null : _lerMpv,
                lerMotor: exo ? _motor.estatisticas : null,
                geracao: _pedido,
                soInterface: exo,
                hzEcra: _hzEcra,
                extra: [
                  if (_android && !exo) ('Modo de descodificação', _rotuloModoAtual),
                  if (mk != null) ('Saída · hwdec pedido', '${mk.config.vo} · ${mk.config.hwdec}')
                  else ('Motor', _motor.nome),
                  if (exo) ('Modo túnel', _prefs.modoTunel ? 'pedido' : 'desligado')
                  else ('Desentrelaçamento', _textoDesentrelacamento),
                  if (_android && (_linhasNoEcra.value ?? 0) > 0)
                    ('Linhas no ecrã · do vídeo', '${_linhasNoEcra.value!.round()} · ${_tamanhoAgora?.height.round() ?? 0}'),
                  if (_hzPedidos != null) ('Taxa do ecrã pedida', '${_hzPedidos!.toStringAsFixed(2)} Hz'),
                ],
              ),
            ),
          if (_erro != null)
            CartaoErroCanal(
              texto: '${canal.nome}: $_erro',
              aoTentar: _abrir,
              aoCompativel: _abrirCompativel,
              aoAnterior: _historico.anterior != null ? () => _agir(AcaoPlayer.alternarCanal) : null,
              aoVoltar: widget.aoSair,
            ),
        ]),
      ),
    );
  }
}
