/// «Procurar atualizações» (Definições) e «Atualizar» (também no aviso ao abrir): procura a
/// release da edição, escolhe o pacote deste aparelho, descarrega-o (com progresso e «Cancelar»)
/// e instala-o — no Android pelo instalador do sistema; no Windows pela troca dos ficheiros.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../../atualizar/descarregar.dart';
import '../../atualizar/instalar_android.dart';
import '../../atualizar/instalar_windows.dart' as windows;
import '../../atualizar/pacote_certo.dart';
import '../../dados/nova_versao.dart';
import '../../dados/novidades.dart';
import '../../edicao.dart';
import '../../idioma/idioma.dart';
import '../../rede/http.dart';
import '../design/design.dart';

/// Descarrega o pacote (ver [descarregarPacote]).
typedef DescarregarPacote = Future<File> Function(
  Pacote p,
  Directory pasta, {
  void Function(int recebidos, int total)? progresso,
  Cancelamento? cancelamento,
});

Future<File> _descarregar(
  Pacote p,
  Directory pasta, {
  void Function(int recebidos, int total)? progresso,
  Cancelamento? cancelamento,
}) => descarregarPacote(p, pasta, progresso: progresso, cancelamento: cancelamento);

/// Tudo o que o fluxo usa de fora (nos testes, falsos).
class Atualizador {
  const Atualizador({
    required this.procurar,
    required this.plataforma,
    required this.partilha,
    required this.pasta,
    this.descarregar = _descarregar,
    this.android = const InstaladorAndroid(),
    this.instalarWindows,
    this.pastaGravavel,
    this.abrirPagina,
    this.limpar = limparPasta,
  });

  /// O da app: a edição e a plataforma em que corre.
  factory Atualizador.daApp() => Atualizador(
    procurar: () => procurarVersao(atual: versaoApp, prefixo: edicaoPartilha ? prefixoPartilha : prefixoCompleta),
    plataforma: Platform.isAndroid
        ? Plataforma.android
        : Platform.isWindows
        ? Plataforma.windows
        : Plataforma.outra,
    partilha: edicaoPartilha,
    pasta: () async => Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}atualizar'),
    abrirPagina: Platform.isWindows ? _abrirNoWindows : null,
    // a app sai logo a seguir: o script só troca os ficheiros depois de ela fechar
    instalarWindows: Platform.isWindows ? (zip) => windows.instalarWindows(zip, fechar: () async => exit(0)) : null,
    pastaGravavel: Platform.isWindows ? () => windows.pastaGravavel(File(Platform.resolvedExecutable).parent) : null,
  );

  final Future<Procura> Function() procurar;
  final Plataforma plataforma;
  final bool partilha;

  /// Onde se descarrega (no Android, a pasta `atualizar` da cache: a do FileProvider).
  final Future<Directory> Function() pasta;
  final DescarregarPacote descarregar;
  final InstaladorAndroid android;

  /// Windows: troca os ficheiros e fecha a app (null: abre a página da release).
  final Future<void> Function(File zip)? instalarWindows;

  /// Windows: a pasta da app aceita os ficheiros novos? (null: não se sabe, tenta-se)
  final bool Function()? pastaGravavel;

  /// Apaga os pacotes de atualizações anteriores da pasta (ver [limparPasta]).
  final Future<void> Function(Directory pasta) limpar;

  /// Abre a página da release no browser; null onde não há como.
  final Future<bool> Function(String url)? abrirPagina;
}

Future<bool> _abrirNoWindows(String url) async {
  try {
    await Process.start('rundll32', ['url.dll,FileProtocolHandler', url], mode: ProcessStartMode.detached);
    return true;
  } on ProcessException {
    return false;
  }
}

/// Ao abrir a app: apaga os pacotes de atualizações anteriores (já instalados).
Future<void> limparAtualizacoesAntigas() async {
  try {
    await limparPasta(await Atualizador.daApp().pasta());
  } catch (_) {
    /* sem pasta temporária: nada a limpar */
  }
}

