import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/nova_versao.dart';
import '../../tarefas/servico_tarefas.dart';
import '../../verificar/servico.dart';
import '../atualizar/fluxo_atualizar.dart';
import '../design/mensagens.dart';
import '../gestor/painel_atividade.dart';
import '../novidades.dart';
import '../gestor/tela_gestor.dart';
import 'barra_seccoes.dart';
import '../../idioma/idioma.dart';

/// As secções da app (Jogos só quando a casca o recebe: não existe na edição de partilha).
enum Seccao { verTv, jogos, gestor, definicoes }

/// Um foco que alcança-se com as setas mas que não conta como "primeiro controlo" de uma secção
/// (o foco ao entrar nela vai para o conteúdo, não para o indicador de atividade no canto).
class FocoForaDaEntrada extends FocusNode {
  FocoForaDaEntrada({super.debugLabel, super.canRequestFocus, super.skipTraversal});
}

/// Um bloco (o cabeçalho de um ecrã, os filtros) cujos controlos alcançam-se com as setas mas
/// não contam como "primeiro controlo" da secção: entrar nela vai para o conteúdo (o 1.º jogo).
/// Se não houver mais nada, vão eles.
class ForaDaEntrada extends StatefulWidget {
  const ForaDaEntrada({super.key, required this.child});
  final Widget child;

  @override
  State<ForaDaEntrada> createState() => _ForaDaEntradaState();
}

