/// Descarregar um pacote da release para ficheiro, com progresso e cancelamento. No fim confirma
/// o tamanho e o SHA-256 (quando a release o dá); se falhar ou se cancelar, não fica nada.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../dados/nova_versao.dart';
import '../idioma/idioma.dart';
import '../rede/http.dart';
import '../rede/raizes.dart';

/// O pacote descarregado não é o publicado (tamanho ou SHA-256 diferentes, ou incompleto).
class ErroPacote implements Exception {
  ErroPacote(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// Abre o download: o corpo e o tamanho anunciado (Content-Length; null se não vier).
typedef AbrirDownload = Future<(Stream<List<int>>, int?)> Function(Uri uri, Cancelamento? cancelamento);

/// Guarda o último resumo da conversão em pedaços do SHA-256.
class _Resumo implements Sink<Digest> {
  Digest? valor;
  @override
  void add(Digest d) => valor = d;
  @override
  void close() {}
}

/// Descarrega `p` para `<pasta>/<p.nome>` (passando por `<p.nome>.parcial`). `progresso` recebe
/// os bytes recebidos e o total (o da release).
Future<File> descarregarPacote(
  Pacote p,
  Directory pasta, {
  void Function(int recebidos, int total)? progresso,
  Cancelamento? cancelamento,
  AbrirDownload abrir = abrirDownloadHttp,
}) async {
  cancelamento?.verificar();
  await pasta.create(recursive: true);
  final sep = Platform.pathSeparator;
  final parcial = File('${pasta.path}$sep${p.nome}.parcial');
  final destino = File('${pasta.path}$sep${p.nome}');
  IOSink? escrita;
  try {
    final (corpo, _) = await abrir(Uri.parse(p.url), cancelamento);
    escrita = parcial.openWrite();
    final resumo = _Resumo();
    final hash = sha256.startChunkedConversion(resumo);
    var recebidos = 0;
    await for (final pedaco in corpo) {
      cancelamento?.verificar();
      escrita.add(pedaco);
      hash.add(pedaco);
      recebidos += pedaco.length;
      if (recebidos > p.tamanho) throw ErroPacote(tr('o pacote recebido é maior do que o publicado'));
      progresso?.call(recebidos, p.tamanho);
    }
    cancelamento?.verificar();
    hash.close();
    await escrita.close();
    escrita = null;
    if (recebidos != p.tamanho) {
      throw ErroPacote(tr('o pacote ficou incompleto ({0} de {1} bytes)', [recebidos, p.tamanho]));
    }
    final esperado = p.sha256;
    if (esperado != null && resumo.valor.toString() != esperado.toLowerCase()) {
      throw ErroPacote(tr('o pacote recebido não é o publicado (SHA-256 diferente)'));
    }
    if (await destino.exists()) await destino.delete();
    return await parcial.rename(destino.path);
  } catch (_) {
    try {
      await escrita?.close();
    } catch (_) {
      /* já fechado */
    }
    try {
      if (await parcial.exists()) await parcial.delete();
    } on FileSystemException {
      /* fica para a limpeza seguinte */
    }
    rethrow;
  }
}

/// O download a sério: um cliente próprio (o do GitHub redireciona para outro servidor), sem
/// limite de tamanho e com 30 s no máximo sem receber nada.
Future<(Stream<List<int>>, int?)> abrirDownloadHttp(Uri uri, Cancelamento? cancelamento) async {
  final cliente = HttpClient(context: contextoSeguro())..connectionTimeout = const Duration(seconds: 30);
  final pedido = await cliente.getUrl(uri).timeout(const Duration(seconds: 30));
  pedido.headers.set(HttpHeaders.userAgentHeader, 'TVIntel');
  final deixar = cancelamento?.ouvir(() => pedido.abort(Cancelado()));
  try {
    final resposta = await pedido.close().timeout(const Duration(seconds: 30));
    if (resposta.statusCode >= 400) {
      throw ErroHttp(resposta.statusCode, uri.toString());
    }
    final total = resposta.contentLength >= 0 ? resposta.contentLength : null;
    final corpo = resposta
        .timeout(const Duration(seconds: 30))
        .transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleDone: (sink) {
              deixar?.call();
              cliente.close();
              sink.close();
            },
          ),
        );
    return (corpo, total);
  } catch (_) {
    deixar?.call();
    cliente.close(force: true);
    rethrow;
  }
}
