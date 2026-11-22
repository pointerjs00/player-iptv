import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../design/design.dart';
import '../../idioma/idioma.dart';

/// "Continuar a ver": o último canal visto, com a lista, em destaque no topo do Player. OK (ou
/// toque) abre o player logo nesse canal.
class CartaoContinuar extends StatelessWidget {
  const CartaoContinuar({super.key, required this.visto, required this.lista, required this.aoAbrir,
      this.numero, this.autofocus = false});

  final UltimoVisto visto;
  final Lista lista;
  final VoidCallback aoAbrir;
  final bool autofocus;

  /// O número do canal na lista (null = não se sabe: só se mostra o grupo).
  final int? numero;

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
    final detalhe = [if (numero != null) tr('Canal {0}', [numero]), if (visto.grupo.isNotEmpty) visto.grupo].join(' · ');
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
              gradient: Tokens.gradienteAcento,
              borderRadius: BorderRadius.circular(logo * .26),
            ),
            child: visto.logo.startsWith('http')
                ? Image.network(visto.logo, fit: BoxFit.contain, errorBuilder: (_, _, _) => vazio,
                    cacheWidth: (logo * MediaQuery.devicePixelRatioOf(context)).round())
                : vazio,
          ),
          SizedBox(width: tv ? Tokens.e16 : Tokens.e12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(tr('CONTINUAR A VER · lista {0}', [lista.nomeMostrado]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Tokens.acento, fontSize: tv ? 12.5 : 11, fontWeight: FontWeight.w700, letterSpacing: .4)),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Flexible(
                  child: Text(visto.nome, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: tv ? 18 : 15.5, fontWeight: FontWeight.w700)),
                ),
                if (detalhe.isNotEmpty) ...[
                  const SizedBox(width: Tokens.e12),
                  Flexible(
                    child: Text(detalhe,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Tokens.texto2, fontSize: tv ? 14 : 12.5)),
                  ),
                ],
              ]),
            ]),
          ),
          const SizedBox(width: Tokens.e12),
          // o botão "Ver" é só visual: o foco é do cartão (uma só paragem)
          Container(
            padding: EdgeInsets.symmetric(horizontal: tv ? 16 : 14, vertical: tv ? 6 : 5),
            decoration: BoxDecoration(
              gradient: Tokens.gradienteAcento,
              borderRadius: BorderRadius.circular(Tokens.raioBotao),
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
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tokens.gradienteAcento),
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
