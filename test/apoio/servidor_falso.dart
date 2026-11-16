import 'dart:convert';
import 'dart:io';

typedef Resposta = (int status, Object corpo);

/// Servidor HTTP local para testes: `responder` recebe o pedido e devolve (status, corpo);
/// corpo Map/List vai como JSON.
class ServidorFalso {
  ServidorFalso(this.responder);
  Resposta Function(HttpRequest pedido) responder;
  late HttpServer _srv;
  final pedidos = <HttpRequest>[];

  String get url => 'http://127.0.0.1:${_srv.port}';

  Future<void> iniciar() async {
    _srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _srv.listen((p) async {
      pedidos.add(p);
      final (status, corpo) = responder(p);
      p.response.statusCode = status;
      p.response.write(corpo is String ? corpo : jsonEncode(corpo));
      await p.response.close();
    });
  }

  Future<void> parar() => _srv.close(force: true);
}
