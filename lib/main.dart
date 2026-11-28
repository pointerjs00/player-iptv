import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'dados/area_gestor.dart';
import 'dados/biblioteca.dart';
import 'dados/estatisticas.dart';
import 'dados/licencas.dart';
import 'dados/novidades.dart';
import 'dados/nova_versao.dart';
import 'dados/pasta_dados.dart';
import 'dados/preferencias.dart';
import 'desporto/armazem_desporto.dart';
import 'desporto/cliente_desporto.dart';
import 'desporto/indice_canais.dart';
import 'desporto/preferencias_jogos.dart';
import 'desporto/servico_jogos.dart';
import 'direto/sessao_direto.dart';
import 'edicao.dart';
import 'janelas/janela_player.dart';
import 'marca.dart';
import 'modelo/canal.dart';
import 'rede/http.dart';
import 'tarefas/servico_tarefas.dart';
import 'ui/definicoes/tela_definicoes.dart';
import 'ui/design/componentes.dart';
import 'ui/design/ecra.dart';
import 'ui/atualizar/fluxo_atualizar.dart';
import 'ui/design/escala_interface.dart';
import 'ui/design/mensagens.dart';
import 'ui/design/revelar_topo.dart';
import 'ui/gestor/tela_gestor.dart';
import 'ui/inicio/tela_inicio.dart';
import 'ui/jogos/tela_jogos.dart';
import 'ui/jogos/fila_hoje.dart';
import 'ui/player/player_canais.dart';
import 'ui/player/tempo_visto.dart';
import 'ui/poupanca_dados.dart';
import 'ui/principal/tela_principal.dart';
import 'ui/realce_foco.dart';
import 'ui/tema.dart';
import 'verificar/servico.dart';
import 'idioma/idioma.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  registarLicencasLibmpv(); // GPLv3 do libmpv/ffmpeg: Definições -> Licenças
  final i = args.indexOf('--player');
  if (Platform.isWindows && i >= 0 && i + 1 < args.length) {
    // esta é a janela do player (Windows): liga-se à janela principal
    final porta = int.parse(args[i + 1]);
    // a principal fechou: o gravado apaga-se antes de a janela sair do processo
    final ligacao = await LigacaoPrincipal.ligar(porta,
        token: Platform.environment[JanelaPlayer.variavelToken] ?? '', aoFechar: () async {
      await guardarTempoVisto().timeout(const Duration(seconds: 1), onTimeout: () {});
      await fecharSessoesDireto().timeout(const Duration(seconds: 2), onTimeout: () {});
      exit(0);
    });
    // as sobras do direto gravado (de um fecho à força), antes de qualquer canal; as sessões de
    // outra janela do player ainda viva estão bloqueadas e ficam
    await limparDireto();
    // as mesmas preferências do player que no Android (o ficheiro da janela principal)
    // a abertura que a principal manda já pode chegar durante estas esperas: a ligação
    // guarda-a até a app a escutar (ver LigacaoPrincipal.aberturas)
    final pastaPlayer = await pastaDados();
    Preferencias.atual = await Preferencias.abrir(pastaPlayer);
    // o tempo visto: é esta janela que o escreve (a principal relê-o)
    Estatisticas.atual = await Estatisticas.abrir(pastaPlayer);
    idiomaApp.value = Preferencias.atual.idioma;
    runApp(AppJanelaPlayer(ligacao: ligacao));
    return;
  }
  final pasta = await pastaDados();
  // uma só instância: duas janelas principais reescreviam a biblioteca uma por cima da outra
  _bloqueio = await Biblioteca.bloquearInstancia(pasta);
  if (_bloqueio == null) {
    runApp(_Aviso(tr('A app já está aberta noutra janela. Feche esta e use a outra.')));
    return;
  }
  // só com o bloqueio (outra instância podia estar a gravar): o direto gravado que ficou de um
  // fecho à força apaga-se antes de qualquer player abrir
  await limparDireto();
  final Biblioteca biblioteca;
  final AreaGestor area;
  try {
    biblioteca = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
  } catch (e) {
    runApp(_Aviso(tr('Não foi possível ler as listas guardadas ({0}). Feche outros programas que as possam ter abertas e abra a app de novo.', [descreverErro(e)])));
    return;
  }
  await configurarRealceFoco(); // Android TV: o realce do foco sempre visível
  instalarRevelarTopo(); // o topo de uma página com scroll nunca fica cortado
  // o player: desentrelaçamento, formato, descodificação, volume, taxa do ecrã
  Preferencias.atual = await Preferencias.abrir(pasta, tv: EcraTv.nativo);
  // o tempo visto (as estatísticas do Início)
  Estatisticas.atual = await Estatisticas.abrir(pasta);
  idiomaApp.value = Preferencias.atual.idioma;
  // as novidades: uma vez depois de cada atualização (numa instalação nova, não)
  final novidades = await novidadesPorVer(pasta,
      instalacaoNova: biblioteca.listas.isEmpty && area.listas.isEmpty);
  // os «Jogos» (não existem na edição de partilha)
  final jogos = edicaoPartilha ? null : await _abrirJogos(pasta, biblioteca);
  // o aviso de nova versão (GitHub Releases), fora dos dados móveis: cada edição só das suas releases
  Future<NovaVersao?> novaVersao() => novaVersaoPorAvisar(pasta,
      atual: versaoApp,
      emDadosMoveis: PoupancaDados.atual.emDadosMoveis,
      prefixo: edicaoPartilha ? prefixoPartilha : prefixoCompleta);
  unawaited(limparAtualizacoesAntigas());
  runApp(AppPlayerIptv(biblioteca: biblioteca, area: area, novidades: novidades, jogos: jogos, novaVersao: novaVersao));
}

