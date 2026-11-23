import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

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
import '../../idioma/idioma.dart';
import '../../importar/m3u.dart' show semGrupo;

const grupoFavoritos = '★ Favoritos';

/// O grupo virtual dos últimos canais vistos (ver [Lista.vistos]).
const grupoVistos = 'Vistos há pouco';

/// Pede os canais de uma lista ao servidor (o protocolo da conta; substituível nos testes).
typedef AbrirLista = Future<ConteudoLista> Function(Conta conta, {Cancelamento? cancelamento, Aviso? aviso});

/// O passo do carregamento para o loader ("a pedir os canais · página 3/12" → "A pedir os
/// canais · página 3/12" e 0.25) e o progresso quando há total. Sem o caminho do portal no fim.
(String, double?) passoCarregamento(String aviso) {
  var t = aviso.trim().replaceFirst(RegExp(r'\s*\([^)]*\)$'), '');
  if (t.isEmpty) return (tr('A ligar…'), null);
  t = t[0].toUpperCase() + t.substring(1);
  final m = RegExp(r'(?:página|page) (\d+)/(\d+)').firstMatch(t);
  final total = m == null ? 0 : int.parse(m[2]!);
  return (t, total > 0 ? (int.parse(m![1]!) / total).clamp(0.0, 1.0) : null);
}

Future<ConteudoLista> _abrirPeloProtocolo(Conta conta, {Cancelamento? cancelamento, Aviso? aviso}) =>
    Protocolo.para(conta).abrir(conta, cancelamento: cancelamento, aviso: aviso);

/// O conteúdo de uma lista: grupos à esquerda, canais à direita (no telemóvel, grupos em
/// cima). No topo da coluna dos grupos, «Filtrar grupos» só mexe nos grupos; no topo da coluna
/// dos canais, «Pesquisar canais ou número» procura em todos os grupos (sem acentos nem maiúsculas).
class TelaConteudo extends StatefulWidget {
  const TelaConteudo({super.key, required this.biblioteca, required this.lista, this.abrir,
      this.atualizar = false, AbrirLista? abrirLista, this.dns = resolverDns, this.continuar,
      this.indexar})
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

  /// Para testes: em vez do isolate, indexa os nomes de uma lista grande (5000 canais ou mais).
  final Future<IndiceNomes> Function(List<String> nomes)? indexar;

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

