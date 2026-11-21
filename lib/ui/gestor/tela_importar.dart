import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../../importar/importar.dart';
import '../../importar/stbstalker.dart';
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

/// As origens de onde se importa.
enum OrigemImportacao { ficheiros, colar, stbstalker, doPlayer }

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

/// O sub-ecrã de importar (passo 1): quatro origens (Ficheiros · Colar texto · Listas do stbstalker ·
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
    required this.focoOrigens,
  });

  final Biblioteca biblioteca;
  final AreaGestor area;
  final ServicoVerificacao servico;
  final ServicoTarefas tarefas;
  final RegistoImportacoes registo;
  final String baseStb;

  /// O foco da primeira origem (recebe o foco ao abrir o ecrã).
  final FocusNode focoOrigens;

  @override
  State<TelaImportar> createState() => _TelaImportarState();
}

class _TelaImportarState extends State<TelaImportar> {
  OrigemImportacao _origem = OrigemImportacao.ficheiros;
  late DateTime _inicio = _hoje(), _fim = _hoje();
  final _texto = TextEditingController();

  /// Os blocos para CIMA/BAIXO: origens, painel da origem, resultado e "Limpar o Gestor".
  final _blocos = [
    for (final b in ['Origens', 'Painel', 'Resultado', 'Limpar'])
      FocusNode(debugLabel: 'Bloco $b', canRequestFocus: false, skipTraversal: true),
  ];

  Biblioteca get _b => widget.biblioteca;
  AreaGestor get _g => widget.area;

