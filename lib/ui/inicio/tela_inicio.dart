import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../modelo/canal.dart';
import '../../verificar/servico.dart';
import '../adicionar.dart';
import '../conteudo/tela_conteudo.dart';
import '../tema.dart';
import 'cartao_lista.dart';

/// Início: as listas guardadas em cartões, com pesquisa e filtro por estado.
class TelaInicio extends StatefulWidget {
  const TelaInicio({super.key, required this.biblioteca, this.servico, this.separadorVerificar});

  final Biblioteca biblioteca;

  /// Verifica listas e guarda o resultado; sem ele não há botões de verificar.
  final ServicoVerificacao? servico;

  /// O separador "Verificar" (a interface do verificador).
  final Widget? separadorVerificar;

  @override
  State<TelaInicio> createState() => _TelaInicioState();
}

class _TelaInicioState extends State<TelaInicio> {
  String _q = '';
  String? _filtro; // null = todas; 'por_verificar' = sem resultado

  static const _filtros = [
    (null, 'Todas'),
    ('funciona', 'Funcionam'),
    ('inconclusivo', 'INC'),
    ('nao_funciona', 'Não funcionam'),
    ('por_verificar', 'Por verificar'),
  ];

  List<Lista> _visiveis() {
    final q = semAcentos(_q.trim());
    return [
      for (final l in widget.biblioteca.listas)
        if ((_filtro == null || (l.ultima?.estado ?? 'por_verificar') == _filtro) &&
            (q.isEmpty || semAcentos('${l.nomeMostrado} ${l.conta.endereco} ${l.conta.nome}').contains(q)))
          l,
    ];
  }

  Future<void> _remover(Lista l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover lista?'),
        content: Text('A lista ${l.nomeMostrado} sai da app (os favoritos e a cache de canais também).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (ok == true) await widget.biblioteca.remover(l.id);
  }

  void _abrir(Lista l) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TelaConteudo(biblioteca: widget.biblioteca, lista: l),
      ));

  Widget _listas() => ListenableBuilder(
        listenable: Listenable.merge([widget.biblioteca, ?widget.servico]),
        builder: (context, _) {
          final todas = widget.biblioteca.listas;
          final vis = _visiveis();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Pesquisar listas'),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ),
                for (final (v, t) in _filtros)
                  ChoiceChip(label: Text(t), selected: _filtro == v, onSelected: (_) => setState(() => _filtro = v)),
                if (widget.servico != null && todas.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => widget.servico!.verificarVarias(vis),
                    icon: const Icon(Icons.playlist_add_check),
                    label: Text('Verificar ${vis.length == todas.length ? 'todas' : 'as ${vis.length} visíveis'}'),
                  ),
              ]),
            ),
            Expanded(
              child: todas.isEmpty
                  ? _vazio()
                  : vis.isEmpty
                      ? const Center(child: Text('Nenhuma lista com este filtro.'))
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          // no telemóvel, um cartão por linha (com o nome inteiro)
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: MediaQuery.sizeOf(context).width < 600 ? 600 : 340,
                            mainAxisExtent: 224, crossAxisSpacing: 12, mainAxisSpacing: 12,
                          ),
                          itemCount: vis.length,
                          itemBuilder: (_, i) => CartaoLista(
                            lista: vis[i],
                            autofocus: i == 0,
                            aoAbrir: () => _abrir(vis[i]),
                            aoVerificar: widget.servico == null ? null : () => widget.servico!.verificar(vis[i]),
                            verificando: widget.servico?.aVerificar(vis[i].id) ?? false,
                            aoRemover: () => _remover(vis[i]),
                          ),
                        ),
            ),
          ]);
        },
      );

  Widget _vazio() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.live_tv_outlined, size: 56, color: Cores.texto2),
          const SizedBox(height: 12),
          const Text('Ainda não há listas.', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text('Importe o Accounts.json, ficheiros .ini, listas M3U ou cole as linhas.',
                textAlign: TextAlign.center, style: TextStyle(color: Cores.texto2)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            autofocus: true,
            onPressed: () => mostrarAdicionar(context, widget.biblioteca),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar listas'),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final temVerificar = widget.separadorVerificar != null;
    final corpo = Scaffold(
      appBar: AppBar(
        title: const Text('Player IPTV'),
        bottom: temVerificar
            ? const TabBar(tabs: [Tab(text: 'Listas'), Tab(text: 'Verificar')])
            : null,
        actions: [
          IconButton(
            tooltip: 'Adicionar listas',
            onPressed: () => mostrarAdicionar(context, widget.biblioteca),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: temVerificar ? TabBarView(children: [_listas(), widget.separadorVerificar!]) : _listas(),
    );
    return temVerificar ? DefaultTabController(length: 2, child: corpo) : corpo;
  }
}
