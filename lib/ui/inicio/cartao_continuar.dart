import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../design/design.dart';

/// "Continuar a ver": o último canal visto, com a lista, em destaque no topo do Player. OK (ou
/// toque) abre o player logo nesse canal.
class CartaoContinuar extends StatelessWidget {
  const CartaoContinuar({super.key, required this.visto, required this.lista, required this.aoAbrir,
      this.autofocus = false});

  final UltimoVisto visto;
  final Lista lista;
  final VoidCallback aoAbrir;
  final bool autofocus;

  static double altura(bool tv) => tv ? 132 : 108;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final logo = tv ? 76.0 : 60.0;
    final vazio = Icon(Icons.live_tv_rounded, color: Colors.white, size: logo * .5);
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
            decoration: BoxDecoration(
              gradient: Tokens.gradienteAcento,
              borderRadius: BorderRadius.circular(logo * .26),
              boxShadow: const [BoxShadow(color: Color(0x406C7BFF), blurRadius: 16, offset: Offset(0, 6))],
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
              Text('Continuar a ver',
                  style: TextStyle(
                      color: Tokens.acento, fontSize: tv ? 15 : 12.5, fontWeight: FontWeight.w700, letterSpacing: .4)),
              const SizedBox(height: 2),
              Text(visto.nome, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: tv ? 26 : 20, fontWeight: FontWeight.w700)),
              Text(
                [if (visto.grupo.isNotEmpty) visto.grupo, lista.nomeMostrado].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Tokens.texto2, fontSize: tv ? 16 : 13),
              ),
            ]),
          ),
          const SizedBox(width: Tokens.e12),
          Container(
            width: tv ? 56 : 44,
            height: tv ? 56 : 44,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tokens.gradienteAcento),
            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: tv ? 34 : 28),
          ),
        ]),
      ),
    );
  }
}
