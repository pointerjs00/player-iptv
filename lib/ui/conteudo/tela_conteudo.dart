import 'dart:async';
import 'dart:isolate';

import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../modelo/canal.dart';
import '../../protocolos/protocolo.dart';
import '../../rede/http.dart';
import '../campo_tv.dart';
import '../player/abrir_canal.dart';
import '../realce_foco.dart';
import '../tema.dart';

const grupoFavoritos = '★ Favoritos';

/// O conteúdo de uma lista: grupos à esquerda, canais à direita (no telemóvel, grupos em
/// cima). A pesquisa procura canais em todos os grupos, sem acentos nem maiúsculas.
class TelaConteudo extends StatefulWidget {
  const TelaConteudo({super.key, required this.biblioteca, required this.lista, this.abrir});

  final Biblioteca biblioteca;
  final Lista lista;

  /// Para testes: em vez de abrir o player. Devolve o canal que estava a tocar ao sair.
  final FutureOr<int?> Function(List<Canal> canais, int i)? abrir;

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

  // feitos uma vez por lista (com 100 mil canais, refazê-los a cada build congela a TV)
  Map<String, List<Canal>> _porGrupo = const {};
  List<String>? _nomes; // os nomes sem acentos, pela ordem de `canais`
  Timer? _atrasoPesquisa;
  int _versaoFavoritos = 0;
  String? _chaveVisiveis;
  List<Canal> _visiveis = const [];

  // ao voltar do player: o canal que estava a tocar recebe o foco
  final _scrollCanais = ScrollController();
  final _focoRegresso = FocusNode();
  Canal? _canalAFocar;
  static const _alturaCanal = 56.0;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _cancelamento?.cancelar();
    _atrasoPesquisa?.cancel();
    _scrollCanais.dispose();
    _focoRegresso.dispose();
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

  void _mostrar(ConteudoLista c) {
    final porGrupo = <String, List<Canal>>{};
    for (final x in c.canais) {
      (porGrupo[x.grupo] ??= []).add(x);
    }
    setState(() {
      _conteudo = c;
      _contagens = {for (final e in porGrupo.entries) e.key: e.value.length};
      _porGrupo = porGrupo;
      _nomes = null;
      _chaveVisiveis = null;
      _erro = null;
      _grupo ??= widget.lista.favoritos.isNotEmpty ? grupoFavoritos : (c.grupos.isEmpty ? null : c.grupos.first);
    });
    _indexarNomes(c);
  }

  /// Os nomes sem acentos, para a pesquisa: numa lista grande, fora da thread da interface.
  Future<void> _indexarNomes(ConteudoLista c) async {
    final nomes = [for (final x in c.canais) x.nome];
    final List<String> r;
    if (nomes.length < 5000) {
      r = [for (final n in nomes) semAcentos(n)];
    } else {
      r = await _normalizarNumIsolate(nomes);
    }
    if (!mounted || !identical(c, _conteudo)) return;
    _nomes = r;
    if (_qCanais.trim().isNotEmpty) setState(() => _chaveVisiveis = null);
  }

