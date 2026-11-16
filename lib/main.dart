import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'dados/biblioteca.dart';
import 'janelas/janela_player.dart';
import 'modelo/canal.dart';
import 'ui/inicio/tela_inicio.dart';
import 'ui/player/player_canais.dart';
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
    final ligacao = await LigacaoPrincipal.ligar(porta);
    runApp(AppJanelaPlayer(ligacao: ligacao));
    return;
  }
  final pasta = await getApplicationSupportDirectory();
  final biblioteca = await Biblioteca.abrir(pasta);
  runApp(AppPlayerIptv(biblioteca: biblioteca));
}

const _pt = Locale('pt', 'PT');

class AppPlayerIptv extends StatefulWidget {
  const AppPlayerIptv({super.key, required this.biblioteca});
  final Biblioteca biblioteca;

  @override
  State<AppPlayerIptv> createState() => _AppPlayerIptvState();
}

class _AppPlayerIptvState extends State<AppPlayerIptv> {
  late final _servico = ServicoVerificacao(widget.biblioteca);

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
        locale: _pt,
        supportedLocales: const [_pt],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: TelaInicio(
          biblioteca: widget.biblioteca,
          servico: _servico,
          separadorVerificar: TelaVerificar(biblioteca: widget.biblioteca, servico: _servico),
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
