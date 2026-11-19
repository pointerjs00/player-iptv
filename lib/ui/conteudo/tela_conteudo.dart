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
import '../design/barra_teclas.dart';
import '../design/mensagens.dart';

const grupoFavoritos = '★ Favoritos';

/// O grupo virtual dos últimos canais vistos (ver [Lista.vistos]).
const grupoVistos = 'Vistos há pouco';

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

/// Onde procura a pesquisa da lista aberta: nos canais e nos grupos, só nos canais ou só nos grupos.
enum _Alcance { tudo, canais, grupos }

/// O conteúdo de uma lista: grupos à esquerda, canais à direita (no telemóvel, grupos em
/// cima). Uma só pesquisa procura canais (em todos os grupos) e grupos, sem acentos nem
/// maiúsculas; os encontrados ficam nas duas colunas.
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

  /// A pesquisa (já com o atraso de [_pesquisar]) e onde procura.
  String _q = '';
  _Alcance _alcance = _Alcance.tudo;
  final _textoPesquisa = TextEditingController();
  final _focoPesquisa = FocusNode(debugLabel: 'Pesquisa da lista');

  /// Há texto no campo (já, sem o atraso): o Voltar limpa-o e a barra de teclas muda.
  bool _comTexto = false;

  /// A pesquisa aplica-se aos canais / aos grupos (conforme [_alcance]).
  bool get _pesquisaCanais => _alcance != _Alcance.grupos && _q.trim().isNotEmpty;
  bool get _pesquisaGrupos => _alcance != _Alcance.canais && _q.trim().isNotEmpty;
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

  /// O canal com o foco na lista visível (0 = o primeiro): o "i" do "i de n".
  int _indice = 0;

  /// Os dígitos carregados para ir a um canal pelo número (apagam-se ao fim de 1,5 s).
  String _digitos = '';
  Timer? _atrasoDigitos;

  /// A altura de cada canal: uma linha de 56 (maior na TV: vê-se de longe).
  double _alturaCanal(bool tv) => tv ? 68 : 56;
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
    _atrasoDigitos?.cancel();
    _scrollCanais.dispose();
    _focoRegresso.dispose();
    _focoCancelar.dispose();
    _textoPesquisa.dispose();
    _focoPesquisa.dispose();
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
      mostrarMensagem(context, 'O último canal visto já não está nesta lista.');
      return;
    }
    _limparPesquisa();
    setState(() => _grupo = canal.grupo);
    final canais = _canaisVisiveis();
    final i = canais.indexOf(canal);
    if (i >= 0) _abrirCanal(canais, i);
  }

  /// O que se escolheu nas opções (do grupo `g` ou do topo).
  Future<void> _opcoes([String? g]) async {
    final l = widget.lista;
    final grupo = g ?? (_grupo == grupoFavoritos || _grupo == grupoVistos ? null : _grupo);
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
            mostrarMensagem(context, 'Não foi possível guardar (${descreverErro(e)}).', tipo: MensagemTipo.erro);
          }
        });
    switch (o) {
      case OpcaoCanais.esconderGrupo:
        final escondido = grupo!;
        final eraAtual = _grupo == escondido;
        unawaited(gravar(widget.biblioteca.esconderGrupo(l.id, escondido, true)));
        if (!_verEscondidos && eraAtual) _grupo = _primeiroGrupo(_conteudo!);
        mostrarMensagem(context, 'Grupo "$escondido" escondido', acao: 'Desfazer', aoAcao: () {
          if (!mounted) return;
          unawaited(gravar(widget.biblioteca.esconderGrupo(l.id, escondido, false)));
          setState(() {
            if (eraAtual) _grupo = escondido;
            _chaveVisiveis = null;
          });
        });
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
    if (_pesquisaCanais) setState(() => _chaveVisiveis = null);
  }

  void _pesquisar(String v) {
    if (_comTexto != v.isNotEmpty) setState(() => _comTexto = v.isNotEmpty);
    _atrasoPesquisa?.cancel();
    // espera que se pare de escrever: cada tecla não refaz a pesquisa
    _atrasoPesquisa = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _q = v);
    });
  }

  /// Apaga a pesquisa (o campo e os resultados).
  void _limparPesquisa() {
    _atrasoPesquisa?.cancel();
    _textoPesquisa.clear();
    setState(() {
      _q = '';
      _comTexto = false;
    });
  }

  /// Escolhe o grupo `g`. Com pesquisa, apaga-a e abre o grupo, com o foco nele (já na coluna
  /// com todos os grupos).
  void _escolherGrupo(String g) {
    if (!_comTexto && _q.trim().isEmpty) {
      setState(() => _grupo = g);
      return;
    }
    _limparPesquisa();
    setState(() => _grupo = g);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focosGrupos[g]?.requestFocus();
    });
  }

  /// A escrever na pesquisa (com o teclado): aí o Voltar só acaba a edição (é do [CampoTv]).
  /// Lê-se o campo como foi construído: o Voltar que acaba a edição ainda não o refez.
  bool _aEscreverNaPesquisa() {
    final e = _focoPesquisa.context?.findAncestorWidgetOfExactType<EditableText>();
    return _focoPesquisa.hasFocus && e != null && !e.readOnly;
  }

  /// O Voltar do sistema com texto na pesquisa limpa-a; sem texto, sai.
  void _voltar(bool saiu, Object? _) {
    if (saiu || !_comTexto || _aEscreverNaPesquisa()) return;
    _limparPesquisa();
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
          mostrarMensagem(context, 'Não foi possível atualizar: $texto', tipo: MensagemTipo.erro);
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

  /// Os grupos à vista; com pesquisa nos grupos, só os encontrados (sem os virtuais, como os
  /// favoritos, e sem os escondidos).
  List<String> _gruposVisiveis() {
    final c = _conteudo;
    if (c == null) return const [];
    final escondidos = widget.lista.gruposEscondidos;
    if (_pesquisaGrupos) {
      final q = semAcentos(_q.trim());
      return [
        for (final g in c.grupos)
          if (semAcentos(g).contains(q) && (_verEscondidos || !escondidos.contains(g))) g,
      ];
    }
    return [
      if (widget.lista.favoritos.isNotEmpty) grupoFavoritos,
      if (_vistosExistentes(c).isNotEmpty) grupoVistos,
      for (final g in c.grupos)
        if (_verEscondidos || !escondidos.contains(g)) g,
    ];
  }

  /// Os vistos há pouco que ainda estão na lista, do mais recente para o mais antigo.
  List<Canal> _vistosExistentes(ConteudoLista c) {
    final vistos = widget.lista.vistos;
    if (vistos.isEmpty) return const [];
    final porId = {for (final x in c.canais) x.id: x};
    return [for (final id in vistos) if (porId[id] != null) porId[id]!];
  }

  List<Canal> _canaisVisiveis() {
    final c = _conteudo;
    if (c == null) return const [];
    final q = _pesquisaCanais ? semAcentos(_q.trim()) : '';
    final ordem = widget.lista.ordemCanais;
    final escondidos = widget.lista.gruposEscondidos;
    final chave = '${ordem.name}|${_verEscondidos ? '' : escondidos.join('\u0000')}|'
        '${q.isNotEmpty ? 'q:$q' : (_grupo == grupoFavoritos ? 'f:$_versaoFavoritos' : _grupo == grupoVistos ? 'v:${widget.lista.vistos.join(',')}' : 'g:$_grupo')}';
    if (chave == _chaveVisiveis) return _visiveis;
    _chaveVisiveis = chave;
    _indice = 0;
    final List<Canal> r;
    if (q.isNotEmpty) {
      final nomes = _nomes ??= [for (final x in c.canais) semAcentos(x.nome)];
      // os grupos escondidos também ficam fora da pesquisa
      final semEscondidos = _verEscondidos || escondidos.isEmpty;
      // um número escrito também encontra o canal com esse número
      final numero = int.tryParse(q);
      r = [
        for (var i = 0; i < c.canais.length; i++)
          if ((nomes[i].contains(q) || (numero != null && c.canais[i].numero == numero)) &&
              (semEscondidos || !escondidos.contains(c.canais[i].grupo)))
            c.canais[i],
      ];
    } else if (_grupo == grupoVistos) {
      // pela ordem em que se viram, não pela ordem dos canais
      _visiveis = _vistosExistentes(c);
      return _visiveis;
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
    _focarNoCanal(canais, volta);
  }

  /// Rola até ao canal `i` (deixa-o a meio) e dá-lhe o foco.
  void _focarNoCanal(List<Canal> canais, int i) {
    setState(() => _canalAFocar = canais[i]);
    if (_scrollCanais.hasClients) {
      final p = _scrollCanais.position;
      final h = _alturaCanal(ecraTv(context));
      _scrollCanais.jumpTo((_margemLista + i * h - p.viewportDimension / 2 + h / 2)
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
    // o Voltar com texto na pesquisa limpa-a em vez de sair
    return PopScope(
      canPop: !_comTexto,
      onPopInvokedWithResult: _voltar,
      child: Scaffold(
      body: SafeArea(
        child: Stack(children: [
          // com o loader por cima, nada de baixo recebe o foco
          ExcludeFocus(
            excluding: _aCarregar,
            // Menu (do comando) abre as opções dos canais
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              includeSemantics: false,
              onKeyEvent: (_, e) {
                if (e is! KeyDownEvent) return KeyEventResult.ignored;
                if (e.logicalKey == LogicalKeyboardKey.contextMenu && _conteudo != null) {
                  _opcoes();
                  return KeyEventResult.handled;
                }
                // a tecla Voltar com texto na pesquisa limpa-a (a escrever, o campo fica com ela)
                if (_comTexto &&
                    (e.logicalKey == LogicalKeyboardKey.goBack || e.logicalKey == LogicalKeyboardKey.escape)) {
                  _limparPesquisa();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Column(children: [
                _barraTopo(largo),
                Expanded(child: _corpo()),
                BarraTeclas(_comTexto
                    ? const [('↑', 'pesquisa'), ('OK', 'abrir'), ('Voltar', 'limpar')]
                    : const [
                        ('OK', 'ver'),
                        ('OK mantido', 'favorito'),
                        ('←', 'grupos'),
                        ('0–9', 'ir para o canal'),
                        ('Menu', 'opções dos canais'),
                      ]),
              ]),
            ),
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
      ),
    ),
    );
  }

  /// Mostra/esconde os grupos escondidos (o botão "Grupos escondidos: n" do topo).
  void _alternarEscondidos() {
    final l = widget.lista;
    setState(() {
      _verEscondidos = !_verEscondidos;
      if (!_verEscondidos && l.gruposEscondidos.contains(_grupo)) _grupo = _primeiroGrupo(_conteudo!);
      _chaveVisiveis = null;
    });
    if (!_verEscondidos) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final g = _grupo;
        if (mounted && g != null) _focosGrupos[g]?.requestFocus();
      });
    }
  }

  /// O topo: "‹ Início", o nome da lista, o n.º de canais, a pesquisa, a ordem e os grupos escondidos.
  Widget _barraTopo(bool largo) {
    final tv = ecraTv(context);
    final l = widget.lista;
    final total = _conteudo?.canais.length;
    final carregado = _conteudo != null;
    final tamanho = tv ? 16.0 : 14.0;
    final estilo = TextStyle(fontSize: tamanho);
    final inicio = TextButton(
      onPressed: () => Navigator.of(context).maybePop(),
      child: Text('‹ Início', style: estilo),
    );
    final nome = Text(l.nomeMostrado,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: tv ? 22 : 18, fontWeight: FontWeight.w700));
    final contagem = total == null
        ? null
        : Text(total == 1 ? '1 canal' : '$total canais', style: TextStyle(color: Tokens.texto2, fontSize: tamanho));
    final pesquisa = CampoTv(
      key: const Key('pesquisa-canais'),
      controller: _textoPesquisa,
      focusNode: _focoPesquisa,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: 'Pesquisar canais, grupos ou o número',
      ),
      onChanged: _pesquisar,
    );
    // onde procura: «Tudo · Canais · Grupos» (uma escolha só)
    final alcance = Row(mainAxisSize: MainAxisSize.min, children: [
      for (final (i, (a, t)) in const [
        (_Alcance.tudo, 'Tudo'),
        (_Alcance.canais, 'Canais'),
        (_Alcance.grupos, 'Grupos'),
      ].indexed) ...[
        if (i > 0) const SizedBox(width: Tokens.e4),
        ChoiceChip(
          label: Text(t),
          selected: _alcance == a,
          // compactos: cabem ao lado da pesquisa na TV a 960
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          labelPadding: const EdgeInsets.symmetric(horizontal: Tokens.e4),
          onSelected: (_) => setState(() => _alcance = a),
        ),
      ],
    ]);
    final ordem = Tooltip(
      message: 'Opções dos canais',
      child: OutlinedButton(
        onPressed: carregado ? _opcoes : null,
        child: Text('Ordem: ${l.ordemCanais == OrdemCanais.az ? 'A–Z' : 'da lista'}', style: estilo),
      ),
    );
    final escondidos = OutlinedButton(
      onPressed: carregado && (l.gruposEscondidos.isNotEmpty || _verEscondidos) ? _alternarEscondidos : null,
      child: Text('Grupos escondidos: ${l.gruposEscondidos.length}', style: estilo),
    );
    final atualizar = IconButton(
      tooltip: 'Atualizar a lista de canais',
      onPressed: _atualizar,
      icon: const Icon(Icons.refresh),
    );
    // o estado da última verificação e a validade (sugestão 9), discretos
    Widget info([Widget? antes]) => Align(alignment: Alignment.centerLeft, child: _cabecalhoLista(antes));
    if (largo) {
      // a pesquisa e o «Tudo · Canais · Grupos» ficam na 1.ª linha; abaixo de 1600 px a ordem e os
      // grupos escondidos passam para a linha do estado; entre 900 e 1100 px também o n.º de canais
      // (a pesquisa fica larga na TV a 960); abaixo de 900 px é o «Tudo · Canais · Grupos» que
      // desce, para uma linha sua
      final largura = MediaQuery.sizeOf(context).width;
      final medio = largura < 1600;
      final alcanceEmBaixo = largura < 900;
      final contagemEmBaixo = largura < 1100 && !alcanceEmBaixo;
      final caixaPesquisa = Expanded(
          child: Align(alignment: Alignment.centerRight,
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: pesquisa)));
      return Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e8, Tokens.e16, Tokens.e8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            inicio,
            const SizedBox(width: Tokens.e8),
            ConstrainedBox(constraints: BoxConstraints(maxWidth: contagemEmBaixo ? 180 : 220), child: nome),
            if (contagem != null && !contagemEmBaixo) ...[const SizedBox(width: Tokens.e12), contagem],
            const SizedBox(width: Tokens.e16),
            caixaPesquisa,
            if (!alcanceEmBaixo) ...[const SizedBox(width: Tokens.e8), alcance],
            if (!medio) ...[const SizedBox(width: Tokens.e12), ordem, const SizedBox(width: Tokens.e8), escondidos],
            atualizar,
          ]),
          if (alcanceEmBaixo) ...[
            const SizedBox(height: Tokens.e4),
            Align(alignment: Alignment.centerLeft, child: alcance),
          ],
          const SizedBox(height: Tokens.e4),
          if (medio)
            Row(children: [
              // o n.º de canais vai com o estado (parte de linha como ele, se não couber)
              Expanded(child: info(contagemEmBaixo ? contagem : null)),
              ordem,
              const SizedBox(width: Tokens.e8),
              escondidos,
            ])
          else
            info(),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.e8, Tokens.e4, Tokens.e8, Tokens.e4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          inicio,
          Expanded(child: nome),
          if (contagem != null) ...[const SizedBox(width: Tokens.e8), contagem],
          atualizar,
        ]),
        Padding(padding: const EdgeInsets.symmetric(horizontal: Tokens.e8), child: pesquisa),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.e8, Tokens.e8, Tokens.e8, 0),
          child: Align(alignment: Alignment.centerLeft, child: alcance),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.e8, Tokens.e8, Tokens.e8, 0),
          child: Wrap(spacing: Tokens.e8, runSpacing: Tokens.e4, children: [ordem, escondidos]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(Tokens.e8, Tokens.e8, Tokens.e8, 0), child: info()),
      ]),
    );
  }

  /// O estado da última verificação, a validade e quando foi verificada.
  Widget _cabecalhoLista([Widget? antes]) {
    final tv = ecraTv(context);
    final u = widget.lista.ultima;
    final validade = textoValidade(u?.validade ?? '');
    final quando = u == null ? '' : dataRelativa(u.data);
    final secundario = TextStyle(color: Tokens.texto2, fontSize: tv ? 15 : 13);
    return Wrap(spacing: Tokens.e8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      ?antes,
      PilulaEstado(estadoDe(widget.lista)),
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
          Flexible(child: Text('da cache · ${dataRelativa(_daCache!)}', maxLines: 1,
              overflow: TextOverflow.ellipsis, style: secundario)),
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
    final pesquisa = _pesquisaCanais;
    if (largo) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 280, child: SuperficieVidro(child: _colunaGrupos())),
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
    // sem coluna dos grupos: os grupos (com pesquisa, os encontrados) numa fila de chips por
    // cima dos canais
    final grupos = _gruposVisiveis();
    final q = _pesquisaGrupos ? semAcentos(_q.trim()) : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_pesquisaGrupos) _titulo('Grupos · ${grupos.length}'),
      SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.e16),
          itemCount: grupos.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) => ChoiceChip(
            label: _comRealce(grupos[i], q, const TextStyle()),
            selected: !pesquisa && grupos[i] == _grupo,
            onSelected: (_) => _escolherGrupo(grupos[i]),
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
                      SizedBox(width: 248, child: grupos),
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

  TextStyle _estiloCabecalho() =>
      TextStyle(color: Tokens.texto2, fontWeight: FontWeight.w700, fontSize: ecraTv(context) ? 16.0 : 14.0);

  /// O cabeçalho de uma coluna ("Grupos · 2").
  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e12, Tokens.e16, Tokens.e4),
        child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: _estiloCabecalho()),
      );

  /// O texto com a parte encontrada (`q`, já sem acentos) em [Tokens.acento]; sem ela, só o texto.
  Widget _comRealce(String texto, String q, TextStyle estilo) {
    final normal = q.isEmpty ? '' : semAcentos(texto);
    // só quando as posições batem certo (tirar os acentos quase nunca muda o comprimento)
    final i = normal.length == texto.length ? normal.indexOf(q) : -1;
    if (i < 0) return Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: texto.substring(0, i)),
        TextSpan(text: texto.substring(i, i + q.length), style: const TextStyle(color: Tokens.acento)),
        TextSpan(text: texto.substring(i + q.length)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: estilo,
    );
  }

  /// Por cima dos canais: o grupo (com pesquisa, "Canais · n") à esquerda e `i de n` à direita
  /// (i = o canal com o foco).
  Widget _cabecalhoCanais(int n, bool pesquisa) {
    final estilo = _estiloCabecalho();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e12, Tokens.e16, Tokens.e4),
      child: Row(children: [
        Expanded(
          child: Text(
            pesquisa ? 'Canais · $n' : (_grupo ?? 'Todos'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: estilo,
          ),
        ),
        if (n > 0) ...[
          const SizedBox(width: Tokens.e12),
          Text('${_indice.clamp(0, n - 1) + 1} de $n', key: const Key('contador-canais'), style: estilo),
        ],
      ]),
    );
  }

  /// ↑ no primeiro grupo ou no primeiro canal vai à pesquisa (a procura direcional podia ir
  /// parar à ordem ou aos grupos escondidos, que estão mais perto).
  bool _subirParaPesquisa(KeyEvent e, bool noPrimeiro) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.arrowUp || !noPrimeiro) return false;
    _focoPesquisa.requestFocus();
    return true;
  }

  Widget _colunaGrupos() {
    final grupos = _gruposVisiveis();
    final tv = ecraTv(context);
    final q = _pesquisaGrupos ? semAcentos(_q.trim()) : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_pesquisaGrupos) _titulo('Grupos · ${grupos.length}'),
      Expanded(
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          onKeyEvent: (_, e) =>
              _subirParaPesquisa(e, grupos.isNotEmpty && (_focosGrupos[grupos.first]?.hasPrimaryFocus ?? false))
                  ? KeyEventResult.handled
                  : KeyEventResult.ignored,
          child: FocusTraversalGroup(
          child: ListView.builder(
            key: const Key('lista-grupos'),
            // margem para a borda de realce não ser cortada pelo vidro
            padding: const EdgeInsets.all(_margemLista),
            itemCount: grupos.length,
            itemBuilder: (_, i) {
              final g = grupos[i];
              final n = g == grupoFavoritos
                  ? widget.lista.favoritos.length
                  : g == grupoVistos ? _vistosExistentes(_conteudo!).length : (_contagens[g] ?? 0);
              final fav = g == grupoFavoritos || g == grupoVistos;
              final escondido = !fav && widget.lista.gruposEscondidos.contains(g);
              void escolher() => _escolherGrupo(g);
              final tile = RealceFoco(
                construir: (_, aoMudarFoco) => ListTile(
                  focusNode: _focoGrupo(g),
                  onFocusChange: aoMudarFoco,
                  dense: !tv,
                  // o foco começa no grupo escolhido
                  autofocus: g == _grupo,
                  selected: g == _grupo && !_pesquisaCanais,
                  title: _comRealce(g, q, TextStyle(fontSize: tv ? 17 : 14, fontWeight: FontWeight.w500,
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
      ),
    ]);
  }

  Widget _listaCanais(List<Canal> canais) {
    if (canais.isEmpty) {
      return const Center(child: Text('Nenhum canal.', style: TextStyle(color: Tokens.texto2)));
    }
    final tv = ecraTv(context);
    final pesquisa = _pesquisaCanais;
    final q = pesquisa ? semAcentos(_q.trim()) : '';
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
            final numero = '${c.numero ?? i + 1}';
            final larguraNumero = tv ? 64.0 : 52.0;
            // uma linha inteira: número, logótipo, nome e estrela. O número fica por cima da
            // margem esquerda da linha (fora do ListTile: não faz parte do que recebe o foco)
            return OkMantido(
              aoCarregar: abrir,
              aoManter: favorito,
              child: GestureDetector(
                onSecondaryTap: favorito,
                child: Stack(children: [
                  RealceFoco(
                    construir: (_, aoMudarFoco) => ListTile(
                      onFocusChange: (f) {
                        aoMudarFoco(f);
                        if (f && _indice != i) setState(() => _indice = i);
                      },
                      focusNode: identical(c, _canalAFocar) ? _focoRegresso : null,
                      autofocus: focarPrimeiro && i == 0,
                      contentPadding: EdgeInsets.only(left: Tokens.e16 + larguraNumero, right: Tokens.e8),
                      leading: _Logo(c.logo, c.nome, tamanho: tv ? 52 : 40),
                      minLeadingWidth: tv ? 52 : 40,
                      title: _comRealce(c.nome, q, TextStyle(fontSize: tv ? 19 : 15, fontWeight: FontWeight.w500)),
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
                  Positioned(
                    left: Tokens.e16,
                    top: 0,
                    bottom: 0,
                    width: larguraNumero - Tokens.e8,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(numero, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Tokens.texto2, fontSize: tv ? 17 : 14,
                                fontFeatures: const [FontFeature.tabularFigures()])),
                      ),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  static const _teclasDigitos = [
    LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
  ];
  static const _teclasNumpad = [
    LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  int? _digito(LogicalKeyboardKey k) {
    final i = _teclasDigitos.indexOf(k);
    final j = _teclasNumpad.indexOf(k);
    return i >= 0 ? i : (j >= 0 ? j : null);
  }

  /// "0–9, ir para o canal": os dígitos carregados seguidos formam o número do canal (o do
  /// portal ou, sem número, a posição na lista) e o foco vai para ele.
  void _irParaNumero(int d) {
    _atrasoDigitos?.cancel();
    _atrasoDigitos = Timer(const Duration(milliseconds: 1500), () => _digitos = '');
    final canais = _canaisVisiveis();
    int? procurar(String t) {
      final n = int.tryParse(t);
      if (n == null) return null;
      final porNumero = canais.indexWhere((c) => c.numero == n);
      if (porNumero >= 0) return porNumero;
      return !canais.any((c) => c.numero != null) && n >= 1 && n <= canais.length ? n - 1 : null;
    }

    var i = procurar('$_digitos$d');
    if (i != null) {
      _digitos += '$d';
    } else {
      // sem esse número: recomeça só com este dígito
      _digitos = '$d';
      i = procurar(_digitos);
    }
    if (i != null) _focarNoCanal(canais, i);
  }

  /// Nos canais: DIREITA fica no canal (à direita não há nada; a procura direcional saltava
  /// para o "Atualizar" lá em cima) e ESQUERDA volta ao grupo escolhido (não ao filtro dos
  /// grupos, que pode estar mais perto do canal de cima).
  KeyEventResult _teclaCanais(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final d = _digito(e.logicalKey);
    if (d != null) {
      if (e is KeyDownEvent) _irParaNumero(d);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
    if (_subirParaPesquisa(e, _indice == 0)) return KeyEventResult.handled;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      final g = _focosGrupos[_grupo];
      if (g != null && g.context != null && g.canRequestFocus) {
        g.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// "Desfazer": repõe o canal como estava antes (só se ainda não foi mudado entretanto).
  void _desfazerFavorito(String id, bool tinhaPassadoAFavorito) {
    if (!mounted || widget.lista.favoritos.contains(id) != tinhaPassadoAFavorito) return;
    widget.biblioteca.alternarFavorito(widget.lista.id, id);
    setState(() => _versaoFavoritos++);
  }

  /// Põe/tira o canal `i` dos favoritos (o conjunto muda logo; a gravação em disco segue em
  /// segundo plano). No grupo dos favoritos o canal sai da lista: o foco passa ao que fica no
  /// lugar dele (ou, sem favoritos, ao primeiro grupo).
  void _alternarFavorito(List<Canal> canais, int i) {
    final c = canais[i];
    final agora = !widget.lista.favoritos.contains(c.id);
    widget.biblioteca.alternarFavorito(widget.lista.id, c.id);
    final noGrupoFav = _grupo == grupoFavoritos && !_pesquisaCanais;
    setState(() => _versaoFavoritos++);
    mostrarMensagem(context, agora ? '${c.nome} está nos favoritos' : '${c.nome} saiu dos favoritos',
        acao: 'Desfazer', aoAcao: () => _desfazerFavorito(c.id, agora));
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

/// O logótipo do canal num quadrado de vidro (ou as iniciais do nome, sem logótipo).
class _Logo extends StatelessWidget {
  const _Logo(this.url, this.nome, {required this.tamanho});
  final String url;
  final String nome;
  final double tamanho;

  /// "PT: RTP 1 HD" → "PR": a 1.ª letra de até duas palavras (uma só palavra: as duas primeiras).
  static String iniciais(String nome) {
    final alfanum = RegExp(r'[^\p{L}\p{N}]', unicode: true);
    final palavras = [
      for (final p in nome.split(RegExp(r'\s+')))
        if (p.replaceAll(alfanum, '').isNotEmpty) p.replaceAll(alfanum, ''),
    ];
    if (palavras.isEmpty) return '';
    final r = palavras.length == 1
        ? palavras.first.characters.take(2).toString()
        : '${palavras[0].characters.first}${palavras[1].characters.first}';
    return r.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final ini = iniciais(nome);
    final vazio = ini.isEmpty
        ? Icon(Icons.tv_rounded, color: Tokens.texto2, size: tamanho * .5)
        // RichText (não Text): as iniciais são só decoração, o nome já está ao lado
        : Center(child: ExcludeSemantics(child: RichText(maxLines: 1, text: TextSpan(text: ini,
            style: TextStyle(color: Tokens.texto2, fontSize: tamanho * .36, fontWeight: FontWeight.w700)))));
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
