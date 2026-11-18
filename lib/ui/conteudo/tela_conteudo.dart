import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
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
import 'opcoes_conteudo.dart';
import '../tema.dart';
import '../../verificar/estado.dart';
import '../../verificar/verificador.dart';

const grupoFavoritos = '★ Favoritos';

/// Pede os canais de uma lista ao servidor (o protocolo da conta; substituível nos testes).
typedef AbrirLista = Future<ConteudoLista> Function(Conta conta, {Cancelamento? cancelamento, Aviso? aviso});

/// O passo do carregamento para o loader ("a pedir os canais · página 3/12" → "A pedir os
/// canais · página 3/12" e 0.25) e o progresso quando há total. Sem o caminho do portal no fim.
(String, double?) passoCarregamento(String aviso) {
  var t = aviso.trim().replaceFirst(RegExp(r'\s*\([^)]*\)$'), '');
  if (t.isEmpty) return ('A ligar…', null);
  t = t[0].toUpperCase() + t.substring(1);
  final m = RegExp(r'página (\d+)/(\d+)').firstMatch(t);
  final total = m == null ? 0 : int.parse(m[2]!);
  return (t, total > 0 ? (int.parse(m![1]!) / total).clamp(0.0, 1.0) : null);
}

Future<ConteudoLista> _abrirPeloProtocolo(Conta conta, {Cancelamento? cancelamento, Aviso? aviso}) =>
    Protocolo.para(conta).abrir(conta, cancelamento: cancelamento, aviso: aviso);

/// O conteúdo de uma lista: grupos à esquerda, canais à direita (no telemóvel, grupos em
/// cima). A pesquisa procura canais em todos os grupos, sem acentos nem maiúsculas.
class TelaConteudo extends StatefulWidget {
  const TelaConteudo({super.key, required this.biblioteca, required this.lista, this.abrir,
      this.atualizar = false, AbrirLista? abrirLista, this.dns = resolverDns, this.continuar})
      : abrirLista = abrirLista ?? _abrirPeloProtocolo;

  final Biblioteca biblioteca;
  final Lista lista;

  /// Para testes: em vez de abrir o player. Devolve o canal que estava a tocar ao sair.
  final FutureOr<int?> Function(List<Canal> canais, int i)? abrir;

  /// "Atualizar canais": pede os canais ao servidor logo ao abrir (a cache, se houver, fica por baixo).
  final bool atualizar;

  /// Pede os canais ao servidor.
  final AbrirLista abrirLista;

  /// Depois de uma falha: o host existe? (DNS inexistente = a lista não funciona)
  final ResolverDns dns;

  /// "Continuar a ver": o id do canal a abrir no player logo que os canais estejam à vista.
  final String? continuar;

  @override
  State<TelaConteudo> createState() => _TelaConteudoState();
}

class _TelaConteudoState extends State<TelaConteudo> {
  ConteudoLista? _conteudo;
  String? _erro;
  String _aviso = '';
  bool _aCarregar = false;
  Cancelamento? _cancelamento;

  /// Os canais mostrados vêm da cache gravada a esta hora (null = do servidor, ou nenhuns).
  DateTime? _daCache;

  /// O "Cancelar" do loader, e quem tinha o foco antes do loader (volta para lá ao fechar).
  final _focoCancelar = FocusNode(debugLabel: 'Cancelar o carregamento');
  FocusNode? _focoAntes;
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

  /// Os grupos escondidos também à vista (com um ícone), para os voltar a mostrar.
  bool _verEscondidos = false;
  bool _continuou = false;

