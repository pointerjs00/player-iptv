import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'dados/area_gestor.dart';
import 'dados/biblioteca.dart';
import 'dados/licencas.dart';
import 'dados/pasta_dados.dart';
import 'dados/preferencias.dart';
import 'direto/sessao_direto.dart';
import 'janelas/janela_player.dart';
import 'marca.dart';
import 'modelo/canal.dart';
import 'rede/http.dart';
import 'tarefas/servico_tarefas.dart';
import 'ui/definicoes/tela_definicoes.dart';
import 'ui/design/componentes.dart';
import 'ui/design/ecra.dart';
import 'ui/design/escala_interface.dart';
import 'ui/design/mensagens.dart';
import 'ui/design/revelar_topo.dart';
import 'ui/gestor/tela_gestor.dart';
import 'ui/inicio/tela_inicio.dart';
import 'ui/player/player_canais.dart';
import 'ui/principal/tela_principal.dart';
import 'ui/realce_foco.dart';
import 'ui/tema.dart';
import 'verificar/servico.dart';

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
      await fecharSessoesDireto().timeout(const Duration(seconds: 2), onTimeout: () {});
      exit(0);
    });
    // as sobras do direto gravado (de um fecho à força), antes de qualquer canal; as sessões de
    // outra janela do player ainda viva estão bloqueadas e ficam
    await limparDireto();
    // as mesmas preferências do player que no Android (o ficheiro da janela principal)
    // a abertura que a principal manda já pode chegar durante estas esperas: a ligação
    // guarda-a até a app a escutar (ver LigacaoPrincipal.aberturas)
    Preferencias.atual = await Preferencias.abrir(await pastaDados());
    runApp(AppJanelaPlayer(ligacao: ligacao));
    return;
  }
  final pasta = await pastaDados();
  // uma só instância: duas janelas principais reescreviam a biblioteca uma por cima da outra
  _bloqueio = await Biblioteca.bloquearInstancia(pasta);
  if (_bloqueio == null) {
    runApp(const _Aviso('A app já está aberta noutra janela. Feche esta e use a outra.'));
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
    runApp(_Aviso('Não foi possível ler as listas guardadas (${descreverErro(e)}). '
        'Feche outros programas que as possam ter abertas e abra a app de novo.'));
    return;
  }
  await configurarRealceFoco(); // Android TV: o realce do foco sempre visível
  instalarRevelarTopo(); // o topo de uma página com scroll nunca fica cortado
  // o player: desentrelaçamento, formato, descodificação, volume, taxa do ecrã
  Preferencias.atual = await Preferencias.abrir(pasta, tv: EcraTv.nativo);
  runApp(AppPlayerIptv(biblioteca: biblioteca, area: area));
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
                FilledButton(autofocus: true, onPressed: () => exit(0), child: const Text('Fechar')),
              ]),
            ),
          ),
        ),
      );
}

const _pt = Locale('pt', 'PT');

class AppPlayerIptv extends StatefulWidget {
  const AppPlayerIptv({super.key, required this.biblioteca, required this.area});
  final Biblioteca biblioteca;
  final AreaGestor area;

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
  void dispose() {
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
        locale: _pt,
        supportedLocales: const [_pt],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // três secções fixas que guardam o estado; o "Alterar nas Definições" do Gestor muda de secção
        home: TelaPrincipal(
          tarefas: _tarefas,
          verificacao: _servico,
          pedidoGestor: _pedidoGestor,
          verTv: TelaInicio(biblioteca: widget.biblioteca, area: widget.area, servico: _servicoPlayer),
          gestor: TelaGestor(biblioteca: widget.biblioteca, area: widget.area, servico: _servico, tarefas: _tarefas, pedido: _pedidoGestor),
          definicoes: TelaDefinicoes(
              biblioteca: widget.biblioteca, area: widget.area, preferencias: Preferencias.atual, servico: _servico),
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

  Window? get _janela => WindowManager.instance.getCurrent();

  @override
  void initState() {
    super.initState();
    widget.ligacao.aberturas.stream.listen((a) async {
      // as definições podem ter mudado na janela principal desde a última abertura
      await Preferencias.atual.recarregar();
      if (!mounted) return;
      setState(() {
        _lista = a.$1;
        _canais = a.$2;
        _i = a.$3;
      });
      _janela
        ?..title = '${a.$2[a.$3].nome} — ${a.$1}'
        ..focus();
    });
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
        locale: _pt,
        supportedLocales: const [_pt],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: _canais.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : PlayerCanais(
                  canais: _canais,
                  indice: _i,
                  nomeLista: _lista,
                  resolver: (c, {continuar = false}) => widget.ligacao.fonte(_canais.indexOf(c)),
                  aoSair: () => exit(0),
                  criarSessao: criarSessaoDireto,
                  alternarEcraInteiro: _ecraInteiro,
                ),
        ),
      );
}
