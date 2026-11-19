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

/// Guarda a mensagem à vista (uma de cada vez: a nova substitui a anterior). Vive na
/// `TelaPrincipal`; a tecla Menu do comando ativa a ação enquanto a mensagem está visível,
/// sem passar pelo foco (por isso nunca o rouba).
class ControladorMensagens extends ChangeNotifier {
  Mensagem? _atual;
  Timer? _fim;
  bool _ouve = false;

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
      HardwareKeyboard.instance.addHandler(_tecla);
      _ouve = true;
    }
    if (!comAcao) _largarTecla();
    notifyListeners();
  }

  void _largarTecla() {
    if (!_ouve) return;
    HardwareKeyboard.instance.removeHandler(_tecla);
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

  bool _tecla(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.contextMenu || _atual?.aoAcao == null) return false;
    ativarAcao();
    return true;
  }

  @override
  void dispose() {
    _fim?.cancel();
    _largarTecla();
    super.dispose();
  }
}

/// Dá aos ecrãs o [ControladorMensagens] da `TelaPrincipal`.
class MensagensHost extends InheritedWidget {
  const MensagensHost({super.key, required this.controlador, required super.child});
  final ControladorMensagens controlador;

  static ControladorMensagens? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MensagensHost>()?.controlador;

  @override
  bool updateShouldNotify(MensagensHost old) => controlador != old.controlador;
}

typedef Mensageiro = void Function(String texto,
    {MensagemTipo tipo, String? acao, VoidCallback? aoAcao, Duration duracao});

/// Mostra uma mensagem no canto superior direito. Com `acao` (e `aoAcao`), a mensagem dura
/// 8 s e mostra "Menu: (a ação)"; a tecla Menu do comando (ou um toque/clique) ativa-a.
/// Fora da `TelaPrincipal` (a janela do player, um ecrã sozinho) cai numa SnackBar.
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

/// A sobreposição no canto superior direito. Não recebe foco.
class SobreposicaoMensagens extends StatelessWidget {
  const SobreposicaoMensagens({super.key, required this.controlador});
  final ControladorMensagens controlador;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controlador,
        builder: (context, _) {
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
