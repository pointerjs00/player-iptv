import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../dados/preferencias_player.dart';
import '../../modelo/canal.dart';
import '../../protocolos/protocolo.dart';
import '../../rede/http.dart';
import '../design/componentes.dart';
import '../design/ecra.dart';
import 'aviso_buffering.dart';
import 'compativel_sessao.dart';
import 'configuracao_mpv.dart';
import 'diagnostico.dart';
import 'estatisticas.dart';
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

/// O player: toca o canal `indice` de `canais`. Cima/baixo (ou Canal +/-) troca de canal,
/// OK mostra a informação, Voltar/Esc sai.
class PlayerCanais extends StatefulWidget {
  const PlayerCanais({super.key, required this.canais, required this.indice, required this.resolver,
      required this.nomeLista, required this.aoSair, this.alternarEcraInteiro, this.aoMudarCanal});

  final List<Canal> canais;
  final int indice;
  final ResolverFonte resolver;
  final String nomeLista;
  final VoidCallback aoSair;
  final VoidCallback? alternarEcraInteiro;

  /// O canal que está a tocar mudou (cima/baixo): ao sair, a lista foca este.
  final ValueChanged<int>? aoMudarCanal;

  @override
  State<PlayerCanais> createState() => PlayerCanaisState();
}

class PlayerCanaisState extends State<PlayerCanais> with WidgetsBindingObserver {
  static final _android = PlataformaVideo.atual == PlataformaVideo.android;