class _ForaDaEntradaState extends State<ForaDaEntrada> {
  final _foco = FocoForaDaEntrada(debugLabel: 'Fora da entrada', canRequestFocus: false, skipTraversal: true);

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(focusNode: _foco, includeSemantics: false, child: widget.child);
}

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
      this.jogos, this.inicial = Seccao.verTv, this.sair = SystemNavigator.pop, this.tarefas, this.verificacao, this.pedidoGestor,
      this.novidades = false, this.novaVersao, this.atualizador});

  /// Mostra as novidades desta versão ao abrir (a primeira vez depois de atualizar).
  final bool novidades;

  /// Procura uma versão nova da app ao abrir (null: não procura; ver [novaVersaoPorAvisar]).
  final Future<NovaVersao?> Function()? novaVersao;

  /// Para testes: o que o «Atualizar» do aviso usa (null: o da app).
  final Atualizador? atualizador;

  final Widget verTv;

  /// O ecrã «Jogos» (null: a secção não aparece).
  final Widget? jogos;
  final Widget gestor;
  final Widget definicoes;

  /// A secção à vista ao abrir.
  final Seccao inicial;

  /// Fecha a app (o segundo Voltar em Ver TV).
  final VoidCallback sair;

  /// O trabalho longo: cada tarefa que acaba dá aqui o seu aviso, em qualquer secção.
  final ServicoTarefas? tarefas;

  /// A verificação do Gestor (não é uma tarefa): quando uma ronda acaba, dá o aviso "Verificação terminada".
  final ServicoVerificacao? verificacao;

  /// Por onde se pede ao Gestor que abra um sub-ecrã ("Ver resultados" abre o da verificação).
  final ValueNotifier<EcraGestor?>? pedidoGestor;

  /// Mostra a secção `s` e põe o foco nela (onde estava, ou no primeiro controlo).
  static void irPara(BuildContext context, Seccao s) =>
      context.getInheritedWidgetOfExactType<SeccaoAtual>()?.irPara(s);

  /// O que faz Voltar quando a secção de `context` está à vista, antes da casca (por exemplo, num
  /// passo do Gestor, voltar ao resumo do Gestor em vez de ir para Ver TV). `tratar`
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

  /// As secções à vista, pela ordem da barra.
  List<Seccao> get _seccoes => [for (final s in Seccao.values) if (s != Seccao.jogos || widget.jogos != null) s];

  /// O conteúdo de cada secção (não recebe o foco: serve para saber onde ele está).
  final _focosSeccao = [
    for (final s in Seccao.values)
      FocusNode(debugLabel: 'Secção ${s.name}', canRequestFocus: false, skipTraversal: true),
  ];
  // (um foco por valor de Seccao, à vista ou não; indexados por Seccao.index)

  /// O foco de cada secção na barra lateral.
  final _focosBarra = [for (final s in Seccao.values) FocusNode(debugLabel: 'Barra ${s.name}')];

  /// O Voltar que cada secção trata ela própria (ver [TelaPrincipal.aoVoltar]).
  final _voltarNaSeccao = <Seccao, bool Function()>{};

  /// O último controlo com o foco em cada secção (DIREITA na barra e Voltar regressam a ele).
  final _ultimo = <Seccao, FocusNode>{};

  /// Depois do primeiro Voltar, durante [_tempoSair], o segundo fecha a app.
  static const _tempoSair = Duration(seconds: 2);
  Timer? _podeSair;

  /// As mensagens no canto superior direito (ver [mostrarMensagem]): as do [AnfitriaoMensagens] da
  /// app (por cima de todas as rotas) ou, sem ele (testes de um ecrã), as da própria casca.
  final _proprias = ControladorMensagens();
  ControladorMensagens? _daApp;
  ControladorMensagens get _mensagens => _daApp ?? _proprias;

  /// Android/TV: Voltar em Ver TV não fecha logo a app. No Windows a janela fecha-se pelo
  /// botão de fechar, como sempre.
  bool get _confirmarSaida => defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focoMudou);
    _ouvirAvisos();
    if (widget.novidades) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(mostrarNovidadesDaVersao(context));
      });
    }
    final procurar = widget.novaVersao;
    if (procurar != null) unawaited(_avisarNovaVersao(procurar));
  }

  /// Há uma versão nova publicada: diz qual e onde se descarrega (a TV não tem browser para abrir).
  Future<void> _avisarNovaVersao(Future<NovaVersao?> Function() procurar) async {
    final v = await procurar();
    if (v == null || !mounted) return;
    final pagina = v.pagina.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/tag/.*$'), '');
    _mensagens.mostrar(tr('Há uma versão nova da app: {0}. Descarrega em {1}', [v.versao, pagina]),
        acao: tr('Atualizar'),
        aoAcao: _naCasca(() => unawaited(atualizarApp(context, v, a: widget.atualizador))),
        duracao: const Duration(seconds: 15));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _daApp = MensagensHost.maybeOf(context);
  }

  /// A ação de um aviso da casca pode chegar com a lista aberta ou o player por cima (a mensagem
  /// vê-se em todas as rotas): primeiro volta-se à casca, para a ação se ver.
  VoidCallback? _naCasca(VoidCallback? f) => f == null
      ? null
      : () {
          if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
          f();
        };

  StreamSubscription<Tarefa>? _subTarefas;
  bool _verificava = false;

  @override
  void didUpdateWidget(TelaPrincipal antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.tarefas != widget.tarefas || antigo.verificacao != widget.verificacao) {
      antigo.verificacao?.removeListener(_aoMudarVerificacao);
      _subTarefas?.cancel();
      _ouvirAvisos();
    }
  }

  /// Esta casca é a única dona dos avisos de fim: o de cada tarefa e o da verificação do Gestor.
  void _ouvirAvisos() {
    _subTarefas = widget.tarefas?.acabadas.listen(_avisarTarefa);
    final v = widget.verificacao;
    _verificava = v?.ocupado ?? false;
    v?.addListener(_aoMudarVerificacao);
  }

  /// O aviso de fim de uma tarefa: o resultado, com a ação da tarefa (ou "Tentar de novo" se falhou).
  void _avisarTarefa(Tarefa t) {
    final falhou = t.estado == EstadoTarefa.falhou;
    String? acao = t.rotuloAcao;
    VoidCallback? aoAcao = t.aoAcao;
    if (acao == null && falhou && t.repetir != null) {
      acao = tr('Tentar de novo');
      aoAcao = () => t.repetir!();
    }
    _mensagens.mostrar(
      t.resultado ?? t.titulo,
      tipo: switch (t.estado) {
        EstadoTarefa.terminada => MensagemTipo.sucesso,
        EstadoTarefa.falhou => MensagemTipo.erro,
        _ => MensagemTipo.info,
      },
      acao: acao,
      aoAcao: _naCasca(aoAcao),
    );
  }

  /// Uma ronda do Gestor acabou (ocupado passou de true a false): o relatório, também quando foi
  /// parada (com as que chegaram ao fim).
  void _aoMudarVerificacao() {
    final v = widget.verificacao!;
    final acabou = _verificava && !v.ocupado;
    _verificava = v.ocupado;
    if (!acabou) return;
    final resumo = resumoVerificacao(v);
    if (resumo == null) {
      if (v.parada) _mensagens.mostrar(tr('Verificação parada. Nenhuma lista chegou ao fim.'));
      return;
    }
    _mensagens.mostrar(
      '${v.parada ? 'Verificação parada' : 'Verificação terminada'}: $resumo',
      tipo: v.parada ? MensagemTipo.info : MensagemTipo.sucesso,
      acao: tr('Ver resultados'),
      aoAcao: _naCasca(() {
        _mudar(Seccao.gestor, focar: false);
        widget.pedidoGestor?.value = EcraGestor.verificacao;
      }),
    );
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focoMudou);
    _podeSair?.cancel();
    _subTarefas?.cancel();
    widget.verificacao?.removeListener(_aoMudarVerificacao);
    _proprias.dispose();
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

  /// O controlo mais acima (e mais à esquerda) à vista na secção, fora dos [ForaDaEntrada]; só
  /// sem nenhum, o mais acima dos que estão neles.
  FocusNode? _primeiroDe(Seccao s) {
    final seccao = _focosSeccao[s.index];
    final caixa = seccao.context?.findRenderObject();
    if (caixa is! RenderBox || !caixa.hasSize) return null;
    final area = caixa.localToGlobal(Offset.zero) & caixa.size;
    FocusNode? melhor, melhorFora;
    bool antes(FocusNode n, FocusNode? m) {
      if (m == null) return true;
      final r = n.rect, o = m.rect;
      return r.top < o.top - 4 || ((r.top - o.top).abs() <= 4 && r.left < o.left);
    }

    for (final n in seccao.traversalDescendants) {
      if (!n.canRequestFocus || n.skipTraversal || n.context == null || n is FocusScopeNode) continue;
      // só os que estão à vista (o que já saiu de cima não conta)
      if (!area.contains(n.rect.center)) continue;
      if (n is FocoForaDaEntrada) continue;
      if (n.ancestors.any((a) => a is FocoForaDaEntrada)) {
        if (antes(n, melhorFora)) melhorFora = n;
      } else if (antes(n, melhor)) {
        melhor = n;
      }
    }
    return melhor ?? melhorFora;
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
    final seccoes = _seccoes;
    final i = seccoes.indexWhere((s) => _focosBarra[s.index].hasPrimaryFocus);
    if (i < 0) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        if (i > 0) _focosBarra[seccoes[i - 1].index].requestFocus();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        if (i < seccoes.length - 1) _focosBarra[seccoes[i + 1].index].requestFocus();
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
    _mensagens.mostrar(tr('Carregue outra vez em Voltar para sair'), duracao: _tempoSair);
  }

  @override
  Widget build(BuildContext context) {
    final largo = _largo(context);
    final ecras = {
      Seccao.verTv: widget.verTv,
      if (widget.jogos != null) Seccao.jogos: widget.jogos!,
      Seccao.gestor: widget.gestor,
      Seccao.definicoes: widget.definicoes,
    };
    final seccoes = _seccoes;
    final conteudo = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: (_, e) => _teclaConteudo(context, e),
      child: IndexedStack(
        index: seccoes.indexOf(_atual).clamp(0, seccoes.length - 1),
        sizing: StackFit.expand,
        children: [
          for (final s in seccoes)
            Focus(
                focusNode: _focosSeccao[s.index],
                includeSemantics: false,
                child: _SeccaoDoEcra(seccao: s, child: ecras[s]!)),
        ],
      ),
    );
    return SeccaoAtual(
      seccao: _atual,
      irPara: (s) => _mudar(s, focar: true),
      child: _daApp != null
          ? _casca(context, largo, conteudo)
          : MensagensHost(
              controlador: _proprias,
              child: Stack(children: [
                Positioned.fill(child: _casca(context, largo, conteudo)),
                SobreposicaoMensagens(controlador: _proprias),
              ]),
            ),
    );
  }

  Widget _casca(BuildContext context, bool largo, Widget conteudo) {
    final seccoes = _seccoes;
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
                        seccoes: seccoes,
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
                  selectedIndex: seccoes.indexOf(_atual).clamp(0, seccoes.length - 1),
                  onDestinationSelected: (i) => _mudar(seccoes[i], focar: false),
                  destinations: [
                    for (final s in seccoes)
                      NavigationDestination(icon: Icon(rotulosSeccoes[s]!.$2), label: tr(rotulosSeccoes[s]!.$1)),
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