  @override
  void dispose() {
    _texto.dispose();
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

  static String _n(int n, String um, String varios) => '$n ${n == 1 ? um : varios}';

  void _aviso(String t) {
    if (mounted) mostrarMensagem(context, t);
  }

  // ---------------------------------------------------------------- importar

  Future<void> _escolherFicheiros() async {
    final List<PlatformFile> ficheiros;
    try {
      ficheiros = await FilePicker.pickFiles(dialogTitle: 'Escolher listas');
    } catch (e) {
      return _aviso('Não foi possível abrir os ficheiros: ${descreverErro(e)}');
    }
    if (ficheiros.isEmpty) return;
    widget.registo.iniciar(
        widget.tarefas, 'Importar ficheiros', (p) => importarEscolhidos(_g, ficheiros, p: p));
  }

  void _juntarTexto() {
    final texto = _texto.text;
    if (texto.trim().isEmpty) return _aviso('Cole primeiro as listas, uma por linha.');
    widget.registo.iniciar(widget.tarefas, 'Importar texto colado', (p) => importarTexto(_g, texto));
    _texto.clear();
  }

  void _procurarStb() {
    // as datas podem mudar durante a pesquisa: o resumo fala das que foram pesquisadas
    final inicio = _inicio, fim = _fim, base = widget.baseStb;
    final periodo = inicio == fim ? _dd(inicio) : '${_dd(inicio)} a ${_dd(fim)}';
    widget.registo.iniciar(widget.tarefas, '$tituloTarefaStb · $periodo', (p) async {
      p(null, 'a procurar os posts');
      const parada = _Falha('Pesquisa parada. Nenhuma lista foi junta ao Gestor.');
      final ResultadoStb r;
      try {
        r = await importarEntre(inicio, fim,
            base: base,
            aoProgresso: (lidos, posts, linhas) => p(lidos / posts, '$linhas encontradas'),
            cancelado: () => p.cancelado);
      } on Cancelado {
        throw parada;
      } catch (e) {
        if (p.cancelado) throw parada;
        throw _Falha('Não foi possível pesquisar: ${descreverErro(e)}');
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

  void _importarDoPlayer() {
    final n = _b.listas.length;
    if (n == 0) return _aviso('Ainda não há listas em Ver TV.');
    widget.registo.iniciar(widget.tarefas, 'Importar de Ver TV', (p) async {
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
    if (listas.isEmpty) return _aviso('As listas novas já estão na fila.');
    widget.servico.verificarVarias(listas);
    _aviso(listas.length == 1 ? '1 lista entrou na fila.' : '${listas.length} listas entraram na fila.');
  }

  Future<void> _limpar() async {
    final n = _g.listas.length;
    if (n == 0) return _aviso('O Gestor já está vazio.');
    final ok = await confirmar(context,
        icone: Icons.delete_sweep_outlined,
        titulo: 'Limpar o Gestor?',
        texto: '${n == 1 ? 'A lista do Gestor sai' : 'As $n listas do Gestor saem'}. As listas de Ver TV não mudam.',
        acao: 'Limpar');
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
    _procurarStb();
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
        final colunas = telemovel
            ? 1
            : caixa.maxWidth >= 560
                ? 4
                : 2;
        final nPlayer = _b.listas.length;
        final origens = <(OrigemImportacao, IconData, String, String)>[
          (OrigemImportacao.ficheiros, Icons.file_open_outlined, 'Ficheiros', 'Accounts.json, .ini, .m3u, .txt'),
          (OrigemImportacao.colar, Icons.content_paste_rounded, 'Colar texto', 'Uma lista por linha'),
          (OrigemImportacao.stbstalker, Icons.event_note_outlined, 'Listas do stbstalker',
              'Publicadas entre duas datas'),
          (OrigemImportacao.doPlayer, Icons.download_for_offline_outlined, 'De Ver TV',
              nPlayer == 0 ? 'Ainda não há listas em Ver TV' : 'As $nPlayer listas que já tens'),
        ];
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
          _titulo('Ficheiros'),
          _explicacao('Escolha um ou mais ficheiros: Accounts.json, .ini, .m3u ou .txt.'),
          FilledButton.icon(
            onPressed: _escolherFicheiros,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Escolher ficheiros'),
          ),
        ]);
      case OrigemImportacao.colar:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _titulo('Colar texto'),
          _explicacao('Cole as listas, uma por linha (portal e MAC, ligação Xtream ou M3U).'),
          // o comando da TV não fica preso no campo: o teclado só abre com OK (ver CampoTv)
          CampoTv(
            controller: _texto,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'http://portal.com/c/ 00:1A:79:00:00:01\nhttp://servidor:8080/get.php?username=…\nhttp://…/lista.m3u',
            ),
          ),
          const SizedBox(height: Tokens.e12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _juntarTexto,
              icon: const Icon(Icons.playlist_add_rounded),
              label: const Text('Juntar ao Gestor'),
            ),
          ),
        ]);
      case OrigemImportacao.stbstalker:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titulo('Listas do stbstalker'),
          _explicacao('Junta as listas publicadas no blog entre duas datas, sem duplicar.'),
          Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.end, children: [
            OutlinedButton.icon(
              onPressed: _escolherDatas,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text('Escolher datas · ${dataCurta(_inicio)} – ${dataCurta(_fim)}'),
            ),
            // fica sempre ligado: carregar durante uma pesquisa inicia outra tarefa
            FilledButton.icon(
              onPressed: _procurarStb,
              icon: const Icon(Icons.search),
              label: const Text('Procurar e juntar'),
            ),
          ]),
        ]);
      case OrigemImportacao.doPlayer:
        final n = _b.listas.length;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titulo('De Ver TV'),
          _explicacao(n == 0
              ? 'Ainda não há listas em Ver TV.'
              : 'Copia ${n == 1 ? 'a lista' : 'as $n listas'} de Ver TV para o Gestor, sem duplicar.'),
          FilledButton.icon(
            onPressed: _importarDoPlayer,
            icon: const Icon(Icons.download_for_offline_outlined),
            label: const Text('Importar de Ver TV'),
          ),
        ]);
    }
  }

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
          Text(t.detalhe.isEmpty ? 'A importar…' : 'A importar · ${t.detalhe}',
              style: const TextStyle(color: Tokens.texto2)),
        ]);
      case EstadoTarefa.falhou:
        corpo = Text('Com erro (${t.resultado ?? 'falhou'})', style: const TextStyle(color: Tokens.texto));
      case EstadoTarefa.cancelada:
        corpo = const Text('Cancelada.', style: TextStyle(color: Tokens.texto2));
      case EstadoTarefa.terminada:
        final r = widget.registo.resumoDe(t);
        if (r == null) {
          corpo = Text(t.resultado ?? '', style: const TextStyle(color: Tokens.texto));
          break;
        }
        final novas = [for (final id in r.idsNovas) if (_g.porId(id) != null) id];
        corpo = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _numero('Encontradas', r.encontradas),
          _numero('Novas no Gestor', r.novas),
          _numero('Já estavam no Gestor', r.repetidas),
          for (final e in r.erros)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Com erro ($e)', style: const TextStyle(color: Tokens.texto)),
            ),
          if (novas.isNotEmpty) ...[
            const SizedBox(height: Tokens.e12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _verificarNovas(r),
                icon: const Icon(Icons.playlist_add_check),
                label: Text(novas.length == 1 ? 'Verificar a 1 nova' : 'Verificar as ${novas.length} novas'),
              ),
            ),
          ],
        ]);
    }
    return Semantics(
      liveRegion: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Resultado', style: TextStyle(fontWeight: FontWeight.w600)),
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
    const rotulo = Text('Limpar o Gestor');
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
