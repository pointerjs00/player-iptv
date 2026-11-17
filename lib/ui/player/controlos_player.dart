import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../design/componentes.dart';
import '../design/ecra.dart';
import '../design/movimento.dart';
import '../design/tokens.dart';
import 'aplicar_preferencias.dart';
import 'maquina_controlos.dart';
import 'painel_definicoes.dart';
import 'relogio_direto.dart';

/// O que a barra mostra do canal a tocar.
class EstadoControlos {
  const EstadoControlos({required this.canal, required this.subtitulo, this.aTocar = true,
      this.velocidade = 1.0, this.erro = false});

  final String canal;

  /// "grupo · 3/120 · lista".
  final String subtitulo;
  final bool aTocar;
  final double velocidade;

  /// Está à vista o cartão de erro do canal (OK tenta de novo).
  final bool erro;
}

/// A barra de controlos e o painel de definições por cima do vídeo (`child`), e as teclas do
/// comando conforme o que está à vista ([MaquinaControlos]):
/// - escondida: cima/baixo mudam de canal, esquerda/direita recuam/avançam 10 s, OK mostra a barra;
/// - barra: as setas andam pelos botões; esconde-se após 5 s sem atividade;
/// - painel: as setas andam pelo painel; não se esconde sozinho.
/// Voltar fecha o painel, depois a barra, depois sai. Teclas multimédia sempre.
class ControlosPlayer extends StatefulWidget {
  const ControlosPlayer({
    super.key,
    required this.estado,
    required this.atraso,
    required this.aoAgir,
    required this.aoMudarVelocidade,
    required this.definicoes,
    required this.child,
    this.comEcraInteiro = false,
    this.lerInfoStream,
    this.esconderApos = const Duration(seconds: 5),
  });

  final EstadoControlos estado;

  /// Quanto se está atrás do direto (lido a cada segundo com a barra à vista).
  final Duration Function() atraso;

  /// Faz uma ação do player (canal, recuar, play/pausa, sair…).
  final ValueChanged<AcaoPlayer> aoAgir;
  final ValueChanged<double> aoMudarVelocidade;

  /// Os itens do painel (pedidos de novo a cada construção: mostram os valores atuais).
  final List<ItemDefinicao> Function() definicoes;

  /// Lê do player as [propriedadesInfoStream] (resolução, imagens/s, débito): só com a barra
  /// à vista, a cada segundo (no player verdadeiro, fora da thread da UI).
  final Future<Map<String, String>> Function()? lerInfoStream;

  /// Windows: botão de ecrã inteiro e duplo clique.
  final bool comEcraInteiro;
  final Duration esconderApos;
  final Widget child;

  @override
  State<ControlosPlayer> createState() => ControlosPlayerState();
}

class ControlosPlayerState extends State<ControlosPlayer> {
  final _m = MaquinaControlos();
  // fora da navegação com as setas: com o ecrã todo, era o "vizinho" de qualquer botão da barra
  final _raiz = FocusNode(debugLabel: 'player', skipTraversal: true);
  final _play = FocusNode(debugLabel: 'play/pausa');
  final _botaoDefinicoes = FocusNode(debugLabel: 'definições');
  final _painel = FocusNode(debugLabel: 'painel', skipTraversal: true);
  Timer? _esconder;
  Timer? _relogio;
  Timer? _fimInfo;
  bool _infoCanal = false;
  String? _infoStream;
  bool _aLerInfo = false;

  VistaPlayer get vista => _m.vista;

  @override
  void dispose() {
    _esconder?.cancel();
    _relogio?.cancel();
    _fimInfo?.cancel();
    _raiz.dispose();
    _play.dispose();
    _botaoDefinicoes.dispose();
    _painel.dispose();
    super.dispose();
  }