  /// O grupo escolhido (null = nenhum: "Todos os canais"). A pesquisa dos canais procura só nele.
  /// Mudar de grupo (por qualquer caminho) leva a lista dos canais ao topo.
  String? get _grupo => _grupoEscolhido;
  set _grupo(String? g) {
    if (g == _grupoEscolhido) return;
    _grupoEscolhido = g;
    // depois do frame: a lista já tem os canais do grupo novo (e pode mudar-se durante um build)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _grupoEscolhido == g && _scrollCanais.hasClients) _scrollCanais.jumpTo(0);
    });
  }

  String? _grupoEscolhido;

  /// A pesquisa dos canais (já com o atraso de [_pesquisar]) e o filtro dos grupos (idem).
  String _q = '';
  String _qGrupos = '';
  final _textoPesquisa = TextEditingController();
  final _focoPesquisa = FocusNode(debugLabel: 'Pesquisa dos canais');
  final _textoGrupos = TextEditingController();
  final _focoFiltroGrupos = FocusNode(debugLabel: 'Filtro dos grupos');

  /// Há texto num campo (já, sem o atraso): o Voltar limpa-o e a barra de teclas muda.
  bool _comTexto = false;
  bool _comTextoGrupos = false;

  bool get _pesquisaCanais => _q.trim().isNotEmpty;
  bool get _pesquisaGrupos => _qGrupos.trim().isNotEmpty;
  Map<String, int> _contagens = const {};

  // feitos uma vez por lista (com 100 mil canais, refazê-los a cada build congela a TV)
  Map<String, List<Canal>> _porGrupo = const {};
  Map<String, List<int>> _posicoesPorGrupo = const {}; // as posições em `canais` (para os nomes sem acentos)
  Map<String, String> _gruposSemAcentos = const {}; // para a pesquisa nos grupos
  List<String>? _nomes; // os nomes sem acentos, pela ordem de `canais`
  Int32List? _ordemAz; // as posições em `canais` por ordem A–Z (dos nomes sem acentos)
  Int32List? _lugarAz; // o lugar de cada posição na ordem A–Z (para ordenar um grupo sem refazer nomes)

  /// A lista à vista devia estar A–Z mas a ordem ainda não está feita: mostra-se a original.
  bool _aOrdenar = false;
  Timer? _atrasoPesquisa;
  Timer? _atrasoFiltro;
  int _versaoFavoritos = 0;
  String? _chaveVisiveis;
  List<Canal> _visiveis = const [];

  // ao voltar do player: o canal que estava a tocar recebe o foco
  final _scrollCanais = ScrollController();
  final _scrollGrupos = ScrollController();
  final _focoRegresso = FocusNode();
  Canal? _canalAFocar;

  /// A coluna dos canais (não recebe o foco: diz se o foco está num canal).
  final _focoColunaCanais = FocusNode(debugLabel: 'Coluna dos canais', canRequestFocus: false, skipTraversal: true);

  /// Os grupos escondidos também à vista (com um ícone), para os voltar a mostrar.
  bool _verEscondidos = false;
  bool _continuou = false;

  /// A coluna dos grupos (não recebe o foco: diz se o foco está num grupo).
  final _focoColunaGrupos = FocusNode(debugLabel: 'Coluna dos grupos', canRequestFocus: false, skipTraversal: true);

  /// O foco de cada grupo (depois de esconder um, o foco passa ao grupo escolhido).
  final _focosGrupos = <String, FocusNode>{};
  FocusNode _focoGrupo(String g) => _focosGrupos.putIfAbsent(g, () => FocusNode(debugLabel: 'Grupo $g'));

  /// O foco da linha "Todos os canais" (sem grupo escolhido).
  final _focoTodos = FocusNode(debugLabel: 'Todos os canais');

  /// O foco da linha do grupo escolhido ("Todos os canais", sem grupo); null se não estiver à vista.
  FocusNode? get _focoEscolhido => _grupo == null ? _focoTodos : _focosGrupos[_grupo];

  /// O canal com o foco na lista visível (0 = o primeiro): o "i" do "i de n".
  int _indice = 0;

  /// Os dígitos carregados para ir a um canal pelo número (apagam-se ao fim de 1,5 s).
  String _digitos = '';
  Timer? _atrasoDigitos;

  /// A altura de cada canal: uma linha de 56 (maior na TV: vê-se de longe). No telemóvel o nome
  /// vai até duas linhas (e, com pesquisa, o grupo por baixo): a altura acompanha a letra.
  double _alturaCanal() {
    if (ecraTv(context)) return 68;
    if (!ecraTelemovel(context)) return 56;
    // o nome (15) em duas linhas e, com pesquisa, o grupo (12); a altura de cada linha de texto
    // nos ListTile (Material 3) é 1,5 vezes a letra; mais 8 em cima e em baixo
    final letra = 2 * 15 + (_pesquisaCanais ? 12 : 0);
    final precisa = (Tokens.e16 + fatorTexto(context) * letra * 1.5).ceilToDouble();
    final minimo = _pesquisaCanais ? 72.0 : 64.0;
    return precisa < minimo ? minimo : precisa;
  }

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
    _atrasoFiltro?.cancel();
    _atrasoDigitos?.cancel();
    _scrollCanais.dispose();
    _scrollGrupos.dispose();
    _textoGrupos.dispose();
    _focoFiltroGrupos.dispose();
    _focoColunaGrupos.dispose();
    _focoRegresso.dispose();
    _focoColunaCanais.dispose();
    _focoCancelar.dispose();
    _textoPesquisa.dispose();
    _focoPesquisa.dispose();
    _focoTodos.dispose();
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
    final posicoes = <String, List<int>>{};
    for (var i = 0; i < c.canais.length; i++) {
      final x = c.canais[i];
      (porGrupo[x.grupo] ??= []).add(x);
      (posicoes[x.grupo] ??= []).add(i);
    }
    setState(() {
      _conteudo = c;
      _contagens = {for (final e in porGrupo.entries) e.key: e.value.length};
      _porGrupo = porGrupo;
      _posicoesPorGrupo = posicoes;
      _gruposSemAcentos = {for (final g in c.grupos) g: semAcentos(g)};
      _nomes = null;
      _ordemAz = null;
      _lugarAz = null;
      _chaveVisiveis = null;
      _erro = null;
      // abre sem grupo ("Todos os canais"); ao atualizar, o grupo escolhido fica (se ainda existir)
      _validarGrupo();
    });
    _indexarNomes(c);
    if (widget.continuar != null && !_continuou) {
      _continuou = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _continuarA(widget.continuar!);
      });
    }
  }

  /// "Continuar a ver": abre o player nesse canal, com os canais do grupo dele.
  void _continuarA(String id) {
    final canal = _conteudo?.canais.where((c) => c.id == id).firstOrNull;
    if (canal == null) {
      mostrarMensagem(context, tr('O último canal visto já não está nesta lista.'));
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
    _aplicarOpcao(o, grupo);
  }

  /// Aplica a opção `o` (do menu das opções, ou do ⋮ do topo no telemóvel) ao grupo `grupo`.
  void _aplicarOpcao(OpcaoCanais o, String? grupo) {
    final l = widget.lista;
    Future<void> gravar(Future<void> f) => f.catchError((Object e) {
          if (mounted) {
            mostrarMensagem(context, tr('Não foi possível guardar ({0}).', [descreverErro(e)]), tipo: MensagemTipo.erro);
          }
        });
    switch (o) {
      case OpcaoCanais.esconderGrupo:
        final escondido = grupo!;
        final eraAtual = _grupo == escondido;
        unawaited(gravar(widget.biblioteca.esconderGrupo(l.id, escondido, true)));
        if (!_verEscondidos && eraAtual) _grupo = null;
        mostrarMensagem(context, tr('Grupo "{0}" escondido', [escondido]), acao: tr('Desfazer'), aoAcao: () {
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
        if (!_verEscondidos && l.gruposEscondidos.contains(_grupo)) _grupo = null;
    }
    setState(() => _chaveVisiveis = null);
    // o grupo com o foco pode ter saído: o foco vai para o grupo escolhido
    if (o == OpcaoCanais.esconderGrupo || o == OpcaoCanais.ocultarEscondidos) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focoEscolhido?.requestFocus();
      });
    }
  }

  /// Os nomes sem acentos (para a pesquisa) e a ordem A–Z: numa lista grande, fora da thread da
  /// interface. Até estarem prontos, a lista A–Z mostra-se pela ordem original ("A ordenar…").
  Future<void> _indexarNomes(ConteudoLista c) async {
    final nomes = [for (final x in c.canais) x.nome];
    final r = nomes.length < 5000 ? indexarNomes(nomes) : await (widget.indexar ?? _indexarNumIsolate)(nomes);
    if (!mounted || !identical(c, _conteudo)) return;
    _nomes = r.nomes;
    _ordemAz = r.ordem;
    _lugarAz = r.lugar;
    if (!_pesquisaCanais && !_aOrdenar) return;
    // a lista troca de ordem: o canal com o foco (as linhas não têm chave: o foco ficava na mesma
    // posição, já com outro canal) continua com ele, na posição nova
    final antes = _visiveis;
    final focado = _focoColunaCanais.hasFocus && _indice < antes.length ? antes[_indice] : null;
    setState(() => _chaveVisiveis = null);
    if (focado == null) return;
    final canais = _canaisVisiveis();
    final i = canais.indexWhere((x) => identical(x, focado));
    if (i < 0) return;
    _indice = i;
    _focarNoCanal(canais, i);
  }

  /// O grupo escolhido ainda existe (depois de mudar o conteúdo ou os favoritos)? Senão (ou
  /// Favoritos/Vistos vazios), passa a "Todos os canais". Diz se mudou.
  bool _validarGrupo() {
    final g = _grupo;
    final c = _conteudo;
    if (g == null || c == null) return false;
    final existe = g == grupoFavoritos
        ? widget.lista.favoritos.isNotEmpty
        : g == grupoVistos
            ? _vistosExistentes(c).isNotEmpty
            : _porGrupo.containsKey(g) || c.grupos.contains(g);
    if (existe) return false;
    _grupo = null;
    _chaveVisiveis = null;
    return true;
  }

  void _pesquisar(String v) {
    if (_comTexto != v.isNotEmpty) setState(() => _comTexto = v.isNotEmpty);
    _atrasoPesquisa?.cancel();
    // espera que se pare de escrever: cada tecla não refaz a pesquisa
    _atrasoPesquisa = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _q = v);
    });
  }

  /// Confirmar a pesquisa (Enter, OK, «Pesquisar» do teclado): aplica-a já (sem esperar os 150 ms) e
  /// o foco vai ao 1.º canal encontrado; sem resultados fica no campo.
  void _confirmarPesquisa(String v) {
    _atrasoPesquisa?.cancel();
    setState(() {
      _comTexto = v.isNotEmpty;
      _q = v;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final canais = _canaisVisiveis();
      if (canais.isNotEmpty) {
        _focarNoCanal(canais, 0);
      } else if (_focoPesquisa.context != null) {
        _focoPesquisa.requestFocus();
      }
    });
  }

  /// Apaga a pesquisa (o campo e os resultados). Com o foco num canal encontrado, o foco vai
  /// ao 1.º canal do que fica à vista: a linha focada passaria a ser outro canal (ou deixaria
  /// de existir) e o "i de n" e o ↑ ficariam desencontrados dela.
  void _limparPesquisa() {
    _atrasoPesquisa?.cancel();
    _textoPesquisa.clear();
    final nosCanais = _focoColunaCanais.hasFocus;
    setState(() {
      _q = '';
      _comTexto = false;
    });
    if (!nosCanais) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final canais = _canaisVisiveis();
      if (canais.isNotEmpty) {
        _focarNoCanal(canais, 0);
      } else {
        final g = _focoEscolhido;
        if (g != null && g.context != null && g.canRequestFocus) g.requestFocus();
      }
    });
  }

  void _filtrarGrupos(String v) {
    if (_comTextoGrupos != v.isNotEmpty) setState(() => _comTextoGrupos = v.isNotEmpty);
    _atrasoFiltro?.cancel();
    _atrasoFiltro = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _qGrupos = v);
    });
  }

  /// Confirmar o filtro dos grupos: aplica-o já e o foco vai ao 1.º grupo encontrado (a seguir a
  /// «Todos os canais», que nunca é filtrada); sem resultados fica no campo.
  void _confirmarFiltroGrupos(String v) {
    _atrasoFiltro?.cancel();
    setState(() {
      _comTextoGrupos = v.isNotEmpty;
      _qGrupos = v;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final grupos = _gruposVisiveis();
      if (grupos.isEmpty) {
        if (_focoFiltroGrupos.context != null) _focoFiltroGrupos.requestFocus();
        return;
      }
      // o 1.º grupo pode estar fora do que a lista construiu: volta-se ao topo e foca-se no frame seguinte
      if (_scrollGrupos.hasClients) _scrollGrupos.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final f = _focosGrupos[grupos.first];
        if (f != null && f.context != null && f.canRequestFocus) {
          f.requestFocus();
        } else if (_focoFiltroGrupos.context != null) {
          _focoFiltroGrupos.requestFocus();
        }
      });
    });
  }

  /// Nos grupos: DIREITA vai sempre ao primeiro canal do grupo escolhido (a lista volta ao topo).
  KeyEventResult _teclaGrupos(KeyEvent e) {
    if (e is KeyUpEvent || e.logicalKey != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
    final canais = _canaisVisiveis();
    if (canais.isEmpty || _focoColunaCanais.context == null) return KeyEventResult.ignored;
    setState(() => _canalAFocar = canais.first);
    if (_scrollCanais.hasClients) _scrollCanais.jumpTo(0);
    // depois do frame: o primeiro canal já está construído (com o nó de regresso)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focoRegresso.requestFocus();
    });
    return KeyEventResult.handled;
  }

  /// O cursor do campo está no fim (ou no início) do texto, sem seleção.
  bool _cursorNoFim(TextEditingController c) =>
      !c.selection.isValid || (c.selection.isCollapsed && c.selection.extentOffset >= c.text.length);
  bool _cursorNoInicio(TextEditingController c) =>
      !c.selection.isValid || (c.selection.isCollapsed && c.selection.extentOffset <= 0);

  /// → no filtro dos grupos vai à pesquisa dos canais: sempre, em modo de leitura (comando); a
  /// escrever, só com o cursor no fim do texto.
  bool _setaFiltroGrupos(LogicalKeyboardKey k, bool aEscrever) {
    if (k != LogicalKeyboardKey.arrowRight || (aEscrever && !_cursorNoFim(_textoGrupos))) return false;
    if (_focoPesquisa.context == null) return false;
    _focoPesquisa.requestFocus();
    return true;
  }

  /// ← na pesquisa dos canais volta ao filtro dos grupos (se há coluna de grupos): sempre, em
  /// modo de leitura; a escrever, só com o cursor no início.
  bool _setaPesquisaCanais(LogicalKeyboardKey k, bool aEscrever) {
    if (k != LogicalKeyboardKey.arrowLeft || (aEscrever && !_cursorNoInicio(_textoPesquisa))) return false;
    if (_focoFiltroGrupos.context == null) return false;
    _focoFiltroGrupos.requestFocus();
    return true;
  }

  /// Apaga o filtro dos grupos. Com o foco num grupo, o foco vai ao grupo escolhido (ou, se ele
  /// não estiver à vista, ao campo): a linha focada pode deixar de existir.
  void _limparFiltroGrupos() {
    _atrasoFiltro?.cancel();
    _textoGrupos.clear();
    final nosGrupos = _focoColunaGrupos.hasFocus;
    setState(() {
      _qGrupos = '';
      _comTextoGrupos = false;
    });
    if (!nosGrupos) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final g = _focoEscolhido;
      if (g != null && g.context != null && g.canRequestFocus) {
        g.requestFocus();
      } else {
        _focoFiltroGrupos.requestFocus();
      }
    });
  }

  /// Escolhe o grupo `g` (null = "Todos os canais"), com os canais a partir do primeiro. Com
  /// pesquisa de canais, apaga-a e abre o grupo, com o foco nele.
  void _escolherGrupo(String? g) {
    // outro grupo: os canais dele aparecem a partir do primeiro (não onde o anterior estava)
    if (g != _grupo && _scrollCanais.hasClients) _scrollCanais.jumpTo(0);
    if (!_comTexto && _q.trim().isEmpty) {
      setState(() => _grupo = g);
      return;
    }
    _limparPesquisa();
    setState(() => _grupo = g);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focoEscolhido?.requestFocus();
    });
  }

  /// A escrever num campo (com o teclado): aí o Voltar só acaba a edição (é do [CampoTv]).
  /// Lê-se o campo como foi construído: o Voltar que acaba a edição ainda não o refez.
  bool _aEscreverEm(FocusNode foco) {
    final e = foco.context?.findAncestorWidgetOfExactType<EditableText>();
    return foco.hasFocus && e != null && !e.readOnly;
  }

  /// O Voltar com texto limpa um campo: o da coluna onde está o foco, se tiver texto; senão o outro.
  void _limparComVoltar() {
    final nosGrupos = _focoFiltroGrupos.hasFocus || _focoColunaGrupos.hasFocus;
    if (nosGrupos && _comTextoGrupos) {
      _limparFiltroGrupos();
    } else if (_comTexto) {
      _limparPesquisa();
    } else if (_comTextoGrupos) {
      _limparFiltroGrupos();
    }
  }

  /// O Voltar do sistema com texto num campo limpa-o; sem texto, sai.
  void _voltar(bool saiu, Object? _) {
    if (saiu || !(_comTexto || _comTextoGrupos)) return;
    if (_aEscreverEm(_focoPesquisa) || _aEscreverEm(_focoFiltroGrupos)) return;
    _limparComVoltar();
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
          mostrarMensagem(context, tr('Não foi possível atualizar: {0}', [texto]), tipo: MensagemTipo.erro);
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

  /// Os grupos à vista; com o filtro (`filtrar`), só os encontrados (sem os virtuais, como os
  /// favoritos, e sem os escondidos).
  List<String> _gruposVisiveis({bool filtrar = true}) {
    final c = _conteudo;
    if (c == null) return const [];
    final escondidos = widget.lista.gruposEscondidos;
    if (filtrar && _pesquisaGrupos) {
      final q = semAcentos(_qGrupos.trim());
      return [
        for (final g in c.grupos)
          if ((_gruposSemAcentos[g] ?? semAcentos(g)).contains(q) && (_verEscondidos || !escondidos.contains(g))) g,
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
    final grupo = _grupo == grupoFavoritos
        ? 'f:$_versaoFavoritos'
        : _grupo == grupoVistos ? 'v:${widget.lista.vistos.join(',')}' : 'g:${_grupo ?? ''}';
    final chave = '${ordem.name}|${_verEscondidos ? '' : escondidos.join('\u0000')}|$grupo|'
        '${q.isNotEmpty ? 'q:$q' : ''}';
    if (chave == _chaveVisiveis) return _visiveis;
    _chaveVisiveis = chave;
    _indice = 0;
    _aOrdenar = false;
    // sem grupo, os grupos escondidos ficam de fora (também da pesquisa)
    final semEscondidos = _verEscondidos || escondidos.isEmpty;
    bool visivel(int i) => semEscondidos || !escondidos.contains(c.canais[i].grupo);
    final favoritos = widget.lista.favoritos;
    final numero = int.tryParse(q); // um número escrito também encontra o canal com esse número

    if (_grupo == grupoVistos) {
      // poucos (até maxVistos), pela ordem em que se viram
      final vistos = _vistosExistentes(c);
      return _visiveis = q.isEmpty
          ? vistos
          : [
              for (final x in vistos)
                if (semAcentos(x.nome).contains(q) || (numero != null && x.numero == numero)) x,
            ];
    }
    final az = ordem == OrdemCanais.az;
    if (q.isEmpty && !az) {
      // pela ordem da lista: as listas já feitas, sem copiar
      if (_grupo == grupoFavoritos) return _visiveis = [for (final x in c.canais) if (favoritos.contains(x.id)) x];
      if (_grupo != null) return _visiveis = _porGrupo[_grupo] ?? const [];
      return _visiveis = semEscondidos ? c.canais : [for (final x in c.canais) if (!escondidos.contains(x.grupo)) x];
    }

    // as posições em `canais` do que fica à vista
    final List<int> pos;
    var jaAz = false;
    if (q.isEmpty) {
      if (_grupo == grupoFavoritos) {
        pos = [for (var i = 0; i < c.canais.length; i++) if (favoritos.contains(c.canais[i].id)) i];
      } else if (_grupo != null) {
        pos = List.of(_posicoesPorGrupo[_grupo] ?? const <int>[]);
      } else if (_ordemAz != null) {
        // "Todos os canais" A–Z: a ordem já feita (com 100 mil, ordenar aqui congelava a TV)
        pos = [for (final i in _ordemAz!) if (visivel(i)) i];
        jaAz = true;
      } else {
        pos = [for (var i = 0; i < c.canais.length; i++) if (visivel(i)) i];
      }
    } else {
      final nomes = _nomes ??= [for (final x in c.canais) semAcentos(x.nome)];
      bool encontra(int i) => nomes[i].contains(q) || (numero != null && c.canais[i].numero == numero);
      if (_grupo == grupoFavoritos) {
        pos = [for (var i = 0; i < c.canais.length; i++) if (favoritos.contains(c.canais[i].id) && encontra(i)) i];
      } else if (_grupo != null) {
        // só as posições do grupo: com 100 mil canais não se percorre a lista toda
        pos = [for (final i in _posicoesPorGrupo[_grupo] ?? const <int>[]) if (encontra(i)) i];
      } else {
        pos = [for (var i = 0; i < c.canais.length; i++) if (encontra(i) && visivel(i)) i];
      }
    }
    if (az && !jaAz) {
      final lugar = _lugarAz;
      if (lugar != null) {
        // pelo lugar na ordem A–Z já feita: sem refazer os nomes sem acentos
        pos.sort((a, b) => lugar[a] - lugar[b]);
      } else {
        _aOrdenar = true; // ainda não está pronta: a ordem original, troca-se depois
      }
    }
    return _visiveis = [for (final i in pos) c.canais[i]];
  }

  /// Quantos canais tem "Todos os canais" (sem os dos grupos escondidos, se não estão à vista).
  int _totalTodos(ConteudoLista c) {
    final escondidos = widget.lista.gruposEscondidos;
    if (_verEscondidos || escondidos.isEmpty) return c.canais.length;
    var n = c.canais.length;
    for (final g in escondidos) {
      n -= _contagens[g] ?? 0;
    }
    return n;
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
      final h = _alturaCanal();
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
      if (_conteudo == null) _erro = tr('carregamento cancelado');
    });
    _devolverFoco();
  }

  @override
  Widget build(BuildContext context) {
    final largo = MediaQuery.sizeOf(context).width >= 720;
    // sem coluna dos grupos o filtro não se vê: limpa-se (depois do frame) e o Voltar não o conta
    if (!largo && (_comTextoGrupos || _qGrupos.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && MediaQuery.sizeOf(context).width < 720) _limparFiltroGrupos();
      });
    }
    final filtroAtivo = largo && _comTextoGrupos;
    // o Voltar com texto num campo limpa-o em vez de sair
    return PopScope(
      canPop: !(_comTexto || filtroAtivo),
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
                // a tecla Voltar com texto num campo limpa-o (a escrever, o campo fica com ela)
                if ((_comTexto || filtroAtivo) &&
                    (e.logicalKey == LogicalKeyboardKey.goBack || e.logicalKey == LogicalKeyboardKey.escape)) {
                  _limparComVoltar();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Column(children: [
                _barraTopo(largo),
                Expanded(child: _corpo()),
                BarraTeclas(_comTexto || filtroAtivo
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
                  titulo: _conteudo == null ? tr('A carregar os canais') : tr('A atualizar os canais'),
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
      if (!_verEscondidos && l.gruposEscondidos.contains(_grupo)) _grupo = null;
      _chaveVisiveis = null;
    });
    if (!_verEscondidos) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focoEscolhido?.requestFocus();
      });
    }
  }

  /// O topo: "‹ Início", o nome da lista, o n.º de canais, a ordem e os grupos escondidos.
  Widget _barraTopo(bool largo) {
    final tv = ecraTv(context);
    final l = widget.lista;
    final total = _conteudo?.canais.length;
    final carregado = _conteudo != null;
    final tamanho = tv ? 16.0 : 14.0;
    final estilo = TextStyle(fontSize: tamanho);
    final inicio = TextButton(
      // sai sempre, mesmo com texto na pesquisa (só o Voltar a limpa primeiro): pop() não passa
      // pelo PopScope
      onPressed: () => Navigator.of(context).pop(),
      child: Text(tr('‹ Início'), style: estilo),
    );
    final nome = Text(l.nomeMostrado,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: tv ? 22 : 18, fontWeight: FontWeight.w700));
    final contagem = total == null
        ? null
        : Text(total == 1 ? tr('1 canal') : tr('{0} canais', [total]), style: TextStyle(color: Tokens.texto2, fontSize: tamanho));
    final ordem = Tooltip(
      message: tr('Opções dos canais'),
      child: OutlinedButton(
        onPressed: carregado ? _opcoes : null,
        child: Text(tr('Ordem: {0}', [l.ordemCanais == OrdemCanais.az ? 'A–Z' : tr('da lista')]), style: estilo),
      ),
    );
    final escondidos = OutlinedButton(
      onPressed: carregado && (l.gruposEscondidos.isNotEmpty || _verEscondidos) ? _alternarEscondidos : null,
      child: Text(tr('Grupos escondidos: {0}', [l.gruposEscondidos.length]), style: estilo),
    );
    final atualizar = IconButton(
      tooltip: tr('Atualizar a lista de canais'),
      onPressed: _atualizar,
      icon: const Icon(Icons.refresh),
    );
    // o estado da última verificação e a validade (sugestão 9), discretos
    Widget info([Widget? antes]) => Align(alignment: Alignment.centerLeft, child: _cabecalhoLista(antes));
    if (ecraTelemovel(context)) return _barraTopoTelemovel(contagem, atualizar, info);
    if (largo) {
      // abaixo de 1600 px a ordem e os grupos escondidos passam para a linha do estado
      final medio = MediaQuery.sizeOf(context).width < 1600;
      return Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e8, Tokens.e16, Tokens.e8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            inicio,
            const SizedBox(width: Tokens.e8),
            // o nome e a contagem ficam com o espaço todo do meio (um Flexible + Spacer dividiam-no a
            // meias e a ordem e os escondidos ficavam a meio do topo)
            Expanded(
              child: Row(children: [
                Flexible(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: nome)),
                if (contagem != null) ...[const SizedBox(width: Tokens.e12), contagem],
              ]),
            ),
            if (!medio) ...[ordem, const SizedBox(width: Tokens.e8), escondidos, atualizar],
          ]),
          const SizedBox(height: Tokens.e4),
          // ecrã médio: as três opções juntas no canto da linha do estado (CIMA na pesquisa dos
          // canais chega lá)
          if (medio)
            Row(children: [
              Expanded(child: info()),
              ordem,
              const SizedBox(width: Tokens.e8),
              escondidos,
              atualizar,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.e8, Tokens.e8, Tokens.e8, 0),
          child: Wrap(spacing: Tokens.e8, runSpacing: Tokens.e4, children: [ordem, escondidos]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(Tokens.e8, Tokens.e8, Tokens.e8, 0), child: info()),
      ]),
    );
  }

  /// O topo no telemóvel, como uma barra de app: ← (só o ícone), o nome da lista (até duas
  /// linhas) com o n.º de canais por baixo, ⟳ e um ⋮ com a ordem, os grupos escondidos e
  /// «Atualizar canais»; por baixo, o estado e a validade.
  Widget _barraTopoTelemovel(Widget? contagem, Widget atualizar, Widget Function([Widget?]) info) {
    final l = widget.lista;
    final carregado = _conteudo != null;
    final az = l.ordemCanais == OrdemCanais.az;
    final n = l.gruposEscondidos.length;
    PopupMenuItem<Object> item(OpcaoCanais o, String texto, {bool ativo = true, bool marcado = false}) =>
        PopupMenuItem(
          value: o,
          enabled: ativo,
          child: Row(children: [
            Expanded(child: Text(texto)),
            if (marcado) const Padding(
              padding: EdgeInsets.only(left: Tokens.e8),
              child: Icon(Icons.check_rounded, color: Tokens.acento),
            ),
          ]),
        );
    // «Atualizar canais» não é uma opção dos canais: vai como o próprio [_atualizar]
    final menu = PopupMenuButton<Object>(
      key: const Key('menu-lista-aberta'),
      tooltip: tr('Mais opções'),
      enabled: carregado,
      icon: const Icon(Icons.more_vert),
      onSelected: (o) => o is OpcaoCanais ? _aplicarOpcao(o, null) : _atualizar(),
      itemBuilder: (_) => [
        item(OpcaoCanais.ordemLista, tr('Ordem: da lista'), marcado: !az),
        item(OpcaoCanais.ordemAz, tr('Ordem: A–Z'), marcado: az),
        if (_verEscondidos)
          item(OpcaoCanais.ocultarEscondidos, tr('Ocultar grupos escondidos'))
        else
          item(OpcaoCanais.verEscondidos, tr('Mostrar grupos escondidos ({0})', [n]), ativo: n > 0),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(value: _atualizar, child: Text(tr('Atualizar canais'))),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.e4, Tokens.e4, Tokens.e4, Tokens.e4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(
            tooltip: tr('Voltar ao Início'),
            // sai sempre, mesmo com texto na pesquisa (como o «‹ Início»)
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: Tokens.e4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(l.nomeMostrado,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.2)),
              ?contagem,
            ]),
          ),
          atualizar,
          menu,
        ]),
        Padding(padding: const EdgeInsets.fromLTRB(Tokens.e12, Tokens.e4, Tokens.e12, 0), child: info()),
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
            ? tr('Ainda não foi verificada')
            // "hoje às 14:05", "há 3 dias" ou uma data ("em 02/01/2026")
            : tr('Verificada {0}{1}', [quando.startsWith(RegExp('[0-9]')) ? tr('em ') : '', quando]),
        style: secundario,
      ),
      // os canais vêm da cache: discreto, com a hora (o "Atualizar" está em cima)
      if (_daCache != null && _conteudo != null)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history_rounded, size: tv ? 16 : 14, color: Tokens.texto2),
          const SizedBox(width: 4),
          Flexible(child: Text(tr('da cache · {0}', [dataRelativa(_daCache!)]), maxLines: 1,
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
                  Text(tr('Não foi possível abrir a lista: {0}', [_erro]), textAlign: TextAlign.center),
                  const SizedBox(height: Tokens.e16),
                  FilledButton(autofocus: true, onPressed: _carregar, child: Text(tr('Tentar de novo'))),
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _campoPesquisaCanais(),
                _cabecalhoCanais(canais.length, pesquisa),
                Expanded(child: lista),
              ]),
            ),
          ),
        ]),
      );
    }
    final corpoCanais = [
      _campoPesquisaCanais(),
      _cabecalhoCanais(canais.length, pesquisa),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.e12, 0, Tokens.e12, Tokens.e12),
          child: SuperficieVidro(child: lista),
        ),
      ),
    ];
    if (ecraTelemovel(context)) {
      // no telemóvel: os grupos num botão «Grupo: …» que abre uma folha com pesquisa
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _botaoGrupo(),
        ...corpoCanais,
      ]);
    }
    // sem coluna dos grupos (nem filtro): os grupos numa fila de chips por cima da pesquisa dos canais
    final grupos = _gruposVisiveis(filtrar: false);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.e16),
          // o 1.º chip, "Todos", tira a escolha do grupo
          itemCount: grupos.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final g = i == 0 ? null : grupos[i - 1];
            return ChoiceChip(
              label: Text(g == null ? tr('Todos') : _nomeGrupo(g), maxLines: 1, overflow: TextOverflow.ellipsis),
              // a pesquisa procura no grupo escolhido: ele continua marcado
              selected: g == _grupo,
              onSelected: (_) => _escolherGrupo(g),
            );
          },
        ),
      ),
      ...corpoCanais,
    ]);
  }

  /// O nome de um grupo para mostrar (null = «Todos os canais»).
  static String _nomeGrupo(String? g) =>
      g == null ? tr('Todos os canais') : (g == grupoFavoritos || g == grupoVistos || g == semGrupo ? tr(g) : g);

  /// Quantos canais tem o grupo `g` (os virtuais incluídos).
  int _contagemGrupo(String g) => g == grupoFavoritos
      ? widget.lista.favoritos.length
      : g == grupoVistos ? _vistosExistentes(_conteudo!).length : (_contagens[g] ?? 0);

  /// No telemóvel: «Grupo: (nome) ▾», da largura do ecrã; abre a folha dos grupos.
  Widget _botaoGrupo() => Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e12, Tokens.e4, Tokens.e12, 0),
        child: OutlinedButton(
          key: const Key('botao-grupo'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(Tokens.alvoToque),
            padding: const EdgeInsets.symmetric(horizontal: Tokens.e16, vertical: Tokens.e8),
          ),
          onPressed: _escolherNaFolha,
          child: Row(children: [
            Expanded(
              child: Text(tr('Grupo: {0}', [_nomeGrupo(_grupo)]), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: Tokens.e8),
            const Icon(Icons.arrow_drop_down_rounded),
          ]),
        ),
      );

  /// A folha dos grupos (telemóvel): pesquisa, «Todos os canais», Favoritos e Vistos (se houver)
  /// e cada grupo com a contagem (os escondidos só com «Mostrar grupos escondidos»). Escolher um
  /// fecha-a e mostra-o; o toque longo num grupo abre o menu dele; arrastar para baixo fecha-a.
  Future<void> _escolherNaFolha() async {
    final c = _conteudo;
    if (c == null) return;
    final todos = _gruposVisiveis(filtrar: false);
    final escondidos = widget.lista.gruposEscondidos;
    final altura = MediaQuery.sizeOf(context).height;
    // o grupo escolhido (que não «Todos os canais», sempre a 1.ª) fica à vista quando a folha abre
    final chaveEscolhido = GlobalKey();
    final rolar = ScrollController();
    if (_grupo != null) {
      var tentativas = 0;
      void mostrarEscolhido(Duration _) {
        final ctx = chaveEscolhido.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, alignment: .3);
          return;
        }
        // a linha ainda não foi construída (a lista só constrói o que está perto da vista):
        // desce-se uma folha e tenta-se no frame seguinte
        if (!rolar.hasClients || tentativas++ > 50) return;
        final p = rolar.position;
        if (p.pixels >= p.maxScrollExtent) return;
        rolar.jumpTo((p.pixels + p.viewportDimension).clamp(0, p.maxScrollExtent));
        WidgetsBinding.instance.addPostFrameCallback(mostrarEscolhido);
      }

      WidgetsBinding.instance.addPostFrameCallback(mostrarEscolhido);
    }
    // (grupo, false) = escolheu (null = «Todos os canais»); (grupo, true) = toque longo (o menu
    // do grupo); null = fechou sem escolher
    final r = await showModalBottomSheet<(String?, bool)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        var q = '';
        // a altura da folha ao abrir: com a pesquisa nunca fica mais baixa (não salta a cada tecla)
        double? alturaInicial;
        final chaveFolha = GlobalKey();
        return StatefulBuilder(builder: (ctx, mudar) {
          final busca = semAcentos(q.trim());
          // com pesquisa, só os grupos encontrados (sem Favoritos nem Vistos, como no filtro da TV)
          final grupos = busca.isEmpty
              ? todos
              : [
                  for (final g in c.grupos)
                    if (todos.contains(g) && (_gruposSemAcentos[g] ?? semAcentos(g)).contains(busca)) g,
                ];
          Widget linha(String? g, int n) {
            final escondido = g != null && escondidos.contains(g);
            final real = g != null && g != grupoFavoritos && g != grupoVistos;
            return ListTile(
              key: g != null && g == _grupo ? chaveEscolhido : null,
              selected: g == _grupo,
              title: _comRealce(_nomeGrupo(g), g == null ? '' : busca,
                  TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: escondido ? Tokens.texto2 : null),
                  linhas: 2),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (escondido) ...[
                  const Icon(Icons.visibility_off_outlined, size: 16, color: Tokens.texto2, semanticLabel: 'escondido'),
                  const SizedBox(width: 6),
                ],
                Text('$n', style: const TextStyle(color: Tokens.texto2, fontSize: 13)),
              ]),
              onTap: () => Navigator.pop(ctx, (g, false)),
              onLongPress: real ? () => Navigator.pop(ctx, (g, true)) : null,
            );
          }

          if (alturaInicial == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final caixa = chaveFolha.currentContext?.findRenderObject();
              if (caixa is RenderBox && caixa.hasSize) alturaInicial = caixa.size.height;
            });
          }
          final maxima = altura * .85;
          final teclado = MediaQuery.viewInsetsOf(ctx).bottom;
          return ConstrainedBox(
            key: const Key('folha-grupos'),
            constraints: BoxConstraints(
              minHeight: alturaInicial == null ? 0 : math.min(alturaInicial! + teclado, maxima),
              maxHeight: maxima,
            ),
            child: Padding(
              // o teclado no ecrã não tapa a lista
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
              child: Column(key: chaveFolha, mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e8),
                  child: CampoTv(
                    decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: tr('Pesquisar grupos')),
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => mudar(() => q = v),
                  ),
                ),
                Flexible(
                  child: ListView(
                    controller: rolar,
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: Tokens.e8),
                    children: [
                      // «Todos os canais» nunca é filtrada
                      linha(null, _totalTodos(c)),
                      for (final g in grupos) linha(g, _contagemGrupo(g)),
                      if (busca.isNotEmpty && grupos.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: Tokens.e16, vertical: Tokens.e12),
                          child: Text(tr('Nenhum grupo'), style: TextStyle(color: Tokens.texto2, fontSize: 15)),
                        ),
                    ],
                  ),
                ),
              ]),
            ),
          );
        });
      },
    );
    rolar.dispose();
    if (r == null || !mounted) return;
    final (g, menu) = r;
    if (menu) {
      unawaited(_opcoes(g));
    } else {
      _escolherGrupo(g);
    }
  }

  /// Enquanto carrega: blocos com a forma dos grupos e dos canais, com um brilho a passar.
  Widget _esqueleto(bool largo, bool tv) {
    final h = _alturaCanal();
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

  /// Um campo no topo de uma coluna.
  Widget _campoColuna(Key chave, TextEditingController texto, FocusNode foco, IconData icone, String dica,
          ValueChanged<String> aoMudar, ValueChanged<String> aoConfirmar,
          bool Function(LogicalKeyboardKey, bool) aoSeta) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e12, Tokens.e8, Tokens.e12, 0),
        child: CampoTv(
          key: chave,
          controller: texto,
          focusNode: foco,
          decoration: InputDecoration(prefixIcon: Icon(icone), hintText: dica),
          onChanged: aoMudar,
          onSubmitted: aoConfirmar,
          textInputAction: TextInputAction.search,
          aoSeta: aoSeta,
        ),
      );

  /// A pesquisa dos canais: sem grupo, em todos; com grupo, só nele ("Pesquisar em Desporto").
  Widget _campoPesquisaCanais() {
    final g = _grupo;
    final dica = g == null ? tr('Pesquisar canais ou número') : tr('Pesquisar em {0}', [g == grupoFavoritos ? tr('Favoritos') : _nomeGrupo(g)]);
    return _campoColuna(const Key('pesquisa-canais'), _textoPesquisa, _focoPesquisa, Icons.search, dica, _pesquisar,
        _confirmarPesquisa, _setaPesquisaCanais);
  }

  /// O texto com a parte encontrada (`q`, já sem acentos) em [Tokens.anelFoco]; sem ela, só o texto.
  Widget _comRealce(String texto, String q, TextStyle estilo, {int linhas = 1}) {
    final normal = q.isEmpty ? '' : semAcentos(texto);
    // só quando as posições batem certo (tirar os acentos quase nunca muda o comprimento)
    final i = normal.length == texto.length ? normal.indexOf(q) : -1;
    if (i < 0) return Text(texto, maxLines: linhas, overflow: TextOverflow.ellipsis, style: estilo);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: texto.substring(0, i)),
        TextSpan(text: texto.substring(i, i + q.length), style: const TextStyle(color: Tokens.anelFoco)),
        TextSpan(text: texto.substring(i + q.length)),
      ]),
      maxLines: linhas,
      overflow: TextOverflow.ellipsis,
      style: estilo,
    );
  }

  /// Por cima dos canais: o grupo (com pesquisa, "Desporto · n", ou sem grupo "Canais · n") à
  /// esquerda e `i de n` à direita (i = o canal com o foco).
  Widget _cabecalhoCanais(int n, bool pesquisa) {
    final estilo = _estiloCabecalho();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e12, Tokens.e16, Tokens.e4),
      child: Row(children: [
        Expanded(
          child: Text(
            pesquisa ? '${_grupo == null ? tr('Canais') : _nomeGrupo(_grupo)} · $n' : _nomeGrupo(_grupo),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: estilo,
          ),
        ),
        if (_aOrdenar) ...[
          const SizedBox(width: Tokens.e12),
          Text('A ordenar…', style: estilo.copyWith(fontWeight: FontWeight.w400)),
        ],
        // o «i de n» é para o comando: no telemóvel é só ruído
        if (n > 0 && !ecraTelemovel(context)) ...[
          const SizedBox(width: Tokens.e12),
          Text(tr('{0} de {1}', [_indice.clamp(0, n - 1) + 1, n]), key: const Key('contador-canais'), style: estilo),
        ],
      ]),
    );
  }

  /// ↑ no primeiro grupo ou no primeiro canal vai ao campo dessa coluna (a procura direcional podia
  /// ir parar à ordem ou aos grupos escondidos, que estão mais perto).
  bool _subirParaCampo(KeyEvent e, bool noPrimeiro, FocusNode campo) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.arrowUp || !noPrimeiro) return false;
    campo.requestFocus();
    return true;
  }

  Widget _colunaGrupos() {
    final grupos = _gruposVisiveis();
    final tv = ecraTv(context);
    final q = _pesquisaGrupos ? semAcentos(_qGrupos.trim()) : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _campoColuna(const Key('filtro-grupos'), _textoGrupos, _focoFiltroGrupos, Icons.filter_list,
          tr('Filtrar grupos'), _filtrarGrupos, _confirmarFiltroGrupos, _setaFiltroGrupos),
      Expanded(
        child: Focus(
          focusNode: _focoColunaGrupos,
          includeSemantics: false,
          // "Todos os canais" é sempre a primeira linha
          onKeyEvent: (_, e) => _subirParaCampo(e, _focoTodos.hasPrimaryFocus, _focoFiltroGrupos)
              ? KeyEventResult.handled
              : _teclaGrupos(e),
          child: FocusTraversalGroup(
          child: ListView.builder(
            key: const Key('lista-grupos'),
            controller: _scrollGrupos,
            // margem para a borda de realce não ser cortada pelo vidro
            padding: const EdgeInsets.all(_margemLista),
            // a 1.ª linha, "Todos os canais", nunca é filtrada
            itemCount: grupos.length + 1,
            itemBuilder: (_, j) {
              if (j == 0) return _linhaTodos(tv);
              final g = grupos[j - 1];
              final n = _contagemGrupo(g);
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
                  // a pesquisa procura no grupo escolhido: ele continua marcado
                  selected: g == _grupo,
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

  /// "Todos os canais", com o total: escolhê-la tira a escolha do grupo.
  Widget _linhaTodos(bool tv) => RealceFoco(
        construir: (_, aoMudarFoco) => ListTile(
          focusNode: _focoTodos,
          onFocusChange: aoMudarFoco,
          dense: !tv,
          autofocus: _grupo == null,
          selected: _grupo == null,
          title: Text(tr('Todos os canais'), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: tv ? 17 : 14, fontWeight: FontWeight.w500)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${_totalTodos(_conteudo!)}', style: TextStyle(color: Tokens.texto2, fontSize: tv ? 15 : 12.5)),
          ]),
          onTap: () => _escolherGrupo(null),
        ),
      );

  Widget _listaCanais(List<Canal> canais) {
    if (canais.isEmpty) {
      return Center(child: Text(tr('Nenhum canal.'), style: TextStyle(color: Tokens.texto2)));
    }
    final tv = ecraTv(context);
    final telemovel = ecraTelemovel(context);
    final pesquisa = _pesquisaCanais;
    final q = pesquisa ? semAcentos(_q.trim()) : '';
    // no telemóvel o número só tem a largura dos algarismos do maior (o nome fica com o resto)
    final larguraNumero = tv
        ? 64.0
        : telemovel
            ? (_algarismos(canais) * 14 * .62 * fatorTexto(context)).ceilToDouble() + Tokens.e8
            : 52.0;
    // no ecrã estreito (sem coluna de grupos) o foco começa no 1.º canal
    final focarPrimeiro = MediaQuery.sizeOf(context).width < 720;
    return Focus(
      focusNode: _focoColunaCanais,
      includeSemantics: false,
      onKeyEvent: _teclaCanais,
      child: FocusTraversalGroup(
        // virtualizada (itemExtent fixo) e sem animar cada canal: listas de 100 mil
        child: ListView.builder(
          key: const Key('lista-canais'),
          controller: _scrollCanais,
          padding: const EdgeInsets.all(_margemLista),
          itemCount: canais.length,
          itemExtent: _alturaCanal(),
          itemBuilder: (_, i) {
            final c = canais[i];
            final fav = widget.lista.favoritos.contains(c.id);
            void abrir() => _abrirCanal(canais, i);
            void favorito() => _alternarFavorito(canais, i);
            // a linha é a única paragem do foco: a estrela só mostra o estado e responde ao
            // toque/rato; no comando, OK mantido (ou toque longo, ou clique direito) põe/tira
            final numero = '${c.numero ?? i + 1}';
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
                      contentPadding: EdgeInsets.only(
                          left: (telemovel ? Tokens.e8 : Tokens.e16) + larguraNumero, right: telemovel ? 0 : Tokens.e8),
                      leading: _Logo(c.logo, c.nome, tamanho: tv ? 52 : 40),
                      minLeadingWidth: tv ? 52 : 40,
                      horizontalTitleGap: telemovel ? Tokens.e12 : null,
                      title: _comRealce(c.nome, q, TextStyle(fontSize: tv ? 19 : 15, fontWeight: FontWeight.w500),
                          linhas: telemovel ? 2 : 1),
                      subtitle: pesquisa
                          ? Text(c.grupo, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: tv ? 14 : 12, color: Tokens.texto2))
                          : null,
                      trailing: ExcludeFocus(
                        child: IconButton(
                          tooltip: fav ? tr('Tirar dos favoritos') : tr('Pôr nos favoritos'),
                          icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: fav ? Tokens.aviso : Tokens.texto2, size: tv ? 28 : 24),
                          onPressed: favorito,
                          // no telemóvel, um alvo de 48 × 48 (também numa janela estreita do
                          // computador, onde o tema não junta a margem de toque)
                          constraints: telemovel
                              ? const BoxConstraints(minWidth: Tokens.alvoToque, minHeight: Tokens.alvoToque)
                              : null,
                          padding: telemovel ? EdgeInsets.zero : null,
                        ),
                      ),
                      onTap: abrir,
                      onLongPress: favorito,
                    ),
                  ),
                  Positioned(
                    left: telemovel ? Tokens.e8 : Tokens.e16,
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

  /// Quantos algarismos tem o maior número de `canais` (o do portal ou a posição), pelo menos 2.
  /// Guardado para a mesma lista (com 100 mil canais não se refaz a cada build).
  int _algarismos(List<Canal> canais) {
    if (identical(canais, _algarismosDe)) return _nAlgarismos;
    var maior = canais.length;
    for (final c in canais) {
      final n = c.numero;
      if (n != null && n > maior) maior = n;
    }
    _algarismosDe = canais;
    return _nAlgarismos = '$maior'.length < 2 ? 2 : '$maior'.length;
  }

  List<Canal>? _algarismosDe;
  int _nAlgarismos = 2;

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
  /// grupos de cima, que pode estar mais perto).
  KeyEventResult _teclaCanais(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final d = _digito(e.logicalKey);
    if (d != null) {
      if (e is KeyDownEvent) _irParaNumero(d);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
    if (_subirParaCampo(e, _indice == 0, _focoPesquisa)) return KeyEventResult.handled;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      final g = _focoEscolhido;
      if (g != null && (g.context?.mounted ?? false) && g.canRequestFocus) {
        g.requestFocus();
        return KeyEventResult.handled;
      }
      // sem grupos à vista (filtro sem resultados): vai ao filtro, que está na coluna dos grupos
      if (_focoFiltroGrupos.context?.mounted ?? false) {
        _focoFiltroGrupos.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// "Desfazer": repõe o canal como estava antes (só se ainda não foi mudado entretanto).
  void _desfazerFavorito(String id, bool tinhaPassadoAFavorito) {
    if (!mounted || widget.lista.favoritos.contains(id) != tinhaPassadoAFavorito) return;
    widget.biblioteca.alternarFavorito(widget.lista.id, id);
    setState(() {
      _versaoFavoritos++;
      _validarGrupo();
    });
  }

  /// Põe/tira o canal `i` dos favoritos (o conjunto muda logo; a gravação em disco segue em
  /// segundo plano). No grupo dos favoritos o canal sai da lista: o foco passa ao que fica no
  /// lugar dele (ou, sem favoritos, a "Todos os canais").
  void _alternarFavorito(List<Canal> canais, int i) {
    final c = canais[i];
    final agora = !widget.lista.favoritos.contains(c.id);
    widget.biblioteca.alternarFavorito(widget.lista.id, c.id);
    final noGrupoFav = _grupo == grupoFavoritos && !_pesquisaCanais;
    var saiu = false;
    setState(() {
      _versaoFavoritos++;
      // o último favorito: os Favoritos desaparecem (também com pesquisa) e fica "Todos os canais"
      saiu = _validarGrupo();
    });
    mostrarMensagem(context, agora ? tr('{0} está nos favoritos', [c.nome]) : tr('{0} saiu dos favoritos', [c.nome]),
        acao: tr('Desfazer'), aoAcao: () => _desfazerFavorito(c.id, agora));
    if (!noGrupoFav || agora) return;
    final restantes = _canaisVisiveis();
    if (saiu || restantes.isEmpty) {
      if (!saiu) setState(() => _grupo = null);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focoEscolhido?.requestFocus();
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
Future<IndiceNomes> _indexarNumIsolate(List<String> nomes) => Isolate.run(() => indexarNomes(nomes));

/// Os nomes sem acentos, as posições por ordem A–Z e o lugar de cada posição nessa ordem.
typedef IndiceNomes = ({List<String> nomes, Int32List ordem, Int32List lugar});

/// Indexa os `nomes` (ver [IndiceNomes]).
IndiceNomes indexarNomes(List<String> nomes) {
  final normal = [for (final n in nomes) semAcentos(n)];
  final ordem = Int32List.fromList(List<int>.generate(normal.length, (i) => i)
    ..sort((a, b) {
      final r = normal[a].compareTo(normal[b]);
      return r != 0 ? r : a - b;
    }));
  final lugar = Int32List(normal.length);
  for (var k = 0; k < ordem.length; k++) {
    lugar[ordem[k]] = k;
  }
  return (nomes: normal, ordem: ordem, lugar: lugar);
}
