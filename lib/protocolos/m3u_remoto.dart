import '../importar/m3u.dart';
import '../modelo/canal.dart';
import '../modelo/conta.dart';
import '../rede/http.dart';
import 'protocolo.dart';

/// Lista M3U por URL (ou ficheiro local `file:///`).
class M3uRemoto implements Protocolo {
  @override
  Future<ConteudoLista> abrir(Conta conta, {Cancelamento? cancelamento, Aviso? aviso}) async {
    aviso?.call('a descarregar a lista');
    final String texto;
    try {
      texto = await obterTexto(conta.endereco, timeout: const Duration(seconds: 30), cancelamento: cancelamento);
    } on ErroHttp catch (e) {
      // R12: 401/403 pode ser WAF, geo ou IP: não prova nada
      if (e.status == 401 || e.status == 403) throw ErroLista('servidor recusou o acesso à lista (${e.status})');
      rethrow;
    }
    // R13: HTML, login ou captive portal é o ambiente, não prova sobre a lista
    if (!pareceListaM3u(texto)) throw ErroLista('o endereço não devolveu uma lista M3U');
    aviso?.call('a ler os canais');
    return lerM3uAsync(texto);
  }

  @override
  Future<FonteVideo> fonte(Conta conta, Canal canal, {Cancelamento? cancelamento}) async =>
      FonteVideo(canal.url, {
        'User-Agent': canal.userAgent ?? uaVlc,
        if (canal.referer != null) 'Referer': canal.referer!,
      });
}

/// Aceita o mesmo que a importação ([pareceM3u]: `#EXTM3U` ou `#EXTINF`), mas recusa o que
/// claramente não é uma lista: vazio, HTML ou JSON (mesmo que tragam "#EXTINF" no texto).
bool pareceListaM3u(String texto) {
  final t = texto.replaceFirst('﻿', '').trimLeft();
  if (t.isEmpty || t.startsWith('<') || t.startsWith('{') || t.startsWith('[')) return false;
  return pareceM3u(t);
}
