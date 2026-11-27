import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../desporto/catalogo.dart';
import '../../desporto/hora_lisboa.dart';
import '../../desporto/modelo.dart';
import '../../desporto/onde_ver.dart';
import '../../desporto/preferencias_jogos.dart';
import '../../desporto/servico_jogos.dart';
import '../../idioma/idioma.dart';
import '../design/design.dart';

/// "20:45" em Lisboa.
String horaLisboa(DateTime utc) {
  final l = utcParaLisboa(utc);
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String nomeCanalTv(String id) => canalPorId(id)?.nome ?? id;

String nomeConfianca(Confianca c) => switch (c) {
      Confianca.confirmado => tr('Confirmado'),
      Confianca.provavel => tr('Provável'),
      Confianca.possivel => tr('Possível'),
    };

IconData iconeConfianca(Confianca c) => switch (c) {
      Confianca.confirmado => Icons.check_circle_rounded,
      Confianca.provavel => Icons.schedule_rounded,
      Confianca.possivel => Icons.help_outline_rounded,
    };

/// A competição e a ronda («Liga Portugal Betclic · Jornada 12»); sem a competição dentro do
/// bloco dela.
String legendaJogo(JogoComCanais j, {bool comCompeticao = true}) {
  final c = comCompeticao ? j.competicao?.nome ?? '' : '';
  final r = j.jogo.ronda;
  if (r == null || r.isEmpty) return c;
  final ronda = int.tryParse(r) != null ? tr('Jornada {0}', [r]) : r;
  return c.isEmpty ? ronda : '$c · $ronda';
}

/// As fontes de um canal, pela ordem em que se experimentam (spec §8).
List<FonteCanal> fontesDoCanal(String canalTv, FontesDosCanais fontes, PreferenciasJogos prefs) =>
    ordenarFontes(fontes.fontes(canalTv), ultima: prefs.ultimaFonte(canalTv), preferida: prefs.qualidade);

/// «▶ Ver» de um jogo: as fontes de todos os canais dele, o canal mais seguro primeiro.
List<FonteCanal> fontesDoJogo(JogoComCanais j, FontesDosCanais fontes, PreferenciasJogos prefs) => [
      for (final t in j.canais) ...fontesDoCanal(t.canal, fontes, prefs),
    ];

/// A hora, ou o estado do jogo («● AO VIVO 67'», «Terminado»).
class HoraJogo extends StatelessWidget {
  const HoraJogo(this.jogo, {super.key, this.grande = false});
  final Jogo jogo;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final tam = grande ? 22.0 : (ecraTv(context) ? 17.0 : 15.0);
    final pequeno = TextStyle(fontSize: tam * .62, fontWeight: FontWeight.w700, color: Tokens.texto2);
    // numa só linha e encolhe se não cabe (a letra grande do telemóvel cortava «● AO VIVO»)
    Widget linha(String t, TextStyle s) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(t, maxLines: 1, softWrap: false, style: s),
        );
    final hora = TextStyle(fontFamily: Tokens.letraTitulos, fontSize: tam, fontWeight: FontWeight.w700, color: Tokens.texto);
    return switch (jogo.estado) {
      EstadoJogo.aoVivo || EstadoJogo.intervalo => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          linha(tr('● AO VIVO'), pequeno.copyWith(color: Tokens.mau, letterSpacing: .6)),
          linha(jogo.estado == EstadoJogo.intervalo ? tr('Intervalo') : (jogo.minuto ?? ''), hora.copyWith(color: Tokens.mau)),
        ]),
      EstadoJogo.terminado => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          linha(tr('Terminado'), pequeno),
          linha(horaLisboa(jogo.inicio), hora.copyWith(color: Tokens.texto2)),
        ]),
      EstadoJogo.adiado => linha(tr('Adiado'), pequeno.copyWith(color: Tokens.aviso)),
      EstadoJogo.cancelado => linha(tr('Cancelado'), pequeno.copyWith(color: Tokens.aviso)),
      EstadoJogo.agendado => linha(horaLisboa(jogo.inicio), hora),
    };
  }
}

/// Uma equipa: o emblema, o nome e os golos.
class EquipaJogo extends StatelessWidget {
  const EquipaJogo({super.key, required this.nome, this.emblema, this.golos, this.tamanho = 15});
  final String nome;
  final String? emblema;
  final String? golos;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final e = emblema;
    final lado = tamanho * 1.25;
    return Row(children: [
      SizedBox(
        width: lado,
        height: lado,
        child: e == null
            ? const Icon(Icons.shield_outlined, size: 14, color: Tokens.texto2)
            : Image.network(e,
                width: lado,
                height: lado,
                errorBuilder: (_, _, _) => const Icon(Icons.shield_outlined, size: 14, color: Tokens.texto2)),
      ),
      const SizedBox(width: Tokens.e8),
      Expanded(
        child: Text(nome,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: tamanho, fontWeight: FontWeight.w600, color: Tokens.texto)),
      ),
      if (golos != null) ...[
        const SizedBox(width: Tokens.e8),
        Text(golos!, style: TextStyle(fontFamily: Tokens.letraTitulos, fontSize: tamanho, fontWeight: FontWeight.w700)),
      ],
    ]);
  }
}

/// Os golos de cada lado de «2–1».
(String?, String?) golosDe(Jogo j) {
  final r = j.resultado;
  if (r == null) return (null, null);
  final p = r.split(RegExp('[–-]'));
  return p.length == 2 ? (p[0].trim(), p[1].trim()) : (null, null);
}

