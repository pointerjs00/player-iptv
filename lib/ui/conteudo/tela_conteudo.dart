import 'dart:async';
import 'dart:isolate';

import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../modelo/canal.dart';
import '../../modelo/conta.dart';
import '../../protocolos/protocolo.dart';
import '../../rede/http.dart';
import '../campo_tv.dart';
import '../design/design.dart';
import '../player/abrir_canal.dart';
import '../realce_foco.dart';
import '../tema.dart';

const grupoFavoritos = '★ Favoritos';

/// Pede os canais de uma lista ao servidor (o protocolo da conta; substituível nos testes).
typedef AbrirLista = Future<ConteudoLista> Function(Conta conta, {Cancelamento? cancelamento, Aviso? aviso});

Future<ConteudoLista> _abrirPeloProtocolo(Conta conta, {Cancelamento? cancelamento, Aviso? aviso}) =>
    Protocolo.para(conta).abrir(conta, cancelamento: cancelamento, aviso: aviso);

/// O conteúdo de uma lista: grupos à esquerda, canais à direita (no telemóvel, grupos em
/// cima). A pesquisa procura canais em todos os grupos, sem acentos nem maiúsculas.
class TelaConteudo extends StatefulWidget {
  const TelaConteudo({super.key, required this.biblioteca, required this.lista, this.abrir,
      this.atualizar = false, AbrirLista? abrirLista})
      : abrirLista = abrirLista ?? _abrirPeloProtocolo;

  final Biblioteca biblioteca;
  final Lista lista;

  /// Para testes: em vez de abrir o player. Devolve o canal que estava a tocar ao sair.
  final FutureOr<int?> Function(List<Canal> canais, int i)? abrir;

  /// "Atualizar canais": pede os canais ao servidor logo ao abrir (a cache, se houver, fica por baixo).
  final bool atualizar;

  /// Pede os canais ao servidor.
  final AbrirLista abrirLista;

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

