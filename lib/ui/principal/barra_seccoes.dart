import 'package:material_ui/material_ui.dart';

import '../../marca.dart';
import '../design/design.dart';
import '../realce_foco.dart';
import 'tela_principal.dart';

/// O nome e o ícone de cada secção (a barra lateral e a NavigationBar do telemóvel).
const rotulosSeccoes = {
  Seccao.verTv: ('Ver TV', Icons.live_tv_rounded),
  Seccao.gestor: ('Gestor', Icons.inventory_2_outlined),
  Seccao.definicoes: ('Definições', Icons.settings_outlined),
};

/// A barra lateral das secções (ecrãs largos e TV): o nome da app em cima e uma linha por
/// secção. As setas dentro da barra e a passagem para o conteúdo tratam-se em [TelaPrincipal].
class BarraSeccoes extends StatelessWidget {
  const BarraSeccoes({super.key, required this.atual, required this.aoEscolher, this.focos});

  /// A largura da barra.
  static const largura = 220.0;

  /// A secção à vista.
  final Seccao atual;

  /// OK (ou toque) numa secção.
  final ValueChanged<Seccao> aoEscolher;

  /// O foco de cada secção (pela ordem de [Seccao.values]).
  final List<FocusNode>? focos;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: largura,
        // um Material (e não uma caixa com cor): os ListTile pintam o fundo e o ink nele
        child: Material(
          color: Tokens.superficie,
          shape: const Border(right: BorderSide(color: Tokens.bordaVidro)),
          child: ListView(
          padding: const EdgeInsets.fromLTRB(Tokens.e12, Tokens.e24, Tokens.e12, Tokens.e16),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(Tokens.e8, 0, Tokens.e8, Tokens.e24),
              child: MarcaApp(),
            ),
            for (final s in Seccao.values)
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.e8),
                child: RealceFoco(
                  raio: Tokens.raioBotao,
                  construir: (context, aoMudarFoco) => ListTile(
                    focusNode: focos?[s.index],
                    selected: s == atual,
                    selectedColor: Tokens.texto,
                    selectedTileColor: Tokens.superficie3,
                    iconColor: Tokens.texto2,
                    textColor: Tokens.texto2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.raioBotao)),
                    leading: Icon(rotulosSeccoes[s]!.$2),
                    title: Text(rotulosSeccoes[s]!.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                    onFocusChange: aoMudarFoco,
                    onTap: () => aoEscolher(s),
                  ),
                ),
              ),
          ],
          ),
        ),
      );
}

/// O nome da app com o ícone dela (ferramentas/gerar_icones.py).
class MarcaApp extends StatelessWidget {
  const MarcaApp({super.key});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Image.asset('assets/marca/logo.png', width: 34, height: 34, filterQuality: FilterQuality.medium),
        const SizedBox(width: 10),
        const Flexible(
          child: Text(nomeApp,
              overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      ]);
}
