import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../desporto/modelo.dart';
import '../../desporto/onde_ver.dart';
import '../../desporto/preferencias_jogos.dart';
import '../../idioma/idioma.dart';
import '../design/design.dart';
import 'linha_jogo.dart';

String nomeQualidade(Qualidade q) => switch (q) {
      Qualidade.sd => 'SD',
      Qualidade.hd => 'HD',
      Qualidade.fhd => 'FHD',
      Qualidade.uhd => '4K',
    };

/// O «Onde ver» de um canal: as fontes dele em todas as listas, pela ordem em que se
/// experimentam. OK numa fonte abre-a (e as seguintes ficam para a troca automática); «Este não é
/// o canal» tira-a. Devolve as fontes a abrir (null: fechou sem escolher).
Future<List<FonteCanal>?> mostrarOndeVer(
  BuildContext context, {
  required String canalTv,
  required FontesDosCanais fontes,
  required PreferenciasJogos preferencias,
}) =>
    showDialog<List<FonteCanal>>(
      context: context,
      builder: (_) => FolhaOndeVer(canalTv: canalTv, fontes: fontes, preferencias: preferencias),
    );

class FolhaOndeVer extends StatefulWidget {
  const FolhaOndeVer({super.key, required this.canalTv, required this.fontes, required this.preferencias});
  final String canalTv;
  final FontesDosCanais fontes;
  final PreferenciasJogos preferencias;

  @override
  State<FolhaOndeVer> createState() => _FolhaOndeVerState();
}

class _FolhaOndeVerState extends State<FolhaOndeVer> {
  bool _aAtualizar = false;

  @override
  void initState() {
    super.initState();
    widget.fontes.addListener(_mudou);
    widget.preferencias.addListener(_mudou);
  }

  @override
  void dispose() {
    widget.fontes.removeListener(_mudou);
    widget.preferencias.removeListener(_mudou);
    super.dispose();
  }

  void _mudou() {
    if (mounted) setState(() {});
  }

  Future<void> _atualizar() async {
    setState(() => _aAtualizar = true);
    try {
      await widget.fontes.atualizar();
    } finally {
      if (mounted) setState(() => _aAtualizar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = fontesDoCanal(widget.canalTv, widget.fontes, widget.preferencias);
    final ultima = widget.preferencias.ultimaFonte(widget.canalTv);
    final semCache = widget.fontes.listasSemCache;
    final ecra = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(Tokens.e16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 620, maxHeight: ecra.height * .85),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.e16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            CabecalhoSeccao(
              icone: Icons.live_tv_rounded,
              titulo: tr('Onde ver: {0}', [nomeCanalTv(widget.canalTv)]),
              subtitulo: lista.isEmpty ? null : tr('{0} fontes · OK abre, e se falhar passa à seguinte', [lista.length]),
            ),
            if (lista.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Tokens.e16),
                child: Text(tr('Nenhuma das tuas listas tem este canal'),
                    style: const TextStyle(fontSize: 15, color: Tokens.texto2)),
              )
            else
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final (i, f) in lista.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Tokens.e8),
                      child: _LinhaFonte(
                        fonte: f,
                        autofocus: i == 0,
                        funcionou: ultima != null && ultima.listaId == f.lista.id && ultima.canalId == f.canal.id,
                        aoAbrir: () => Navigator.of(context).pop([...lista.sublist(i), ...lista.sublist(0, i)]),
                        aoNaoE: () => widget.preferencias.associar(f.lista.id, f.canal, null),
                      ),
                    ),
                ]),
              ),
            if (semCache > 0) ...[
              const SizedBox(height: Tokens.e8),
              Row(children: [
                Expanded(
                  child: Text(tr('{0} listas ainda sem canais guardados', [semCache]),
                      style: const TextStyle(fontSize: 13, color: Tokens.texto2)),
                ),
                OutlinedButton.icon(
                  onPressed: _aAtualizar ? null : () => unawaited(_atualizar()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(tr('Atualizar canais')),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

class _LinhaFonte extends StatelessWidget {
  const _LinhaFonte({required this.fonte, required this.funcionou, required this.aoAbrir, required this.aoNaoE,
      this.autofocus = false});
  final FonteCanal fonte;
  final bool funcionou;
  final VoidCallback aoAbrir;
  final VoidCallback aoNaoE;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final mau = fonteNaoFunciona(fonte);
    return Opacity(
      opacity: mau ? .55 : 1,
      child: Row(children: [
        Expanded(
          child: CartaoModerno(
            autofocus: autofocus,
            escalaFoco: 1.01,
            padding: const EdgeInsets.symmetric(horizontal: Tokens.e12, vertical: 10),
            onTap: aoAbrir,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(fonte.lista.nomeMostrado,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                const SizedBox(width: Tokens.e8),
                PilulaEstado(estadoDe(fonte.lista), compacta: true),
              ]),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(fonte.canal.nome, style: const TextStyle(fontSize: 13, color: Tokens.texto2)),
                Etiqueta(texto: nomeQualidade(fonte.qualidade)),
                if (funcionou)
                  Etiqueta(icone: Icons.check_rounded, texto: tr('Funcionou da última vez'), tom: TomEtiqueta.acento),
              ]),
            ]),
          ),
        ),
        const SizedBox(width: Tokens.e8),
        IconButton(
          tooltip: tr('Este não é o canal'),
          onPressed: aoNaoE,
          icon: const Icon(Icons.link_off_rounded),
        ),
      ]),
    );
  }
}