  /// Mostra o nome do canal uns segundos (ao mudar de canal com a barra escondida).
  void mostrarInfoCanal() {
    _fimInfo?.cancel();
    setState(() => _infoCanal = true);
    _fimInfo = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _infoCanal = false);
    });
  }

  /// Volta a contar os 5 s (só com a barra; o painel não se esconde sozinho).
  void _agendar() {
    _esconder?.cancel();
    if (_m.vista != VistaPlayer.controlos) return;
    _esconder = Timer(widget.esconderApos, () {
      if (mounted && _m.vista == VistaPlayer.controlos) _executar(_m.voltar());
    });
  }

  void _atualizarRelogio() {
    final ver = _m.vista != VistaPlayer.escondida;
    if (ver && _relogio == null) {
      _lerInfo();
      _relogio = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        _lerInfo();
      });
    } else if (!ver) {
      _relogio?.cancel();
      _relogio = null;
    }
  }

  Future<void> _lerInfo() async {
    final ler = widget.lerInfoStream;
    if (ler == null || _aLerInfo || _m.vista == VistaPlayer.escondida) return;
    _aLerInfo = true;
    try {
      final texto = textoInfoStream(await ler());
      if (mounted && texto != _infoStream) setState(() => _infoStream = texto);
    } catch (_) {
      // o player pode estar a fechar: fica o último valor
    } finally {
      _aLerInfo = false;
    }
  }

  void _depoisDoFrame(VoidCallback f) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) f();
      });

  /// Mostra a barra (OK, toque, rato) com o foco no play/pausa.
  void _mostrar() {
    if (_m.vista != VistaPlayer.escondida) {
      _agendar();
      return;
    }
    _m.mostrar();
    _depoisMudarVista();
    _depoisDoFrame(_play.requestFocus);
  }

  void _depoisMudarVista() {
    setState(() {});
    _atualizarRelogio();
    _agendar();
  }

  void _abrirPainel() {
    _m.abrirPainel();
    _depoisMudarVista();
    // (o autofocus não vale aqui: o foco já estava num botão da barra)
    _depoisDoFrame(() {
      final primeiro = _painel.traversalDescendants.where((n) => n.canRequestFocus).firstOrNull;
      primeiro?.requestFocus();
    });
  }

  void _executar(AcaoPlayer a) {
    switch (a) {
      case AcaoPlayer.passar:
        break;
      case AcaoPlayer.mostrarControlos:
        _m.vista = VistaPlayer.escondida;
        _mostrar();
      case AcaoPlayer.esconderControlos:
        _raiz.requestFocus(); // antes de a barra deixar de ser focável
        _depoisMudarVista();
      case AcaoPlayer.fecharPainel:
        _depoisMudarVista();
        _depoisDoFrame(_botaoDefinicoes.requestFocus);
      default:
        widget.aoAgir(a);
    }
  }

  /// Um botão da barra: faz a ação e adia o esconder.
  void _botao(AcaoPlayer a) {
    _agendar();
    widget.aoAgir(a);
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    // o Voltar do comando no Android chega como tecla E como "voltar" do sistema (mesmo com a
    // tecla tratada): fica só o do sistema (PopScope), senão cada Voltar contava duas vezes
    if (e.logicalKey == LogicalKeyboardKey.goBack) return KeyEventResult.ignored;
    _agendar();
    if (e is KeyRepeatEvent) {
      // tecla presa: com a barra/painel é a navegação; escondida não muda de canal em rajada
      return _m.vista == VistaPlayer.escondida ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    final a = _m.tecla(e.logicalKey, erro: widget.estado.erro);
    if (a == AcaoPlayer.passar) return KeyEventResult.ignored;
    _executar(a);
    return KeyEventResult.handled;
  }

  void _tocou() {
    switch (_m.vista) {
      case VistaPlayer.escondida:
        _mostrar();
      case VistaPlayer.controlos || VistaPlayer.painel:
        _executar(_m.voltar());
    }
  }

  void _velocidadeSeguinte() {
    final i = velocidades.indexOf(widget.estado.velocidade);
    _agendar();
    widget.aoMudarVelocidade(velocidades[(i + 1) % velocidades.length]);
  }

  @override
  Widget build(BuildContext context) {
    final vista = _m.vista;
    final verBarra = vista != VistaPlayer.escondida;
    final duracao = duracaoAnimada(context, Tokens.duracaoMedia);
    return PopScope(
      // o Voltar do sistema quando não chega como tecla (gesto/predictive back)
      canPop: vista == VistaPlayer.escondida,
      onPopInvokedWithResult: (saiu, _) {
        if (!saiu) _executar(_m.voltar());
      },
      child: Focus(
        focusNode: _raiz,
        autofocus: true,
        onKeyEvent: _tecla,
        child: MouseRegion(
          onHover: (_) => _mostrar(),
          child: Stack(fit: StackFit.expand, children: [
            // à volta do vídeo (e não por cima): os botões do cartão de erro continuam a receber
            // os toques (o toque mais de dentro ganha)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _tocou,
              onDoubleTap: widget.comEcraInteiro ? () => widget.aoAgir(AcaoPlayer.ecraInteiro) : null,
              onLongPress: () => widget.aoAgir(AcaoPlayer.estatisticas),
              onVerticalDragEnd: (d) {
                if (_m.vista != VistaPlayer.escondida) return;
                widget.aoAgir((d.primaryVelocity ?? 0) < 0 ? AcaoPlayer.canalSeguinte : AcaoPlayer.canalAnterior);
              },
              child: widget.child,
            ),
            // o nome do canal ao fazer zapping (sem foco: as setas continuam a mudar de canal)
            IgnorePointer(
              child: AnimatedOpacity(
                key: const ValueKey('infoCanal'),
                opacity: _infoCanal && !verBarra ? 1 : 0,
                duration: duracao,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(Tokens.e24),
                    child: SuperficieVidro(
                      cor: const Color(0xCC0B0F17),
                      raio: Tokens.raioBotao,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: _Titulo(estado: widget.estado),
                    ),
                  ),
                ),
              ),
            ),
            ExcludeFocus(
              excluding: vista != VistaPlayer.controlos,
              child: IgnorePointer(
                ignoring: !verBarra,
                child: AnimatedOpacity(
                  key: const ValueKey('barra'),
                  opacity: verBarra ? 1 : 0,
                  duration: duracao,
                  curve: Tokens.curva,
                  child: _camadaBarra(context),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: duracao,
              child: vista == VistaPlayer.painel
                  ? Focus(
                      key: const ValueKey('painel'),
                      focusNode: _painel,
                      canRequestFocus: false,
                      child: PainelDefinicoes(itens: widget.definicoes()),
                    )
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _camadaBarra(BuildContext context) {
    final tv = ecraTv(context);
    final e = widget.estado;
    final atraso = widget.atraso();
    final emDireto = atraso < RelogioDireto.limiar;
    final icone = tv ? 32.0 : 26.0;
    Widget botao(IconData i, String dica, AcaoPlayer a) =>
        IconButton(icon: Icon(i, size: icone), tooltip: dica, color: Tokens.texto, onPressed: () => _botao(a));
    return Stack(children: [
      // em cima: Voltar (fechar a janela/sair) e ecrã inteiro (Windows)
      Positioned(
        top: Tokens.e16,
        left: Tokens.e16,
        right: Tokens.e16,
        child: Row(children: [
          _Vidro(child: botao(Icons.arrow_back, 'Voltar', AcaoPlayer.sair)),
          const Spacer(),
          if (widget.comEcraInteiro)
            _Vidro(child: botao(Icons.fullscreen, 'Ecrã inteiro (F11)', AcaoPlayer.ecraInteiro)),
        ]),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          // escurece só o fundo do ecrã (o texto lê-se sobre imagens claras) — sem desfoque
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xB3000000), Color(0x00000000)],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(Tokens.e24, Tokens.e32 * 2, Tokens.e24, tv ? Tokens.e32 : Tokens.e16),
            child: SuperficieVidro(
              cor: const Color(0xCC0B0F17),
              elevacao: 2,
              padding: const EdgeInsets.fromLTRB(Tokens.e24, Tokens.e16, Tokens.e24, Tokens.e12),
              child: FocusTraversalGroup(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _Titulo(estado: e),
                        if (widget.lerInfoStream != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(_infoStream ?? '— · — · —',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: tv ? 16 : 13,
                                    color: Tokens.texto2,
                                    fontFeatures: const [FontFeature.tabularFigures()])),
                          ),
                      ]),
                    ),
                    const SizedBox(width: Tokens.e16),
                    _IndicadorDireto(emDireto: emDireto, atraso: atraso),
                  ]),
                  const SizedBox(height: Tokens.e12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: Tokens.e8,
                    runSpacing: Tokens.e8,
                    children: [
                      botao(Icons.skip_previous_rounded, 'Canal anterior', AcaoPlayer.canalAnterior),
                      botao(Icons.replay_10_rounded, 'Recuar 10 s', AcaoPlayer.recuar),
                      Tooltip(
                        message: e.aTocar ? 'Pausa' : 'Reproduzir',
                        child: FilledButton(
                          focusNode: _play,
                          onPressed: () => _botao(AcaoPlayer.playPausa),
                          child: Icon(e.aTocar ? Icons.pause_rounded : Icons.play_arrow_rounded, size: icone),
                        ),
                      ),
                      botao(Icons.forward_10_rounded, 'Avançar 10 s', AcaoPlayer.avancar),
                      botao(Icons.skip_next_rounded, 'Canal seguinte', AcaoPlayer.canalSeguinte),
                      const SizedBox(width: Tokens.e16),
                      Tooltip(
                        message: 'Velocidade',
                        child: TextButton(
                          onPressed: _velocidadeSeguinte,
                          child: Text(textoVelocidade(e.velocidade),
                              style: TextStyle(fontSize: tv ? 18 : 15, color: Tokens.texto)),
                        ),
                      ),
                      if (!emDireto)
                        Tooltip(
                          message: 'Voltar ao direto',
                          child: TextButton.icon(
                            onPressed: () => _botao(AcaoPlayer.voltarAoDireto),
                            icon: const Icon(Icons.skip_next_rounded, color: Tokens.mau),
                            label: Text('Voltar ao direto',
                                style: TextStyle(fontSize: tv ? 18 : 15, color: Tokens.texto)),
                          ),
                        ),
                      IconButton(
                        focusNode: _botaoDefinicoes,
                        icon: Icon(Icons.settings_rounded, size: icone),
                        tooltip: 'Definições',
                        color: Tokens.texto,
                        onPressed: _abrirPainel,
                      ),
                    ],
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo({required this.estado});
  final EstadoControlos estado;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(estado.canal,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: tv ? 26 : 20, fontWeight: FontWeight.w700, color: Tokens.texto)),
      Text(estado.subtitulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: tv ? 16 : 13, color: Tokens.texto2)),
    ]);
  }
}

