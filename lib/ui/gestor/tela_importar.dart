import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../../importar/importar.dart';
import '../../importar/stbstalker.dart';
import '../../importar/telegram.dart';
import '../../modelo/conta.dart';
import '../../rede/http.dart';
import '../../tarefas/servico_tarefas.dart';
import '../../verificar/servico.dart';
import '../adicionar.dart';
import '../campo_tv.dart';
import '../design/design.dart';
import '../design/mensagens.dart';
import '../navegacao_blocos.dart';
import '../verificar/dialogos_gestor.dart';
import 'calendario_intervalo.dart';
import 'indicador_atividade.dart';
import '../../idioma/idioma.dart';
import '../../edicao.dart';

/// As origens de onde se importa.
enum OrigemImportacao { ficheiros, adicionar, stbstalker, telegram, doPlayer }

/// Uma pesquisa/importação que falhou: a mensagem é a que se mostra (sem "Exception:").
class _Falha implements Exception {
  const _Falha(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// As importações do Gestor: cada uma corre numa [Tarefa] e este registo guarda o [ResumoImportacao]
/// de cada uma e qual foi a última a arrancar (a que o painel "Resultado" mostra). Pertence ao
/// Gestor, não ao ecrã: sair e voltar a meio de uma pesquisa não perde nada.
class RegistoImportacoes extends ChangeNotifier {
  Tarefa? _ultima;
  final _frutos = <String, List<ResumoImportacao>>{};

  /// A importação mais recente (a decorrer ou acabada); null se ainda não houve nenhuma.
  Tarefa? get ultima => _ultima;

  /// O resumo de uma importação acabada (null enquanto decorre, ou se falhou).
  ResumoImportacao? resumoDe(Tarefa t) => (_frutos[t.id] ?? const []).firstOrNull;

  /// Arranca já a importação (devolve a tarefa sem esperar).
  Tarefa iniciar(ServicoTarefas tarefas, String titulo, Future<ResumoImportacao> Function(Progresso p) trabalho) {
    final fruto = <ResumoImportacao>[];
    final t = tarefas.iniciar(titulo, (p) async {
      final r = await trabalho(p);
      fruto.add(r);
      return r.texto;
    });
    _frutos[t.id] = fruto;
    _ultima = t;
    notifyListeners();
    return t;
  }
}

/// O sub-ecrã de importar (passo 1): quatro origens (Ficheiros · Adicionar lista · Listas do stbstalker ·
/// De Ver TV), o painel da origem escolhida e o painel "Resultado" da última importação, com
/// "Verificar as n novas". Cada importação é uma tarefa em segundo plano: o botão fica logo livre
/// (carregar outra vez inicia outra) e o ecrã só observa.
class TelaImportar extends StatefulWidget {
  const TelaImportar({
    super.key,
    required this.biblioteca,
    required this.area,
    required this.servico,
    required this.tarefas,
    required this.registo,
    required this.baseStb,
    required this.baseTelegram,
    required this.focoOrigens,
  });

  final Biblioteca biblioteca;
  final AreaGestor area;
  final ServicoVerificacao servico;
  final ServicoTarefas tarefas;
  final RegistoImportacoes registo;
  final String baseStb;
  final String baseTelegram;

  /// O foco da primeira origem (recebe o foco ao abrir o ecrã).
  final FocusNode focoOrigens;

  @override
  State<TelaImportar> createState() => _TelaImportarState();
}

class _TelaImportarState extends State<TelaImportar> {
  OrigemImportacao _origem = OrigemImportacao.ficheiros;
  late DateTime _inicio = _hoje(), _fim = _hoje();
  final _texto = TextEditingController();

  /// "Adicionar lista": o tipo escolhido e os campos (o MAC começa com o prefixo habitual).
  FormaLista _forma = FormaLista.portalMac;
  static const _prefixoMac = '00:1A:79:';
  final _endereco = TextEditingController();
  final _mac = TextEditingController(text: _prefixoMac);
  final _utilizador = TextEditingController();
  final _password = TextEditingController();
  final _focosFormas = [for (final f in FormaLista.values) FocusNode(debugLabel: 'Tipo ${f.nome}')];

  /// O canal do Telegram (michelstv4 por omissão; o campo fica aberto a outros canais públicos).
  final _canalTg = TextEditingController(text: edicaoPartilha ? '' : telegramCanalOmissao);

  /// Os blocos para CIMA/BAIXO: origens, painel da origem, resultado e "Limpar o Gestor".
  final _blocos = [
    for (final b in ['Origens', 'Painel', 'Resultado', 'Limpar'])
      FocusNode(debugLabel: 'Bloco $b', canRequestFocus: false, skipTraversal: true),
  ];

  Biblioteca get _b => widget.biblioteca;
  AreaGestor get _g => widget.area;

  @override
  void initState() {
    super.initState();
    // o tipo com o foco fica escolhido: os campos dele aparecem logo (sem ter de carregar em OK)
    for (final (i, f) in _focosFormas.indexed) {
      f.addListener(() {
        final forma = FormaLista.values[i];
        if (mounted && f.hasPrimaryFocus && _forma != forma) setState(() => _forma = forma);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_texto, _endereco, _mac, _utilizador, _password, _canalTg]) {
      c.dispose();
    }
    for (final f in _focosFormas) {
      f.dispose();
    }
    for (final b in _blocos) {
      b.dispose();
    }
    super.dispose();
  }

  static DateTime _hoje() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _dd(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _n(int n, String um, String varios) => '$n ${tr(n == 1 ? um : varios)}';

  void _aviso(String t) {
    if (mounted) mostrarMensagem(context, t);
  }

  // ---------------------------------------------------------------- importar

  Future<void> _escolherFicheiros() async {
    final List<PlatformFile> ficheiros;
    try {
      ficheiros = await FilePicker.pickFiles(dialogTitle: tr('Escolher listas'));
    } catch (e) {
      return _aviso(tr('Não foi possível abrir os ficheiros: {0}', [descreverErro(e)]));
    }
    if (ficheiros.isEmpty) return;
    widget.registo.iniciar(
        widget.tarefas, tr('Importar ficheiros'), (p) => importarEscolhidos(_g, ficheiros, p: p));
  }

  /// "Juntar ao Gestor" do "Adicionar lista": a lista dos campos (ou as coladas, em "Várias").
  void _juntar() {
    if (_forma == FormaLista.varias) {
      final texto = _texto.text;
      if (texto.trim().isEmpty) return _aviso(tr('Cole primeiro as listas, uma por linha.'));
      widget.registo.iniciar(widget.tarefas, tr('Importar texto colado'), (p) => importarTexto(_g, texto));
      _texto.clear();
      return;
    }
    final r = contaManual(_forma,
        endereco: _endereco.text, mac: _mac.text, utilizador: _utilizador.text, password: _password.text);
    if (r.erro != null) return _aviso(r.erro!);
    final c = r.conta!;
    widget.registo.iniciar(widget.tarefas, tr('Adicionar lista · {0}', [c.nome]), (p) => importarConta(_g, c));
    _endereco.clear();
    _mac.text = _prefixoMac;
    _utilizador.clear();
    _password.clear();
  }

  void _procurarStb() {
    if (edicaoPartilha) return;
    // as datas podem mudar durante a pesquisa: o resumo fala das que foram pesquisadas
    final inicio = _inicio, fim = _fim, base = widget.baseStb;
    final periodo = inicio == fim ? _dd(inicio) : '${_dd(inicio)} a ${_dd(fim)}';
    widget.registo.iniciar(widget.tarefas, '${tr(tituloTarefaStb)} · $periodo', (p) async {
      p(null, tr('a procurar os posts'));
      final parada = _Falha(tr('Pesquisa parada. Nenhuma lista foi junta ao Gestor.'));
      final ResultadoStb r;
      try {
        r = await importarEntre(inicio, fim,
            base: base,
            aoProgresso: (lidos, posts, linhas) => p(lidos / posts, tr('{0} encontradas', [linhas])),
            cancelado: () => p.cancelado);
      } on Cancelado {
        throw parada;
      } catch (e) {
        if (p.cancelado) throw parada;
        throw _Falha(tr('Não foi possível pesquisar: {0}', [descreverErro(e)]));
      }
      // o "Parar" pode chegar com o último post: nada entra no Gestor depois dele
      if (p.cancelado) throw parada;
      if (r.erro != null) return ResumoImportacao(erros: [r.erro!]);
      final contas = [
        for (final l in r.linhas)
          if (contaDeLinha(l) case final c?) Importada(c),
      ];
      return juntarAoGestor(_g, () => _g.adicionar(contas), encontradas: contas.length);
    });
  }

  void _procurarTelegram() {
    if (edicaoPartilha) return;
    final canal = canalDeTexto(_canalTg.text);
    if (canal == null) return _aviso(tr('Escreva o nome do canal (por exemplo @michelstv4).'));
    final inicio = _inicio, fim = _fim, base = widget.baseTelegram;
    final periodo = inicio == fim ? _dd(inicio) : '${_dd(inicio)} a ${_dd(fim)}';
    widget.registo.iniciar(widget.tarefas, '${tr(tituloTarefaTelegram)} · @$canal · $periodo', (p) async {
      p(null, tr('a procurar as mensagens'));
      final parada = _Falha(tr('Pesquisa parada. Nenhuma lista foi junta ao Gestor.'));
      final ResultadoTelegram r;
      try {
        r = await importarTelegram(canal, inicio, fim,
            base: base,
            aoProgresso: (lidas, encontradas) => p(null, tr('{0} encontradas', [encontradas])),
            cancelado: () => p.cancelado);
      } on Cancelado {
        throw parada;
      } catch (e) {
        if (p.cancelado) throw parada;
        throw _Falha(tr('Não foi possível pesquisar: {0}', [descreverErro(e)]));
      }
      if (p.cancelado) throw parada;
      if (r.erro != null) return ResumoImportacao(erros: [r.erro!]);
      final contas = [for (final c in r.contas) Importada(c)];
      return juntarAoGestor(_g, () => _g.adicionar(contas), encontradas: contas.length);
    });
  }

  void _importarDoPlayer() {
    final n = _b.listas.length;
    if (n == 0) return _aviso(tr('Ainda não há listas em Ver TV.'));
    widget.registo.iniciar(widget.tarefas, tr('Importar de Ver TV'), (p) async {
      p(null, _n(n, 'lista', 'listas'));
      return juntarAoGestor(_g, () => _g.importarDoPlayer(_b), encontradas: n);
    });
  }

  /// "Verificar as n novas": só as novas desta importação entram na fila (as que já lá estão ou
  /// que entretanto saíram do Gestor ficam de fora).
  void _verificarNovas(ResumoImportacao r) {
    final listas = [
      for (final id in r.idsNovas)
        if (_g.porId(id) case final l? when !widget.servico.aVerificar(id)) l,
    ];
    if (listas.isEmpty) return _aviso(tr('As listas novas já estão na fila.'));
    widget.servico.verificarVarias(listas);
    _aviso(listas.length == 1 ? tr('1 lista entrou na fila.') : tr('{0} listas entraram na fila.', [listas.length]));
  }

  Future<void> _limpar() async {
    final n = _g.listas.length;
    if (n == 0) return _aviso(tr('O Gestor já está vazio.'));
    final ok = await confirmar(context,
        icone: Icons.delete_sweep_outlined,
        titulo: tr('Limpar o Gestor?'),
        texto: tr('{0}. As listas de Ver TV não mudam.', [n == 1 ? tr('A lista do Gestor sai') : tr('As {0} listas do Gestor saem', [n])]),
        acao: tr('Limpar'));
    if (!ok) return;
    if (widget.servico.ocupado) widget.servico.parar();
    await _g.limpar();
  }

  /// O calendário no próprio ecrã (o seletor do sistema não deixava o OK do comando confirmar o dia).
  /// Ao voltar com um intervalo, guarda-o e inicia a pesquisa.
  Future<void> _escolherDatas() async {
    final r = await escolherIntervalo(context, inicio: _inicio, fim: _fim, hoje: _hoje());
    if (r == null || !mounted) return;
    setState(() {
      _inicio = r.start;
      _fim = r.end;
    });
    if (_origem == OrigemImportacao.telegram) {
      _procurarTelegram();
    } else {
      _procurarStb();
    }
  }

  // ---------------------------------------------------------------- construção

  Widget _bloco(int i, Widget filho, {bool vidro = true}) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.e16),
        child: Focus(
          focusNode: _blocos[i],
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          child: vidro ? SuperficieVidro(padding: const EdgeInsets.all(Tokens.e16 + 4), child: filho) : filho,
        ),
      );

  /// Os cartões das origens: quatro numa linha (ou dois e dois num ecrã estreito); no telemóvel,
  /// uma por linha (ícone, título e descrição lado a lado: nada se parte a meio da palavra).
  Widget _origens() => LayoutBuilder(builder: (context, caixa) {
        final telemovel = ecraTelemovel(context);
        final nPlayer = _b.listas.length;
        final origens = <(OrigemImportacao, IconData, String, String)>[
          (OrigemImportacao.ficheiros, Icons.file_open_outlined, tr('Ficheiros'), tr('Accounts.json, .ini, .m3u, .txt')),
          (OrigemImportacao.adicionar, Icons.playlist_add_rounded, tr('Adicionar lista'), tr('Portal MAC, Xtream ou M3U')),
          if (!edicaoPartilha) ...[
            (OrigemImportacao.stbstalker, Icons.event_note_outlined, tr('Listas do stbstalker'),
                tr('Publicadas entre duas datas')),
            (OrigemImportacao.telegram, Icons.send_outlined, tr('Listas do Telegram'),
                tr('De um canal público')),
          ],
          (OrigemImportacao.doPlayer, Icons.download_for_offline_outlined, tr('De Ver TV'),
              nPlayer == 0 ? tr('Ainda não há listas em Ver TV') : tr('As {0} listas que já tens', [nPlayer])),
        ];
        // todas as origens numa só linha (assim, BAIXO de qualquer uma vai ao painel, não a outra
        // origem); num ecrã estreito (telemóvel) ficam uma por linha
        final colunas = telemovel ? 1 : origens.length;
        final cartoes = [
          for (final (i, (o, icone, titulo, sub)) in origens.indexed)
            _CartaoOrigem(
              focusNode: i == 0 ? widget.focoOrigens : null,
              icone: icone,
              titulo: titulo,
              subtitulo: sub,
              escolhida: _origem == o,
              aoEscolher: () => setState(() => _origem = o),
              deitado: telemovel,
            ),
        ];
        // linhas de cartões com a mesma altura (o comando trata-os como uma só linha)
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < cartoes.length; i += colunas) ...[
            if (i > 0) const SizedBox(height: Tokens.e8),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var j = i; j < i + colunas && j < cartoes.length; j++) ...[
                  if (j > i) const SizedBox(width: Tokens.e8),
                  Expanded(child: cartoes[j]),
                ],
              ]),
            ),
          ],
        ]);
      });

  static Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.e8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  static Widget _explicacao(String t) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.e12),
        child: Text(t, style: const TextStyle(color: Tokens.texto2)),
      );

  /// O painel da origem escolhida.
  Widget _painel() {
    switch (_origem) {
      case OrigemImportacao.ficheiros:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titulo(tr('Ficheiros')),
          _explicacao(tr('Escolha um ou mais ficheiros: Accounts.json, .ini, .m3u ou .txt.')),
          FilledButton.icon(
            onPressed: _escolherFicheiros,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(tr('Escolher ficheiros')),
          ),
        ]);
      case OrigemImportacao.adicionar:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _titulo(tr('Nova lista')),
          _explicacao(tr('Escolha o tipo de lista e preencha os dados.')),
          // os tipos: ESQUERDA/DIREITA passam de um ao outro pela ordem, mesmo partidos em duas linhas;
          // o que tem o foco fica escolhido
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            includeSemantics: false,
            onKeyEvent: (_, e) => _teclaFormas(e),
            child: Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
              for (final (i, f) in FormaLista.values.indexed)
                ChoiceChip(
                  focusNode: _focosFormas[i],
                  label: Text(f.nome),
                  selected: _forma == f,
                  onSelected: (_) => setState(() => _forma = f),
                ),
            ]),
          ),
          const SizedBox(height: Tokens.e16),
          ..._campos(),
          const SizedBox(height: Tokens.e12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _juntar,
              icon: const Icon(Icons.playlist_add_rounded),
              label: Text(tr('Juntar ao Gestor')),
            ),
          ),
        ]);
      case OrigemImportacao.stbstalker:
        if (edicaoPartilha) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titulo(tr('Listas do stbstalker')),
          _explicacao(tr('Junta as listas publicadas no blog entre duas datas, sem duplicar.')),
          Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.end, children: [
            OutlinedButton.icon(
              onPressed: _escolherDatas,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(tr('Escolher datas · {0} – {1}', [dataCurta(_inicio), dataCurta(_fim)])),
            ),
            // fica sempre ligado: carregar durante uma pesquisa inicia outra tarefa
            FilledButton.icon(
              onPressed: _procurarStb,
              icon: const Icon(Icons.search),
              label: Text(tr('Procurar e juntar')),
            ),
          ]),
        ]);
      case OrigemImportacao.telegram:
        if (edicaoPartilha) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titulo(tr('Listas do Telegram')),
          _explicacao(tr('Junta as listas de um canal público do Telegram, entre duas datas. '
              'Lê o texto das mensagens (Xtream, M3U e portal MAC); não lê ficheiros anexados.')),
          _campo(_canalTg, tr('Canal do Telegram'), '@michelstv4'),
          const SizedBox(height: Tokens.e8),
          Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.end, children: [
            OutlinedButton.icon(
              onPressed: _escolherDatas,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(tr('Escolher datas · {0} – {1}', [dataCurta(_inicio), dataCurta(_fim)])),
            ),
            FilledButton.icon(
              onPressed: _procurarTelegram,
              icon: const Icon(Icons.search),
              label: Text(tr('Procurar e juntar')),
            ),
          ]),
        ]);
      case OrigemImportacao.doPlayer:
        final n = _b.listas.length;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titulo(tr('De Ver TV')),
          _explicacao(n == 0
              ? tr('Ainda não há listas em Ver TV.')
              : tr('Copia {0} de Ver TV para o Gestor, sem duplicar.', [n == 1 ? tr('a lista') : tr('as {0} listas', [n])])),
          FilledButton.icon(
            onPressed: _importarDoPlayer,
            icon: const Icon(Icons.download_for_offline_outlined),
            label: Text(tr('Importar de Ver TV')),
          ),
        ]);
    }
  }

  /// Um campo de uma linha com rótulo (o comando da TV só abre o teclado com OK: ver CampoTv).
  Widget _campo(TextEditingController c, String rotulo, String exemplo) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.e8),
        child: CampoTv(
          controller: c,
          decoration: InputDecoration(labelText: rotulo, hintText: exemplo),
        ),
      );

  KeyEventResult _teclaFormas(KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final i = _focosFormas.indexWhere((f) => f.hasPrimaryFocus);
    if (i < 0) return KeyEventResult.ignored;
    final j = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowRight => i + 1,
      LogicalKeyboardKey.arrowLeft => i - 1,
      _ => null,
    };
    if (j == null || j < 0 || j >= _focosFormas.length) return KeyEventResult.ignored;
    _focosFormas[j].requestFocus();
    return KeyEventResult.handled;
  }

  /// Os campos do tipo escolhido em "Adicionar lista".
  List<Widget> _campos() => switch (_forma) {
        FormaLista.portalMac => [
            _campo(_endereco, tr('Endereço do portal'), 'http://portal.com:8080/c/'),
            _campo(_mac, tr('Endereço MAC'), '00:1A:79:12:34:56'),
          ],
        FormaLista.xtreamLink => [
            _campo(_endereco, tr('Link Xtream'), 'http://servidor.com:8080/get.php?username=…&password=…'),
          ],
        FormaLista.xtreamConta => [
            _campo(_endereco, tr('Servidor'), 'http://servidor.com:8080'),
            _campo(_utilizador, tr('Utilizador'), ''),
            _campo(_password, tr('Palavra-passe'), ''),
          ],
        FormaLista.m3u => [
            _campo(_endereco, tr('Endereço da lista'), 'http://servidor.com/lista.m3u'),
          ],
        FormaLista.varias => [
            _explicacao(tr('Cole as listas, uma por linha (portal e MAC, ligação Xtream ou M3U).')),
            CampoTv(
              controller: _texto,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText:
                    'http://portal.com/c/ 00:1A:79:00:00:01\nhttp://servidor:8080/get.php?username=…\nhttp://…/lista.m3u',
              ),
            ),
          ],
      };

  Widget _numero(String rotulo, int n) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(rotulo, style: const TextStyle(color: Tokens.texto2))),
          Text('$n', style: const TextStyle(color: Tokens.texto, fontWeight: FontWeight.w700)),
        ]),
      );

  /// O painel "Resultado" da última importação: o progresso enquanto decorre; depois os números.
  Widget _resultado(Tarefa t) {
    final Widget corpo;
    switch (t.estado) {
      case EstadoTarefa.aDecorrer:
        corpo = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LinearProgressIndicator(value: t.progresso, minHeight: 6),
          const SizedBox(height: Tokens.e4),
          Text(t.detalhe.isEmpty ? tr('A importar…') : tr('A importar · {0}', [t.detalhe]),
              style: const TextStyle(color: Tokens.texto2)),
        ]);
      case EstadoTarefa.falhou:
        corpo = Text(tr('Com erro ({0})', [t.resultado ?? 'falhou']), style: const TextStyle(color: Tokens.texto));
      case EstadoTarefa.cancelada:
        corpo = Text(tr('Cancelada.'), style: TextStyle(color: Tokens.texto2));
      case EstadoTarefa.terminada:
        final r = widget.registo.resumoDe(t);
        if (r == null) {
          corpo = Text(t.resultado ?? '', style: const TextStyle(color: Tokens.texto));
          break;
        }
        final novas = [for (final id in r.idsNovas) if (_g.porId(id) != null) id];
        corpo = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _numero(tr('Encontradas'), r.encontradas),
          _numero(tr('Novas no Gestor'), r.novas),
          _numero(tr('Já estavam no Gestor'), r.repetidas),
          for (final e in r.erros)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(tr('Com erro ({0})', [e]), style: const TextStyle(color: Tokens.texto)),
            ),
          if (novas.isNotEmpty) ...[
            const SizedBox(height: Tokens.e12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _verificarNovas(r),
                icon: const Icon(Icons.playlist_add_check),
                label: Text(novas.length == 1 ? tr('Verificar a 1 nova') : tr('Verificar as {0} novas', [novas.length])),
              ),
            ),
          ],
        ]);
    }
    return Semantics(
      liveRegion: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Resultado'), style: TextStyle(fontWeight: FontWeight.w600)),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: Tokens.e8),
          child: Text(t.titulo, style: const TextStyle(color: Tokens.texto2, fontSize: 12.5)),
        ),
        corpo,
      ]),
    );
  }

  /// «Limpar o Gestor»: no telemóvel uma ação secundária e destrutiva (texto vermelho, separada
  /// por um traço, no fim do ecrã); na TV e no Windows o botão de contorno de sempre.
  Widget _botaoLimpar() {
    const icone = Icon(Icons.delete_sweep_outlined);
    final rotulo = Text(tr('Limpar o Gestor'));
    if (!ecraTelemovel(context)) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(onPressed: _limpar, icon: icone, label: rotulo),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(height: Tokens.e16, color: Tokens.bordaVidro),
      TextButton.icon(
        onPressed: _limpar,
        style: TextButton.styleFrom(foregroundColor: Tokens.mau, minimumSize: const Size(0, Tokens.alvoToque)),
        icon: icone,
        label: rotulo,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_g, _b, widget.tarefas, widget.registo]),
        builder: (context, _) {
          final ultima = widget.registo.ultima;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Tokens.e16),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              includeSemantics: false,
              onKeyEvent: (_, e) => moverEntreBlocos(_blocos, e),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // sem cabeçalho: a faixa dos passos, por cima, já diz «1 · Importar»
                _bloco(0, _origens(), vidro: false),
                _bloco(1, _painel()),
                if (ultima != null) _bloco(2, _resultado(ultima)) else const SizedBox.shrink(),
                // fica ligado com o Gestor vazio (um botão desligado perde o foco do comando)
                _bloco(3, _botaoLimpar(), vidro: false),
              ]),
            ),
          );
        },
      );
}

