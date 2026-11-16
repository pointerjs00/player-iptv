import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../modelo/canal.dart';
import '../../protocolos/protocolo.dart';
import '../../rede/http.dart';
import '../player/abrir_canal.dart';
import '../tema.dart';

const grupoFavoritos = '★ Favoritos';

/// O conteúdo de uma lista: grupos à esquerda, canais à direita (no telemóvel, grupos em
/// cima). A pesquisa procura canais em todos os grupos, sem acentos nem maiúsculas.
class TelaConteudo extends StatefulWidget {
  const TelaConteudo({super.key, required this.biblioteca, required this.lista, this.abrir});

  final Biblioteca biblioteca;
  final Lista lista;

  /// Para testes: em vez de abrir o player.
  final void Function(List<Canal> canais, int i)? abrir;

  @override
  State<TelaConteudo> createState() => _TelaConteudoState();
}

class _TelaConteudoState extends State<TelaConteudo> {
  ConteudoLista? _conteudo;
  String? _erro;
  String _aviso = '';
  bool _aCarregar = false;
  Cancelamento? _cancelamento;
  String? _grupo;
  String _qCanais = '';
  String _qGrupos = '';
  Map<String, int> _contagens = const {};

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _cancelamento?.cancelar();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final cache = await widget.biblioteca.canaisEmCache(widget.lista.id);
    if (!mounted) return;
    if (cache != null && cache.canais.isNotEmpty) {
      _mostrar(cache);
    } else {
      await _carregar();
    }
  }

  void _mostrar(ConteudoLista c) => setState(() {
        _conteudo = c;
        _contagens = c.contagens();
        _erro = null;
        _grupo ??= widget.lista.favoritos.isNotEmpty ? grupoFavoritos : (c.grupos.isEmpty ? null : c.grupos.first);
      });

  Future<void> _carregar() async {
    _cancelamento?.cancelar();
    final can = _cancelamento = Cancelamento();
    setState(() {
      _aCarregar = true;
      _erro = null;
      _aviso = 'a ligar…';
    });
    try {
      final c = await Protocolo.para(widget.lista.conta).abrir(widget.lista.conta, cancelamento: can,
          aviso: (t) { if (mounted) setState(() => _aviso = t); });
      await widget.biblioteca.guardarCanais(widget.lista.id, c);
      if (mounted) _mostrar(c);
    } on Cancelado {
      // saiu do ecrã ou carregou em Cancelar
    } catch (e) {
      if (mounted) setState(() => _erro = e is ErroLista ? e.mensagem : descreverErro(e));
    } finally {
      if (mounted && identical(can, _cancelamento)) setState(() => _aCarregar = false);
    }
  }

  List<String> _gruposVisiveis() {
    final c = _conteudo;
    if (c == null) return const [];
    final q = semAcentos(_qGrupos.trim());
    return [
      if (widget.lista.favoritos.isNotEmpty) grupoFavoritos,
      for (final g in c.grupos) if (q.isEmpty || semAcentos(g).contains(q)) g,
    ];
  }

  List<Canal> _canaisVisiveis() {
    final c = _conteudo;
    if (c == null) return const [];
    final q = semAcentos(_qCanais.trim());
    if (q.isNotEmpty) return [for (final x in c.canais) if (semAcentos(x.nome).contains(q)) x];
    if (_grupo == grupoFavoritos) return [for (final x in c.canais) if (widget.lista.favoritos.contains(x.id)) x];
    return _grupo == null ? c.canais : c.doGrupo(_grupo!);
  }

  void _abrirCanal(List<Canal> canais, int i) {
    if (widget.abrir != null) return widget.abrir!(canais, i);
    abrirCanal(context, widget.lista, canais, i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lista.nomeMostrado),
        actions: [
          IconButton(
            tooltip: 'Atualizar a lista de canais',
            onPressed: _aCarregar ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(children: [
        if (_aCarregar) _barraCarregar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            key: const Key('pesquisa-canais'),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _conteudo == null
                  ? 'Pesquisar canais'
                  : 'Pesquisar em ${_conteudo!.canais.length} canais de ${_conteudo!.grupos.length} grupos',
            ),
            onChanged: (v) => setState(() => _qCanais = v),
          ),
        ),
        Expanded(child: _corpo()),
      ]),
    );
  }

  Widget _barraCarregar() => Material(
        color: Cores.superficie2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Expanded(child: Text(_aviso, maxLines: 1, overflow: TextOverflow.ellipsis)),
            TextButton(
              onPressed: () {
                _cancelamento?.cancelar();
                setState(() => _aCarregar = false);
              },
              child: const Text('Cancelar'),
            ),
          ]),
        ),
      );

  Widget _corpo() {
    if (_conteudo == null) {
      if (_erro != null) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: Cores.mau),
            const SizedBox(height: 8),
            Text('Não foi possível abrir a lista: $_erro', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(autofocus: true, onPressed: _carregar, child: const Text('Tentar de novo')),
          ]),
        );
      }
      return const SizedBox.shrink();
    }
    final largo = MediaQuery.sizeOf(context).width >= 720;
    final canais = _canaisVisiveis();
    final lista = _listaCanais(canais);
    final pesquisa = _qCanais.trim().isNotEmpty;
    if (largo) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 300, child: _colunaGrupos()),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _cabecalhoCanais(canais.length, pesquisa),
            Expanded(child: lista),
          ]),
        ),
      ]);
    }
    final grupos = _gruposVisiveis();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: grupos.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) => ChoiceChip(
            label: Text(grupos[i]),
            selected: !pesquisa && grupos[i] == _grupo,
            onSelected: (_) => setState(() { _grupo = grupos[i]; _qCanais = ''; }),
          ),
        ),
      ),
      _cabecalhoCanais(canais.length, pesquisa),
      Expanded(child: lista),
    ]);
  }

  Widget _cabecalhoCanais(int n, bool pesquisa) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          pesquisa
              ? (n == 1 ? '1 canal encontrado' : '$n canais encontrados')
              : '${_grupo ?? 'Todos'} · ${n == 1 ? '1 canal' : '$n canais'}',
          style: const TextStyle(color: Cores.texto2, fontWeight: FontWeight.w700, fontSize: 12),
        ),
      );

  Widget _colunaGrupos() {
    final grupos = _gruposVisiveis();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          key: const Key('filtro-grupos'),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.filter_list), hintText: 'Filtrar grupos'),
          onChanged: (v) => setState(() => _qGrupos = v),
        ),
      ),
      Expanded(
        child: FocusTraversalGroup(
          child: ListView.builder(
            itemCount: grupos.length,
            itemBuilder: (_, i) {
              final g = grupos[i];
              final n = g == grupoFavoritos ? widget.lista.favoritos.length : (_contagens[g] ?? 0);
              return ListTile(
                dense: true,
                selected: g == _grupo && _qCanais.trim().isEmpty,
                title: Text(g, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text('$n', style: const TextStyle(color: Cores.texto2)),
                onTap: () => setState(() => _grupo = g),
              );
            },
          ),
        ),
      ),
    ]);
  }

  Widget _listaCanais(List<Canal> canais) {
    if (canais.isEmpty) {
      return const Center(child: Text('Nenhum canal.', style: TextStyle(color: Cores.texto2)));
    }
    final pesquisa = _qCanais.trim().isNotEmpty;
    return FocusTraversalGroup(
      child: ListView.builder(
        itemCount: canais.length,
        itemExtent: 56,
        itemBuilder: (_, i) {
          final c = canais[i];
          final fav = widget.lista.favoritos.contains(c.id);
          return ListTile(
            leading: _Logo(c.logo),
            title: Text(c.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: pesquisa ? Text(c.grupo, maxLines: 1, style: const TextStyle(fontSize: 12)) : null,
            trailing: IconButton(
              tooltip: fav ? 'Tirar dos favoritos' : 'Pôr nos favoritos',
              icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Cores.aviso : null),
              onPressed: () {
                // o conjunto muda logo; a gravação em disco segue em segundo plano
                widget.biblioteca.alternarFavorito(widget.lista.id, c.id);
                setState(() {});
              },
            ),
            onTap: () => _abrirCanal(canais, i),
          );
        },
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo(this.url);
  final String url;

  @override
  Widget build(BuildContext context) {
    const vazio = SizedBox(width: 40, height: 40, child: Icon(Icons.tv, color: Cores.texto2));
    if (!url.startsWith('http')) return vazio;
    return SizedBox(
      width: 40, height: 40,
      child: Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => vazio),
    );
  }
}
