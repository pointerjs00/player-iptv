import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../design/componentes.dart';
import '../design/ecra.dart';
import '../design/movimento.dart';
import '../design/ponto_direto.dart';
import '../design/tokens.dart';
import 'ajuste_toque.dart';
import 'aplicar_preferencias.dart';
import 'barra_progresso.dart';
import 'controlo_volume.dart';
import 'maquina_controlos.dart';
import 'numero_canal.dart';
import 'painel_definicoes.dart';
import 'progresso.dart';
import 'relogio_direto.dart';
import '../../idioma/idioma.dart';

/// "Casa › Desporto · em direto": o subtítulo do canal no topo ([EstadoControlos.subtitulo]).
String subtituloCanal({required String lista, required String grupo}) =>
    grupo.trim().isEmpty ? tr('{0} · em direto', [lista]) : tr('{0} › {1} · em direto', [lista, grupo.trim()]);

/// O que a barra mostra do canal a tocar.
class EstadoControlos {
  const EstadoControlos({this.numero, required this.canal, required this.subtitulo, this.aTocar = true,
      this.velocidade = 1.0, this.erro = false, this.podeAlternar = false});

  /// O número do canal (em grande, antes do nome); null = sem número.
  final int? numero;
  final String canal;

  /// "lista › grupo · em direto" ([subtituloCanal]).
  final String subtitulo;
  final bool aTocar;
  final double velocidade;

  /// Está à vista o cartão de erro do canal (OK tenta de novo).
  final bool erro;

  /// Há um canal visto antes deste (o botão "Canal visto antes" aparece).
  final bool podeAlternar;
}

