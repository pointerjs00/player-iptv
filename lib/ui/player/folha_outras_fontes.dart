import 'package:material_ui/material_ui.dart';

import '../../idioma/idioma.dart';
import '../design/design.dart';

/// Uma fonte do canal no «Outras fontes»: a lista, o nome do canal nela e se já falhou.
typedef FonteDoPlayer = ({String lista, String canal, bool falhou});

/// «Outras fontes» (modo «Jogo»): as fontes do canal, como no «Onde ver». O foco começa na que
/// está a tocar (`atual`); OK numa fonte devolve o índice dela (null: fechou sem escolher).
Future<int?> mostrarOutrasFontes(BuildContext context, List<FonteDoPlayer> fontes, {required int atual}) =>
    showDialog<int>(context: context, builder: (_) => FolhaOutrasFontes(fontes: fontes, atual: atual));

class FolhaOutrasFontes extends StatelessWidget {
  const FolhaOutrasFontes({super.key, required this.fontes, required this.atual});
  final List<FonteDoPlayer> fontes;
  final int atual;

  @override
  Widget build(BuildContext context) {
    final ecra = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(Tokens.e16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: ecra.height * .85),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.e16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            CabecalhoSeccao(
              icone: Icons.alt_route_rounded,
              titulo: tr('Outras fontes'),
              subtitulo: tr('{0} fontes deste canal · OK muda sem sair do player', [fontes.length]),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final (i, f) in fontes.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Tokens.e8),
                    child: _LinhaFonte(
                      fonte: f,
                      aTocar: i == atual,
                      aoEscolher: () => Navigator.of(context).pop(i),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LinhaFonte extends StatelessWidget {
  const _LinhaFonte({required this.fonte, required this.aTocar, required this.aoEscolher});
  final FonteDoPlayer fonte;
  final bool aTocar;
  final VoidCallback aoEscolher;

  @override
  Widget build(BuildContext context) {
    final cor = aTocar ? Tokens.acento : Tokens.texto2;
    return Opacity(
      // a que falhou continua escolhível (volta a ser tentada), só mais apagada
      opacity: fonte.falhou && !aTocar ? .6 : 1,
      child: CartaoModerno(
        autofocus: aTocar,
        destaque: aTocar,
        escalaFoco: 1.01,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.e12, vertical: 10),
        onTap: aoEscolher,
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: cor.withValues(alpha: .16), shape: BoxShape.circle),
            child: Icon(aTocar ? Icons.play_arrow_rounded : Icons.live_tv_rounded, size: 20, color: cor),
          ),
          const SizedBox(width: Tokens.e12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fonte.lista,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Tokens.texto)),
              const SizedBox(height: 2),
              Text(fonte.canal,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Tokens.texto2)),
            ]),
          ),
          if (aTocar) ...[
            const SizedBox(width: Tokens.e8),
            Etiqueta(icone: Icons.graphic_eq_rounded, texto: tr('A ver'), tom: TomEtiqueta.acento),
          ] else if (fonte.falhou) ...[
            const SizedBox(width: Tokens.e8),
            Etiqueta(icone: Icons.error_outline_rounded, texto: tr('Falhou')),
          ],
        ]),
      ),
    );
  }
}