/// O botão das Definições: procura e diz o resultado; havendo versão nova, oferece «Atualizar».
Future<void> procurarAtualizacoes(BuildContext context, {Atualizador? a}) async {
  final at = a ?? Atualizador.daApp();
  final procura = await showDialog<Procura>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AProcurar(at.procurar),
  );
  if (procura == null || !context.mounted) return;
  switch (procura) {
    case EmDia(:final versao):
      await _aviso(
        context,
        Icons.check_circle_outline_rounded,
        tr('Atualizações'),
        tr('Estás na versão mais recente ({0}).', [versao]),
      );
    case SemResposta():
      await _aviso(
        context,
        Icons.cloud_off_rounded,
        tr('Atualizações'),
        tr('Não foi possível ver se há versão nova. Tenta mais tarde.'),
      );
    case HaNova(:final v):
      final sim = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.system_update_rounded, color: Tokens.acento2, size: 32),
          title: Text(tr('Atualizações')),
          content: Text(tr('Há uma versão nova: {0}.', [v.versao])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Agora não'))),
            FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Atualizar'))),
          ],
        ),
      );
      if (sim == true && context.mounted) await atualizarApp(context, v, a: at);
  }
}

/// Descarrega e instala a versão `v` (o pacote desta plataforma e edição).
Future<void> atualizarApp(BuildContext context, NovaVersao v, {Atualizador? a}) async {
  final at = a ?? Atualizador.daApp();
  final abis = at.plataforma == Plataforma.android ? await at.android.abis() : const <String>[];
  final pacote = pacoteDaApp(v.pacotes, plataforma: at.plataforma, abis: abis, partilha: at.partilha);
  if (!context.mounted) return;
  if (pacote == null) {
    await _semAtualizar(context, at, v, tr('Não há pacote desta versão para este aparelho.'));
    return;
  }
  if (at.plataforma == Plataforma.windows && at.pastaGravavel?.call() == false) {
    await _semAtualizar(
      context,
      at,
      v,
      tr(
        'Não é possível atualizar nesta pasta (a app não pode escrever lá). Descarrega a versão nova na página da release.',
      ),
    );
    return;
  }
  if (at.plataforma == Plataforma.android && !await at.android.podeInstalar()) {
    if (context.mounted) await _pedirAutorizacao(context, at);
    return;
  }
  final pasta = await at.pasta();
  // os pacotes de atualizações anteriores (o APK fica na cache depois de instalado)
  await at.limpar(pasta);
  if (!context.mounted) return;
  final resultado = await showDialog<Object>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ADescarregar(versao: v.versao, pacote: pacote, pasta: pasta, descarregar: at.descarregar),
  );
  if (!context.mounted) return;
  if (resultado is File) {
    await _instalar(context, at, v, resultado);
  } else if (resultado != null && resultado is! Cancelado) {
    await _aviso(
      context,
      Icons.error_outline_rounded,
      tr('Atualizações'),
      tr('O download falhou: {0}', [_motivo(resultado)]),
    );
  }
}

Future<void> _instalar(BuildContext context, Atualizador at, NovaVersao v, File f) async {
  switch (at.plataforma) {
    case Plataforma.android:
      try {
        await at.android.instalar(f);
      } catch (e) {
        if (context.mounted) {
          await _aviso(
            context,
            Icons.error_outline_rounded,
            tr('Atualizações'),
            tr('Não foi possível abrir o instalador: {0}', [_motivo(e)]),
          );
        }
      }
    case Plataforma.windows:
      final instalar = at.instalarWindows;
      if (instalar == null) {
        await at.abrirPagina?.call(v.pagina);
        return;
      }
      final sim = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.system_update_rounded, color: Tokens.acento2, size: 32),
          title: Text(tr('Atualizações')),
          content: Text(tr('A versão {0} está pronta. A app fecha, troca os ficheiros e volta a abrir.', [v.versao])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Mais tarde'))),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Fechar e atualizar agora')),
            ),
          ],
        ),
      );
      if (sim != true) return;
      try {
        await instalar(f);
      } catch (e) {
        if (context.mounted) {
          await _aviso(
            context,
            Icons.error_outline_rounded,
            tr('Atualizações'),
            tr('Não foi possível atualizar: {0}', [_motivo(e)]),
          );
        }
      }
    case Plataforma.outra:
      await at.abrirPagina?.call(v.pagina);
  }
}

/// Android sem a autorização «instalar apps desconhecidas»: explica e abre o ecrã onde se dá.
Future<void> _pedirAutorizacao(BuildContext context, Atualizador at) async {
  final sim = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.admin_panel_settings_outlined, color: Tokens.acento2, size: 32),
      title: Text(tr('Falta uma autorização')),
      content: Text(
        tr(
          'Para se atualizar, a TVIntel precisa de autorização para instalar apps desconhecidas. Dá-a no ecrã que vai abrir e depois volta a carregar em «Atualizar».',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Agora não'))),
        FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Dar autorização'))),
      ],
    ),
  );
  if (sim != true) return;
  if (!await at.android.pedirAutorizacao() && context.mounted) {
    await _aviso(
      context,
      Icons.admin_panel_settings_outlined,
      tr('Falta uma autorização'),
      tr(
        'Abre as definições do Android › Apps › TVIntel › Instalar apps desconhecidas e autoriza. Depois volta a carregar em «Atualizar».',
      ),
    );
  }
}