  /// A altura de cada canal (maior na TV: vê-se de longe).
  double _alturaCanal(bool tv) => tv ? 76 : 56;
  static const _margemLista = 8.0;

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
      if (widget.atualizar) await _carregar();
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
      final c = await widget.abrirLista(widget.lista.conta, cancelamento: can,
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
      final h = _alturaCanal(ecraTv(context));
      _scrollCanais.jumpTo((_margemLista + volta * h - p.viewportDimension / 2 + h / 2)
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
    final largo = MediaQuery.sizeOf(context).width >= 720;
    final pesquisa = Padding(
      padding: EdgeInsets.only(top: largo ? 0 : Tokens.e8),
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
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lista.nomeMostrado, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Atualizar a lista de canais',
            onPressed: _atualizar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(children: [
        // cabeçalho: estado da última verificação e validade (sugestão 9) + pesquisa
        Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e12),
          child: largo
              ? Row(children: [
                  Expanded(child: _cabecalhoLista()),
                  const SizedBox(width: Tokens.e16),
                  SizedBox(width: 400, child: pesquisa),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_cabecalhoLista(), pesquisa]),
        ),
        if (_aCarregar) _barraCarregar(),
        Expanded(child: _corpo()),
      ]),
    );
  }

  /// O estado da última verificação, a validade e quando foi verificada.
  Widget _cabecalhoLista() {
    final tv = ecraTv(context);
    final u = widget.lista.ultima;
    final validade = textoValidade(u?.validade ?? '');
    final quando = u == null ? '' : dataRelativa(u.data);
    final secundario = TextStyle(color: Tokens.texto2, fontSize: tv ? 15 : 13);
    return Wrap(spacing: Tokens.e8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      PilulaEstado(u?.estado, grande: tv),
      if (validade.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: Tokens.vidroForte, borderRadius: BorderRadius.circular(Tokens.raioPilula)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_outlined, size: tv ? 16 : 14, color: Tokens.texto2),
            const SizedBox(width: 5),
            Text(validade, style: TextStyle(fontSize: tv ? 15 : 13)),
          ]),
        ),
      Text(
        u == null
            ? 'Ainda não foi verificada'
            // "hoje às 14:05", "há 3 dias" ou uma data ("em 02/01/2026")
            : 'Verificada ${quando.startsWith(RegExp('[0-9]')) ? 'em ' : ''}$quando',
        style: secundario,
      ),
    ]);
  }

  Widget _barraCarregar() => Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e12),
        child: SuperficieVidro(
          raio: Tokens.raioBotao,
          cor: Tokens.vidroForte,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.e16, vertical: 4),
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
    final largo = MediaQuery.sizeOf(context).width >= 720;
    final tv = ecraTv(context);
    if (_conteudo == null) {
      if (_erro != null) {
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Tokens.e24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SuperficieVidro(
                padding: const EdgeInsets.all(Tokens.e24),
                elevacao: 2,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 48, color: Tokens.mau),
                  const SizedBox(height: Tokens.e12),
                  Text('Não foi possível abrir a lista: $_erro', textAlign: TextAlign.center),
                  const SizedBox(height: Tokens.e16),
                  FilledButton(autofocus: true, onPressed: _carregar, child: const Text('Tentar de novo')),
                ]),
              ),
            ),
          ),
        );
      }
      // a ler a cache ou a carregar do servidor: o esqueleto a brilhar
      return _esqueleto(largo, tv);
    }
    final canais = _canaisVisiveis();
    final lista = _listaCanais(canais);
    final pesquisa = _qCanais.trim().isNotEmpty;
    if (largo) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: tv ? 340 : 300, child: SuperficieVidro(child: _colunaGrupos())),
          const SizedBox(width: Tokens.e16),
          Expanded(
            child: SuperficieVidro(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _cabecalhoCanais(canais.length, pesquisa),
                Expanded(child: lista),
              ]),
            ),
          ),
        ]),
      );
    }
    final grupos = _gruposVisiveis();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.e16),
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
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.e12, 0, Tokens.e12, Tokens.e12),
          child: SuperficieVidro(child: lista),
        ),
      ),
    ]);
  }

  /// Enquanto carrega: blocos com a forma dos grupos e dos canais, com um brilho a passar.
  Widget _esqueleto(bool largo, bool tv) {
    final h = _alturaCanal(tv);
    final logo = tv ? 56.0 : 40.0;
    Widget canal(int i) => SizedBox(
          height: h,
          child: Row(children: [
            BlocoEsqueleto(largura: logo, altura: logo, raio: 10),
            const SizedBox(width: Tokens.e16),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                    widthFactor: .35 + (i * 37 % 40) / 100, child: const BlocoEsqueleto(altura: 14)),
              ),
            ),
          ]),
        );
    final canais = Column(children: [for (var i = 0; i < 14; i++) canal(i)]);
    final grupos = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const BlocoEsqueleto(altura: 40, raio: Tokens.raioCampo),
      const SizedBox(height: Tokens.e16),
      for (var i = 0; i < 12; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: FractionallySizedBox(
              widthFactor: .5 + (i * 29 % 40) / 100, child: const BlocoEsqueleto(altura: 14)),
        ),
    ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e16),
      // nunca rola nem transborda: corta o que não cabe
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: double.infinity,
          child: EsqueletoBrilho(
            child: Padding(
              padding: const EdgeInsets.all(Tokens.e16),
              child: largo
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: tv ? 308 : 268, child: grupos),
                      const SizedBox(width: Tokens.e32 + Tokens.e16),
                      Expanded(child: canais),
                    ])
                  : canais,
            ),
          ),
        ),
      ),
    );
  }

  Widget _cabecalhoCanais(int n, bool pesquisa) => Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e12, Tokens.e16, Tokens.e4),
        child: Text(
          pesquisa
              ? (n == 1 ? '1 canal encontrado' : '$n canais encontrados')
              : '${_grupo ?? 'Todos'} · ${n == 1 ? '1 canal' : '$n canais'}',
          style: TextStyle(color: Tokens.texto2, fontWeight: FontWeight.w700, fontSize: ecraTv(context) ? 15 : 13),
        ),
      );

  Widget _colunaGrupos() {
    final grupos = _gruposVisiveis();
    final tv = ecraTv(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e12, Tokens.e12, Tokens.e12, Tokens.e4),
        child: CampoTv(
          key: const Key('filtro-grupos'),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.filter_list), hintText: 'Filtrar grupos'),
          onChanged: (v) => setState(() => _qGrupos = v),
        ),
      ),
      Expanded(
        child: FocusTraversalGroup(
          child: ListView.builder(
            // margem para a borda de realce não ser cortada pelo vidro
            padding: const EdgeInsets.all(_margemLista),
            itemCount: grupos.length,
            itemBuilder: (_, i) {
              final g = grupos[i];
              final n = g == grupoFavoritos ? widget.lista.favoritos.length : (_contagens[g] ?? 0);
              return RealceFoco(
                construir: (_, aoMudarFoco) => ListTile(
                  onFocusChange: aoMudarFoco,
                  dense: !tv,
                  // o foco começa no grupo escolhido
                  autofocus: g == _grupo,
                  selected: g == _grupo && _qCanais.trim().isEmpty,
                  title: Text(g, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: tv ? 17 : 14, fontWeight: FontWeight.w500)),
                  trailing: Text('$n', style: TextStyle(color: Tokens.texto2, fontSize: tv ? 15 : 12.5)),
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
      return const Center(child: Text('Nenhum canal.', style: TextStyle(color: Tokens.texto2)));
    }
    final tv = ecraTv(context);
    final pesquisa = _qCanais.trim().isNotEmpty;
    // no ecrã estreito (sem coluna de grupos) o foco começa no 1.º canal
    final focarPrimeiro = MediaQuery.sizeOf(context).width < 720;
    return FocusTraversalGroup(
      // virtualizada (itemExtent fixo) e sem animar cada canal: listas de 100 mil
      child: ListView.builder(
        key: const Key('lista-canais'),
        controller: _scrollCanais,
        padding: const EdgeInsets.all(_margemLista),
        itemCount: canais.length,
        itemExtent: _alturaCanal(tv),
        itemBuilder: (_, i) {
          final c = canais[i];
          final fav = widget.lista.favoritos.contains(c.id);
          return RealceFoco(
            construir: (_, aoMudarFoco) => ListTile(
              onFocusChange: aoMudarFoco,
              focusNode: identical(c, _canalAFocar) ? _focoRegresso : null,
              autofocus: focarPrimeiro && i == 0,
              leading: _Logo(c.logo, tamanho: tv ? 56 : 40),
              minLeadingWidth: tv ? 56 : 40,
              title: Text(c.nome, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: tv ? 19 : 15, fontWeight: FontWeight.w500)),
              subtitle: pesquisa
                  ? Text(c.grupo, maxLines: 1, style: TextStyle(fontSize: tv ? 14 : 12, color: Tokens.texto2))
                  : null,
              trailing: IconButton(
                tooltip: fav ? 'Tirar dos favoritos' : 'Pôr nos favoritos',
                icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: fav ? Tokens.aviso : Tokens.texto2, size: tv ? 28 : 24),
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

/// O logótipo do canal num quadrado de vidro (ou o ícone de TV sem logótipo).
class _Logo extends StatelessWidget {
  const _Logo(this.url, {required this.tamanho});
  final String url;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final vazio = Icon(Icons.tv_rounded, color: Tokens.texto2, size: tamanho * .5);
    return Container(
      key: const Key('logo-canal'),
      width: tamanho,
      height: tamanho,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Tokens.vidro, borderRadius: BorderRadius.circular(tamanho * .22)),
      child: url.startsWith('http')
          ? Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => vazio,
              // descodificado no tamanho mostrado (poupa memória com muitos logótipos)
              cacheWidth: (tamanho * MediaQuery.devicePixelRatioOf(context)).round())
          : vazio,
    );
  }
}

// função de topo: a closure mandada para o isolate não pode levar o estado do ecrã
Future<List<String>> _normalizarNumIsolate(List<String> nomes) =>
    Isolate.run(() => [for (final n in nomes) semAcentos(n)]);
