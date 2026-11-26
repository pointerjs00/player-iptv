import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../guia/programa.dart';
import '../design/design.dart';
import '../../idioma/idioma.dart';

/// "Continuar a ver": o último canal visto, com a lista, em destaque no topo do Player. OK (ou
/// toque) abre o player logo nesse canal.
class CartaoContinuar extends StatelessWidget {
  const CartaoContinuar({super.key, required this.visto, required this.lista, required this.aoAbrir,
      this.numero, this.autofocus = false, this.programa, this.agora});

  final UltimoVisto visto;
  final Lista lista;
  final VoidCallback aoAbrir;
  final bool autofocus;

  /// O número do canal na lista (null = não se sabe: só se mostra o grupo).
  final int? numero;

  /// O programa a dar (do guia guardado): «Agora: …» e a barra do progresso.
  final Programa? programa;

  /// O instante para o progresso do programa (por omissão, agora).
  final DateTime? agora;

  double _progresso() =>
      programa!.progresso((agora ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000);

  /// Uma faixa baixa: o logótipo pequeno, "CONTINUAR A VER · lista" por cima do canal (com o
  /// número e o grupo ao lado) e o botão "Ver". Cresce com a letra do sistema ([fator], de
  /// [fatorTexto]).
  static double altura(bool tv, [double fator = 1]) => (tv ? 68 : 60) * fator;

  @override
  Widget build(BuildContext context) {
    if (ecraTelemovel(context)) return _telemovel(context);
    final tv = ecraTv(context);
    final logo = tv ? 40.0 : 34.0;
    final vazio = Text(_iniciais(visto.nome),
        style: TextStyle(color: Colors.white, fontSize: logo * .36, fontWeight: FontWeight.w800));
    final p = programa;
    return letraPresa(Semantics(
      button: true,
      label: tr('Continuar a ver {0}, {1}', [visto.nome, lista.nomeMostrado]),
      excludeSemantics: true,
      child: CartaoModerno(
        key: const Key('continuar-a-ver'),
        autofocus: autofocus,
        onTap: aoAbrir,
        escalaFoco: 1.02,
        padding: EdgeInsets.symmetric(horizontal: tv ? 14 : 12, vertical: tv ? 8 : 7),
        child: Row(children: [
          Container(
            width: logo,
            height: logo,
            padding: const EdgeInsets.all(4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Tokens.superficie3,
              border: Border.all(color: Tokens.bordaCartao),
              borderRadius: BorderRadius.circular(logo * .26),
            ),
            child: visto.logo.startsWith('http')
                ? Image.network(visto.logo, fit: BoxFit.contain, errorBuilder: (_, _, _) => vazio,
                    cacheWidth: (logo * MediaQuery.devicePixelRatioOf(context)).round())
                : vazio,
          ),
          SizedBox(width: tv ? Tokens.e16 : Tokens.e12),
          // o canal: «CONTINUAR A VER» e a lista por cima; o nome e as etiquetas por baixo
          Expanded(
            flex: 5,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Text(tr('Continuar a ver').toUpperCase(),
                    maxLines: 1,
                    style: TextStyle(
                        color: Tokens.acento, fontSize: tv ? 11.5 : 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
                const SizedBox(width: Tokens.e8),
                Flexible(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.playlist_play_rounded, size: tv ? 15 : 13, color: Tokens.texto2),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(lista.nomeMostrado,
                          key: const Key('continuar-lista'),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Tokens.texto2, fontSize: tv ? 12.5 : 11.5, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Flexible(
                  flex: 3,
                  child: Text(visto.nome,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: Tokens.letraTitulos, fontSize: tv ? 18 : 15.5, fontWeight: FontWeight.w700)),
                ),
                if (numero != null) ...[
                  const SizedBox(width: Tokens.e8),
                  Etiqueta(key: const Key('continuar-numero'), texto: tr('Canal {0}', [numero]), tom: TomEtiqueta.acento),
                ],
                if (visto.grupo.isNotEmpty) ...[
                  const SizedBox(width: Tokens.e8),
                  Flexible(
                      flex: 2,
                      child: Etiqueta(key: const Key('continuar-grupo'), icone: Icons.folder_outlined, texto: visto.grupo)),
                ],
              ]),
            ]),
          ),
          // o programa a dar (do guia guardado), num bloco à parte com o progresso
          if (p != null) ...[
            Container(
              width: 1,
              height: tv ? 40 : 34,
              margin: EdgeInsets.symmetric(horizontal: tv ? Tokens.e16 : Tokens.e12),
              color: Tokens.bordaCartao,
            ),
            Expanded(flex: 3, child: _programa(p, tv)),
          ],
          const SizedBox(width: Tokens.e12),
          // o botão "Ver" é só visual: o foco é do cartão (uma só paragem)
          Container(
            padding: EdgeInsets.symmetric(horizontal: tv ? 16 : 14, vertical: tv ? 6 : 5),
            decoration: BoxDecoration(
              gradient: Tokens.gradienteAcento,
              borderRadius: BorderRadius.circular(Tokens.raioPilula),
              // o brilho azul elétrico do botão principal
              boxShadow: [BoxShadow(color: Tokens.acento.withValues(alpha: .55), blurRadius: 18)],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.play_arrow_rounded, color: Colors.white, size: tv ? 20 : 18),
              const SizedBox(width: 4),
              Text(tr('Ver'), style: TextStyle(color: Colors.white, fontSize: tv ? 15 : 13.5, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    ));
  }

  /// «● AGORA · faltam 25 min», o título e a barra do progresso.
  Widget _programa(Programa p, bool tv) {
    final agora = (this.agora ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final faltam = ((p.fim - agora) / 60).ceil();
    return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Tokens.mau,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Tokens.mau.withValues(alpha: .7), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 5),
        Text(tr('AGORA'),
            style: TextStyle(color: Tokens.mau, fontSize: tv ? 11 : 10, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
        if (faltam > 0) ...[
          const SizedBox(width: Tokens.e8),
          Flexible(
            child: Text(tr('faltam {0} min', [faltam]),
                key: const Key('continuar-faltam'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Tokens.texto2, fontSize: tv ? 11.5 : 10.5)),
          ),
        ],
      ]),
      const SizedBox(height: 2),
      Text(p.titulo,
          key: const Key('continuar-programa'),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Tokens.texto, fontSize: tv ? 14 : 12.5, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(Tokens.raioPilula),
        child: LinearProgressIndicator(
          key: const Key('continuar-progresso'),
          value: _progresso(),
          minHeight: 3,
          color: Tokens.acento,
          backgroundColor: Tokens.vidroForte,
        ),
      ),
    ]);
  }

  /// No telemóvel (ao alto) o cartão cresce com o que mostra: «Continuar a ver» em cima, o canal
  /// inteiro (até 2 linhas) numa linha própria, «lista · canal · grupo» em baixo e só um ▶ (o
  /// cartão todo é o toque).
  Widget _telemovel(BuildContext context) {
    const logo = 40.0;
    final vazio = Text(_iniciais(visto.nome),
        style: TextStyle(color: Colors.white, fontSize: logo * .36, fontWeight: FontWeight.w800));
    final detalhe = [
      lista.nomeMostrado,
      if (numero != null) tr('Canal {0}', [numero]),
      if (visto.grupo.isNotEmpty) visto.grupo,
    ].join(' · ');
    return letraPresa(Semantics(
      container: true,
      button: true,
      label: tr('Continuar a ver {0}, {1}', [visto.nome, lista.nomeMostrado]),
      child: CartaoModerno(
        key: const Key('continuar-a-ver'),
        autofocus: autofocus,
        onTap: aoAbrir,
        escalaFoco: 1.02,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.e12, vertical: Tokens.e12),
        child: Row(children: [
          Expanded(
            child: ExcludeSemantics(
              child: Row(children: [
                Container(
                  width: logo,
                  height: logo,
                  padding: const EdgeInsets.all(4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: Tokens.gradienteAcento,
                    borderRadius: BorderRadius.circular(logo * .26),
                  ),
                  child: visto.logo.startsWith('http')
                      ? Image.network(visto.logo, fit: BoxFit.contain, errorBuilder: (_, _, _) => vazio,
                          cacheWidth: (logo * MediaQuery.devicePixelRatioOf(context)).round())
                      : vazio,
                ),
                const SizedBox(width: Tokens.e12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Continuar a ver'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Tokens.acento, fontSize: 12, fontWeight: FontWeight.w700)),
                    Text(visto.nome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                    if (detalhe.isNotEmpty)
                      Text(detalhe,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Tokens.texto2, fontSize: 12.5)),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(width: Tokens.e12),
          // só visual (o toque é do cartão), mas lido como «Ver»
          Semantics(
            container: true,
            label: tr('Ver'),
            excludeSemantics: true,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: Tokens.gradienteAcento,
                boxShadow: [BoxShadow(color: Tokens.acento.withValues(alpha: .55), blurRadius: 16)],
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
            ),
          ),
        ]),
      ),
    ));
  }
}

/// As iniciais do canal (até duas letras/dígitos) para o bloco sem logótipo.
String _iniciais(String nome) {
  final p = nome.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  final r = p.length == 1 ? p.first.substring(0, p.first.length.clamp(0, 2)) : '${p[0][0]}${p[1][0]}';
  return r.toUpperCase();
}
