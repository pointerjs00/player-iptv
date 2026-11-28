import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/guia/armazem.dart';
import 'package:player_iptv/guia/fontes.dart';
import 'package:player_iptv/guia/programa.dart';
import 'package:player_iptv/guia/servico_guia.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/rede/http.dart';

const agora = 1795435200;

/// Uma fonte de guia falsa: conta os pedidos e responde o que o teste disser.
class FonteFalsa implements FonteGuia {
  FonteFalsa({this.todosDa, this.canalDa});
  Map<String, List<Programa>> Function()? todosDa;
  List<Programa> Function(Canal c)? canalDa;
  int pedidosTodos = 0;
  final pedidosCanal = <String>[];
  GuiaLista? anteriorRecebido;
  bool naoMudou = false;

  @override
  Future<ResultadoGuia> todos(Conta conta, List<Canal> canais, {GuiaLista? anterior, Cancelamento? cancelamento}) async {
    pedidosTodos++;
    anteriorRecebido = anterior;
    if (naoMudou) return const ResultadoGuia.naoMudou();
    final f = todosDa;
    if (f == null) throw ErroHttp(403);
    return ResultadoGuia(f(), etag: '"e"');
  }

  @override
  Future<List<Programa>> doCanal(Conta conta, Canal canal, {Cancelamento? cancelamento}) async {
    pedidosCanal.add(canal.id);
    final f = canalDa;
    if (f == null) throw ErroHttp(500);
    return f(canal);
  }
}

const rtp = Canal(id: '1', nome: 'RTP 1', grupo: 'PT');
const sic = Canal(id: '2', nome: 'SIC', grupo: 'PT');
final conta = Conta('x', Tipo.xtream, 'http://x');

