import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/atualizar/descarregar.dart';
import 'package:player_iptv/atualizar/instalar_android.dart';
import 'package:player_iptv/atualizar/pacote_certo.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/nova_versao.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/ui/atualizar/fluxo_atualizar.dart';
import 'package:player_iptv/ui/definicoes/tela_definicoes.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';
import 'package:player_iptv/ui/tema.dart';

import 'ajuda_dpad.dart';

class _AndroidFalso implements InstaladorAndroid {
  bool pode = true, ecraExiste = true, canalFalha = false, browser = true;
  final instalados = <String>[];
  final abertas = <String>[];
  var pedidos = 0;
  @override
  Future<List<String>> abis() async {
    if (canalFalha) throw PlatformException(code: 'erro', message: 'o canal falhou');
    return ['arm64-v8a', 'armeabi-v7a'];
  }

  @override
  Future<bool> abrirPagina(String url) async {
    abertas.add(url);
    return browser;
  }

  @override
  Future<bool> podeInstalar() async => pode;
  @override
  Future<bool> pedirAutorizacao() async {
    pedidos++;
    return ecraExiste;
  }

  @override
  Future<void> instalar(File apk) async => instalados.add(apk.path);
}

const _apk = Pacote('TVIntel-1.0.29-android-arm64.apk', 'https://x/a.apk', 100, null);
const _zip = Pacote('TVIntel-1.0.29-windows.zip', 'https://x/w.zip', 100, null);
const _nova = NovaVersao('1.0.29', 'https://github.com/x/y/releases/tag/v1.0.29', pacotes: [_apk, _zip]);

