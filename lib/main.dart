import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'dados/area_gestor.dart';
import 'dados/biblioteca.dart';
import 'dados/preferencias.dart';
import 'janelas/janela_player.dart';
import 'modelo/canal.dart';
import 'rede/http.dart';
import 'ui/design/componentes.dart';
import 'ui/design/ecra.dart';
import 'ui/inicio/tela_inicio.dart';
import 'ui/player/player_canais.dart';
import 'ui/realce_foco.dart';
import 'ui/tema.dart';
import 'ui/verificar/tela_verificar.dart';
import 'verificar/servico.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final i = args.indexOf('--player');
  if (Platform.isWindows && i >= 0 && i + 1 < args.length) {
    // esta é a janela do player (Windows): liga-se à janela principal
    final porta = int.parse(args[i + 1]);
    final ligacao =
        await LigacaoPrincipal.ligar(porta, token: Platform.environment[JanelaPlayer.variavelToken] ?? '');
    // as mesmas preferências do player que no Android (o ficheiro da janela principal)
    Preferencias.atual = await Preferencias.abrir(await getApplicationSupportDirectory());
    runApp(AppJanelaPlayer(ligacao: ligacao));
    return;
  }
  final pasta = await getApplicationSupportDirectory();
  // uma só instância: duas janelas principais reescreviam a biblioteca uma por cima da outra
  _bloqueio = await Biblioteca.bloquearInstancia(pasta);
  if (_bloqueio == null) {
    runApp(const _Aviso('A app já está aberta noutra janela. Feche esta e use a outra.'));
    return;
  }
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
  late final _servico = ServicoVerificacao(widget.biblioteca, colecao: widget.area);

  @override
  void dispose() {
    _servico.parar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Player IPTV',
        debugShowCheckedModeBanner: false,
        theme: temaApp(),
        // o fundo azul-noite por trás de todos os ecrãs (os Scaffold são transparentes)
        builder: (_, w) => TemaConformeRealce(child: FundoCinema(child: w!)),
        locale: _pt,
        supportedLocales: const [_pt],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: TelaInicio(
          biblioteca: widget.biblioteca,
          area: widget.area,
          separadorGestor: TelaVerificar(biblioteca: widget.biblioteca, area: widget.area, servico: _servico),
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
    widget.ligacao.aberturas.stream.listen((a) {
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
                  resolver: (c) => widget.ligacao.fonte(_canais.indexOf(c)),
                  aoSair: () => exit(0),
                  alternarEcraInteiro: _ecraInteiro,
                ),
        ),
      );
}
