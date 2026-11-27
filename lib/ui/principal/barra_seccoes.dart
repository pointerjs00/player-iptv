import 'package:material_ui/material_ui.dart';

import '../../marca.dart';
import '../design/design.dart';
import '../realce_foco.dart';
import 'tela_principal.dart';
import '../../idioma/idioma.dart';

/// O nome e o ícone de cada secção (a barra lateral e a NavigationBar do telemóvel).
const rotulosSeccoes = {
  Seccao.verTv: ('Ver TV', Icons.live_tv_rounded),
  Seccao.jogos: ('Jogos', Icons.sports_soccer_rounded),
  Seccao.gestor: ('Gestor', Icons.inventory_2_outlined),
  Seccao.definicoes: ('Definições', Icons.settings_outlined),
};

/// A barra lateral das secções (ecrãs largos e TV): estreita, com o logótipo em cima e, por
/// secção, o ícone com um rótulo curto por baixo; a secção à vista fica num cartão branco. As
/// setas dentro da barra e a passagem para o conteúdo tratam-se em [TelaPrincipal].
class BarraSeccoes extends StatelessWidget {
  const BarraSeccoes({super.key, required this.atual, required this.aoEscolher, this.focos,
      this.seccoes = const [Seccao.verTv, Seccao.gestor, Seccao.definicoes]});

  /// As secções à vista, pela ordem.
  final List<Seccao> seccoes;

  /// A largura da barra.
  static const largura = 112.0;

  /// A secção à vista.
  final Seccao atual;

  /// OK (ou toque) numa secção.
  final ValueChanged<Seccao> aoEscolher;

  /// O foco de cada secção (indexado por [Seccao.index]).
  final List<FocusNode>? focos;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: largura,
        child: Material(
          color: Tokens.fundo.withValues(alpha: .6),
          shape: const Border(right: BorderSide(color: Tokens.bordaVidro)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Tokens.e16, 28, Tokens.e16, Tokens.e16),
            children: [
              const Center(child: MarcaApp()),
              const SizedBox(height: 28),
              for (final s in seccoes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ItemSeccao(
                    rotulo: tr(rotulosSeccoes[s]!.$1),
                    icone: rotulosSeccoes[s]!.$2,
                    ativa: s == atual,
                    focusNode: focos?[s.index],
                    aoEscolher: () => aoEscolher(s),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// Uma secção da barra: o ícone e o rótulo por baixo. A ativa é um cartão branco com o texto
/// escuro (a mudança de secção anima a cor); o foco do comando tem a mira, como o resto da app.
class _ItemSeccao extends StatelessWidget {
  const _ItemSeccao({required this.rotulo, required this.icone, required this.ativa, required this.aoEscolher,
      this.focusNode});

  final String rotulo;
  final IconData icone;
  final bool ativa;
  final VoidCallback aoEscolher;
  final FocusNode? focusNode;

  static const raio = 22.0;

  @override
  Widget build(BuildContext context) {
    final cor = ativa ? Tokens.fundo : Tokens.texto2;
    return RealceFoco(
      raio: raio,
      construir: (context, aoMudarFoco) => AnimatedContainer(
        duration: duracaoAnimada(context, Tokens.duracaoMedia),
        curve: Tokens.curva,
        decoration: BoxDecoration(
          color: ativa ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(raio),
          boxShadow: ativa
              ? [BoxShadow(color: Tokens.acento.withValues(alpha: .35), blurRadius: 30, offset: const Offset(0, 10))]
              : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            focusNode: focusNode,
            onFocusChange: aoMudarFoco,
            onTap: aoEscolher,
            borderRadius: BorderRadius.circular(raio),
            child: SizedBox(
              height: 78,
              width: double.infinity,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icone, color: cor, size: 24),
                const SizedBox(height: 6),
                Text(rotulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: ativa ? FontWeight.w700 : FontWeight.w600, color: cor)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// O ícone da app (ferramentas/gerar_icones.py), com o nome para os leitores de ecrã.
class MarcaApp extends StatelessWidget {
  const MarcaApp({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: nomeApp,
        child: Image.asset('assets/marca/logo.png', width: 46, height: 46, filterQuality: FilterQuality.medium),
      );
}