void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('servico_guia'));
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  ServicoGuia servico(FonteFalsa f, {bool comArmazem = true, int Function()? relogio}) => ServicoGuia(
      chave: 'l1', conta: conta, fonte: f, armazem: Future.value(comArmazem ? ArmazemGuia(pasta) : null),
      agora: relogio ?? () => agora);

  Map<String, List<Programa>> guiaRtp() => {
        '1': [
          const Programa(agora - 600, agora + 1200, 'Telejornal', 'As notícias do dia'),
          const Programa(agora + 1200, agora + 4800, 'Futebol: Benfica x Porto'),
        ],
      };

  test('sem guia guardado: descarrega o de todos, grava-o e a pesquisa funciona', () async {
    final f = FonteFalsa(todosDa: guiaRtp);
    final s = servico(f);
    await s.usarCanais([rtp, sic]);
    expect(f.pedidosTodos, 1);
    expect(s.estado, EstadoGuia.pronto);
    final (atual, seguinte) = s.agoraESeguinteDe(rtp);
    expect(atual!.titulo, 'Telejornal');
    expect(seguinte!.titulo, 'Futebol: Benfica x Porto');
    expect(s.procurar('telejornal'), {'1': (programa: atual, aDar: true)});
    expect(s.procurar('benfica')['1']!.aDar, isFalse);
    expect(s.procurar('novela'), isEmpty);
    expect(s.pesquisaDisponivel, isTrue);
    s.dispose();
    expect((await ArmazemGuia(pasta).ler('l1'))!.porCanal.keys, ['1'], reason: 'ficou gravado');
  });

  test('com um guia guardado recente que cobre as próximas horas: usa-o sem descarregar', () async {
    final longo = guiaRtp()..['1']!.add(const Programa(agora + 4800, agora + 4 * 3600, 'Filme'));
    await ArmazemGuia(pasta).gravar('l1', GuiaLista(longo, criado: DateTime.fromMillisecondsSinceEpoch((agora - 600) * 1000)));
    final f = FonteFalsa(todosDa: guiaRtp);
    final s = servico(f);
    await s.usarCanais([rtp]);
    expect(f.pedidosTodos, 0);
    expect(s.estado, EstadoGuia.pronto);
    expect(s.programas(rtp), hasLength(3));
    s.dispose();
  });

  test('o guardado já só cobre pouco tempo: descarrega de novo', () async {
    await ArmazemGuia(pasta).gravar('l1', GuiaLista(guiaRtp(), criado: DateTime.fromMillisecondsSinceEpoch((agora - 600) * 1000)));
    final f = FonteFalsa(todosDa: guiaRtp);
    final s = servico(f);
    await s.usarCanais([rtp]);
    expect(f.pedidosTodos, 1);
    s.dispose();
  });

  test('guardado há mais de 4 horas: pergunta se mudou (304) e continua com o guardado', () async {
    await ArmazemGuia(pasta).gravar('l1', GuiaLista(guiaRtp(), criado: DateTime.fromMillisecondsSinceEpoch((agora - 5 * 3600) * 1000), etag: '"v1"'));
    final f = FonteFalsa(todosDa: guiaRtp)..naoMudou = true;
    final s = servico(f);
    await s.usarCanais([rtp]);
    expect(f.pedidosTodos, 1);
    expect(f.anteriorRecebido!.etag, '"v1"');
    expect(s.programas(rtp), hasLength(2));
    s.dispose();
  });

  test('o servidor não dá o guia de todos: pede só o do canal escolhido, uma vez', () async {
    final f = FonteFalsa(canalDa: (c) => [const Programa(agora - 60, agora + 60, 'Só deste')]);
    final s = servico(f, comArmazem: false);
    await s.usarCanais([rtp, sic]);
    expect(s.estado, EstadoGuia.soPorCanal);
    expect(s.pesquisaDisponivel, isFalse);
    await s.pedirCanal(sic);
    await s.pedirCanal(sic);
    expect(f.pedidosCanal, ['2']);
    expect(s.agoraESeguinteDe(sic).$1!.titulo, 'Só deste');
    expect(s.procurar('deste').keys, ['2'], reason: 'o que já se pediu também se encontra');
    s.dispose();
  });

  test('para o player: pede o guia do canal se faltar e devolve o programa a dar e o seguinte', () async {
    final f = FonteFalsa(canalDa: (c) => [
          const Programa(agora - 60, agora + 60, 'Só deste'),
          const Programa(agora + 60, agora + 120, 'Depois'),
        ]);
    final s = servico(f, comArmazem: false);
    await s.usarCanais([rtp, sic]);
    final (atual, seguinte) = await s.programasAgora(sic);
    expect(atual!.titulo, 'Só deste');
    expect(seguinte!.titulo, 'Depois');
    await s.programasAgora(sic);
    expect(f.pedidosCanal, ['2'], reason: 'o que já se tem não se volta a pedir');
    s.dispose();
    expect(await s.programasAgora(rtp), (null, null), reason: 'fechado (saiu-se da lista): não pede nada');
  });

  test('uma falha do canal espera 10 minutos antes de voltar a pedir', () async {
    var t = agora;
    final f = FonteFalsa();
    final s = servico(f, comArmazem: false, relogio: () => t);
    await s.usarCanais([rtp]);
    await s.pedirCanal(rtp);
    await s.pedirCanal(rtp);
    expect(f.pedidosCanal, ['1']);
    t += 11 * 60;
    await s.pedirCanal(rtp);
    expect(f.pedidosCanal, ['1', '1']);
    s.dispose();
  });

  test('«A seguir» não mostra um programa repetido dentro do que está a dar (23:30–00:00 e 23:31–00:00)', () async {
    final s = servico(FonteFalsa(todosDa: () => {
          '1': [
            const Programa(agora - 600, agora + 1200, 'Liga Francesa - Magazine'),
            const Programa(agora - 540, agora + 1200, 'Liga Francesa - Magazine'),
            const Programa(agora + 1200, agora + 6600, 'Titulares - Informação'),
          ],
        }), comArmazem: false);
    await s.usarCanais([rtp]);
    final (atual, seguinte) = s.agoraESeguinteDe(rtp);
    expect(atual!.inicio, agora - 600);
    expect(seguinte!.titulo, 'Titulares - Informação');
    expect(s.programas(rtp), hasLength(2));
    s.dispose();
  });

  test('o que já acabou sai sozinho com o tempo', () async {
    var t = agora;
    final s = servico(FonteFalsa(todosDa: guiaRtp), comArmazem: false, relogio: () => t);
    await s.usarCanais([rtp]);
    t = agora + 1300;
    expect(s.programas(rtp).map((p) => p.titulo), ['Futebol: Benfica x Porto']);
    expect(s.procurar('futebol')['1']!.aDar, isTrue);
    s.dispose();
  });
}
