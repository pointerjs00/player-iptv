import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../modelo/canal.dart';
import '../../verificar/servico.dart';
import '../adicionar.dart';
import '../campo_tv.dart';
import '../conteudo/tela_conteudo.dart';
import '../design/design.dart';
import '../realce_foco.dart';
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
  int? _abaFocada; // a aba com o foco do comando (para o realce)
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
        icon: const Icon(Icons.delete_outline_rounded, color: Tokens.mau, size: 32),
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

  void _abrir(Lista l) => Navigator.of(context).push(rotaSuave<void>(
        TelaConteudo(biblioteca: widget.biblioteca, lista: l),
      ));

  Widget _listas() => ListenableBuilder(
        listenable: Listenable.merge([widget.biblioteca, ?widget.servico]),
        builder: (context, _) {
          final todas = widget.biblioteca.listas;
          final vis = _visiveis();
          final tv = ecraTv(context);
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e12, Tokens.e16, Tokens.e4),
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 280,
                  child: CampoTv(
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
                      ? const Center(
                          child: Text('Nenhuma lista com este filtro.', style: TextStyle(color: Tokens.texto2)))
                      : GridView.builder(
                          // margem para o cartão focado crescer (1.04) e brilhar sem ser cortado
                          padding: const EdgeInsets.all(Tokens.e24),
                          // no telemóvel, um cartão por linha (com o nome inteiro)
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: MediaQuery.sizeOf(context).width < 600 ? 600 : (tv ? 400 : 340),
                            mainAxisExtent: CartaoLista.altura(tv),
                            crossAxisSpacing: Tokens.e16,
                            mainAxisSpacing: Tokens.e16,
                          ),
                          itemCount: vis.length,
                          // só os primeiros entram em cascata (entradaEmCascata ignora índices > 30)
                          itemBuilder: (_, i) => entradaEmCascata(i, CartaoLista(
                            lista: vis[i],
                            autofocus: i == 0,
                            aoAbrir: () => _abrir(vis[i]),
                            aoVerificar: widget.servico == null ? null : () => widget.servico!.verificar(vis[i]),
                            verificando: widget.servico?.aVerificar(vis[i].id) ?? false,
                            aoRemover: () => _remover(vis[i]),
                          )),
                        ),
            ),
          ]);
        },
      );

  Widget _vazio() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tokens.e24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: entradaEmCascata(0, SuperficieVidro(
              padding: const EdgeInsets.all(Tokens.e32),
              elevacao: 2,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tokens.gradienteAcento),
                  child: const Icon(Icons.live_tv_outlined, size: 36, color: Colors.white),
                ),
                const SizedBox(height: Tokens.e16),
                const Text('Ainda não há listas.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: Tokens.e8),
                const Text('Importe o Accounts.json, ficheiros .ini, listas M3U ou cole as linhas.',
                    textAlign: TextAlign.center, style: TextStyle(color: Tokens.texto2)),
                const SizedBox(height: Tokens.e24),
                FilledButton.icon(
                  autofocus: true,
                  onPressed: () => mostrarAdicionar(context, widget.biblioteca),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar listas'),
                ),
              ]),
            )),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final temVerificar = widget.separadorVerificar != null;
    final corpo = Scaffold(
      appBar: AppBar(
        // as abas ficam na mesma linha do "+": CIMA a partir do conteúdo para nas abas (nada
        // por cima delas) e ESQUERDA/DIREITA trocam Listas, Verificar e o "+"
        title: temVerificar
            ? Row(children: [
                // no telemóvel não há espaço para o nome e as abas
                if (MediaQuery.sizeOf(context).width >= 600) ...const [_Marca(), SizedBox(width: Tokens.e16)],
                Expanded(
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: Colors.transparent,
                    onFocusChange: (f, i) => setState(() => _abaFocada = f ? i : (_abaFocada == i ? null : _abaFocada)),
                    tabs: [
                      for (final (i, t) in const ['Listas', 'Verificar'].indexed)
                        Tab(child: MolduraFoco(focado: _abaFocada == i, raio: 8, child: _Aba(t))),
                    ],
                  ),
                ),
              ])
            : const _Marca(),
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
    return temVerificar
        // com "reduzir movimento" a troca de abas também é instantânea
        ? DefaultTabController(length: 2, animationDuration: duracaoAnimada(context, kTabScrollDuration), child: corpo)
        : corpo;
  }
}

/// O nome da app com o ícone em gradiente.
class _Marca extends StatelessWidget {
  const _Marca();

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(gradient: Tokens.gradienteAcento, borderRadius: BorderRadius.circular(9)),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 10),
        const Text('Player IPTV'),
      ]);
}

/// O nome de uma aba (com espaço para a borda do realce).
class _Aba extends StatelessWidget {
  const _Aba(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Text(texto));
}