/// A etiqueta de um canal, com a marca da confiança.
class EtiquetaCanal extends StatelessWidget {
  const EtiquetaCanal(this.t, {super.key, this.escolhida = false, this.aoTocar});
  final Transmissao t;
  final bool escolhida;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final e = Etiqueta(
      icone: iconeConfianca(t.confianca),
      texto: nomeCanalTv(t.canal),
      tom: escolhida ? TomEtiqueta.acento : TomEtiqueta.neutro,
    );
    return Tooltip(
      message: nomeConfianca(t.confianca),
      child: aoTocar == null ? e : GestureDetector(onTap: aoTocar, child: e),
    );
  }
}

/// Um jogo na lista: uma só paragem do foco. ←/→ escolhem a etiqueta de canal, OK abre o «Onde
/// ver» dela e OK mantido faz «▶ Ver» (todas as fontes do jogo). No telemóvel, tocar abre o
/// detalhe.
class LinhaJogo extends StatefulWidget {
  const LinhaJogo({
    super.key,
    required this.item,
    required this.aoOndeVer,
    required this.aoVer,
    required this.aoDetalhe,
    this.focusNode,
    this.aoFocar,
    this.destaque = false,
    this.mostrarCompeticao = true,
    this.autofocus = false,
  });

  /// O foco começa nesta linha (o primeiro jogo de um ecrã).
  final bool autofocus;

  /// O nome da competição na legenda (não, quando os jogos estão agrupados por ela).
  final bool mostrarCompeticao;

  /// Joga uma equipa favorita (o cartão fica em destaque).
  final bool destaque;

  final JogoComCanais item;

  /// O «Onde ver» do canal `canal` (o id do catálogo).
  final ValueChanged<String> aoOndeVer;
  final VoidCallback aoVer;
  final VoidCallback aoDetalhe;
  final FocusNode? focusNode;

  /// O foco entrou nesta linha (a coluna à direita mostra este jogo).
  final VoidCallback? aoFocar;

  @override
  State<LinhaJogo> createState() => LinhaJogoState();
}

class LinhaJogoState extends State<LinhaJogo> {
  int _etiqueta = 0;
  bool _focada = false;

  /// A etiqueta de canal escolhida (para os testes).
  int get etiqueta => _etiqueta;

  List<Transmissao> get _canais => widget.item.canais;

  /// ESQUERDA na 1.ª etiqueta segue (vai à barra das secções); DIREITA na última também segue
  /// (vai à coluna do jogo, à direita, nos ecrãs largos).
  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft && _etiqueta > 0) {
      setState(() => _etiqueta--);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight && _etiqueta < _canais.length - 1) {
      setState(() => _etiqueta++);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _ok() {
    if (ecraTelemovel(context) || _canais.isEmpty) {
      widget.aoDetalhe();
    } else {
      widget.aoOndeVer(_canais[_etiqueta.clamp(0, _canais.length - 1)].canal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.item.jogo;
    final tv = ecraTv(context);
    final telemovel = ecraTelemovel(context);
    final (gc, gf) = golosDe(j);
    final tam = tv ? 16.0 : 15.0;
    final equipas = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      EquipaJogo(nome: j.casa, emblema: j.emblemaCasa, golos: gc, tamanho: tam),
      const SizedBox(height: 2),
      EquipaJogo(nome: j.fora, emblema: j.emblemaFora, golos: gf, tamanho: tam),
    ]);
    final legenda = Text(legendaJogo(widget.item, comCompeticao: widget.mostrarCompeticao),
        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Tokens.texto2));
    final etiquetas = Wrap(spacing: 6, runSpacing: 4, children: [
      for (final (i, t) in _canais.indexed)
        EtiquetaCanal(t, escolhida: _focada && i == _etiqueta, aoTocar: () => widget.aoOndeVer(t.canal)),
    ]);
    final conteudo = telemovel
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 64, child: HoraJogo(j)),
            const SizedBox(width: Tokens.e8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                equipas,
                const SizedBox(height: 4),
                legenda,
                if (_canais.isNotEmpty) ...[const SizedBox(height: 6), etiquetas],
              ]),
            ),
          ])
        : Row(children: [
            SizedBox(width: tv ? 84 : 76, child: HoraJogo(j)),
            const SizedBox(width: Tokens.e12),
            Expanded(flex: 5, child: equipas),
            const SizedBox(width: Tokens.e12),
            Expanded(flex: 3, child: legenda),
            const SizedBox(width: Tokens.e12),
            Expanded(flex: 5, child: _canais.isEmpty
                ? Text(tr('Ainda sem canal anunciado'), style: const TextStyle(fontSize: 12.5, color: Tokens.texto2))
                : etiquetas),
          ]);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: _tecla,
      onFocusChange: (f) {
        if (f != _focada) setState(() => _focada = f);
        if (f) widget.aoFocar?.call();
      },
      child: CartaoModerno(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        escalaFoco: 1.01,
        destaque: widget.destaque,
        padding: EdgeInsets.symmetric(horizontal: Tokens.e16, vertical: tv ? 10 : Tokens.e12),
        onTap: _ok,
        onLongPress: _canais.isEmpty ? null : widget.aoVer,
        child: conteudo,
      ),
    );
  }
}
