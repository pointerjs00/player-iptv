import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

enum MensagemTipo { info, sucesso, erro, progresso }

/// Uma mensagem à vista no canto superior direito.
class Mensagem {
  const Mensagem(this.texto, this.tipo, this.acao, this.aoAcao);
  final String texto;
  final MensagemTipo tipo;
  final String? acao;
  final VoidCallback? aoAcao;
}

/// Guarda a mensagem à vista (uma de cada vez: a nova substitui a anterior). Vive no
/// [AnfitriaoMensagens] da app (ou, sem ele, na `TelaPrincipal`). Enquanto uma mensagem com ação
/// está de facto à vista, a tecla Menu do comando ativa a ação antes de chegar ao ecrã (sem
/// passar pelo foco, por isso nunca o rouba); sem ela, a tecla Menu é do ecrã.
class ControladorMensagens extends ChangeNotifier {
  Mensagem? _atual;
  Timer? _fim;
  bool _ouve = false;

  /// A sobreposição está tapada por outra rota (só acontece com a da `TelaPrincipal`, quando a
  /// lista aberta ou o player estão por cima): a mensagem não se vê e a tecla Menu não é dela.
  bool tapada = false;

  Mensagem? get atual => _atual;

  void mostrar(String texto,
      {MensagemTipo tipo = MensagemTipo.info,
      String? acao,
      VoidCallback? aoAcao,
      Duration duracao = const Duration(seconds: 4)}) {
    _fim?.cancel();
    final comAcao = acao != null && aoAcao != null;
    _atual = Mensagem(texto, tipo, comAcao ? acao : null, comAcao ? aoAcao : null);
    if (comAcao && duracao < const Duration(seconds: 8)) duracao = const Duration(seconds: 8);
    _fim = Timer(duracao, fechar);
    if (comAcao && !_ouve) {
      // antes do foco: se a tecla é da mensagem, o ecrã não a recebe
      FocusManager.instance.addEarlyKeyEventHandler(_tecla);
      _ouve = true;
    }
    if (!comAcao) _largarTecla();
    notifyListeners();
  }

  void _largarTecla() {
    if (!_ouve) return;
    FocusManager.instance.removeEarlyKeyEventHandler(_tecla);
    _ouve = false;
  }

  void fechar() {
    _fim?.cancel();
    _fim = null;
    _largarTecla();
    if (_atual == null) return;
    _atual = null;
    notifyListeners();
  }

  /// Executa a ação da mensagem (e fecha-a).
  void ativarAcao() {
    final f = _atual?.aoAcao;
    fechar();
    f?.call();
  }

  KeyEventResult _tecla(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.contextMenu || _atual?.aoAcao == null || tapada) {
      return KeyEventResult.ignored;
    }
    ativarAcao();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _fim?.cancel();
    _largarTecla();
    super.dispose();
  }
}

/// Dá aos ecrãs o [ControladorMensagens] do [AnfitriaoMensagens] (ou da `TelaPrincipal`).
class MensagensHost extends InheritedWidget {
  const MensagensHost({super.key, required this.controlador, required super.child});
  final ControladorMensagens controlador;

  static ControladorMensagens? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MensagensHost>()?.controlador;

  @override
  bool updateShouldNotify(MensagensHost old) => controlador != old.controlador;
}

/// O anfitrião das mensagens da app inteira: vive no `MaterialApp.builder`, por cima do
/// Navigator, por isso todas as rotas (a casca, a lista aberta, o player do Android) partilham
/// o mesmo canto superior direito e a mesma tecla Menu.
class AnfitriaoMensagens extends StatefulWidget {
  const AnfitriaoMensagens({super.key, required this.child});
  final Widget child;

  @override
  State<AnfitriaoMensagens> createState() => _AnfitriaoMensagensState();
}

class _AnfitriaoMensagensState extends State<AnfitriaoMensagens> {
  final _controlador = ControladorMensagens();

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MensagensHost(
        controlador: _controlador,
        child: Stack(children: [
          Positioned.fill(child: widget.child),
          SobreposicaoMensagens(controlador: _controlador),
        ]),
      );
}

typedef Mensageiro = void Function(String texto,
    {MensagemTipo tipo, String? acao, VoidCallback? aoAcao, Duration duracao});

