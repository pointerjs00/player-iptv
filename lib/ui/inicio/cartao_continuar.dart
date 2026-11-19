import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../design/design.dart';

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
    final tv = ecraTv(context);
    final logo = tv ? 40.0 : 34.0;
    final vazio = Text(_iniciais(visto.nome),
        style: TextStyle(color: Colors.white, fontSize: logo * .36, fontWeight: FontWeight.w800));
    final detalhe = [if (numero != null) 'Canal $numero', if (visto.grupo.isNotEmpty) visto.grupo].join(' · ');
    return letraPresa(Semantics(
      button: true,
      label: 'Continuar a ver ${visto.nome}, ${lista.nomeMostrado}',
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
              Text('CONTINUAR A VER · lista ${lista.nomeMostrado}',
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
              Text('Ver', style: TextStyle(color: Colors.white, fontSize: tv ? 15 : 13.5, fontWeight: FontWeight.w700)),
            ]),
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