/// O cartão de uma origem: o escolhido tem o contorno de destaque.
class _CartaoOrigem extends StatelessWidget {
  const _CartaoOrigem({
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.escolhida,
    required this.aoEscolher,
    this.focusNode,
    this.deitado = false,
  });

  final IconData icone;
  final String titulo, subtitulo;
  final bool escolhida;
  final VoidCallback aoEscolher;
  final FocusNode? focusNode;

  /// Numa linha (telemóvel): o ícone à esquerda, o título e a descrição ao meio e o ✓ à direita.
  final bool deitado;

  Widget _textos({required int linhasSubtitulo}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Tokens.texto)),
          const SizedBox(height: 2),
          Text(subtitulo,
              maxLines: linhasSubtitulo,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: Tokens.texto2)),
        ],
      );

  @override
  Widget build(BuildContext context) => Semantics(
        selected: escolhida,
        // a escolhida tem fundo azul e um ✓; o contorno azul-claro é só do foco (do CartaoModerno)
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: escolhida ? Tokens.superficie3 : null,
            borderRadius: BorderRadius.circular(Tokens.raioBotao),
          ),
          child: CartaoModerno(
            focusNode: focusNode,
            escalaFoco: 1.02,
            raio: Tokens.raioBotao,
            padding: const EdgeInsets.all(Tokens.e12),
            onTap: aoEscolher,
            child: deitado
                ? ConstrainedBox(
                    // (com o padding de 12: 56 de altura, no mínimo)
                    constraints: const BoxConstraints(minHeight: Tokens.alturaLinhaTelemovel - 2 * Tokens.e12),
                    child: Row(children: [
                      Icon(icone, color: escolhida ? Tokens.acento : Tokens.texto2),
                      const SizedBox(width: Tokens.e12),
                      Expanded(child: _textos(linhasSubtitulo: 2)),
                      const SizedBox(width: Tokens.e8),
                      // o ✓ ocupa sempre o seu lugar: escolher não mexe nos textos
                      SizedBox(
                        width: 18,
                        child: escolhida
                            ? const Icon(Icons.check_circle,
                                key: Key('origem-escolhida'),
                                size: 18,
                                color: Tokens.acento,
                                semanticLabel: 'escolhida')
                            : null,
                      ),
                    ]),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Icon(icone, color: escolhida ? Tokens.acento : Tokens.texto2),
                      const Spacer(),
                      if (escolhida)
                        const Icon(Icons.check_circle, key: Key('origem-escolhida'), size: 18, color: Tokens.acento,
                            semanticLabel: 'escolhida'),
                    ]),
                    const SizedBox(height: Tokens.e8),
                    _textos(linhasSubtitulo: 3),
                  ]),
          ),
        ),
      );
}
