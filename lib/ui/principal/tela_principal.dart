import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../design/mensagens.dart';
import 'barra_seccoes.dart';

/// As três secções fixas da app.
enum Seccao { verTv, gestor, definicoes }

/// A secção à vista e como mudar de secção (para os ecrãs dentro de [TelaPrincipal]).
class SeccaoAtual extends InheritedWidget {
  const SeccaoAtual({super.key, required this.seccao, required this.irPara, required super.child});

  final Seccao seccao;
  final ValueChanged<Seccao> irPara;

  /// A casca à volta de `context` (null fora dela, por exemplo num teste só de um ecrã).
  static SeccaoAtual? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SeccaoAtual>();

  @override
  bool updateShouldNotify(SeccaoAtual old) => seccao != old.seccao;
}

/// A casca da app: Ver TV, Gestor e Definições. Nos ecrãs largos (900 px ou mais, e na TV) as secções ficam
/// numa barra lateral ([BarraSeccoes]); no telemóvel, numa NavigationBar em baixo. As três
/// vivem num IndexedStack: cada uma guarda o estado (pesquisa, posição, campos) ao trocar.
///
/// Comando: ESQUERDA no controlo mais à esquerda do conteúdo (ou CIMA no de cima) vai à
/// secção ativa na barra; na barra CIMA/BAIXO andam entre as secções, OK mostra a secção e
/// DIREITA volta ao controlo onde se estava nela. Voltar fora de Ver TV vai para Ver TV; em
/// Ver TV (Android) pede "Carregue outra vez em Voltar para sair".
class TelaPrincipal extends StatefulWidget {
  const TelaPrincipal({super.key, required this.verTv, required this.gestor, required this.definicoes,
      this.inicial = Seccao.verTv, this.sair = SystemNavigator.pop});

  final Widget verTv;
  final Widget gestor;
  final Widget definicoes;

  /// A secção à vista ao abrir.
  final Seccao inicial;

  /// Fecha a app (o segundo Voltar em Ver TV).
  final VoidCallback sair;

  /// Mostra a secção `s` e põe o foco nela (onde estava, ou no primeiro controlo).
  static void irPara(BuildContext context, Seccao s) =>
      context.getInheritedWidgetOfExactType<SeccaoAtual>()?.irPara(s);

  /// O que faz Voltar quando a secção de `context` está à vista, antes da casca (por exemplo, num
  /// sub-ecrã do Gestor, voltar ao ecrã principal do Gestor em vez de ir para Ver TV). `tratar`
  /// devolve true se tratou. Devolve a função que tira o registo (fora da casca não faz nada).
  static VoidCallback aoVoltar(BuildContext context, bool Function() tratar) {
    final s = context.getInheritedWidgetOfExactType<_SeccaoDoEcra>()?.seccao;
    final casca = context.findAncestorStateOfType<_TelaPrincipalState>();
    if (s == null || casca == null) return () {};
    casca._voltarNaSeccao[s] = tratar;
    return () {
      if (casca._voltarNaSeccao[s] == tratar) casca._voltarNaSeccao.remove(s);
    };
  }

  @override
  State<TelaPrincipal> createState() => _TelaPrincipalState();
}

class _TelaPrincipalState extends State<TelaPrincipal> {
  late Seccao _atual = widget.inicial;

  /// O conteúdo de cada secção (não recebe o foco: serve para saber onde ele está).
  final _focosSeccao = [
    for (final s in Seccao.values)
      FocusNode(debugLabel: 'Secção ${s.name}', canRequestFocus: false, skipTraversal: true),
  ];

  /// O foco de cada secção na barra lateral.
  final _focosBarra = [for (final s in Seccao.values) FocusNode(debugLabel: 'Barra ${s.name}')];

  /// O Voltar que cada secção trata ela própria (ver [TelaPrincipal.aoVoltar]).
  final _voltarNaSeccao = <Seccao, bool Function()>{};

  /// O último controlo com o foco em cada secção (DIREITA na barra e Voltar regressam a ele).
  final _ultimo = <Seccao, FocusNode>{};