  void _pesquisar(String v) {
    _atrasoPesquisa?.cancel();
    // espera que se pare de escrever: cada tecla não refaz a pesquisa
    _atrasoPesquisa = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _qCanais = v);
    });
  }

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
    final chave = q.isNotEmpty ? 'q:$q' : (_grupo == grupoFavoritos ? 'f:$_versaoFavoritos' : 'g:$_grupo');
    if (chave == _chaveVisiveis) return _visiveis;
    _chaveVisiveis = chave;
    if (q.isNotEmpty) {
      final nomes = _nomes ??= [for (final x in c.canais) semAcentos(x.nome)];
      _visiveis = [for (var i = 0; i < c.canais.length; i++) if (nomes[i].contains(q)) c.canais[i]];
    } else if (_grupo == grupoFavoritos) {
      _visiveis = [for (final x in c.canais) if (widget.lista.favoritos.contains(x.id)) x];
    } else {
      _visiveis = _grupo == null ? c.canais : (_porGrupo[_grupo] ?? const []);
    }
    return _visiveis;
  }

  Future<void> _abrirCanal(List<Canal> canais, int i) async {
    final volta = widget.abrir != null ? await widget.abrir!(canais, i) : await abrirCanal(context, widget.lista, canais, i);
    if (volta == null || !mounted || volta < 0 || volta >= canais.length) return;
    // a lista visível ainda é a mesma que foi para o player? Então foca o canal que tocava.
    if (!identical(canais, _canaisVisiveis())) return;
    setState(() => _canalAFocar = canais[volta]);
    if (_scrollCanais.hasClients) {
      final p = _scrollCanais.position;
      _scrollCanais.jumpTo((volta * _alturaCanal - p.viewportDimension / 2 + _alturaCanal / 2)
          .clamp(0.0, p.maxScrollExtent));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focoRegresso.requestFocus();
    });
  }

  void _atualizar() {
    if (_aCarregar) return; // fica ligado (não perde o foco); a meio do carregamento não faz nada
    _carregar();
  }

  void _cancelarCarregamento() {
    _cancelamento?.cancelar();
    setState(() {
      _aCarregar = false;
      // sem canais, o corpo mostra "Tentar de novo" (com o foco), em vez de ficar vazio
      if (_conteudo == null) _erro = 'carregamento cancelado';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lista.nomeMostrado),
        actions: [
          IconButton(
            tooltip: 'Atualizar a lista de canais',
            onPressed: _atualizar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(children: [
        if (_aCarregar) _barraCarregar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: CampoTv(
            key: const Key('pesquisa-canais'),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _conteudo == null
                  ? 'Pesquisar canais'
                  : 'Pesquisar em ${_conteudo!.canais.length} canais de ${_conteudo!.grupos.length} grupos',
            ),
            onChanged: _pesquisar,
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
              // sem canais para mostrar, é o único sítio útil para o foco
              autofocus: _conteudo == null,
              onPressed: _cancelarCarregamento,
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
        child: CampoTv(
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
              return RealceFoco(
                construir: (_, aoMudarFoco) => ListTile(
                  onFocusChange: aoMudarFoco,
                  dense: true,
                  // o foco começa no grupo escolhido
                  autofocus: g == _grupo,
                  selected: g == _grupo && _qCanais.trim().isEmpty,
                  title: Text(g, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text('$n', style: const TextStyle(color: Cores.texto2)),
                  onTap: () => setState(() => _grupo = g),
                ),
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
    // no ecrã estreito (sem coluna de grupos) o foco começa no 1.º canal
    final focarPrimeiro = MediaQuery.sizeOf(context).width < 720;
    return FocusTraversalGroup(
      child: ListView.builder(
        controller: _scrollCanais,
        itemCount: canais.length,
        itemExtent: _alturaCanal,
        itemBuilder: (_, i) {
          final c = canais[i];
          final fav = widget.lista.favoritos.contains(c.id);
          return RealceFoco(
            construir: (_, aoMudarFoco) => ListTile(
              onFocusChange: aoMudarFoco,
              focusNode: identical(c, _canalAFocar) ? _focoRegresso : null,
              autofocus: focarPrimeiro && i == 0,
              leading: _Logo(c.logo),
              title: Text(c.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: pesquisa ? Text(c.grupo, maxLines: 1, style: const TextStyle(fontSize: 12)) : null,
              trailing: IconButton(
                tooltip: fav ? 'Tirar dos favoritos' : 'Pôr nos favoritos',
                icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Cores.aviso : null),
                onPressed: () {
                  // o conjunto muda logo; a gravação em disco segue em segundo plano
                  widget.biblioteca.alternarFavorito(widget.lista.id, c.id);
                  setState(() => _versaoFavoritos++);
                },
              ),
              onTap: () => _abrirCanal(canais, i),
            ),
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

// função de topo: a closure mandada para o isolate não pode levar o estado do ecrã
Future<List<String>> _normalizarNumIsolate(List<String> nomes) =>
    Isolate.run(() => [for (final n in nomes) semAcentos(n)]);
