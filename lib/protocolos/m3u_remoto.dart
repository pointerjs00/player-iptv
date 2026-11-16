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
    final texto = await obterTexto(conta.endereco, timeout: const Duration(seconds: 30),
        cancelamento: cancelamento);
    if (!pareceM3u(texto)) throw ErroLista('o endereço não devolveu uma lista M3U', definitivo: true);
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
