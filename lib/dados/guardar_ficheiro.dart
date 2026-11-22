import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../idioma/idioma.dart';

/// Onde o ficheiro ficou (ou que o utilizador cancelou a janela "Guardar como").
class ResultadoGuardar {
  const ResultadoGuardar(this.destino) : cancelado = false;
  const ResultadoGuardar.cancelado()
      : destino = '',
        cancelado = true;

  /// Texto para mostrar, p. ex. "Transferências/Accounts.json".
  final String destino;
  final bool cancelado;
}

/// Falha ao guardar, com uma mensagem já pronta para o utilizador.
class ErroGuardar implements Exception {
  const ErroGuardar(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// A pasta Transferências do Android (acesso nativo via MediaStore).
abstract class DestinoTransferencias {
  /// Nomes de ficheiros já presentes em Transferências.
  Future<List<String>> existentes();

  /// Escreve o ficheiro e devolve o nome REAL com que ficou (o Android pode ter renomeado).
  Future<String> escrever(String nome, Uint8List bytes, String mimeType);
}

/// "Accounts.json" -> "Accounts (2).json" -> "Accounts (3).json" ... sem pisar nenhum existente.
String nomeSemColisao(String nome, Iterable<String> existentes) {
  final usados = existentes.toSet();
  if (!usados.contains(nome)) return nome;
  final ponto = nome.lastIndexOf('.');
  final (base, ext) = ponto > 0 ? (nome.substring(0, ponto), nome.substring(ponto)) : (nome, '');
  for (var n = 2;; n++) {
    final candidato = '$base ($n)$ext';
    if (!usados.contains(candidato)) return candidato;
  }
}

/// Mensagem em português para uma falha ao guardar.
String mensagemErroGuardar(Object e) {
  if (e is ErroGuardar) return e.mensagem;
  if (e is PlatformException) {
    if (e.code == 'permissao') {
      return tr('Sem permissão para guardar nas Transferências. Permita o acesso ao armazenamento e tente de novo.');
    }
    final d = e.message;
    return tr('Não foi possível guardar o ficheiro{0}.', [d == null || d.isEmpty ? '' : ': $d']);
  }
  return tr('Não foi possível guardar o ficheiro: {0}', [e]);
}

class _DestinoNativo implements DestinoTransferencias {
  static const _canal = MethodChannel('player_iptv/ficheiros');

  @override
  Future<List<String>> existentes() async =>
      ((await _canal.invokeListMethod<String>('existentes')) ?? const []).toList();

  @override
  Future<String> escrever(String nome, Uint8List bytes, String mimeType) async {
    final r = await _canal.invokeMethod<String>('guardar', {'nome': nome, 'bytes': bytes, 'mime': mimeType});
    if (r == null) throw ErroGuardar(tr('O Android não devolveu o destino do ficheiro.'));
    return r;
  }
}

/// Guarda [bytes] como [nome]. No Android (telemóvel e TV) vai direto para Transferências,
/// sem janela; no Windows abre o "Guardar como". Lança [ErroGuardar] com mensagem clara se falhar.
Future<ResultadoGuardar> guardarFicheiro(
  String nome,
  Uint8List bytes,
  String mimeType, {
  DestinoTransferencias? destino,
  bool? android,
}) async {
  try {
    if (android ?? Platform.isAndroid) {
      final d = destino ?? _DestinoNativo();
      final nomeFinal = nomeSemColisao(nome, await d.existentes());
      return ResultadoGuardar(tr('Transferências/{0}', [await d.escrever(nomeFinal, bytes, mimeType)]));
    }
    final uri = await FilePicker.saveFile(fileName: nome, bytes: bytes, mimeType: mimeType, dialogTitle: tr('Guardar {0}', [nome]));
    return uri == null ? const ResultadoGuardar.cancelado() : ResultadoGuardar(uri.toString());
  } on ErroGuardar {
    rethrow;
  } catch (e) {
    throw ErroGuardar(mensagemErroGuardar(e));
  }
}