/// O fluxo «Procurar atualizações» / «Atualizar» com as dependências falsas.
void main() {
  late _AndroidFalso android;
  late Completer<File> download;
  late List<Cancelamento?> cancelamentos;
  late List<String> paginas;
  late List<String> descarregados;
  late Directory descargas;
  var paginaAbre = true;

  setUp(() {
    android = _AndroidFalso();
    cancelamentos = [];
    paginas = [];
    descarregados = [];
    paginaAbre = true;
    descargas = Directory.systemTemp.createTempSync('descargas');
  });
  tearDown(() {
    try {
      descargas.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  /// Cria o download pendente aqui (dentro do teste: um Completer do setUp fica fora do tempo
  /// simulado e os `then` dele nunca correm).
  Atualizador atualizador({Procura procura = const HaNova(_nova), Plataforma plataforma = Plataforma.android}) {
    download = Completer<File>();
    return Atualizador(
        procurar: () async => procura,
        plataforma: plataforma,
        partilha: false,
        pasta: () async => descargas,
        // síncrono: a I/O de disco a sério não acaba no tempo simulado dos testes de widgets
        limpar: (d) async {
          for (final e in d.listSync()) {
            e.deleteSync(recursive: true);
          }
        },
        android: android,
        descarregar: (p, pasta, {progresso, cancelamento}) {
          descarregados.add(p.nome);
          cancelamentos.add(cancelamento);
          progresso?.call(25, 100);
          cancelamento?.ouvir(() {
            if (!download.isCompleted) download.completeError(Cancelado());
          });
          return download.future;
        },
        abrirPagina: (url) async {
          paginas.add(url);
          return paginaAbre;
        },
      );
  }

  Future<void> abrir(WidgetTester t, Future<void> Function(BuildContext c) acao) async {
    ecraTvTeste(t);
    await t.pumpWidget(MaterialApp(
      theme: temaApp(),
      home: Builder(
        builder: (c) => Scaffold(body: Center(child: FilledButton(onPressed: () => acao(c), child: const Text('Ir')))),
      ),
    ));
    await t.tap(find.text('Ir'));
    await t.pumpAndSettle();
  }

  testWidgets('em dia: diz que já está na versão mais recente', (t) async {
    await abrir(t, (c) => procurarAtualizacoes(c, a: atualizador(procura: const EmDia('1.0.28'))));
    expect(find.text('Estás na versão mais recente (1.0.28).'), findsOneWidget);
  });

  testWidgets('sem resposta: diz que não foi possível ver', (t) async {
    await abrir(t, (c) => procurarAtualizacoes(c, a: atualizador(procura: const SemResposta())));
    expect(find.text('Não foi possível ver se há versão nova. Tenta mais tarde.'), findsOneWidget);
  });

  testWidgets('há nova: «Atualizar» (com o foco) descarrega o APK certo e abre o instalador', (t) async {
    await abrir(t, (c) => procurarAtualizacoes(c, a: atualizador()));
    expect(find.text('Há uma versão nova: 1.0.29.'), findsOneWidget);
    expect(textosFocados(), 'Atualizar');
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    await t.pump();
    expect(descarregados, ['TVIntel-1.0.29-android-arm64.apk']);
    expect(find.text('A descarregar a versão 1.0.29'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(textosFocados(), 'Cancelar');
    download.complete(File('${Directory.systemTemp.path}/TVIntel-1.0.29-android-arm64.apk'));
    await t.pumpAndSettle();
    expect(find.text('A descarregar a versão 1.0.29'), findsNothing);
    expect(android.instalados.single, endsWith('TVIntel-1.0.29-android-arm64.apk'));
  });

  testWidgets('antes de descarregar apaga os pacotes de atualizações anteriores', (t) async {
    final velho = File('${descargas.path}${Platform.pathSeparator}TVIntel-1.0.27-android-arm64.apk')
      ..writeAsStringSync('velho');
    await abrir(t, (c) => atualizarApp(c, _nova, a: atualizador()));
    expect(descarregados, ['TVIntel-1.0.29-android-arm64.apk']);
    expect(velho.existsSync(), isFalse);
    download.completeError(Cancelado());
    await t.pumpAndSettle();
  });

  testWidgets('«Cancelar» a meio do download: cancela e não instala', (t) async {
    await abrir(t, (c) => atualizarApp(c, _nova, a: atualizador()));
    expect(find.text('A descarregar a versão 1.0.29'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.select); // o foco está em «Cancelar»
    await t.pumpAndSettle();
    expect(cancelamentos.single!.cancelado, isTrue);
    expect(find.text('A descarregar a versão 1.0.29'), findsNothing);
    expect(find.textContaining('falhou'), findsNothing, reason: 'cancelar não é um erro');
    expect(android.instalados, isEmpty);
  });

  testWidgets('Voltar durante o download também cancela', (t) async {
    await abrir(t, (c) => atualizarApp(c, _nova, a: atualizador()));
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(cancelamentos.single!.cancelado, isTrue);
    expect(android.instalados, isEmpty);
  });

  testWidgets('o download falha: mostra o motivo e não instala', (t) async {
    await abrir(t, (c) => atualizarApp(c, _nova, a: atualizador()));
    download.completeError(const SocketException('sem rede'));
    await t.pumpAndSettle();
    expect(find.textContaining('O download falhou'), findsOneWidget);
    expect(android.instalados, isEmpty);
  });

  testWidgets('sem pacote para este aparelho: diz e oferece a página da release', (t) async {
    const semApk = NovaVersao('1.0.29', 'https://github.com/x/y/releases/tag/v1.0.29', pacotes: [_zip]);
    await abrir(t, (c) => atualizarApp(c, semApk, a: atualizador()));
    expect(find.text('Não há pacote desta versão para este aparelho.'), findsOneWidget);
    expect(descarregados, isEmpty);
    await t.tap(find.text('Abrir a página'));
    await t.pumpAndSettle();
    expect(paginas, ['https://github.com/x/y/releases/tag/v1.0.29']);
  });

  testWidgets('Android sem autorização: explica e abre o ecrã do Android; sem ele, diz onde', (t) async {
    android.pode = false;
    await abrir(t, (c) => atualizarApp(c, _nova, a: atualizador()));
    expect(find.textContaining('instalar apps desconhecidas'), findsWidgets);
    expect(textosFocados(), 'Dar autorização');
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(android.pedidos, 1);
    expect(descarregados, isEmpty, reason: 'volta-se a carregar em «Atualizar» depois de autorizar');

    android.ecraExiste = false;
    await t.tap(find.text('Ir'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.textContaining('Apps › TVIntel › Instalar apps desconhecidas'), findsOneWidget);
  });

  testWidgets('Windows: descarrega o zip, pergunta «Fechar e atualizar agora» e troca os ficheiros', (t) async {
    final instalados = <String>[];
    final a = atualizador(plataforma: Plataforma.windows);
    final w = Atualizador(
      procurar: a.procurar,
      plataforma: Plataforma.windows,
      partilha: false,
      pasta: a.pasta,
      descarregar: a.descarregar,
      limpar: a.limpar,
      instalarWindows: (zip) async => instalados.add(zip.path),
      pastaGravavel: () => true,
    );
    await abrir(t, (c) => atualizarApp(c, _nova, a: w));
    expect(descarregados, ['TVIntel-1.0.29-windows.zip']);
    download.complete(File('${Directory.systemTemp.path}/TVIntel-1.0.29-windows.zip'));
    await t.pumpAndSettle();
    expect(textosFocados(), 'Fechar e atualizar agora');
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(instalados.single, endsWith('TVIntel-1.0.29-windows.zip'));
  });

  testWidgets('Windows numa pasta sem escrita: não descarrega e oferece a página', (t) async {
    final a = atualizador(plataforma: Plataforma.windows);
    final w = Atualizador(
      procurar: a.procurar,
      plataforma: Plataforma.windows,
      partilha: false,
      pasta: a.pasta,
      descarregar: a.descarregar,
      limpar: a.limpar,
      instalarWindows: (_) async {},
      pastaGravavel: () => false,
      abrirPagina: a.abrirPagina,
    );
    await abrir(t, (c) => atualizarApp(c, _nova, a: w));
    expect(find.textContaining('Não é possível atualizar nesta pasta'), findsOneWidget);
    expect(descarregados, isEmpty);
    await t.tap(find.text('Abrir a página'));
    await t.pumpAndSettle();
    expect(paginas, [_nova.pagina]);
  });

  testWidgets('Esc fecha o «A procurar…» (sem esperar pela resposta)', (t) async {
    final nunca = Completer<Procura>();
    final a = atualizador();
    final lento = Atualizador(procurar: () => nunca.future, plataforma: a.plataforma, partilha: false, pasta: a.pasta);
    // sem pumpAndSettle enquanto o círculo roda (nunca assenta)
    ecraTvTeste(t);
    await t.pumpWidget(MaterialApp(
      theme: temaApp(),
      home: Builder(
        builder: (c) => Scaffold(
            body: Center(
                child: FilledButton(onPressed: () => procurarAtualizacoes(c, a: lento), child: const Text('Ir')))),
      ),
    ));
    await t.tap(find.text('Ir'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('A procurar uma versão nova…'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('A procurar uma versão nova…'), findsNothing);
    nunca.complete(const EmDia('1.0.28'));
    await t.pumpAndSettle();
    expect(find.textContaining('Estás na versão mais recente'), findsNothing, reason: 'já se desistiu');
  });

  testWidgets('o canal do Android falha: diz que não foi possível, em vez de não fazer nada', (t) async {
    android.canalFalha = true;
    await abrir(t, (c) => atualizarApp(c, _nova, a: atualizador()));
    expect(find.textContaining('Não foi possível atualizar'), findsOneWidget);
    expect(descarregados, isEmpty);
  });

  testWidgets('a página não abre (TV sem browser): mostra o endereço', (t) async {
    paginaAbre = false;
    const semApk = NovaVersao('1.0.29', 'https://github.com/x/y/releases/tag/v1.0.29', pacotes: [_zip]);
    await abrir(t, (c) => atualizarApp(c, semApk, a: atualizador()));
    await t.tap(find.text('Abrir a página'));
    await t.pumpAndSettle();
    expect(find.textContaining('github.com/x/y/releases/tag/v1.0.29'), findsOneWidget);
  });

  testWidgets('sem espaço no disco: diz isso (não a exceção crua)', (t) async {
    await abrir(t, (c) => atualizarApp(c, _nova, a: atualizador()));
    download.completeError(
        const FileSystemException('Write failed', 'pacote.parcial', OSError('There is not enough space on the disk', 112)));
    await t.pumpAndSettle();
    expect(find.textContaining('não foi possível gravar o pacote no disco'), findsOneWidget);
    expect(find.textContaining('FileSystemException'), findsNothing);
  });

  testWidgets('Windows: enquanto prepara a troca mostra «A preparar a atualização…»', (t) async {
    final preparar = Completer<void>();
    final a = atualizador(plataforma: Plataforma.windows);
    final w = Atualizador(
      procurar: a.procurar,
      plataforma: Plataforma.windows,
      partilha: false,
      pasta: a.pasta,
      descarregar: a.descarregar,
      limpar: a.limpar,
      instalarWindows: (_) => preparar.future,
      pastaGravavel: () => true,
    );
    await abrir(t, (c) => atualizarApp(c, _nova, a: w));
    download.complete(File('${Directory.systemTemp.path}/TVIntel-1.0.29-windows.zip'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.select); // «Fechar e atualizar agora»
    await t.pump();
    await t.pump();
    expect(find.text('A preparar a atualização…'), findsOneWidget);
    preparar.completeError(ErroPacote('o Windows não deixou correr o script'));
    await t.pumpAndSettle();
    expect(find.text('A preparar a atualização…'), findsNothing);
    expect(find.textContaining('o Windows não deixou correr o script'), findsOneWidget);
  });

  group('Definições', () {
    late Directory pasta;
    setUp(() => pasta = Directory.systemTemp.createTempSync('def_atualizar'));
    tearDown(() {
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });

    testWidgets('«Sobre»: «Procurar atualizações» procura e mostra o resultado', (t) async {
      ecraTvTeste(t, altura: 1080);
      final bib = (await t.runAsync(() => Biblioteca.abrir(pasta)))!;
      final area = (await t.runAsync(() => AreaGestor.abrir(pasta)))!;
      final prefs = (await t.runAsync(() => Preferencias.abrir(pasta)))!;
      await t.pumpWidget(MaterialApp(
        theme: temaApp(),
        home: TelaPrincipal(
          inicial: Seccao.definicoes,
          verTv: const SizedBox(),
          gestor: const SizedBox(),
          definicoes: TelaDefinicoes(
              biblioteca: bib, area: area, preferencias: prefs, atualizador: atualizador(procura: const EmDia('1.0.28'))),
        ),
      ));
      await t.pump();
      await t.tap(find.text('Sobre e licenças'));
      await t.pumpAndSettle();
      await t.tap(find.text('Procurar atualizações'));
      await t.pumpAndSettle();
      expect(find.text('Estás na versão mais recente (1.0.28).'), findsOneWidget);
    });
  });

  testWidgets('o aviso ao abrir tem a ação «Atualizar»', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: temaApp(),
      home: TelaPrincipal(
        verTv: const SizedBox(),
        gestor: const SizedBox(),
        definicoes: const SizedBox(),
        novaVersao: () async => _nova,
      ),
    ));
    await t.pump();
    await t.pump();
    expect(find.text('Menu: Atualizar'), findsOneWidget);
    await t.pump(const Duration(seconds: 30));
  });
}