/// O que o ecrã «Jogos» usa: as preferências e o índice em `<dados>/desporto`, a cache das fontes
/// em `<dados>/desporto/cache` (a arrumação da cache apaga o que não reconhece).
class Jogos {
  const Jogos(this.preferencias, this.servico, this.indice);
  final PreferenciasJogos preferencias;
  final ServicoJogos servico;
  final IndiceCanais indice;
}

Widget? _telaJogos(Jogos? j) =>
    j == null ? null : TelaJogos(servico: j.servico, fontes: j.indice, preferencias: j.preferencias);

/// «Hoje há jogo» no Início (os jogos de hoje das equipas favoritas).
Widget? _filaJogos(Jogos? j) =>
    j == null ? null : FilaHojeHaJogo(servico: j.servico, fontes: j.indice, preferencias: j.preferencias);

Future<Jogos?> _abrirJogos(Directory dados, Biblioteca biblioteca) async {
  try {
    final sep = Platform.pathSeparator;
    final pasta = await Directory('${dados.path}${sep}desporto').create(recursive: true);
    final preferencias = await PreferenciasJogos.abrir(pasta);
    final armazem = await ArmazemDesporto.abrir(Directory('${pasta.path}${sep}cache'));
    unawaited(armazem.arrumar(agora: DateTime.now().toUtc()));
    final indice = IndiceCanais(biblioteca, pasta, preferencias);
    final servico = ServicoJogos(ClienteDesporto(armazem), preferencias,
        emDadosMoveis: () => PoupancaDados.atual.emDadosMoveis(), fontes: indice);
    return Jogos(preferencias, servico, indice);
  } catch (e) {
    debugPrint('jogos: não abriu (${e.runtimeType})');
    return null;
  }
}

/// Fica aberto enquanto a app corre (é o bloqueio da instância).
RandomAccessFile? _bloqueio;

