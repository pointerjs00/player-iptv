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

  static double altura(bool tv) => tv ? 132 : 108;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final logo = tv ? 76.0 : 60.0;
    final vazio = Text(_iniciais(visto.nome),
        style: TextStyle(color: Colors.white, fontSize: logo * .34, fontWeight: FontWeight.w800));
    final detalhe = [if (numero != null) 'Canal $numero', if (visto.grupo.isNotEmpty) visto.grupo].join(' · ');
    return Semantics(
      button: true,
      label: 'Continuar a ver ${visto.nome}, ${lista.nomeMostrado}',
      excludeSemantics: true,
      child: CartaoModerno(
        key: const Key('continuar-a-ver'),
        autofocus: autofocus,
        onTap: aoAbrir,
        escalaFoco: 1.02,
        padding: EdgeInsets.all(tv ? 18 : 14),
        child: Row(children: [
          Container(
            width: logo,
            height: logo,
            padding: const EdgeInsets.all(6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: Tokens.gradienteAcento,
              borderRadius: BorderRadius.circular(logo * .26),
              boxShadow: [BoxShadow(color: Tokens.acento.withValues(alpha: .25), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: visto.logo.startsWith('http')
                ? Image.network(visto.logo, fit: BoxFit.contain, errorBuilder: (_, _, _) => vazio,
                    cacheWidth: (logo * MediaQuery.devicePixelRatioOf(context)).round())
                : vazio,
          ),
          SizedBox(width: tv ? Tokens.e24 : Tokens.e16),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('CONTINUAR A VER · lista ${lista.nomeMostrado}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Tokens.acento, fontSize: tv ? 15 : 12.5, fontWeight: FontWeight.w700, letterSpacing: .4)),
              const SizedBox(height: 2),
              Text(visto.nome, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: tv ? 26 : 20, fontWeight: FontWeight.w700)),
              if (detalhe.isNotEmpty)
                Text(detalhe,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Tokens.texto2, fontSize: tv ? 16 : 13)),
            ]),
          ),
          const SizedBox(width: Tokens.e12),
          // o botão "Ver" é só visual: o foco é do cartão (uma só paragem)
          Container(
            padding: EdgeInsets.symmetric(horizontal: tv ? 24 : 18, vertical: tv ? 12 : 9),
            decoration: BoxDecoration(
              gradient: Tokens.gradienteAcento,
              borderRadius: BorderRadius.circular(Tokens.raioBotao),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.play_arrow_rounded, color: Colors.white, size: tv ? 26 : 22),
              const SizedBox(width: 4),
              Text('Ver', style: TextStyle(color: Colors.white, fontSize: tv ? 18 : 15, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// As iniciais do canal (até duas letras/dígitos) para o bloco sem logótipo.
String _iniciais(String nome) {
  final p = nome.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  final r = p.length == 1 ? p.first.substring(0, p.first.length.clamp(0, 2)) : '${p[0][0]}${p[1][0]}';
  return r.toUpperCase();
}
