import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../dados/preferencias.dart';
import '../../modelo/canal.dart';
import '../../protocolos/protocolo.dart';
import '../../rede/http.dart';
import '../design/componentes.dart';
import 'aplicar_preferencias.dart';
import 'aviso_buffering.dart';
import 'compativel_sessao.dart';
import 'configuracao_mpv.dart';
import 'controlos_player.dart';
import 'diagnostico.dart';
import 'estatisticas.dart';
import 'faixas.dart';
import 'maquina_controlos.dart';
import 'painel_definicoes.dart';
import 'relogio_direto.dart';
import 'saltos_direto.dart';
import 'taxa_ecra.dart';
import 'vigia_abertura.dart';

/// A mensagem do leitor sem links: nas contas Xtream o link leva o utilizador e a password.
String mensagemErroPlayer(String e) {
  final limpo = semSegredos(e);
  final semPontuacao = limpo.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  return semPontuacao.isEmpty ? 'o canal não abriu' : 'o canal não abriu ($limpo)';
}

/// O erro do mpv faz o canal falhar? Não quando é só a queixa do seek que o media_kit faz ao
/// ligar a superfície de vídeo do Android (num direto não se pode recuar, mas continua a tocar).
bool erroFatalPlayer(String e) => !e.contains('force-seekable') && !e.startsWith('Cannot seek');

