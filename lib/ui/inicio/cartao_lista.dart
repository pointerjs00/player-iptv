import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../modelo/conta.dart';
import '../design/design.dart';
import '../tema.dart';
import 'favoritos_inicio.dart';
import '../../idioma/idioma.dart';

/// Cartão de uma lista no Player: ícone do tipo, nome, servidor, pílula do último resultado,
/// validade e motivo (a verificação faz-se no Gestor). Com o foco do comando cresce e brilha
/// (ver [CartaoModerno]). O menu de ações ([aoMenu]) abre com a pressão longa (toque longo,
/// clique direito, OK mantido) e, no telemóvel, também com o ⋮ «Opções da lista» (48 dp). Fora
/// do telemóvel o cartão não tem botões de dentro: é uma só paragem do foco.
/// Na grelha ([emGrelha]) tem a altura fixa [altura]; fora dela (o telemóvel, uma lista por
/// linha) tem a altura do que mostra e o detalhe da pílula nunca se corta.
class CartaoLista extends StatelessWidget {
  const CartaoLista({super.key, required this.lista, required this.aoAbrir, this.aoMenu, this.autofocus = false,
      this.focusNode, this.resumo, this.emGrelha = true});

  final Lista lista;
  final VoidCallback aoAbrir;
  final VoidCallback? aoMenu;
  final bool autofocus;
  final FocusNode? focusNode;

  /// As contagens da cache de canais (null = a lista não tem cache: não se mostram).
  final ResumoLista? resumo;

  /// Numa grelha de altura fixa (senão, com a altura do conteúdo).
  final bool emGrelha;

  static const _tipos = {Tipo.stalker: 'Stalker', Tipo.xtream: 'Xtream', Tipo.m3u: 'M3U'};
  static const _icones = {
    Tipo.stalker: Icons.settings_input_antenna,
    Tipo.xtream: Icons.dns_outlined,
    Tipo.m3u: Icons.playlist_play_rounded,
  };

  /// A altura do cartão na grelha (maior na TV); sem botões em baixo (verificar é no Gestor).
  /// Baixo: o nome e "tipo · servidor · contagens" ao lado do ícone, a pílula e a validade (na
  /// mesma linha quando cabem; senão a validade passa para baixo) e, quando a lista não
  /// funciona, o motivo. Cresce com a letra do sistema ([fator], de [fatorTexto]).
  static double altura(bool tv, [double fator = 1]) => (tv ? 180 : 164) * fator;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final telemovel = ecraTelemovel(context);
    final u = lista.ultima;
    final validade = textoValidade(u?.validade ?? '');
    final secundario = TextStyle(color: Tokens.texto2, fontSize: tv ? 13 : 12);
    return letraPresa(CartaoModerno(
      autofocus: autofocus,
      focusNode: focusNode,
      onTap: aoAbrir,
      onLongPress: aoMenu,
      // as favoritas em destaque (e à frente das outras: ver ordenarListas)
      destaque: lista.favorita,
      padding: EdgeInsets.symmetric(horizontal: tv ? 14 : Tokens.e12, vertical: Tokens.e12),
      child: _comMarcaDagua(emGrelha, lista.ordem, tv, Column(
        mainAxisSize: emGrelha ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _IconeTipo(_icones[lista.conta.tipo]!, tamanho: tv ? 34 : 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(lista.nomeMostrado, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: tv ? 17 : 15, fontWeight: FontWeight.w700)),
                  ),
                  // a estrela das listas favoritas (no canto de cima, à direita)
                  if (lista.favorita)
                    Padding(
                      padding: const EdgeInsets.only(left: Tokens.e4),
                      child: Icon(Icons.star_rounded, key: const Key('lista-favorita'),
                          color: Tokens.aviso, size: tv ? 22 : 18, semanticLabel: tr('Favorita')),
                    ),
                ]),
                // o tipo e o servidor (as contagens vão nas etiquetas por baixo)
                const SizedBox(height: 2),
                Row(children: [
                  Etiqueta(
                      key: const Key('lista-tipo'), texto: _tipos[lista.conta.tipo], tom: TomEtiqueta.acento, maiusculas: true),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(hostDe(lista.conta.endereco),
                        key: const Key('lista-servidor'),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: secundario),
                  ),
                ]),
              ]),
            ),
            // no telemóvel o menu também se abre com um ⋮ à vista (a pressão longa não se adivinha)
            if (telemovel && aoMenu != null)
              IconButton(
                onPressed: aoMenu,
                tooltip: tr('Opções da lista'),
                icon: const Icon(Icons.more_vert),
                color: Tokens.texto2,
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
          ]),
          SizedBox(height: tv ? 6 : 5),
          // as contagens da cache (quando há)
          if (resumo != null)
            Row(children: [
              Flexible(
                child: Etiqueta(
                    key: const Key('lista-canais'),
                    icone: Icons.live_tv_rounded,
                    valor: '${resumo!.canais}',
                    texto: tr('canais')),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Etiqueta(
                    key: const Key('lista-grupos'),
                    icone: Icons.folder_outlined,
                    valor: '${resumo!.grupos}',
                    texto: tr('grupos')),
              ),
            ])
          else
            SizedBox(height: tv ? 24 : 22),
          if (emGrelha) const Spacer() else const SizedBox(height: Tokens.e8),
          // a pílula e a validade na mesma linha quando cabem; senão a validade vai para baixo
          Wrap(spacing: Tokens.e8, runSpacing: Tokens.e4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            PilulaEstado(estadoDe(lista),
                detalhe: u == null ? null : verificadaHa(u.data), linhasDetalhe: emGrelha ? 1 : null, discreta: true),
            if (validade.isNotEmpty)
              Etiqueta(key: const Key('lista-validade'), icone: Icons.event_outlined, texto: validade),
          ]),
          if (u != null && u.motivo.isNotEmpty && u.estado != 'funciona')
            Padding(
              padding: const EdgeInsets.only(top: Tokens.e4),
              child: Text(u.motivo, maxLines: 1, overflow: TextOverflow.ellipsis, style: secundario),
            ),
        ],
      )),
    ));
  }
}

