import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../modelo/conta.dart';
import '../tema.dart';

/// Cartão de uma lista no Início: nome, tipo, último resultado, validade e ações.
class CartaoLista extends StatelessWidget {
  const CartaoLista({super.key, required this.lista, required this.aoAbrir, this.aoVerificar,
      this.aoRemover, this.verificando = false, this.autofocus = false});

  final Lista lista;
  final VoidCallback aoAbrir;
  final VoidCallback? aoVerificar;
  final VoidCallback? aoRemover;
  final bool verificando;
  final bool autofocus;

  static const _tipos = {Tipo.stalker: 'Stalker', Tipo.xtream: 'Xtream', Tipo.m3u: 'M3U'};

  @override
  Widget build(BuildContext context) {
    final u = lista.ultima;
    final (cor, rotulo, icone) = visualEstado(u?.estado);
    final validade = textoValidade(u?.validade ?? '');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        autofocus: autofocus,
        onTap: aoAbrir,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icone, color: cor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(lista.nomeMostrado, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (aoRemover != null)
                  PopupMenuButton<String>(
                    tooltip: 'Mais opções',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (_) => aoRemover!(),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'remover', child: Text('Remover lista'))],
                  ),
              ]),
              const SizedBox(height: 4),
              Text('${_tipos[lista.conta.tipo]} · ${hostDe(lista.conta.endereco)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Cores.texto2, fontSize: 12)),
              const Spacer(),
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(rotulo, style: TextStyle(color: cor, fontWeight: FontWeight.w700, fontSize: 13)),
                if (u != null)
                  Text(dataRelativa(u.data), style: const TextStyle(color: Cores.texto2, fontSize: 12)),
                if (validade.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Cores.superficie2, borderRadius: BorderRadius.circular(99)),
                    child: Text(validade, style: const TextStyle(fontSize: 12)),
                  ),
              ]),
              if (u != null && u.motivo.isNotEmpty && u.estado != 'funciona')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(u.motivo, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Cores.texto2, fontSize: 12)),
                ),
              const SizedBox(height: 10),
              if (aoVerificar != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    // fica ligado a verificar (um botão desligado perde o foco do comando);
                    // verificar de novo uma lista que já está a ser verificada não faz nada
                    onPressed: aoVerificar,
                    icon: verificando
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(verificando ? 'A verificar…' : 'Verificar de novo'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