/// Dá o link (e os headers) de um canal. No Android chama o protocolo; na janela do player
/// do Windows pede-o à janela principal.
typedef ResolverFonte = Future<FonteVideo> Function(Canal canal);

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
  late MotorMpv _motor;
  late SaltosDireto _saltos;
  late VideoController _video;
  late Future<void> _configurado;
  final _subsPlayer = <StreamSubscription>[];
  int _larguraVista = 0;
  final _taxa = TaxaEcra();
  double? _hzPedidos;
  double? _hzEcra;
  String? _aviso;
  Timer? _esconderAviso;
  Timer? _acertarAtraso;
  bool _estatisticas = false;
  bool _buffering = false;
  double? _percentagemBuffer;
  bool _aTocar = true;
  double _velocidade = 1;
  bool _desentrelacamentoAtivo = false;
  Tracks _faixas = const Tracks();
  Track _faixa = const Track();
  late List<Canal> _canais = widget.canais;
  late int _i = widget.indice;
  String? _erro;
  bool _aAbrir = true;
  int _pedido = 0;

  // nunca ecrã preto mudo: o "a abrir" só sai com imagem; sem ela em 20 s, erro
  late final _vigia = VigiaAbertura(
    aoAbrir: () {
      if (!mounted) return;
      setState(() { _aAbrir = false; _erro = null; });
      _ajustarTaxa(_pedido);
      _vigiarImagem(_pedido);
    },
    aoFalhar: (motivo) {
      if (!mounted) return;
      _player.stop();
      _taxa.repor();
      setState(() { _erro = motivo; _aAbrir = false; });
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _criarPlayer();
    _abrir();
    // o atraso ao direto não passa do que há no buffer (ex.: a rede parou)
    _acertarAtraso = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_relogio.emDireto) _saltos.acertarPeloBuffer();
    });
  }

  void _criarPlayer() {
    _config = ConfiguracaoMpv.para(_plataforma, modo: _modo, hardware: _hardware);
    _player = Player(configuration: _config.configuracaoPlayer);
    _motor = MotorMediaKit(_player);
    _saltos = SaltosDireto(_motor, _relogio);
    _subsPlayer.add(_player.stream.error.listen((e) {
      if (mounted && e.isNotEmpty && erroFatalPlayer(e)) {
        _vigia.parar();
        _taxa.repor();
        setState(() { _erro = mensagemErroPlayer(e); _aAbrir = false; });
      }
    }));
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

  /// Recria o player noutra descodificação (o vo do Android fixa-se ao criar).
  Future<void> _recriar(ModoDescodificacao modo, bool hardware) async {
    for (final s in _subsPlayer) {
      s.cancel();
    }
    _subsPlayer.clear();
    final antigo = _player;
    _modo = modo;
    _hardware = hardware;
    _criarPlayer();
    if (mounted) setState(() {});
    await antigo.dispose();
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
    _abrir();
  }

  Future<void> _abrir() async {
    final pedido = ++_pedido;
    final canal = _canais[_i];
    setState(() {
      _aAbrir = true;
      _erro = null;
      _aTocar = true;
      _velocidade = 1;
    });
    _relogio.reiniciar();
    // o nome do canal uns segundos (no primeiro canal a barra ainda não foi construída)
    final controlos = _controlos.currentState;
    if (controlos != null) {
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
      if (_android && (modo != _modo || hardware != _hardware)) {
        await _recriar(modo, hardware);
      } else if (pedido > 1) {
        await _player.stop();
      }
      if (!mounted || pedido != _pedido) return;
      final f = await widget.resolver(canal);
      if (!mounted || pedido != _pedido) return;
      await _configurado;
      if (!mounted || pedido != _pedido) return;
      // as preferências em cada canal: 1×, volume, silêncio, atraso do áudio, desentrelaçamento…
      _desentrelacamentoAtivo = await aplicarAoAbrir(_motor, _prefs, _sessao, plataforma: _plataforma, modo: _modo);
      if (!mounted || pedido != _pedido) return;
      _vigia.abrindo();
      _larguraVista = 0;
      await _player.open(Media(f.url, httpHeaders: f.headers));
    } catch (e) {
      if (!mounted || pedido != _pedido) return;
      _vigia.parar();
      _taxa.repor();
      setState(() {
        _erro = e is ErroLista ? e.mensagem : descreverErro(e);
        _aAbrir = false;
      });
    }
  }

  /// As propriedades do mpv para as estatísticas (texto; "" quando não há).
  Future<Map<String, String>> _lerMpv() async =>
      {for (final p in propriedadesDiagnostico) p: await _motor.getProperty(p)};

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
        if (!semImagemDireta(larguraVista: _larguraVista, propriedades: m)) return;
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
    _i = (_i + delta) % _canais.length;
    if (_i < 0) _i += _canais.length;
    widget.aoMudarCanal?.call(_i);
    _abrir();
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
      case AcaoPlayer.recuar:
        _saltar(_saltos.recuar);
      case AcaoPlayer.avancar:
        _saltar(_saltos.avancar);
      case AcaoPlayer.voltarAoDireto:
        _saltar(() async {
          if (!_aTocar) await _tocar(true);
          await _saltos.voltarAoDireto();
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
            AcaoPlayer.fecharPainel:
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

  bool get _desentrelacamentoTemEfeito =>
      ConfiguracaoMpv.desentrelacamentoTemEfeito(_plataforma, _modo, hardware: _hardware);

  Future<void> _aplicarDesentrelacamento() async {
    final ativo = await aplicarDesentrelacamento(_motor,
        ligado: _prefs.desentrelacar,
        temEfeito: _desentrelacamentoTemEfeito,
        imagensNaGpu: imagensNaGpu(_plataforma, hardware: _prefs.hardware));
    if (mounted) setState(() => _desentrelacamentoAtivo = ativo);
  }

  /// O modo de descodificação do Android no painel: 0 direta, 1 compatível, 2 software.
  int get _descodificacaoAndroid =>
      !_prefs.hardware ? 2 : (_prefs.modoAndroid == ModoDescodificacao.direto ? 0 : 1);

  String get _rotuloModoAtual => !_hardware ? 'Software' : _modo.rotulo;

  List<ItemDefinicao> _definicoes() {
    final video = escolhaVideo(_faixas.video, _faixa.video);
    final audio = escolhaAudio(_faixas.audio, _faixa.audio);
    final legendas = escolhaLegendas(_faixas.subtitle, _faixa.subtitle);
    final temEfeito = _desentrelacamentoTemEfeito;
    return [
      DefinicaoInterruptor(
        'Desentrelaçamento',
        valor: temEfeito && _prefs.desentrelacar,
        aoMudar: temEfeito ? (v) => _preferir((p) => p.desentrelacar = v, _aplicarDesentrelacamento) : null,
        nota: temEfeito
            ? 'Só nas imagens entrelaçadas (canais 1080i/576i)'
            : 'Na descodificação direta é o próprio aparelho que desentrelaça. Para usar o do '
                'player, escolha "Compatível" em Descodificação.',
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
        aoMudar: audio.opcoes.length > 2 ? (i) => _player.setAudioTrack(audio.faixa(i)) : null,
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
    _esconderAviso?.cancel();
    _acertarAtraso?.cancel();
    _vigia.parar();
    _taxa.fechar();
    for (final s in _subsPlayer) {
      s.cancel();
    }
    _player.dispose();
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
    );
    if (ajuste.escala != 1) video = ClipRect(child: Transform.scale(scale: ajuste.escala, child: video));
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
        ),
        atraso: () => _relogio.atraso,
        aoAgir: _agir,
        aoMudarVelocidade: _mudarVelocidade,
        definicoes: _definicoes,
        comEcraInteiro: widget.alternarEcraInteiro != null,
        child: Stack(fit: StackFit.expand, children: [
          video,
          if (_aAbrir) const Center(child: CircularProgressIndicator()),
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
          AvisoBuffering(aberto: !_aAbrir && _erro == null, buffering: _buffering, percentagem: _percentagemBuffer),
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
                  ('Desentrelaçamento', _desentrelacamentoAtivo ? 'ligado' : 'desligado'),
                  if (_hzPedidos != null) ('Taxa do ecrã pedida', '${_hzPedidos!.toStringAsFixed(2)} Hz'),
                ],
              ),
            ),
          if (_erro != null)
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
                    const SizedBox(height: 8),
                    Text('${canal.nome}: $_erro', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      FilledButton(onPressed: _abrir, child: const Text('Tentar de novo')),
                      const SizedBox(width: 8),
                      TextButton(onPressed: widget.aoSair, child: const Text('Voltar')),
                    ]),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