class _Aviso extends StatelessWidget {
  const _Aviso(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: temaApp(),
        builder: (_, w) => TemaConformeRealce(child: FundoCinema(child: w!)),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 16),
                FilledButton(autofocus: true, onPressed: () => exit(0), child: Text(tr('Fechar'))),
              ]),
            ),
          ),
        ),
      );
}

/// Os idiomas do Material (datas e botões dos diálogos do sistema).
final _locales = [for (final i in Idioma.values) i.locale];

class AppPlayerIptv extends StatefulWidget {
  const AppPlayerIptv(
      {super.key, required this.biblioteca, required this.area, this.novidades = false, this.jogos, this.novaVersao});

  /// Procura uma versão nova ao abrir (null: não procura, como na edição de partilha).
  final Future<NovaVersao?> Function()? novaVersao;
  final Biblioteca biblioteca;
  final AreaGestor area;

  /// null: sem a secção «Jogos».
  final Jogos? jogos;

  /// Mostrar as novidades desta versão ao abrir (a primeira vez depois de atualizar).
  final bool novidades;

  @override
  State<AppPlayerIptv> createState() => _AppPlayerIptvState();
}

class _AppPlayerIptvState extends State<AppPlayerIptv> {
  // um só ritmo por servidor para o Gestor e para o Player: nunca batem ao mesmo servidor ao mesmo tempo
  final _ritmo = RitmoHost();
  late final _servico = ServicoVerificacao(widget.biblioteca, colecao: widget.area, ritmo: _ritmo);
  late final _servicoPlayer = ServicoVerificacao(widget.biblioteca, ritmo: _ritmo);
  // trabalho longo fora dos ecrãs; os ecrãs só observam
  final _tarefas = ServicoTarefas();
  final _pedidoGestor = ValueNotifier<EcraGestor?>(null);

  @override
  void initState() {
    super.initState();
    idiomaApp.addListener(_mudouIdioma);
  }

  /// Outro idioma: o Material muda de `locale` e todos os ecrãs voltam a construir os textos
  /// (sem perder o estado: a secção, a lista aberta e o player ficam onde estavam).
  void _mudouIdioma() {
    if (!mounted) return;
    setState(() {});
    reconstruirTextos(context);
  }

  @override
  void dispose() {
    idiomaApp.removeListener(_mudouIdioma);
    _servico.parar();
    _servicoPlayer.parar();
    _tarefas.dispose();
    _pedidoGestor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: nomeApp,
        debugShowCheckedModeBanner: false,
        theme: temaApp(),
        // o fundo azul-noite por trás de todos os ecrãs (os Scaffold são transparentes); as mensagens
        // por cima do Navigator, para todas as rotas (casca, lista aberta, player do Android). A escala
        // (Compacto) leva o Navigator inteiro: rotas, diálogos, menus e mensagens ficam reduzidos.
        builder: (_, w) => TemaConformeRealce(
            child: FundoCinema(
                child: EscalaConformePreferencias(
                    preferencias: Preferencias.atual, child: AnfitriaoMensagens(child: w!)))),
        locale: idiomaApp.value.locale,
        supportedLocales: _locales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // três secções fixas que guardam o estado; o "Alterar nas Definições" do Gestor muda de secção
        home: TelaPrincipal(
          novidades: widget.novidades,
          novaVersao: widget.novaVersao,
          tarefas: _tarefas,
          verificacao: _servico,
          pedidoGestor: _pedidoGestor,
          verTv: TelaInicio(
              biblioteca: widget.biblioteca,
              area: widget.area,
              servico: _servicoPlayer,
              filaJogos: edicaoPartilha ? null : _filaJogos(widget.jogos)),
          // constante: na edição de partilha o compilador deita fora o ecrã e as fontes
          jogos: edicaoPartilha ? null : _telaJogos(widget.jogos),
          gestor: TelaGestor(biblioteca: widget.biblioteca, area: widget.area, servico: _servico, tarefas: _tarefas, pedido: _pedidoGestor),
          definicoes: TelaDefinicoes(
              biblioteca: widget.biblioteca,
              area: widget.area,
              preferencias: Preferencias.atual,
              servico: _servico,
              jogos: edicaoPartilha ? null : widget.jogos?.preferencias),
        ),
      );
}

