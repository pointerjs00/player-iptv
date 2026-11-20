/// Onde o [GravadorDireto] guarda os blocos: no armazenamento ([ArmazemDisco]) ou em memória
/// ([ArmazemMemoria]). O gravador decide a rotação (quantos blocos, quais se apagam); o armazém só
/// guarda. Um bloco de cada vez está em escrita, e as escritas acrescentam ao fim dele.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

abstract interface class ArmazemBlocos {
  /// Prepara o armazém (a pasta e o bloqueio da sessão, no disco).
  Future<void> preparar();

  /// Abre o bloco `n` para escrita (vazio). O anterior já foi fechado ([fecharAberto]).
  Future<void> abrir(int n);

  /// Acrescenta `dados[de, ate)` ao fim do bloco em escrita.
  Future<void> escrever(List<int> dados, int de, int ate);

  /// Fecha o bloco em escrita (se houver).
  Future<void> fecharAberto();

  /// Apaga o bloco `n` e devolve quantos bytes ocupava (0 se não existia).
  Future<int> apagar(int n);

  /// Até `quanto` bytes do bloco `n` a partir de `posicao` (uma cópia: o bloco pode ser apagado ou
  /// reaproveitado depois).
  Future<List<int>> ler(int n, int posicao, int quanto);

  /// Fecha tudo; com `apagar`, apaga todos os blocos (e a pasta, no disco).
  Future<void> fechar({required bool apagar});
}

/// Os blocos em ficheiros `bloco_<n>.ts` na pasta da sessão. A pasta leva um ficheiro de bloqueio
/// ([nomeBloqueio]) aberto em exclusivo enquanto a sessão vive: a limpeza no arranque de outro
/// processo (a janela do player do Windows) salta as pastas bloqueadas.
class ArmazemDisco implements ArmazemBlocos {
  ArmazemDisco(this.pasta);

  final Directory pasta;

  /// O ficheiro de bloqueio dentro da pasta de cada sessão.
  static const nomeBloqueio = '.sessao.lock';

  RandomAccessFile? _aberto;
  RandomAccessFile? _bloqueio;

  File _ficheiro(int n) => File('${pasta.path}${Platform.pathSeparator}bloco_$n.ts');

  @override
  Future<void> preparar() async {
    await pasta.create(recursive: true);
    try {
      final b = await File('${pasta.path}${Platform.pathSeparator}$nomeBloqueio').open(mode: FileMode.write);
      await b.lock(FileLock.exclusive);
      _bloqueio = b;
    } on FileSystemException catch (e) {
      // sem bloqueio grava-se na mesma (só a limpeza de outro processo a podia apanhar)
      debugPrint('gravador do direto: sem o bloqueio da sessão (código ${e.osError?.errorCode ?? '?'})');
    }
  }

  @override
  Future<void> abrir(int n) async => _aberto = await _ficheiro(n).open(mode: FileMode.writeOnly);

  @override
  Future<void> escrever(List<int> dados, int de, int ate) => _aberto!.writeFrom(dados, de, ate);

  @override
  Future<void> fecharAberto() async {
    final f = _aberto;
    _aberto = null;
    await f?.close();
  }

  @override
  Future<int> apagar(int n) async {
    final f = _ficheiro(n);
    if (!await f.exists()) return 0;
    final tamanho = await f.length();
    await f.delete();
    return tamanho;
  }

  @override
  Future<List<int>> ler(int n, int posicao, int quanto) async {
    final f = await _ficheiro(n).open();
    try {
      await f.setPosition(posicao);
      return await f.read(quanto);
    } finally {
      await f.close();
    }
  }

  @override
  Future<void> fechar({required bool apagar}) async {
    try {
      await fecharAberto();
    } catch (_) {}
    final b = _bloqueio;
    _bloqueio = null;
    try {
      await b?.close(); // fechar também larga o bloqueio
    } catch (_) {}
    if (apagar) await _apagarPasta();
  }

  /// Apaga a pasta da sessão. Se não der (no Windows, um ficheiro ainda aberto por outro), tenta
  /// outra vez; se mesmo assim falhar, regista-o sem o caminho e a limpeza no arranque da app apanha
  /// o que ficou.
  Future<void> _apagarPasta() async {
    for (var tentativa = 0;; tentativa++) {
      try {
        if (await pasta.exists()) await pasta.delete(recursive: true);
        return;
      } on FileSystemException catch (e) {
        if (tentativa >= 1) {
          debugPrint('gravador do direto: a pasta da sessão não foi apagada '
              '(código ${e.osError?.errorCode ?? '?'}); fica para a limpeza no arranque');
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }
}

/// Os blocos em memória: um `Uint8List` de [tamanhoBloco] por bloco. O espaço de um bloco apagado
/// reaproveita-se no bloco seguinte, por isso a memória dos blocos nunca passa de
/// `blocos × tamanhoBloco` (o limite do gravador).
class ArmazemMemoria implements ArmazemBlocos {
  ArmazemMemoria(this.tamanhoBloco);

  final int tamanhoBloco;
  final _blocos = <int, Uint8List>{};
  final _tamanhos = <int, int>{};

  /// Um bloco já apagado, para o próximo (nunca mais do que um).
  Uint8List? _livre;
  int? _aberto;

  /// Os bytes reservados em memória agora (blocos e o que espera reaproveitamento).
  @visibleForTesting
  int get bytesEmUso => (_blocos.length + (_livre == null ? 0 : 1)) * tamanhoBloco;

  @override
  Future<void> preparar() async {}

  @override
  Future<void> abrir(int n) async {
    final b = _livre ?? Uint8List(tamanhoBloco);
    _livre = null;
    _blocos[n] = b;
    _tamanhos[n] = 0;
    _aberto = n;
  }

  @override
  Future<void> escrever(List<int> dados, int de, int ate) async {
    final n = _aberto!;
    final em = _tamanhos[n]!;
    _blocos[n]!.setRange(em, em + ate - de, dados, de);
    _tamanhos[n] = em + ate - de;
  }

  @override
  Future<void> fecharAberto() async => _aberto = null;

  @override
  Future<int> apagar(int n) async {
    final b = _blocos.remove(n);
    _tamanhos.remove(n);
    if (b == null) return 0;
    _livre ??= b;
    return tamanhoBloco;
  }

  @override
  Future<List<int>> ler(int n, int posicao, int quanto) async {
    final b = _blocos[n];
    if (b == null) return Uint8List(0);
    final ate = math.min(_tamanhos[n]!, posicao + quanto);
    return ate <= posicao ? Uint8List(0) : Uint8List.fromList(Uint8List.sublistView(b, posicao, ate));
  }

  @override
  Future<void> fechar({required bool apagar}) async {
    _aberto = null;
    if (!apagar) return;
    _blocos.clear();
    _tamanhos.clear();
    _livre = null;
  }
}
