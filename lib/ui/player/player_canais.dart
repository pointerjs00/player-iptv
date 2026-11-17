import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../modelo/canal.dart';
import '../../protocolos/protocolo.dart';
import '../../rede/http.dart';
import 'vigia_abertura.dart';

/// A mensagem do leitor sem links: nas contas Xtream o link leva o utilizador e a password.
String mensagemErroPlayer(String e) {
  final limpo = semSegredos(e);
  final semPontuacao = limpo.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  return semPontuacao.isEmpty ? 'o canal não abriu' : 'o canal não abriu ($limpo)';
}

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

class PlayerCanaisState extends State<PlayerCanais> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
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
      if (mounted) setState(() { _aAbrir = false; _erro = null; });
    },
    aoFalhar: (motivo) {
      if (!mounted) return;
      _player.stop();
      setState(() { _erro = motivo; _aAbrir = false; _info = true; });
    },
  );

  @override
  void initState() {
    super.initState();
    _subs.add(_player.stream.error.listen((e) {
      if (mounted && e.isNotEmpty) {
        _vigia.parar();
        setState(() { _erro = mensagemErroPlayer(e); _aAbrir = false; _info = true; });
      }
    }));
    _subs.add(_player.stream.buffering.listen(_vigia.buffering));
    _subs.add(_player.stream.width.listen(_vigia.largura));
    _subs.add(_player.stream.position.listen(_vigia.tempo));
    _abrir();
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
      final f = await widget.resolver(canal);
      if (!mounted || pedido != _pedido) return;
      await _player.open(Media(f.url, httpHeaders: f.headers));
    } catch (e) {
      if (!mounted || pedido != _pedido) return;
      _vigia.parar();
      setState(() {
        _erro = e is ErroLista ? e.mensagem : descreverErro(e);
        _aAbrir = false;
        _info = true;
      });
    }
  }

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
    _esconder?.cancel();
    _vigia.parar();
    for (final s in _subs) {
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
        onDoubleTap: widget.alternarEcraInteiro,
        onVerticalDragEnd: (d) => _mudar((d.primaryVelocity ?? 0) < 0 ? 1 : -1),
        child: ColoredBox(
          color: Colors.black,
          child: Stack(fit: StackFit.expand, children: [
            Video(controller: _video, controls: NoVideoControls, fill: Colors.black),
            if (_aAbrir) const Center(child: CircularProgressIndicator()),
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
                    const Text('▲▼ mudar de canal · OK informação · Voltar sair',
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