/// Não dá para atualizar aqui: diz porquê e, se houver como, oferece a página da release.
Future<void> _semAtualizar(BuildContext context, Atualizador at, NovaVersao v, String texto) async {
  final abrir = at.abrirPagina;
  final sim = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.info_outline_rounded, color: Tokens.acento2, size: 32),
      title: Text(tr('Atualizações')),
      content: Text(texto),
      actions: [
        TextButton(autofocus: abrir == null, onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Fechar'))),
        if (abrir != null)
          FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Abrir a página'))),
      ],
    ),
  );
  if (sim == true) await abrir?.call(v.pagina);
}

Future<void> _aviso(BuildContext context, IconData icone, String titulo, String texto) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    icon: Icon(icone, color: Tokens.acento2, size: 32),
    title: Text(titulo),
    content: Text(texto),
    actions: [FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: Text(tr('OK')))],
  ),
);

String _motivo(Object e) => switch (e) {
  ErroPacote(:final mensagem) => mensagem,
  SocketException() || HttpException() => tr('sem ligação à internet'),
  TimeoutException() => tr('o servidor demorou demasiado a responder'),
  ErroHttp(:final status) => tr('o servidor respondeu {0}', [status]),
  _ => '$e',
};

/// «A procurar…» enquanto se pede a lista das releases.
class _AProcurar extends StatefulWidget {
  const _AProcurar(this.procurar);
  final Future<Procura> Function() procurar;

  @override
  State<_AProcurar> createState() => _AProcurarState();
}

class _AProcurarState extends State<_AProcurar> {
  @override
  void initState() {
    super.initState();
    widget.procurar().then(
      (p) {
        if (mounted) Navigator.pop(context, p);
      },
      onError: (_) {
        if (mounted) Navigator.pop(context, const SemResposta());
      },
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    content: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 3)),
        const SizedBox(width: Tokens.e16),
        Text(tr('A procurar uma versão nova…')),
      ],
    ),
  );
}

/// O download com a barra, o tamanho e «Cancelar» (com o foco; Voltar também cancela). Fecha com
/// o ficheiro, com o erro, ou com [Cancelado].
class _ADescarregar extends StatefulWidget {
  const _ADescarregar({required this.versao, required this.pacote, required this.pasta, required this.descarregar});
  final String versao;
  final Pacote pacote;
  final Directory pasta;
  final DescarregarPacote descarregar;

  @override
  State<_ADescarregar> createState() => _ADescarregarState();
}

class _ADescarregarState extends State<_ADescarregar> {
  final _cancelamento = Cancelamento();
  int _recebidos = 0;

  @override
  void initState() {
    super.initState();
    widget
        .descarregar(
          widget.pacote,
          widget.pasta,
          cancelamento: _cancelamento,
          progresso: (r, _) {
            if (mounted) setState(() => _recebidos = r);
          },
        )
        .then((f) => _fechar(f), onError: (Object e) => _fechar(e));
  }

  void _fechar(Object resultado) {
    if (mounted) Navigator.pop(context, resultado);
  }

  void _cancelar() => _cancelamento.cancelar();

  @override
  Widget build(BuildContext context) {
    final total = widget.pacote.tamanho;
    String mb(int b) => (b / (1024 * 1024)).toStringAsFixed(1);
    // Voltar do sistema (PopScope) e Esc/Voltar do comando (o diálogo não se fecha sozinho, por
    // isso o Flutter não trata o Esc): cancelam o download
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (feito, _) {
        if (!feito) _cancelar();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _cancelar,
          const SingleActivator(LogicalKeyboardKey.goBack): _cancelar,
        },
        child: AlertDialog(
          icon: const Icon(Icons.downloading_rounded, color: Tokens.acento2, size: 32),
          title: Text(tr('A descarregar a versão {0}', [widget.versao])),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: total > 0 ? (_recebidos / total).clamp(0.0, 1.0) : null, minHeight: 6),
                const SizedBox(height: Tokens.e8),
                Text(
                  tr('{0} de {1} MB', [mb(_recebidos), mb(total)]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Tokens.texto2),
                ),
              ],
            ),
          ),
          actions: [OutlinedButton(autofocus: true, onPressed: _cancelar, child: Text(tr('Cancelar')))],
        ),
      ),
    );
  }
}
