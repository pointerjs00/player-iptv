import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../design/componentes.dart';
import '../design/ecra.dart';
import '../design/tokens.dart';
import '../realce_foco.dart';

/// Um item do painel de definições do player. Sem ação (`aoMudar`/`mais`… nulos) aparece
/// desligado, com a `nota` a explicar porquê, e o foco salta-o.
sealed class ItemDefinicao {
  const ItemDefinicao(this.titulo, {this.nota});
  final String titulo;

  /// Uma linha de explicação por baixo do título.
  final String? nota;

  bool get ativo;
}

/// Uma de várias opções: direita/OK passam à seguinte (dá a volta), esquerda à anterior.
class DefinicaoEscolha extends ItemDefinicao {
  const DefinicaoEscolha(super.titulo, {required this.opcoes, required this.atual, this.aoMudar, super.nota});
  final List<String> opcoes;
  final int atual;
  final ValueChanged<int>? aoMudar;

  @override
  bool get ativo => aoMudar != null && opcoes.length > 1;
}

/// Ligado/desligado: OK troca, direita liga, esquerda desliga.
class DefinicaoInterruptor extends ItemDefinicao {
  const DefinicaoInterruptor(super.titulo, {required this.valor, this.aoMudar, super.nota});
  final bool valor;
  final ValueChanged<bool>? aoMudar;

  @override
  bool get ativo => aoMudar != null;
}

/// Um valor que sobe/desce aos passos (volume, atraso do áudio): esquerda/direita.
class DefinicaoPassos extends ItemDefinicao {
  const DefinicaoPassos(super.titulo, {required this.valor, this.menos, this.mais, super.nota});
  final String valor;
  final VoidCallback? menos;
  final VoidCallback? mais;

  @override
  bool get ativo => menos != null || mais != null;
}

/// Uma ação (ex.: mostrar as estatísticas): OK.
class DefinicaoAcao extends ItemDefinicao {
  const DefinicaoAcao(super.titulo, {required this.valor, this.aoCarregar, super.nota});
  final String valor;
  final VoidCallback? aoCarregar;

  @override
  bool get ativo => aoCarregar != null;
}

/// O painel de definições do player: vidro escuro à direita, por cima do vídeo (sem desfoque —
/// um BackdropFilter por cima do vídeo pesa num aparelho fraco). O primeiro item ativo fica
/// com o foco; cima/baixo andam pelos itens.
class PainelDefinicoes extends StatelessWidget {
  const PainelDefinicoes({super.key, required this.itens, this.titulo = 'Definições'});
  final List<ItemDefinicao> itens;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final primeiro = itens.indexWhere((i) => i.ativo);
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.e24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tv ? 520 : 440),
          child: SuperficieVidro(
            cor: const Color(0xEB0B0F17),
            elevacao: 3,
            padding: const EdgeInsets.fromLTRB(Tokens.e12, Tokens.e16, Tokens.e12, Tokens.e12),
            child: FocusTraversalGroup(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Tokens.e12, 0, Tokens.e12, Tokens.e8),
                  child: Text(titulo,
                      style: TextStyle(fontSize: tv ? 22 : 18, fontWeight: FontWeight.w700, color: Tokens.texto)),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(4),
                    children: [
                      for (var i = 0; i < itens.length; i++)
                        LinhaDefinicao(key: ValueKey(itens[i].titulo), item: itens[i], autofocus: i == primeiro),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uma linha do painel (focável quando o item está ativo).
class LinhaDefinicao extends StatelessWidget {
  const LinhaDefinicao({super.key, required this.item, this.autofocus = false});
  final ItemDefinicao item;
  final bool autofocus;

  static bool _ok(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter || k == LogicalKeyboardKey.gameButtonA;

  void _carregar() {
    switch (item) {
      case DefinicaoEscolha(:final opcoes, :final atual, :final aoMudar):
        aoMudar?.call((atual + 1) % opcoes.length);
      case DefinicaoInterruptor(:final valor, :final aoMudar):
        aoMudar?.call(!valor);
      case DefinicaoPassos(:final mais):
        mais?.call();
      case DefinicaoAcao(:final aoCarregar):
        aoCarregar?.call();
    }
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final direita = k == LogicalKeyboardKey.arrowRight;
    final esquerda = k == LogicalKeyboardKey.arrowLeft;
    if (_ok(k)) {
      if (e is KeyDownEvent && item is! DefinicaoPassos) _carregar();
      return KeyEventResult.handled;
    }
    if (!direita && !esquerda) return KeyEventResult.ignored;
    // esquerda/direita nunca saem do painel (ficam sempre com o item)
    switch (item) {
      case DefinicaoEscolha(:final opcoes, :final atual, :final aoMudar):
        final n = opcoes.length;
        aoMudar?.call(((direita ? atual + 1 : atual - 1) % n + n) % n);
      case DefinicaoInterruptor(:final aoMudar):
        aoMudar?.call(direita);
      case DefinicaoPassos(:final menos, :final mais):
        (direita ? mais : menos)?.call();
      case DefinicaoAcao():
        break;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final ativo = item.ativo;
    final corTexto = ativo ? Tokens.texto : Tokens.texto2;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _tecla,
        child: RealceFoco(
          raio: Tokens.raioCampo,
          construir: (_, aoMudarFoco) => InkWell(
            autofocus: autofocus,
            onFocusChange: aoMudarFoco,
            onTap: ativo ? _carregar : null,
            borderRadius: BorderRadius.circular(Tokens.raioCampo),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: Tokens.e12, vertical: tv ? 12 : 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.titulo,
                        style: TextStyle(fontSize: tv ? 17 : 15, fontWeight: FontWeight.w600, color: corTexto)),
                    if (item.nota != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(item.nota!, style: TextStyle(fontSize: tv ? 14 : 12, color: Tokens.texto2)),
                      ),
                  ]),
                ),
                const SizedBox(width: Tokens.e12),
                ExcludeFocus(child: _valor(tv, corTexto)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _valor(bool tv, Color cor) {
    final estilo = TextStyle(fontSize: tv ? 16 : 14, color: cor, fontFeatures: const [FontFeature.tabularFigures()]);
    Widget seta(IconData i, VoidCallback? f) => InkWell(
          onTap: f,
          customBorder: const CircleBorder(),
          child: Padding(padding: const EdgeInsets.all(4), child: Icon(i, size: 20, color: f == null ? Tokens.texto2 : cor)),
        );
    switch (item) {
      case DefinicaoEscolha(:final opcoes, :final atual, :final aoMudar):
        final n = opcoes.length;
        final ativo = item.ativo;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          seta(Icons.chevron_left, ativo ? () => aoMudar!(((atual - 1) % n + n) % n) : null),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 90),
            child: Text(opcoes.isEmpty ? '—' : opcoes[atual], textAlign: TextAlign.center, style: estilo),
          ),
          seta(Icons.chevron_right, ativo ? () => aoMudar!((atual + 1) % n) : null),
        ]);
      case DefinicaoInterruptor(:final valor, :final aoMudar):
        return Switch(value: valor, onChanged: aoMudar);
      case DefinicaoPassos(:final valor, :final menos, :final mais):
        return Row(mainAxisSize: MainAxisSize.min, children: [
          seta(Icons.remove, menos),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72),
            child: Text(valor, textAlign: TextAlign.center, style: estilo),
          ),
          seta(Icons.add, mais),
        ]);
      case DefinicaoAcao(:final valor):
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Text(valor, style: estilo),
          Icon(Icons.chevron_right, size: 20, color: cor),
        ]);
    }
  }
}
