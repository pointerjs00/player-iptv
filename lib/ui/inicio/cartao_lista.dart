import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../modelo/conta.dart';
import '../design/design.dart';
import '../tema.dart';

/// Cartão de uma lista no Player: ícone do tipo, nome, servidor, pílula do último resultado,
/// validade e motivo (a verificação faz-se no Gestor). Com o foco do comando cresce e brilha
/// (ver [CartaoModerno]). O menu de ações ([aoMenu]) abre com a pressão longa (toque longo,
/// clique direito, OK mantido). O cartão não tem botões de dentro: é uma só paragem do foco.
class CartaoLista extends StatelessWidget {
  const CartaoLista({super.key, required this.lista, required this.aoAbrir, this.aoMenu, this.autofocus = false,
      this.focusNode});

  final Lista lista;
  final VoidCallback aoAbrir;
  final VoidCallback? aoMenu;
  final bool autofocus;
  final FocusNode? focusNode;

  static const _tipos = {Tipo.stalker: 'Stalker', Tipo.xtream: 'Xtream', Tipo.m3u: 'M3U'};
  static const _icones = {
    Tipo.stalker: Icons.settings_input_antenna,
    Tipo.xtream: Icons.dns_outlined,
    Tipo.m3u: Icons.playlist_play_rounded,
  };

  /// A altura do cartão na grelha (maior na TV); sem botões em baixo (verificar é no Gestor).
  static double altura(bool tv) => tv ? 216 : 188;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final u = lista.ultima;
    final validade = textoValidade(u?.validade ?? '');
    final secundario = TextStyle(color: Tokens.texto2, fontSize: tv ? 14 : 12.5);
    return CartaoModerno(
      autofocus: autofocus,
      focusNode: focusNode,
      onTap: aoAbrir,
      onLongPress: aoMenu,
      padding: EdgeInsets.all(tv ? 18 : Tokens.e16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _IconeTipo(_icones[lista.conta.tipo]!, tamanho: tv ? 48 : 40),
            const SizedBox(width: Tokens.e12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lista.nomeMostrado, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: tv ? 19 : 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${_tipos[lista.conta.tipo]} · ${hostDe(lista.conta.endereco)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: secundario),
              ]),
            ),
          ]),
          const Spacer(),
          Wrap(spacing: Tokens.e8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            PilulaEstado(estadoDe(lista)),
            if (validade.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Tokens.vidroForte,
                  borderRadius: BorderRadius.circular(Tokens.raioPilula),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.event_outlined, size: tv ? 16 : 14, color: Tokens.texto2),
                  const SizedBox(width: 5),
                  Text(validade, style: TextStyle(fontSize: tv ? 14 : 12.5)),
                ]),
              ),
            if (u != null) Text(dataRelativa(u.data), style: secundario),
          ]),
          if (u != null && u.motivo.isNotEmpty && u.estado != 'funciona')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(u.motivo, maxLines: 1, overflow: TextOverflow.ellipsis, style: secundario),
            ),
          const SizedBox(height: Tokens.e4),
        ],
      ),
    );
  }
}

/// O ícone do tipo de lista num quadrado com o gradiente de acento.
class _IconeTipo extends StatelessWidget {
  const _IconeTipo(this.icone, {required this.tamanho});
  final IconData icone;
  final double tamanho;

  @override
  Widget build(BuildContext context) => Container(
        width: tamanho,
        height: tamanho,
        decoration: BoxDecoration(
          gradient: Tokens.gradienteAcento,
          borderRadius: BorderRadius.circular(tamanho * .3),
          boxShadow: const [BoxShadow(color: Color(0x406C7BFF), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Icon(icone, color: Colors.white, size: tamanho * .52),
      );
}
