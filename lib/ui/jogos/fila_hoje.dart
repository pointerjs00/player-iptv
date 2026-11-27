import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../desporto/modelo.dart';
import '../../desporto/nomes.dart';
import '../../desporto/onde_ver.dart';
import '../../desporto/preferencias_jogos.dart';
import '../../desporto/servico_jogos.dart';
import '../../idioma/idioma.dart';
import '../design/design.dart';
import '../design/mensagens.dart';
import '../player/abrir_canal.dart';
import 'linha_jogo.dart';
import 'tela_jogos.dart' show AbrirFontesJogo;

Future<void> _abrirNoPlayer(BuildContext context, List<FonteCanal> fontes, {ValueChanged<FonteCanal>? aoFuncionar}) =>
    abrirFontes(context, fontes, aoFuncionar: aoFuncionar);

/// «Hoje há jogo» no Início: os jogos de hoje das equipas favoritas que têm canal (das
/// competições seguidas: o serviço só tem essas). OK num cartão faz «▶ Ver» (todas as fontes do
/// jogo). Sem nenhum, a fila não aparece. Os dados são os do ecrã «Jogos» (que carrega o dia de
/// hoje ao abrir a app): a fila não pede nada.
class FilaHojeHaJogo extends StatefulWidget {
  const FilaHojeHaJogo({
    super.key,
    required this.servico,
    required this.fontes,
    required this.preferencias,
    this.abrir = _abrirNoPlayer,
    this.agora,
  });

  final ServicoJogos servico;
  final FontesDosCanais fontes;
  final PreferenciasJogos preferencias;
  final AbrirFontesJogo abrir;

  /// Só para os testes: o relógio (o dia de hoje).
  final DateTime Function()? agora;

  @override
  State<FilaHojeHaJogo> createState() => _FilaHojeHaJogoState();
}

class _FilaHojeHaJogoState extends State<FilaHojeHaJogo> {
  @override
  void initState() {
    super.initState();
    widget.servico.addListener(_mudou);
    widget.preferencias.addListener(_mudou);
  }

  @override
  void dispose() {
    widget.servico.removeListener(_mudou);
    widget.preferencias.removeListener(_mudou);
    super.dispose();
  }

  void _mudou() {
    if (mounted) setState(() {});
  }

  Future<void> _ver(JogoComCanais j) async {
    final fontes = fontesDoJogo(j, widget.fontes, widget.preferencias);
    if (fontes.isEmpty) {
      mostrarMensagem(context, tr('Nenhuma das tuas listas tem os canais deste jogo'));
      return;
    }
    await widget.abrir(context, fontes, aoFuncionar: (f) {
      final c = f.canalTv;
      if (c != null) widget.preferencias.registarFuncionou(c, f.lista.id, f.canal.id, DateTime.now().toUtc());
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = (widget.agora ?? DateTime.now)().toLocal();
    final favoritas = widget.preferencias.equipasFavoritas;
    final jogos = favoritas.isEmpty
        ? const <JogoComCanais>[]
        : [
            for (final j in widget.servico.jogos(FiltroJogos(DateTime(a.year, a.month, a.day))))
              if (j.jogo.estado != EstadoJogo.terminado &&
                  favoritas.any((e) => mesmaEquipa(e, j.jogo.casa) || mesmaEquipa(e, j.jogo.fora)))
                j,
          ];
    if (jogos.isEmpty) return const SizedBox.shrink();
    final tv = ecraTv(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e24, Tokens.e16, Tokens.e24, Tokens.e8),
        child: Text(tr('Hoje há jogo · {0}', [jogos.length]),
            style: TextStyle(
                fontFamily: Tokens.letraTitulos, color: Tokens.texto, fontSize: tv ? 20 : 17, fontWeight: FontWeight.w700)),
      ),
      SizedBox(
        // com margem para o cartão focado crescer; cresce com a letra do sistema
        height: (tv ? 104 : 92) * fatorTexto(context) + 16,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.e24, vertical: Tokens.e8),
          itemCount: jogos.length,
          separatorBuilder: (_, _) => const SizedBox(width: Tokens.e12),
          itemBuilder: (_, i) {
            final j = jogos[i];
            final tam = tv ? 15.5 : 14.0;
            return SizedBox(
              width: tv ? 340 : 300,
              child: letraPresa(CartaoModerno(
                destaque: true,
                onTap: () => unawaited(_ver(j)),
                padding: EdgeInsets.symmetric(horizontal: Tokens.e12, vertical: tv ? 12 : 10),
                child: Row(children: [
                  SizedBox(width: tv ? 64 : 56, child: HoraJogo(j.jogo)),
                  const SizedBox(width: Tokens.e8),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      EquipaJogo(nome: j.jogo.casa, emblema: j.jogo.emblemaCasa, tamanho: tam),
                      const SizedBox(height: 2),
                      EquipaJogo(nome: j.jogo.fora, emblema: j.jogo.emblemaFora, tamanho: tam),
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.play_arrow_rounded, size: tv ? 18 : 16, color: Tokens.anelFoco),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(nomeCanalTv(j.canais.first.canal),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Tokens.texto2, fontSize: tv ? 13.5 : 12.5)),
                        ),
                      ]),
                    ]),
                  ),
                ]),
              )),
            );
          },
        ),
      ),
    ]);
  }
}