/// A janela do player no Windows: espera pelo canal que a janela principal mandar.
class AppJanelaPlayer extends StatefulWidget {
  const AppJanelaPlayer({super.key, required this.ligacao});
  final LigacaoPrincipal ligacao;

  @override
  State<AppJanelaPlayer> createState() => _AppJanelaPlayerState();
}

class _AppJanelaPlayerState extends State<AppJanelaPlayer> {
  String _lista = '';
  List<Canal> _canais = const [];
  int _i = 0;

  /// Modo «Jogo»: a lista de cada canal (as fontes) e a troca automática.
  List<String>? _listas;
  bool _troca = false;

  /// O tempo visto (as estatísticas), pela lista aberta.
  void Function(Canal, Duration)? _tempoVisto;

  Window? get _janela => WindowManager.instance.getCurrent();

  @override
  void dispose() {
    idiomaApp.removeListener(_mudouIdioma);
    super.dispose();
  }

  /// O idioma mudou na janela principal (lido ao abrir um canal): os textos voltam a construir-se.
  void _mudouIdioma() {
    if (!mounted) return;
    setState(() {});
    reconstruirTextos(context);
  }

  @override
  void initState() {
    super.initState();
    idiomaApp.addListener(_mudouIdioma);
    widget.ligacao.aberturas.stream.listen((a) async {
      // as definições podem ter mudado na janela principal desde a última abertura
      await Preferencias.atual.recarregar();
      if (!mounted) return;
      setState(() {
        _lista = a.lista;
        _canais = a.canais;
        _i = a.i;
        _listas = a.listas;
        _troca = a.troca;
        _tempoVisto = _contadorPara(a);
      });
      _janela
        ?..title = '${a.canais[a.i].nome} — ${a.listas?[a.i] ?? a.lista}'
        ..focus();
    });
  }

  /// O tempo visto vai para a lista do canal que tocou (no modo «Jogo», a de cada fonte).
  void Function(Canal, Duration) _contadorPara(Abertura a) {
    final nomes = a.listas, ids = a.listaIds;
    if (nomes == null || ids == null) return contadorDeTempo(a.listaId, a.lista);
    final canais = a.canais;
    final porLista = <String, void Function(Canal, Duration)>{};
    return (c, d) {
      final i = canais.indexOf(c);
      if (i < 0) return;
      (porLista[ids[i]] ??= contadorDeTempo(ids[i], nomes[i]))(c, d);
    };
  }

  void _ecraInteiro() {
    final j = _janela;
    if (j != null) j.isFullScreen = !j.isFullScreen;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: nomeApp,
        debugShowCheckedModeBanner: false,
        theme: temaApp(),
        builder: (_, w) => TemaConformeRealce(child: w!),
        locale: idiomaApp.value.locale,
        supportedLocales: _locales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: _canais.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : PlayerCanais(
                  canais: _canais,
                  indice: _i,
                  nomeLista: _lista,
                  listaDe: _listas == null ? null : (c) => _listas![_canais.indexOf(c)],
                  trocaAutomatica: _troca,
                  aoFuncionar: _troca ? widget.ligacao.funcionou : null,
                  resolver: (c, {continuar = false}) => widget.ligacao.fonte(_canais.indexOf(c)),
                  // o guia está na janela principal: pede-se o programa por cada canal
                  programasDe: (c) => widget.ligacao.programas(_canais.indexOf(c)),
                  aoSair: () async {
                    await guardarTempoVisto();
                    exit(0);
                  },
                  criarSessao: criarSessaoDireto,
                  aoTempoVisto: _tempoVisto,
                  alternarEcraInteiro: _ecraInteiro,
                ),
        ),
      );
}