  /// O foco de cada grupo (depois de esconder um, o foco passa ao grupo escolhido).
  final _focosGrupos = <String, FocusNode>{};
  FocusNode _focoGrupo(String g) => _focosGrupos.putIfAbsent(g, () => FocusNode(debugLabel: 'Grupo $g'));

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
    _focoCancelar.dispose();
    for (final f in _focosGrupos.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _iniciar() async {
    final cache = await widget.biblioteca.canaisEmCache(widget.lista.id);
    final data = cache == null ? null : await widget.biblioteca.dataCache(widget.lista.id);
    if (!mounted) return;
    if (cache != null && cache.canais.isNotEmpty) {
      _daCache = data ?? DateTime.now();
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
      _grupo ??= _primeiroGrupo(c);
    });
    _indexarNomes(c);
    if (widget.continuar != null && !_continuou) {
      _continuou = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _continuarA(widget.continuar!);
      });
    }
  }

  String? _primeiroGrupo(ConteudoLista c) {
    if (widget.lista.favoritos.isNotEmpty) return grupoFavoritos;
    final escondidos = widget.lista.gruposEscondidos;
    return c.grupos.where((g) => _verEscondidos || !escondidos.contains(g)).firstOrNull ??
        (c.grupos.isEmpty ? null : c.grupos.first);
  }

  /// "Continuar a ver": abre o player nesse canal, com os canais do grupo dele.
  void _continuarA(String id) {
    final canal = _conteudo?.canais.where((c) => c.id == id).firstOrNull;
    if (canal == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('O último canal visto já não está nesta lista.')));
      return;
    }
    setState(() {
      _grupo = canal.grupo;
      _qCanais = '';
    });
    final canais = _canaisVisiveis();
    final i = canais.indexOf(canal);
    if (i >= 0) _abrirCanal(canais, i);
  }

  /// O que se escolheu nas opções (do grupo `g` ou do topo).
  Future<void> _opcoes([String? g]) async {
    final l = widget.lista;
    final grupo = g ?? (_grupo == grupoFavoritos ? null : _grupo);
    final o = await mostrarOpcoesCanais(context,
        grupo: grupo,
        grupoEscondido: grupo != null && l.gruposEscondidos.contains(grupo),
        soGrupo: g != null,
        ordem: l.ordemCanais,
        verEscondidos: _verEscondidos,
        escondidos: l.gruposEscondidos.length);
    if (o == null || !mounted) return;
    Future<void> gravar(Future<void> f) => f.catchError((Object e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Não foi possível guardar (${descreverErro(e)}).')));
          }
        });
    switch (o) {
      case OpcaoCanais.esconderGrupo:
        unawaited(gravar(widget.biblioteca.esconderGrupo(l.id, grupo!, true)));
        if (!_verEscondidos && _grupo == grupo) _grupo = _primeiroGrupo(_conteudo!);
      case OpcaoCanais.mostrarGrupo:
        unawaited(gravar(widget.biblioteca.esconderGrupo(l.id, grupo!, false)));
      case OpcaoCanais.ordemLista || OpcaoCanais.ordemAz:
        unawaited(gravar(widget.biblioteca
            .definirOrdem(l.id, o == OpcaoCanais.ordemAz ? OrdemCanais.az : OrdemCanais.lista)));
      case OpcaoCanais.verEscondidos || OpcaoCanais.ocultarEscondidos:
        _verEscondidos = o == OpcaoCanais.verEscondidos;
        if (!_verEscondidos && l.gruposEscondidos.contains(_grupo)) _grupo = _primeiroGrupo(_conteudo!);
    }
    setState(() => _chaveVisiveis = null);
    // o grupo com o foco pode ter saído: o foco vai para o grupo escolhido
    if (o == OpcaoCanais.esconderGrupo || o == OpcaoCanais.ocultarEscondidos) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final g = _grupo;
        if (mounted && g != null) _focosGrupos[g]?.requestFocus();
      });
    }
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
    final antes = FocusManager.instance.primaryFocus;
    if (antes != _focoCancelar) _focoAntes = antes;
    setState(() {
      _aCarregar = true;
      _erro = null;
      _aviso = '';
    });
    // o loader cobre o ecrã: o foco vai para o "Cancelar"
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _aCarregar && _focoCancelar.context != null) _focoCancelar.requestFocus();
    });
    try {
      final conta = widget.lista.conta;
      final c = await widget.abrirLista(conta, cancelamento: can,
          aviso: (t) { if (mounted && identical(can, _cancelamento)) setState(() => _aviso = t); });
      await widget.biblioteca.guardarCanais(widget.lista.id, c);
      if (mounted) {
        _daCache = null;
        _mostrar(c);
      }
    } on Cancelado {
      // saiu do ecrã ou carregou em Cancelar
    } catch (e) {
      final texto = e is ErroLista ? e.mensagem : descreverErro(e);
      if (mounted && identical(can, _cancelamento)) {
        if (_conteudo == null) {
          setState(() => _erro = texto);
        } else {
          // os canais da cache continuam à vista
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível atualizar: $texto')));
        }
      }
      unawaited(_marcarSeMorta(e));
    } finally {
      if (mounted && identical(can, _cancelamento)) {
        setState(() => _aCarregar = false);
        _devolverFoco();
      }
    }
  }

  /// O loader fechou: o foco volta a quem o tinha (por exemplo "Atualizar"); sem ninguém, os
  /// widgets com foco automático (grupo escolhido, "Tentar de novo") ficam com ele.
  void _devolverFoco() {
    final antes = _focoAntes;
    _focoAntes = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (antes != null && antes.context != null && antes is! FocusScopeNode && antes.canRequestFocus) {
        antes.requestFocus();
      }
    });
  }

  /// Uma falha que prova que a lista não funciona (conta recusada/expirada/desativada, portal
  /// inexistente — `ErroLista.definitivo` —, uma M3U com 404/410 ou o host que já não existe no DNS) fica registada
  /// como uma verificação "Não funciona". Erros temporários (tempo esgotado, 5xx, 459…) não mudam
  /// o estado.
  Future<void> _marcarSeMorta(Object e) async {
    ResultadoVerificacao? r;
    if (e is ErroLista && e.definitivo) {
      r = ResultadoVerificacao(EstadoV.naoFunciona, e.mensagem);
    } else if (e is ErroHttp) {
      // o servidor respondeu: o host existe. Como no verificador, só o download de uma M3U com
      // um estado definitivo (404/410) é prova; um erro HTTP de uma API (Stalker/Xtream) não
      if (widget.lista.conta.tipo == Tipo.m3u) {
        final c = classificarFalha(e);
        if (c.estado == EstadoV.naoFunciona) r = c;
      }
    } else {
      // pode ser o DNS
      try {
        final d = await widget.dns(hostDe(widget.lista.conta.endereco));
        if (d?.estado == EstadoV.naoFunciona) r = d;
      } catch (_) {
        // sem prova, o estado fica
      }
    }
    if (r == null) return;
    try {
      await widget.biblioteca.registarVerificacao(widget.lista.id, paraUltima(r));
    } catch (_) {
      return; // não se gravou: fica para a próxima
    }
    if (mounted) setState(() {});
  }

  List<String> _gruposVisiveis() {
    final c = _conteudo;
    if (c == null) return const [];
    final q = semAcentos(_qGrupos.trim());
    final escondidos = widget.lista.gruposEscondidos;
    return [
      if (widget.lista.favoritos.isNotEmpty) grupoFavoritos,
      for (final g in c.grupos)
        if ((q.isEmpty || semAcentos(g).contains(q)) && (_verEscondidos || !escondidos.contains(g))) g,
    ];
  }

  List<Canal> _canaisVisiveis() {
    final c = _conteudo;
    if (c == null) return const [];
    final q = semAcentos(_qCanais.trim());
    final ordem = widget.lista.ordemCanais;
    final escondidos = widget.lista.gruposEscondidos;
    final chave = '${ordem.name}|${_verEscondidos ? '' : escondidos.join('\u0000')}|'
        '${q.isNotEmpty ? 'q:$q' : (_grupo == grupoFavoritos ? 'f:$_versaoFavoritos' : 'g:$_grupo')}';
    if (chave == _chaveVisiveis) return _visiveis;
    _chaveVisiveis = chave;
    final List<Canal> r;
    if (q.isNotEmpty) {
      final nomes = _nomes ??= [for (final x in c.canais) semAcentos(x.nome)];
      // os grupos escondidos também ficam fora da pesquisa
      final semEscondidos = _verEscondidos || escondidos.isEmpty;
      r = [
        for (var i = 0; i < c.canais.length; i++)
          if (nomes[i].contains(q) && (semEscondidos || !escondidos.contains(c.canais[i].grupo))) c.canais[i],
      ];
    } else if (_grupo == grupoFavoritos) {
      r = [for (final x in c.canais) if (widget.lista.favoritos.contains(x.id)) x];
    } else {
      r = _grupo == null ? c.canais : (_porGrupo[_grupo] ?? const []);
    }
    _visiveis = ordenarCanais(r, ordem);
    return _visiveis;
  }

  /// Guarda o canal para o "Continuar a ver" (em segundo plano; uma falha não incomoda).
  void _registarVisto(Canal c) =>
      unawaited(widget.biblioteca.registarVisto(widget.lista.id, c).catchError((Object _) {}));

  Future<void> _abrirCanal(List<Canal> canais, int i) async {
    _registarVisto(canais[i]);
    final volta = widget.abrir != null
        ? await widget.abrir!(canais, i)
        : await abrirCanal(context, widget.lista, canais, i, aoVer: _registarVisto);
    if (volta == null || volta < 0 || volta >= canais.length) return;
    _registarVisto(canais[volta]);
    if (!mounted) return;
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
    _devolverFoco();
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
            tooltip: 'Opções dos canais',
            onPressed: _conteudo == null ? null : _opcoes,
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar a lista de canais',
            onPressed: _atualizar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(children: [
        // com o loader por cima, nada de baixo recebe o foco
        ExcludeFocus(
          excluding: _aCarregar,
          child: Column(children: [
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
            Expanded(child: _corpo()),
          ]),
        ),
        // sem cache (ou ao atualizar): o loader em ecrã cheio
        if (_aCarregar)
          Positioned.fill(
            child: Builder(builder: (_) {
              final (passo, progresso) = passoCarregamento(_aviso);
              return CarregadorCanais(
                passo: passo,
                progresso: progresso,
                focoCancelar: _focoCancelar,
                aoCancelar: _cancelarCarregamento,
                titulo: _conteudo == null ? 'A carregar os canais' : 'A atualizar os canais',
              );
            }),
          ),
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
      // os canais vêm da cache: discreto, com a hora (o "Atualizar" está em cima)
      if (_daCache != null && _conteudo != null)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history_rounded, size: tv ? 16 : 14, color: Tokens.texto2),
          const SizedBox(width: 4),
          Text('da cache · ${dataRelativa(_daCache!)}', style: secundario),
        ]),
    ]);
  }

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

  /// O grupo e o número de canais; com o comando (TV ou modo de realce do teclado), à direita, a
  /// dica discreta "OK mantido: favorito" (a estrela não recebe o foco).
  Widget _cabecalhoCanais(int n, bool pesquisa) {
    Theme.of(context); // reconstrói quando o modo de realce muda (TemaConformeRealce troca o tema)
    final tv = ecraTv(context);
    final comando = tv || FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final tamanho = tv ? 15.0 : 13.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e12, Tokens.e16, Tokens.e4),
      child: Row(children: [
        Expanded(
          child: Text(
            pesquisa
                ? (n == 1 ? '1 canal encontrado' : '$n canais encontrados')
                : '${_grupo ?? 'Todos'} · ${n == 1 ? '1 canal' : '$n canais'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Tokens.texto2, fontWeight: FontWeight.w700, fontSize: tamanho),
          ),
        ),
        if (comando && n > 0) ...[
          const SizedBox(width: Tokens.e12),
          Icon(Icons.star_outline_rounded, size: tamanho + 3, color: Tokens.texto2),
          const SizedBox(width: 4),
          Text('OK mantido: favorito', style: TextStyle(color: Tokens.texto2, fontSize: tamanho - 1)),
        ],
      ]),
    );
  }

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
            key: const Key('lista-grupos'),
            // margem para a borda de realce não ser cortada pelo vidro
            padding: const EdgeInsets.all(_margemLista),
            itemCount: grupos.length,
            itemBuilder: (_, i) {
              final g = grupos[i];
              final n = g == grupoFavoritos ? widget.lista.favoritos.length : (_contagens[g] ?? 0);
              final fav = g == grupoFavoritos;
              final escondido = !fav && widget.lista.gruposEscondidos.contains(g);
              void escolher() => setState(() => _grupo = g);
              final tile = RealceFoco(
                construir: (_, aoMudarFoco) => ListTile(
                  focusNode: _focoGrupo(g),
                  onFocusChange: aoMudarFoco,
                  dense: !tv,
                  // o foco começa no grupo escolhido
                  autofocus: g == _grupo,
                  selected: g == _grupo && _qCanais.trim().isEmpty,
                  title: Text(g, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: tv ? 17 : 14, fontWeight: FontWeight.w500,
                          color: escondido ? Tokens.texto2 : null)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (escondido) ...[
                      Icon(Icons.visibility_off_outlined,
                          key: const Key('grupo-escondido'), size: tv ? 18 : 16, color: Tokens.texto2,
                          semanticLabel: 'escondido'),
                      const SizedBox(width: 6),
                    ],
                    Text('$n', style: TextStyle(color: Tokens.texto2, fontSize: tv ? 15 : 12.5)),
                  ]),
                  onTap: escolher,
                  // o menu do grupo: toque longo (o OK mantido vem do OkMantido)
                  onLongPress: fav ? null : () => _opcoes(g),
                ),
              );
              return fav ? tile : OkMantido(aoCarregar: escolher, aoManter: () => _opcoes(g), child: tile);
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
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: _teclaCanais,
      child: FocusTraversalGroup(
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
            void abrir() => _abrirCanal(canais, i);
            void favorito() => _alternarFavorito(canais, i);
            // a linha é a única paragem do foco: a estrela só mostra o estado e responde ao
            // toque/rato; no comando, OK mantido (ou toque longo, ou clique direito) põe/tira
            return OkMantido(
              aoCarregar: abrir,
              aoManter: favorito,
              child: GestureDetector(
                onSecondaryTap: favorito,
                child: RealceFoco(
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
                    trailing: ExcludeFocus(
                      child: IconButton(
                        tooltip: fav ? 'Tirar dos favoritos' : 'Pôr nos favoritos',
                        icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: fav ? Tokens.aviso : Tokens.texto2, size: tv ? 28 : 24),
                        onPressed: favorito,
                      ),
                    ),
                    onTap: abrir,
                    onLongPress: favorito,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Nos canais: DIREITA fica no canal (à direita não há nada; a procura direcional saltava
  /// para o "Atualizar" lá em cima) e ESQUERDA volta ao grupo escolhido (não ao filtro dos
  /// grupos, que pode estar mais perto do canal de cima).
  KeyEventResult _teclaCanais(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      final g = _focosGrupos[_grupo];
      if (g != null && g.context != null && g.canRequestFocus) {
        g.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Põe/tira o canal `i` dos favoritos (o conjunto muda logo; a gravação em disco segue em
  /// segundo plano). No grupo dos favoritos o canal sai da lista: o foco passa ao que fica no
  /// lugar dele (ou, sem favoritos, ao primeiro grupo).
  void _alternarFavorito(List<Canal> canais, int i) {
    final c = canais[i];
    final agora = !widget.lista.favoritos.contains(c.id);
    widget.biblioteca.alternarFavorito(widget.lista.id, c.id);
    final noGrupoFav = _grupo == grupoFavoritos && _qCanais.trim().isEmpty;
    setState(() => _versaoFavoritos++);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(agora ? '${c.nome} está nos favoritos' : '${c.nome} saiu dos favoritos')));
    if (!noGrupoFav || agora) return;
    final restantes = _canaisVisiveis();
    if (restantes.isEmpty) {
      setState(() => _grupo = _primeiroGrupo(_conteudo!));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final g = _grupo;
        if (mounted && g != null) _focosGrupos[g]?.requestFocus();
      });
      return;
    }
    setState(() => _canalAFocar = restantes[i.clamp(0, restantes.length - 1)]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focoRegresso.requestFocus();
    });
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
