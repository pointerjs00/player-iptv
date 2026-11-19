import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../modelo/conta.dart';
import '../design/design.dart';
import '../tema.dart';
import 'favoritos_inicio.dart';

/// Cartão de uma lista no Player: ícone do tipo, nome, servidor, pílula do último resultado,
/// validade e motivo (a verificação faz-se no Gestor). Com o foco do comando cresce e brilha
/// (ver [CartaoModerno]). O menu de ações ([aoMenu]) abre com a pressão longa (toque longo,
/// clique direito, OK mantido). O cartão não tem botões de dentro: é uma só paragem do foco.
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
  static double altura(bool tv, [double fator = 1]) => (tv ? 154 : 140) * fator;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final u = lista.ultima;
    final validade = textoValidade(u?.validade ?? '');
    final secundario = TextStyle(color: Tokens.texto2, fontSize: tv ? 13 : 12);
    return letraPresa(CartaoModerno(
      autofocus: autofocus,
      focusNode: focusNode,
      onTap: aoAbrir,
      onLongPress: aoMenu,
      padding: EdgeInsets.symmetric(horizontal: tv ? 14 : Tokens.e12, vertical: Tokens.e12),
      child: Column(
        mainAxisSize: emGrelha ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _IconeTipo(_icones[lista.conta.tipo]!, tamanho: tv ? 34 : 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lista.nomeMostrado, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: tv ? 17 : 15, fontWeight: FontWeight.w700)),
                // numa linha: o servidor encolhe primeiro (com reticências); as contagens só
                // encolhem se não couberem em 2/3 da largura
                LayoutBuilder(
                  builder: (_, c) => Row(children: [
                    Flexible(
                      child: Text('${_tipos[lista.conta.tipo]} · ${hostDe(lista.conta.endereco)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: secundario),
                    ),
                    if (resumo != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: c.maxWidth * 2 / 3),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(' · ', style: secundario),
                          Flexible(
                            child: Text('${resumo!.canais} canais · ${resumo!.grupos} grupos',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: secundario),
                          ),
                        ]),
                      ),
                  ]),
                ),
              ]),
            ),
          ]),
          if (emGrelha) const Spacer() else const SizedBox(height: Tokens.e8),
          // a pílula e a validade na mesma linha quando cabem; senão a validade vai para baixo
          Wrap(spacing: Tokens.e8, runSpacing: Tokens.e4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            PilulaEstado(estadoDe(lista),
                detalhe: u == null ? null : verificadaHa(u.data), linhasDetalhe: emGrelha ? 1 : null),
            if (validade.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Tokens.vidroForte,
                  borderRadius: BorderRadius.circular(Tokens.raioPilula),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.event_outlined, size: tv ? 15 : 13, color: Tokens.texto2),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(validade,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: tv ? 13 : 12)),
                  ),
                ]),
              ),
          ]),
          if (u != null && u.motivo.isNotEmpty && u.estado != 'funciona')
            Padding(
              padding: const EdgeInsets.only(top: Tokens.e4),
              child: Text(u.motivo, maxLines: 1, overflow: TextOverflow.ellipsis, style: secundario),
            ),
        ],
      ),
    ));
  }
}

/// "verificada há 2 h", "verificada há 3 dias"... (para o detalhe da [PilulaEstado]).
String verificadaHa(DateTime d, [DateTime? agora]) {
  final dif = (agora ?? DateTime.now()).difference(d);
  if (dif.inMinutes < 1) return 'verificada agora';
  if (dif.inMinutes < 60) return 'verificada há ${dif.inMinutes} min';
  if (dif.inHours < 24) return 'verificada há ${dif.inHours} h';
  if (dif.inDays < 30) return 'verificada há ${dif.inDays} ${dif.inDays == 1 ? 'dia' : 'dias'}';
  return 'verificada em ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
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