  /// Depois do primeiro Voltar, durante [_tempoSair], o segundo fecha a app.
  static const _tempoSair = Duration(seconds: 2);
  Timer? _podeSair;

  /// As mensagens no canto superior direito (ver [mostrarMensagem]).
  final _mensagens = ControladorMensagens();

  /// Android/TV: Voltar em Ver TV não fecha logo a app. No Windows a janela fecha-se pelo
  /// botão de fechar, como sempre.
  bool get _confirmarSaida => defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focoMudou);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focoMudou);
    _podeSair?.cancel();
    _mensagens.dispose();
    for (final f in [..._focosSeccao, ..._focosBarra]) {
      f.dispose();
    }
    super.dispose();
  }

  void _focoMudou() {
    final f = FocusManager.instance.primaryFocus;
    if (f == null) return;
    for (final s in Seccao.values) {
      if (f.ancestors.contains(_focosSeccao[s.index])) _ultimo[s] = f;
    }
  }

  bool _vivo(FocusNode n, Seccao s) =>
      n.context?.mounted == true && n.canRequestFocus && n.ancestors.contains(_focosSeccao[s.index]);

  /// O controlo mais acima (e mais à esquerda) à vista na secção.
  FocusNode? _primeiroDe(Seccao s) {
    final seccao = _focosSeccao[s.index];
    final caixa = seccao.context?.findRenderObject();
    if (caixa is! RenderBox || !caixa.hasSize) return null;
    final area = caixa.localToGlobal(Offset.zero) & caixa.size;
    FocusNode? melhor;
    for (final n in seccao.traversalDescendants) {
      if (!n.canRequestFocus || n.skipTraversal || n.context == null || n is FocusScopeNode) continue;
      final r = n.rect;
      // só os que estão à vista (o que já saiu de cima não conta)
      if (!area.contains(r.center)) continue;
      final m = melhor?.rect;
      if (m == null || r.top < m.top - 4 || ((r.top - m.top).abs() <= 4 && r.left < m.left)) melhor = n;
    }
    return melhor;
  }

  /// O foco no conteúdo da secção à vista: onde estava, ou no primeiro controlo.
  bool _focarConteudo() {
    final antes = _ultimo[_atual];
    final alvo = antes != null && _vivo(antes, _atual) ? antes : _primeiroDe(_atual);
    if (alvo == null) return false;
    alvo.requestFocus();
    return true;
  }

  /// Muda de secção. Com `focar`, o foco vai para a nova secção: para a barra, se estava na
  /// barra; senão para o conteúdo dela.
  void _mudar(Seccao s, {required bool focar}) {
    final naBarra = _focosBarra.any((f) => f.hasPrimaryFocus);
    if (s != _atual) setState(() => _atual = s);
    if (!focar) return;
    // depois do frame: a secção nova já pode receber o foco (a antiga deixa de poder)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _atual != s) return;
      if (naBarra && _largo(context)) {
        _focosBarra[s.index].requestFocus();
      } else {
        _focarConteudo();
      }
    });
  }

  /// A partir desta largura (lógica) as secções ficam na barra lateral; abaixo, numa
  /// NavigationBar em baixo. A Android TV (960) fica com a barra lateral.
  static const larguraBarraLateral = 900.0;

  bool _largo(BuildContext context) => MediaQuery.sizeOf(context).width >= larguraBarraLateral;

  /// ESQUERDA (ou CIMA) no conteúdo sem nada nessa direção na secção: a secção na barra.
  KeyEventResult _teclaConteudo(BuildContext context, KeyEvent e) {
    if (e is KeyUpEvent || !_largo(context)) return KeyEventResult.ignored;
    final esquerda = e.logicalKey == LogicalKeyboardKey.arrowLeft;
    if (!esquerda && e.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    final atual = FocusManager.instance.primaryFocus;
    final seccao = _focosSeccao[_atual.index];
    if (atual == null || !atual.ancestors.contains(seccao)) return KeyEventResult.ignored;
    final r = atual.rect;
    // como a procura direcional: ESQUERDA na mesma faixa (um controlo noutra linha mais à
    // esquerda não conta); CIMA em qualquer coluna
    final haMais = seccao.traversalDescendants.any((n) {
      if (n == atual || !n.canRequestFocus || n.skipTraversal || n.context == null) return false;
      final o = n.rect;
      return esquerda ? o.center.dx <= r.left && o.top < r.bottom && o.bottom > r.top : o.center.dy <= r.top;
    });
    if (haMais) return KeyEventResult.ignored;
    _focosBarra[_atual.index].requestFocus();
    return KeyEventResult.handled;
  }

  /// Na barra: CIMA/BAIXO só entre as secções, ESQUERDA fica, DIREITA vai ao conteúdo.
  KeyEventResult _teclaBarra(KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final i = _focosBarra.indexWhere((f) => f.hasPrimaryFocus);
    if (i < 0) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        if (i > 0) _focosBarra[i - 1].requestFocus();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        if (i < _focosBarra.length - 1) _focosBarra[i + 1].requestFocus();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _focarConteudo();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _voltar(BuildContext context) {
    if (_voltarNaSeccao[_atual]?.call() ?? false) return;
    if (_atual != Seccao.verTv) {
      _mudar(Seccao.verTv, focar: true);
      return;
    }
    if (_podeSair?.isActive ?? false) {
      _podeSair!.cancel();
      widget.sair();
      return;
    }
    _podeSair = Timer(_tempoSair, () {});
    _mensagens.mostrar('Carregue outra vez em Voltar para sair', duracao: _tempoSair);
  }

  @override
  Widget build(BuildContext context) {
    final largo = _largo(context);
    final seccoes = [widget.verTv, widget.gestor, widget.definicoes];
    final conteudo = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: (_, e) => _teclaConteudo(context, e),
      child: IndexedStack(
        index: _atual.index,
        sizing: StackFit.expand,
        children: [
          for (final s in Seccao.values)
            Focus(
                focusNode: _focosSeccao[s.index],
                includeSemantics: false,
                child: _SeccaoDoEcra(seccao: s, child: seccoes[s.index])),
        ],
      ),
    );
    return SeccaoAtual(
      seccao: _atual,
      irPara: (s) => _mudar(s, focar: true),
      child: MensagensHost(
        controlador: _mensagens,
        child: Stack(children: [
          Positioned.fill(child: _casca(context, largo, conteudo)),
          SobreposicaoMensagens(controlador: _mensagens),
        ]),
      ),
    );
  }

  Widget _casca(BuildContext context, bool largo, Widget conteudo) {
    return PopScope(
        // Voltar: fora de Ver TV vai para Ver TV; em Ver TV (Android) pede confirmação
        canPop: _atual == Seccao.verTv && !_confirmarSaida,
        onPopInvokedWithResult: (saiu, _) {
          if (!saiu) _voltar(context);
        },
        child: Scaffold(
          body: SafeArea(
            bottom: largo,
            child: largo
                ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      includeSemantics: false,
                      onKeyEvent: (_, e) => _teclaBarra(e),
                      child: BarraSeccoes(
                        atual: _atual,
                        focos: _focosBarra,
                        aoEscolher: (s) => _mudar(s, focar: false),
                      ),
                    ),
                    Expanded(child: conteudo),
                  ])
                : conteudo,
          ),
          bottomNavigationBar: largo
              ? null
              : NavigationBar(
                  selectedIndex: _atual.index,
                  onDestinationSelected: (i) => _mudar(Seccao.values[i], focar: false),
                  destinations: [
                    for (final s in Seccao.values)
                      NavigationDestination(icon: Icon(rotulosSeccoes[s]!.$2), label: rotulosSeccoes[s]!.$1),
                  ],
                ),
        ),
    );
  }
}

/// A secção onde está um ecrã (para [TelaPrincipal.aoVoltar]).
class _SeccaoDoEcra extends InheritedWidget {
  const _SeccaoDoEcra({required this.seccao, required super.child});
  final Seccao seccao;

  @override
  bool updateShouldNotify(_SeccaoDoEcra old) => seccao != old.seccao;
}