/// A barra de controlos e o painel de definições por cima do vídeo (`child`), e as teclas do
/// comando conforme o que está à vista ([MaquinaControlos]):
/// - escondida: cima/Canal+ = canal seguinte, baixo/Canal− = anterior, esquerda/direita recuam/avançam 10 s, OK mostra a barra;
/// - barra: as setas andam pelos botões; esconde-se após 5 s sem atividade;
/// - painel: as setas andam pelo painel; não se esconde sozinho.
/// Voltar fecha o painel, depois a barra, depois sai. Teclas multimédia sempre.
/// Os algarismos escrevem um número de canal (no ecrã; salta com OK ou após [tempoNumero]);
/// "último canal" (ou Backspace) alterna com o canal visto antes.
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
    this.comSaltos = true,
    this.lerInfoStream,
    this.lerProgresso,
    this.aoProcurar,
    this.esconderApos = const Duration(seconds: 5),
    this.aoNumero,
    this.ajusteToque,
    this.volume,
    this.passoVolume = 5,
    this.aoOutrasFontes,
  });

  /// Modo «Jogo»: abre as outras fontes do mesmo canal (null = sem o botão).
  final VoidCallback? aoOutrasFontes;

  /// O volume na barra (o do player, 0–100, e o silêncio); null = sem ele.
  final ({double valor, bool silencio, ValueChanged<double> aoMudar, ValueChanged<bool> aoSilencio})? volume;

  /// Quanto muda o volume em cada ← → da barra (%); no telemóvel, um degrau do sistema.
  final double passoVolume;

  /// Telemóvel Android: os deslizes nas laterais mudam o volume (direita) e o brilho (esquerda).
  final AjusteToque? ajusteToque;

  /// O número de canal escrito com os algarismos (null = os algarismos não fazem nada).
  final ValueChanged<int>? aoNumero;

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

  /// Lê a janela da barra de progresso ([janelaDe]): só com a barra à vista, [intervaloProgresso]
  /// (no player verdadeiro, fora da thread da UI e partilhada com as outras leituras). null = sem
  /// barra de progresso.
  final Future<JanelaProgresso?> Function()? lerProgresso;

  /// Seek da barra de progresso (arrastar, esquerda/direita com ela focada) para `alvo` (segundos
  /// do mpv, dentro da janela).
  final Future<void> Function(JanelaProgresso janela, double alvo)? aoProcurar;

  /// A barra de progresso lê o player assim (a informação do stream e o atraso a cada 2).
  static const intervaloProgresso = Duration(milliseconds: 500);

  /// Windows: botão de ecrã inteiro e duplo clique.
  final bool comEcraInteiro;

  /// Os botões "Recuar 10 s" e "Avançar 10 s" (o motor sabe saltar no que já recebeu).
  final bool comSaltos;
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
  final _botaoVoltar = FocusNode(debugLabel: 'voltar');
  final _progresso = FocusNode(debugLabel: 'progresso');
  final _painel = FocusNode(debugLabel: 'painel', skipTraversal: true);
  Timer? _esconder;
  Timer? _relogio;
  Timer? _fimInfo;
  Timer? _fimNumero;
  bool _infoCanal = false;
  String? _infoStream;
  bool _aLerInfo = false;
  JanelaProgresso? _janela;
  Future<void>? _leituraProgresso;
  int _tique = 0;

  /// Muda a cada canal: uma leitura de um canal anterior que chegue depois é deitada fora.
  int _geracao = 0;

  static String _chaveCanal(EstadoControlos e) => '${e.numero}\u0000${e.canal}\u0000${e.subtitulo}';

  VistaPlayer get vista => _m.vista;

  @override
  void didUpdateWidget(ControlosPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // outro canal: a janela do anterior não vale (traços até à leitura seguinte), nem as leituras
    // dela que ainda estão a caminho
    if (_chaveCanal(oldWidget.estado) != _chaveCanal(widget.estado)) {
      _janela = null;
      _geracao++;
    }
    // o cartão de erro saiu com o foco num botão dele: o foco volta ao player (senão nenhuma
    // tecla chegava aqui)
    if (oldWidget.estado.erro && !widget.estado.erro) {
      _depoisDoFrame(() {
        final foco = FocusManager.instance.primaryFocus;
        if (_m.vista == VistaPlayer.escondida && (foco == null || foco is FocusScopeNode)) {
          _raiz.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _esconder?.cancel();
    _relogio?.cancel();
    _fimInfo?.cancel();
    _fimNumero?.cancel();
    _raiz.dispose();
    _play.dispose();
    _botaoDefinicoes.dispose();
    _botaoVoltar.dispose();
    _progresso.dispose();
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
      if (!mounted || _m.vista != VistaPlayer.controlos) return;
      // um diálogo por cima («Outras fontes»): esconder pedia o foco para o player, tirava-o ao
      // diálogo e as setas passavam a mudar de canal por baixo dele; volta a contar
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
        _agendar();
        return;
      }
      _executar(_m.voltar());
    });
  }

  void _atualizarRelogio() {
    final ver = _m.vista != VistaPlayer.escondida;
    if (ver && _relogio == null) {
      _lerInfo();
      _lerProgresso();
      // uma só cadência para tudo o que a barra lê: a janela do progresso a cada tique, o atraso
      // e a informação do stream a cada segundo
      _tique = 0;
      _relogio = Timer.periodic(ControlosPlayer.intervaloProgresso, (_) {
        if (!mounted) return;
        _lerProgresso();
        if ((++_tique).isEven) {
          setState(() {});
          _lerInfo();
        }
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

  /// Lê a janela do progresso (uma leitura de cada vez; `nova`: depois de um seek, espera pela
  /// que está a caminho e lê outra — a que estava a caminho pode ser de antes do seek).
  Future<void> _lerProgresso({bool nova = false}) async {
    final ler = widget.lerProgresso;
    if (ler == null || _m.vista == VistaPlayer.escondida) return;
    final emCurso = _leituraProgresso;
    if (emCurso != null) {
      if (!nova) return;
      await emCurso;
      return _lerProgresso();
    }
    final geracao = _geracao;
    final leitura = () async {
      try {
        final j = await ler();
        if (mounted && geracao == _geracao) setState(() => _janela = j);
      } catch (_) {
        // o player pode estar a fechar: fica a última janela
      }
    }();
    _leituraProgresso = leitura;
    try {
      await leitura;
    } finally {
      _leituraProgresso = null;
    }
  }

  Future<void> _procurar(JanelaProgresso j, double alvo) async {
    _agendar();
    await widget.aoProcurar?.call(j, alvo);
    if (mounted) await _lerProgresso(nova: true);
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
        // com o cartão de erro à vista, o foco volta a um botão dele (na raiz, esquerda/direita
        // não chegavam ao "Voltar" e o OK era sempre "tentar de novo")
        if (widget.estado.erro) _depoisDoFrame(_focarCartaoErro);
      case AcaoPlayer.fecharPainel:
        _depoisMudarVista();
        _depoisDoFrame(_botaoDefinicoes.requestFocus);
      case AcaoPlayer.algarismo:
        _fimNumero?.cancel();
        _fimNumero = Timer(tempoNumero, () {
          if (mounted && _m.numero.isNotEmpty) _executar(AcaoPlayer.irParaNumero);
        });
        setState(() {});
      case AcaoPlayer.irParaNumero:
        _fimNumero?.cancel();
        final n = _m.tirarNumero();
        setState(() {});
        if (n != null) widget.aoNumero?.call(n);
      case AcaoPlayer.cancelarNumero:
        _fimNumero?.cancel();
        setState(() {});
      default:
        widget.aoAgir(a);
    }
  }

  /// O primeiro botão do cartão de erro (com a barra escondida, os únicos focáveis por baixo da
  /// raiz são os do vídeo: a barra fica fora da navegação e o painel não está à vista).
  void _focarCartaoErro() {
    if (_m.vista != VistaPlayer.escondida || !widget.estado.erro) return;
    _raiz.traversalDescendants.where((n) => n.canRequestFocus).firstOrNull?.requestFocus();
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
    if (widget.aoNumero == null && algarismoDe(e.logicalKey) != null) return KeyEventResult.ignored;
    // o foco saiu da raiz com o vídeo sozinho: está num botão do cartão de erro
    final focoNoErro = widget.estado.erro && _m.vista == VistaPlayer.escondida && !_raiz.hasPrimaryFocus;
    final a = _m.tecla(e.logicalKey, erro: widget.estado.erro, focoNoErro: focoNoErro);
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
      canPop: vista == VistaPlayer.escondida && _m.numero.isEmpty,
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
              onVerticalDragStart: widget.ajusteToque == null
                  ? null
                  : (d) {
                      final largura = context.size?.width ?? 0;
                      if (largura > 0) widget.ajusteToque!.comecar(d.localPosition.dx / largura);
                    },
              onVerticalDragUpdate: widget.ajusteToque == null
                  ? null
                  : (d) {
                      final altura = context.size?.height ?? 0;
                      if (altura > 0) widget.ajusteToque!.mover(-d.delta.dy / altura);
                    },
              onVerticalDragEnd: (d) {
                if (widget.ajusteToque?.terminar() ?? false) return;
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
                      child: _Titulo(estado: widget.estado, linhas: ecraTelemovel(context) ? 2 : 1),
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
            if (widget.ajusteToque != null) IndicadoresAjuste(ajuste: widget.ajusteToque!),
            if (_m.numero.isNotEmpty) IgnorePointer(child: MostradorNumero(numero: _m.numero)),
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
    // telemóvel ao alto: a pílula vai para baixo do nome, ⚙ / velocidade / canal visto antes sobem
    // para a linha do ← e em baixo ficam só ⏮ ⏪ ⏯ ⏩ ⏭ (numa linha)
    final alto = ecraTelemovel(context);
    final e = widget.estado;
    final atraso = widget.atraso();
    final emDireto = atraso < RelogioDireto.limiar;
    final icone = tv ? 32.0 : 26.0;
    final margem = alto ? Tokens.e16 : Tokens.e24;
    // ao toque, alvos de 48 (o tema é compacto)
    final estiloIcone = alto ? IconButton.styleFrom(minimumSize: const Size.square(48)) : null;
    Widget botao(IconData i, String dica, AcaoPlayer a, {FocusNode? foco}) => IconButton(
        focusNode: foco,
        icon: Icon(i, size: icone),
        tooltip: dica,
        color: Tokens.texto,
        style: estiloIcone,
        onPressed: () => _botao(a));
    final alternar =
        e.podeAlternar ? botao(Icons.swap_horiz_rounded, tr('Canal visto antes'), AcaoPlayer.alternarCanal) : null;
    final velocidade = Tooltip(
      message: tr('Velocidade'),
      child: TextButton(
        onPressed: _velocidadeSeguinte,
        // ao alto, na linha do ←: um alvo de toque de 48 como os outros
        style: alto ? TextButton.styleFrom(minimumSize: const Size(56, 48)) : null,
        child: Text(textoVelocidade(e.velocidade), style: TextStyle(fontSize: tv ? 18 : 15, color: Tokens.texto)),
      ),
    );
    final definicoes = IconButton(
      focusNode: _botaoDefinicoes,
      icon: Icon(Icons.settings_rounded, size: icone),
      tooltip: tr('Definições'),
      color: Tokens.texto,
      style: estiloIcone,
      onPressed: _abrirPainel,
    );
    final outras = widget.aoOutrasFontes == null
        ? null
        : IconButton(
            icon: Icon(Icons.alt_route_rounded, size: icone),
            tooltip: tr('Outras fontes'),
            color: Tokens.texto,
            style: estiloIcone,
            onPressed: widget.aoOutrasFontes,
          );
    final voltarAoDireto = emDireto
        ? null
        : Tooltip(
            message: tr('Voltar ao direto'),
            child: TextButton.icon(
              onPressed: () => _botao(AcaoPlayer.voltarAoDireto),
              icon: const Icon(Icons.skip_next_rounded, color: Tokens.mau),
              label: Text(tr('Voltar ao direto'), style: TextStyle(fontSize: tv ? 18 : 15, color: Tokens.texto)),
            ),
          );
    final transporte = [
      botao(Icons.skip_previous_rounded, tr('Canal anterior'), AcaoPlayer.canalAnterior),
      if (widget.comSaltos) botao(Icons.replay_10_rounded, tr('Recuar 10 s'), AcaoPlayer.recuar),
      Tooltip(
        message: e.aTocar ? tr('Pausa') : tr('Reproduzir'),
        child: FilledButton(
          focusNode: _play,
          onPressed: () => _botao(AcaoPlayer.playPausa),
          child: Icon(e.aTocar ? Icons.pause_rounded : Icons.play_arrow_rounded, size: icone),
        ),
      ),
      if (widget.comSaltos) botao(Icons.forward_10_rounded, tr('Avançar 10 s'), AcaoPlayer.avancar),
      botao(Icons.skip_next_rounded, tr('Canal seguinte'), AcaoPlayer.canalSeguinte),
    ];
    final indicador = _IndicadorDireto(emDireto: emDireto, atraso: atraso);
    final v = widget.volume;
    final volume = v == null
        ? null
        : ControloVolume(
            key: const ValueKey('controloVolume'),
            volume: v.valor,
            silencio: v.silencio,
            aoMudar: v.aoMudar,
            aoSilencio: v.aoSilencio,
            passo: widget.passoVolume,
            aoAtividade: _agendar,
            largura: tv ? 140 : (alto ? 160 : 110),
            tamanhoIcone: icone,
            estiloIcone: estiloIcone,
          );
    return Stack(children: [
      // em cima: Voltar (fechar a janela/sair) e ecrã inteiro (Windows)
      Positioned(
        top: Tokens.e16,
        left: Tokens.e16,
        right: Tokens.e16,
        // BAIXO nos botões de cima volta sempre ao play/pausa (a procura direcional escolhia o
        // botão da barra mais perto na horizontal, ou um botão do vídeo pelo meio)
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          onKeyEvent: (_, e) {
            if (e is KeyUpEvent || e.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
            _play.requestFocus();
            return KeyEventResult.handled;
          },
          child: Row(children: [
            _Vidro(child: botao(Icons.arrow_back, tr('Voltar'), AcaoPlayer.sair, foco: _botaoVoltar)),
            const Spacer(),
            if (alto) ...[
              if (alternar != null) ...[_Vidro(child: alternar), const SizedBox(width: Tokens.e8)],
              _Vidro(circulo: false, child: velocidade),
              const SizedBox(width: Tokens.e8),
              if (outras != null) ...[_Vidro(child: outras), const SizedBox(width: Tokens.e8)],
              _Vidro(child: definicoes),
            ],
            if (widget.comEcraInteiro)
              _Vidro(child: botao(Icons.fullscreen, tr('Ecrã inteiro (F11)'), AcaoPlayer.ecraInteiro)),
          ]),
        ),
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
            padding: EdgeInsets.fromLTRB(margem, Tokens.e32 * 2, margem, tv ? Tokens.e32 : Tokens.e16),
            child: SuperficieVidro(
              cor: const Color(0xCC0B0F17),
              elevacao: 2,
              padding: EdgeInsets.fromLTRB(margem, Tokens.e16, margem, Tokens.e12),
              child: FocusTraversalGroup(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _Titulo(estado: e, linhas: alto ? 2 : 1),
                        if (alto) Padding(padding: const EdgeInsets.only(top: Tokens.e8), child: indicador),
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
                    if (!alto) ...[const SizedBox(width: Tokens.e16), indicador],
                  ]),
                  // sempre lá (mesmo sem nada lido): a barra não muda de altura
                  if (widget.lerProgresso != null) ...[
                    const SizedBox(height: Tokens.e8),
                    BarraProgresso(
                      // outro canal: estado novo (um alvo do canal anterior não fica nem é reenviado)
                      key: ValueKey(_chaveCanal(e)),
                      janela: _janela,
                      focusNode: _progresso,
                      aoProcurar: _procurar,
                      // CIMA vai ao "Voltar" de cima e BAIXO ao play/pausa (a procura direcional
                      // podia escolher outro botão, ou nenhum)
                      aoCima: _botaoVoltar.requestFocus,
                      aoBaixo: _play.requestFocus,
                      aoPlayPausa: () => _botao(AcaoPlayer.playPausa),
                      aoAtividade: _agendar,
                      semJanela: (s) => _botao(s < 0 ? AcaoPlayer.recuar : AcaoPlayer.avancar),
                    ),
                  ],
                  const SizedBox(height: Tokens.e12),
                  if (alto) ...[
                    // ⏮ ⏪ ⏯ ⏩ ⏭ numa linha (encolhe só se não couber de todo)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        for (var i = 0; i < transporte.length; i++) ...[
                          if (i > 0) const SizedBox(width: Tokens.e4),
                          transporte[i],
                        ],
                      ]),
                    ),
                    ?voltarAoDireto,
                    if (volume != null) ...[const SizedBox(height: Tokens.e4), volume],
                  ] else
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: Tokens.e8,
                      runSpacing: Tokens.e8,
                      children: [
                        ...transporte,
                        ?alternar,
                        const SizedBox(width: Tokens.e16),
                        ?volume,
                        velocidade,
                        ?voltarAoDireto,
                        ?outras,
                        definicoes,
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
  const _Titulo({required this.estado, this.linhas = 1});
  final EstadoControlos estado;

  /// Até quantas linhas vai o nome do canal (2 no telemóvel ao alto).
  final int linhas;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final numero = estado.numero;
    final nomeESubtitulo = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(estado.canal,
          maxLines: linhas,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: tv ? 26 : 20, fontWeight: FontWeight.w700, color: Tokens.texto)),
      Text(estado.subtitulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: tv ? 16 : 13, color: Tokens.texto2)),
    ]);
    if (numero == null) return nomeESubtitulo;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // o número do canal em azul elétrico, com brilho (o redesenho)
      Text('$numero',
          style: TextStyle(
              fontFamily: Tokens.letraTitulos,
              fontSize: tv ? 44 : 34,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.5,
              color: Tokens.acento,
              shadows: [Shadow(color: Tokens.acento.withValues(alpha: .6), blurRadius: 24)],
              fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(width: Tokens.e16),
      Flexible(child: nomeESubtitulo),
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
          if (emDireto) const PontoDireto(tamanho: 9) else Icon(Icons.history_rounded, size: 16, color: cor),
          const SizedBox(width: 6),
          Text(emDireto ? tr('Em direto') : textoAtraso(atraso),
              style: const TextStyle(
                  color: Tokens.texto, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

/// Um botão redondo num círculo de vidro escuro (lê-se por cima de qualquer imagem).
class _Vidro extends StatelessWidget {
  const _Vidro({required this.child, this.circulo = true});
  final Widget child;

  /// false: uma pílula (para um botão com texto, como a velocidade).
  final bool circulo;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xB30B0F17),
          shape: circulo ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circulo ? null : BorderRadius.circular(Tokens.raioPilula),
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