/// Mostra uma mensagem no canto superior direito. Com `acao` (e `aoAcao`), a mensagem dura
/// 8 s e mostra "Menu: (a ação)"; a tecla Menu do comando (ou um toque/clique) ativa-a.
/// Sem anfitrião (a janela do player no Windows, um ecrã testado sozinho) cai numa SnackBar.
void mostrarMensagem(BuildContext context, String texto,
    {MensagemTipo tipo = MensagemTipo.info,
    String? acao,
    VoidCallback? aoAcao,
    Duration duracao = const Duration(seconds: 4)}) {
  mensageiroDe(context)(texto, tipo: tipo, acao: acao, aoAcao: aoAcao, duracao: duracao);
}

/// O mesmo que [mostrarMensagem], mas apanha já o destino: serve para avisos que chegam
/// depois de um `await`, quando já não se pode usar o `context`.
Mensageiro mensageiroDe(BuildContext context) {
  final c = MensagensHost.maybeOf(context);
  if (c != null) return c.mostrar;
  final m = ScaffoldMessenger.maybeOf(context);
  return (texto, {tipo = MensagemTipo.info, acao, aoAcao, duracao = const Duration(seconds: 4)}) {
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(texto),
      duration: duracao,
      action: acao != null && aoAcao != null ? SnackBarAction(label: acao, onPressed: aoAcao) : null,
    ));
  };
}

/// A sobreposição no canto superior direito. Não recebe foco. Dentro de uma rota (a da
/// `TelaPrincipal`, sem anfitrião na app), marca o controlador como tapado quando essa rota não
/// é a de cima.
class SobreposicaoMensagens extends StatefulWidget {
  const SobreposicaoMensagens({super.key, required this.controlador});
  final ControladorMensagens controlador;

  @override
  State<SobreposicaoMensagens> createState() => _SobreposicaoMensagensState();
}

class _SobreposicaoMensagensState extends State<SobreposicaoMensagens> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.controlador.tapada = !(ModalRoute.of(context)?.isCurrent ?? true);
  }

  @override
  void didUpdateWidget(SobreposicaoMensagens antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.controlador != widget.controlador) {
      widget.controlador.tapada = !(ModalRoute.of(context)?.isCurrent ?? true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controlador,
        builder: (context, _) {
          final controlador = widget.controlador;
          final m = controlador.atual;
          if (m == null) return const SizedBox.shrink();
          return Positioned(
            top: Tokens.e16,
            right: Tokens.e16,
            child: SafeArea(
              child: ExcludeFocus(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Semantics(liveRegion: true, container: true, child: _Cartao(m, controlador)),
                ),
              ),
            ),
          );
        },
      );
}

class _Cartao extends StatelessWidget {
  const _Cartao(this.m, this.controlador);
  final Mensagem m;
  final ControladorMensagens controlador;

  @override
  Widget build(BuildContext context) {
    final cor = switch (m.tipo) {
      MensagemTipo.sucesso => Tokens.ok,
      MensagemTipo.erro => Tokens.mau,
      _ => Tokens.anelFoco,
    };
    final icone = switch (m.tipo) {
      MensagemTipo.sucesso => Icons.check_circle_outline,
      MensagemTipo.erro => Icons.error_outline,
      _ => Icons.info_outline,
    };
    final corpo = Container(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.e16, vertical: Tokens.e12),
      decoration: BoxDecoration(
        color: Tokens.superficie2,
        borderRadius: BorderRadius.circular(Tokens.raioBotao),
        border: Border.all(color: Tokens.bordaVidro),
        boxShadow: Tokens.sombra2,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m.tipo == MensagemTipo.progresso)
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cor))
        else
          Icon(icone, size: 20, color: cor),
        const SizedBox(width: Tokens.e12),
        Flexible(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.texto, style: const TextStyle(color: Tokens.texto, fontSize: 15)),
            if (m.acao != null)
              Padding(
                padding: const EdgeInsets.only(top: Tokens.e4),
                child: Text('Menu: ${m.acao}',
                    style: const TextStyle(color: Tokens.anelFoco, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ]),
    );
    return Material(
      type: MaterialType.transparency,
      child: m.aoAcao == null
          ? corpo
          : GestureDetector(behavior: HitTestBehavior.opaque, onTap: controlador.ativarAcao, child: corpo),
    );
  }
}