  // a configuração do mpv para direto (buffer, reconexão, descodificação por plataforma); o
  // player é recriado se um canal precisar do modo "Compatível" (o vo fixa-se ao criar)
  ModoDescodificacao _modo = PreferenciasPlayer.atual.modoAndroid;
  late ConfiguracaoMpv _config;
  late Player _player;
  late VideoController _video;
  late Future<void> _configurado;
  final _subsPlayer = <StreamSubscription>[];
  int _larguraVista = 0;
  final _taxa = TaxaEcra();
  double? _hzPedidos;
  double? _hzEcra;
  String? _avisoModo;
  Timer? _esconderAviso;
  bool _estatisticas = false;
  bool _buffering = false;
  double? _percentagemBuffer;
  late List<Canal> _canais = widget.canais;
  late int _i = widget.indice;
  String? _erro;
  bool _aAbrir = true;
  bool _info = true;
  Timer? _esconder;
  int _pedido = 0;
  final _subs = <StreamSubscription>[];
  final _foco = FocusNode();

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
      setState(() { _erro = motivo; _aAbrir = false; _info = true; });
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _criarPlayer();
    _abrir();
  }

  void _criarPlayer() {
    _config = ConfiguracaoMpv.para(PlataformaVideo.atual, modo: _modo);
    _player = Player(configuration: _config.configuracaoPlayer);
    _subsPlayer.add(_player.stream.error.listen((e) {
      if (mounted && e.isNotEmpty && erroFatalPlayer(e)) {
        _vigia.parar();
        _taxa.repor();
        setState(() { _erro = mensagemErroPlayer(e); _aAbrir = false; _info = true; });
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
    // o controlador de vídeo antes de configurar o mpv (as propriedades esperam por ele)
    _video = VideoController(_player, configuration: _config.configuracaoVideo);
    _configurado = aplicarConfiguracao(_player, _config);
  }

  /// Recria o player noutro modo de descodificação (o vo do Android fixa-se ao criar).
  Future<void> _trocarModo(ModoDescodificacao modo) async {
    for (final s in _subsPlayer) {
      s.cancel();
    }
    _subsPlayer.clear();
    final antigo = _player;
    _modo = modo;
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
    setState(() { _aAbrir = true; _erro = null; });
    _mostrarInfo();
    try {
      _vigia.comecar(); // o prazo conta desde o pedido do link
      // ao mudar de canal, o anterior para já: senão continuava a tocar (e a mandar imagem e
      // posição) enquanto o link novo se resolve
      final modo =
          _android ? CompativelNaSessao.instancia.modoPara(_chave(canal), PreferenciasPlayer.atual.modoAndroid) : _modo;
      if (modo != _modo) {
        await _trocarModo(modo);
      } else if (pedido > 1) {
        await _player.stop();
      }
      if (!mounted || pedido != _pedido) return;
      final f = await widget.resolver(canal);
      if (!mounted || pedido != _pedido) return;
      await _configurado;
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
        _info = true;
      });
    }
  }

  /// As propriedades do mpv para as estatísticas (texto; "" quando não há).
  Future<Map<String, String>> _lerMpv() async {
    final mpv = _player.platform;
    if (mpv is! NativePlayer) return const {};
    return {for (final p in propriedadesDiagnostico) p: await mpv.getProperty(p)};
  }

  /// Android TV / Fire TV: pede o modo de ecrã que combina com o fps do canal (50 fps -> 50 Hz),
  /// para cada imagem ficar o mesmo tempo no ecrã (sem judder).
  Future<void> _ajustarTaxa(int pedido) async {
    if (!_android) return;
    await _lerHzEcra();
    if (!PreferenciasPlayer.atual.ajustarTaxaEcra) return;
    final mpv = _player.platform;
    if (mpv is! NativePlayer) return;
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
    if (!_android || _modo != ModoDescodificacao.direto) return;
    final player = _player;
    try {
      // duas leituras seguidas sem imagem (a saída de vídeo do media_kit troca de vo no arranque)
      for (final espera in const [Duration(seconds: 2), Duration(seconds: 1)]) {
        await Future<void>.delayed(espera);
        if (!mounted || pedido != _pedido || !identical(player, _player)) return;
        final mpv = player.platform;
        if (mpv is! NativePlayer) return;
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
    _mostrarAvisoModo('Modo compatível ativado para este canal');
    _abrir();
  }

  void _mostrarAvisoModo(String texto) {
    _esconderAviso?.cancel();
    setState(() => _avisoModo = texto);
    _esconderAviso = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _avisoModo = null);
    });
  }

  /// Comando/teclado: Menu ou I; telemóvel (sem essas teclas): toque longo.
  static String _teclasEstatisticas(BuildContext context) =>
      ecraTv(context) || !PlayerCanaisState._android ? 'Menu/I estatísticas' : 'toque longo: estatísticas';

  /// Mostra/esconde a sobreposição "Estatísticas" (também para a Task 5).
  void alternarEstatisticas() => setState(() => _estatisticas = !_estatisticas);

  void _mostrarInfo() {
    _esconder?.cancel();
    setState(() => _info = true);
    _esconder = Timer(const Duration(seconds: 4), () {
      if (mounted && _erro == null) setState(() => _info = false);
    });
  }

  void _mudar(int delta) {
    if (_canais.length < 2) return;
    _i = (_i + delta) % _canais.length;
    if (_i < 0) _i += _canais.length;
    widget.aoMudarCanal?.call(_i);
    _abrir();
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.pageUp || k == LogicalKeyboardKey.channelUp) {
      _mudar(-1);
    } else if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.channelDown) {
      _mudar(1);
    } else if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      _erro != null ? _abrir() : _mostrarInfo();
    } else if (k == LogicalKeyboardKey.info || k == LogicalKeyboardKey.keyI ||
        k == LogicalKeyboardKey.contextMenu) {
      alternarEstatisticas();
    } else if (k == LogicalKeyboardKey.escape) {
      // o Voltar do Android/comando já fecha a página do player (o sistema trata dele)
      widget.aoSair();
    } else if (k == LogicalKeyboardKey.f11 && widget.alternarEcraInteiro != null) {
      widget.alternarEcraInteiro!();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _esconder?.cancel();
    _esconderAviso?.cancel();
    _vigia.parar();
    _taxa.fechar();
    for (final s in [..._subs, ..._subsPlayer]) {
      s.cancel();
    }
    _player.dispose();
    _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canal = _canais[_i];
    return Focus(
      focusNode: _foco,
      autofocus: true,
      onKeyEvent: _tecla,
      child: GestureDetector(
        onTap: _mostrarInfo,
        onLongPress: alternarEstatisticas,
        onDoubleTap: widget.alternarEcraInteiro,
        onVerticalDragEnd: (d) => _mudar((d.primaryVelocity ?? 0) < 0 ? 1 : -1),
        child: ColoredBox(
          color: Colors.black,
          child: Stack(fit: StackFit.expand, children: [
            Video(key: ObjectKey(_video), controller: _video, controls: NoVideoControls, fill: Colors.black),
            if (_aAbrir) const Center(child: CircularProgressIndicator()),
            // a meio do canal, à espera de dados (o arranque tem o indicador de cima)
            if (_avisoModo != null)
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: SuperficieVidro(
                    cor: const Color(0xD90B0F17),
                    raio: 14,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Text(_avisoModo!, style: const TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
              ),
            AvisoBuffering(aberto: !_aAbrir && _erro == null, buffering: _buffering, percentagem: _percentagemBuffer),
            if (_estatisticas)
              Positioned(
                top: 24,
                left: 24,
                child: PainelEstatisticas(
                  ler: _lerMpv,
                  geracao: _pedido,
                  hzEcra: _hzEcra,
                  extra: [
                    if (_android) ('Modo de descodificação', _modo.rotulo),
                    ('Saída · hwdec pedido', '${_config.vo} · ${_config.hwdec}'),
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
            AnimatedOpacity(
              opacity: _info ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                        colors: [Color(0xCC000000), Color(0x00000000)]),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(canal.nome, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text('${canal.grupo} · ${_i + 1}/${_canais.length} · ${widget.nomeLista}',
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text('▲▼ mudar de canal · OK informação · ${_teclasEstatisticas(context)} · Voltar sair',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