/// "● Em direto" ou o atraso ("−0:20").
class _IndicadorDireto extends StatelessWidget {
  const _IndicadorDireto({required this.emDireto, required this.atraso});
  final bool emDireto;
  final Duration atraso;

  @override
  Widget build(BuildContext context) {
    final cor = emDireto ? Tokens.mau : Tokens.neutro;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cor.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(Tokens.raioPilula),
        border: Border.all(color: cor.withValues(alpha: .5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(emDireto ? Icons.circle : Icons.history_rounded, size: emDireto ? 10 : 16, color: cor),
          const SizedBox(width: 6),
          Text(emDireto ? 'Em direto' : textoAtraso(atraso),
              style: const TextStyle(
                  color: Tokens.texto, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

/// Um botão redondo num círculo de vidro escuro (lê-se por cima de qualquer imagem).
class _Vidro extends StatelessWidget {
  const _Vidro({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xB30B0F17),
          shape: BoxShape.circle,
          border: Border.all(color: Tokens.bordaVidro),
        ),
        child: child,
      );
}

/// O que a barra lê do mpv para [textoInfoStream].
const propriedadesInfoStream = ['width', 'height', 'container-fps', 'estimated-vf-fps', 'video-bitrate'];

String _decimal(double v, int casas) {
  var t = v.toStringAsFixed(casas);
  if (t.contains('.')) t = t.replaceFirst(RegExp(r'\.?0+$'), '');
  return t.replaceAll('.', ',');
}

/// "1280×720 · 50 fps · 3,1 Mb/s" (vírgula decimal; "—" no que não se sabe).
String textoInfoStream(Map<String, String> m) {
  double? n(String k) {
    final v = double.tryParse(m[k]?.trim() ?? '');
    return v != null && v > 0 ? v : null;
  }

  final w = n('width'), h = n('height');
  final fps = n('container-fps') ?? n('estimated-vf-fps');
  final br = n('video-bitrate');
  return [
    w != null && h != null ? '${w.round()}×${h.round()}' : '—',
    fps != null ? '${_decimal(fps, 2)} fps' : '—',
    br != null ? '${_decimal(br / 1e6, 1)} Mb/s' : '—',
  ].join(' · ');
}
