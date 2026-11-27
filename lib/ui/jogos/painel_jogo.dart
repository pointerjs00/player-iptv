import 'package:material_ui/material_ui.dart';

import '../../desporto/onde_ver.dart';
import '../../desporto/servico_jogos.dart';
import '../../idioma/idioma.dart';
import '../conteudo/painel_canal.dart' show LogoCanal;
import '../design/design.dart';
import 'linha_jogo.dart';

/// O detalhe de um jogo: a coluna à direita dos ecrãs largos e a página do telemóvel. Com
/// `focavel`, os canais e o «▶ Ver» recebem o foco.
class PainelJogo extends StatelessWidget {
  const PainelJogo({
    super.key,
    required this.item,
    required this.fontes,
    required this.aoOndeVer,
    required this.aoVer,
    this.focavel = false,
  });

  final JogoComCanais item;
  final FontesDosCanais fontes;
  final ValueChanged<String> aoOndeVer;
  final VoidCallback aoVer;
  final bool focavel;

  @override
  Widget build(BuildContext context) {
    final j = item.jogo;
    final (gc, gf) = golosDe(j);
    final temFontes = item.canais.any((t) => fontes.fontes(t.canal).isNotEmpty);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(legendaJogo(item), style: const TextStyle(fontSize: 13, color: Tokens.texto2)),
      const SizedBox(height: Tokens.e12),
      HoraJogo(j, grande: true),
      const SizedBox(height: Tokens.e12),
      EquipaJogo(nome: j.casa, emblema: j.emblemaCasa, golos: gc, tamanho: 19),
      const SizedBox(height: Tokens.e8),
      EquipaJogo(nome: j.fora, emblema: j.emblemaFora, golos: gf, tamanho: 19),
      const SizedBox(height: Tokens.e24),
      Text(tr('Onde dá'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Tokens.texto)),
      const SizedBox(height: Tokens.e8),
      if (item.canais.isEmpty)
        Text(tr('Ainda sem canal anunciado'), style: const TextStyle(color: Tokens.texto2))
      else
        for (final t in item.canais)
          _LinhaCanal(
            nome: nomeCanalTv(t.canal),
            logo: logoDoCanal(t.canal, fontes),
            confianca: '${nomeConfianca(t.confianca)} · ${_fontes(fontes.fontes(t.canal).length)}',
            icone: iconeConfianca(t.confianca),
            focavel: focavel,
            aoTocar: () => aoOndeVer(t.canal),
          ),
      if (temFontes) ...[
        const SizedBox(height: Tokens.e16),
        Align(
          alignment: Alignment.centerLeft,
          child: ExcludeFocus(
            excluding: !focavel,
            child: FilledButton.icon(
              onPressed: aoVer,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(tr('Ver')),
            ),
          ),
        ),
      ],
    ]);
  }
}

String _fontes(int n) => n == 1 ? tr('1 fonte') : tr('{0} fontes', [n]);

class _LinhaCanal extends StatelessWidget {
  const _LinhaCanal({required this.nome, required this.logo, required this.confianca, required this.icone,
      required this.focavel, required this.aoTocar});
  final String nome, logo, confianca;
  final IconData icone;
  final bool focavel;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) => InkWell(
        canRequestFocus: focavel,
        borderRadius: BorderRadius.circular(Tokens.raioBotao),
        onTap: aoTocar,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Tokens.alvoToque),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.e8, vertical: 6),
            child: Row(children: [
              LogoCanal(logo, nome, tamanho: 36, chave: Key('logo-$nome')),
              const SizedBox(width: Tokens.e8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Row(children: [
                    Icon(icone, size: 14, color: Tokens.anelFoco),
                    const SizedBox(width: 4),
                    Flexible(child: Text(confianca, style: const TextStyle(fontSize: 12.5, color: Tokens.texto2))),
                  ]),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: Tokens.texto2),
            ]),
          ),
        ),
      );
}