/// Na grelha: o número de ordem da lista ("007") em grande e quase transparente no canto de
/// baixo, por trás do conteúdo. É só decoração: RichText (não Text) e sem semântica, para não
/// entrar no que se lê nem no texto do cartão com o foco.
Widget _comMarcaDagua(bool emGrelha, int ordem, bool tv, Widget conteudo) {
  if (!emGrelha) return conteudo;
  return Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
    Positioned(
      right: -4,
      bottom: tv ? -26 : -22,
      child: ExcludeSemantics(
        child: RichText(
          key: const Key('marca-dagua-lista'),
          text: TextSpan(
            text: ordem.toString().padLeft(3, '0'),
            style: TextStyle(
              fontFamily: Tokens.letraTitulos,
              fontSize: tv ? 84 : 72,
              fontWeight: FontWeight.w800,
              letterSpacing: -4,
              height: 1,
              color: Tokens.anelFoco.withValues(alpha: .07),
            ),
          ),
        ),
      ),
    ),
    conteudo,
  ]);
}

/// "verificada há 2 h", "verificada há 3 dias"... (para o detalhe da [PilulaEstado]).
String verificadaHa(DateTime d, [DateTime? agora]) {
  final dif = (agora ?? DateTime.now()).difference(d);
  if (dif.inMinutes < 1) return tr('verificada agora');
  if (dif.inMinutes < 60) return tr('verificada há {0} min', [dif.inMinutes]);
  if (dif.inHours < 24) return tr('verificada há {0} h', [dif.inHours]);
  if (dif.inDays < 30) return tr('verificada há {0} {1}', [dif.inDays, dif.inDays == 1 ? tr('dia') : tr('dias')]);
  return tr('verificada em {0}/{1}/{2}', [d.day.toString().padLeft(2, '0'), d.month.toString().padLeft(2, '0'), d.year]);
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
          boxShadow: [BoxShadow(color: Tokens.acento.withValues(alpha: .25), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Icon(icone, color: Colors.white, size: tamanho * .52),
      );
}
