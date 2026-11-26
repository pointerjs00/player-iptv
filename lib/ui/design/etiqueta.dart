import 'package:material_ui/material_ui.dart';

import 'ecra.dart';
import 'tokens.dart';

/// O tom de uma [Etiqueta]: neutra (vidro), de acento (azul) ou de destaque (só a borda azul).
enum TomEtiqueta { neutro, acento, contorno }

/// Uma pílula pequena de informação («Canal 289», «STALKER», «4676 canais»): ícone opcional e
/// um texto numa só linha, que se corta com reticências quando não cabe.
class Etiqueta extends StatelessWidget {
  const Etiqueta({super.key, this.icone, this.texto, this.valor, this.tom = TomEtiqueta.neutro, this.maiusculas = false});

  final IconData? icone;

  /// O texto (com [valor], vai depois do número, mais apagado: «4676 canais»).
  final String? texto;

  /// Um número em destaque à frente do [texto].
  final String? valor;
  final TomEtiqueta tom;

  /// Em maiúsculas pequenas e espaçadas (o tipo da lista).
  final bool maiusculas;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final tam = maiusculas ? (tv ? 11.5 : 10.5) : (tv ? 13.0 : 12.0);
    final (fundo, borda, cor) = switch (tom) {
      TomEtiqueta.acento => (Tokens.acento.withValues(alpha: .18), Tokens.acento.withValues(alpha: .45), Tokens.anelFoco),
      TomEtiqueta.contorno => (Colors.transparent, Tokens.acento.withValues(alpha: .5), Tokens.texto),
      TomEtiqueta.neutro => (Tokens.vidroForte, Tokens.bordaVidro, Tokens.texto2),
    };
    final v = valor, t = texto ?? '';
    final estilo = TextStyle(
      color: cor,
      fontSize: tam,
      fontWeight: maiusculas ? FontWeight.w800 : FontWeight.w500,
      letterSpacing: maiusculas ? 1.2 : null,
      height: 1.2,
    );
    final rotulo = v == null
        ? Text(maiusculas ? t.toUpperCase() : t, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: estilo)
        : Text.rich(
            TextSpan(children: [
              TextSpan(text: v, style: const TextStyle(color: Tokens.texto, fontWeight: FontWeight.w700)),
              if (t.isNotEmpty) TextSpan(text: ' $t'),
            ]),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: estilo);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: tv ? 9 : 8, vertical: tv ? 3 : 2.5),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(Tokens.raioPilula),
        border: Border.all(color: borda),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icone != null) ...[
          Icon(icone, size: tam + 2, color: tom == TomEtiqueta.neutro ? Tokens.texto2 : Tokens.anelFoco),
          const SizedBox(width: 4),
        ],
        Flexible(child: rotulo),
      ]),
    );
  }
}
