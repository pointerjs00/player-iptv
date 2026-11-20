import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';

Importada _imp(String linha, [UltimaVerificacao? u]) => Importada(contaDeLinha(linha)!, u);
UltimaVerificacao _u(String estado, [int dia = 1]) =>
    UltimaVerificacao(estado: estado, data: DateTime(2026, 3, dia), validade: '2027-10-16');

/// Verificador falso: o estado pedido para cada host.
class _Falso extends Verificador {
  _Falso(this.estados);
  final Map<String, EstadoV> estados;

  @override
  Future<ResultadoVerificacao> verificarUmaVez(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, void Function(String)? aviso}) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return ResultadoVerificacao(estados[hostDe(conta.endereco)] ?? EstadoV.naoFunciona, 'falso',
        validade: '2027-10-16');
  }
}

void main() {
  late Directory pasta;
  setUp(() async => pasta = await Directory.systemTemp.createTemp('gestor'));
  tearDown(() async {
    try {
      await pasta.delete(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  group('AreaGestor', () {
    test('adicionar não duplica pela chave, remover, limpar e tudo persiste noutro ficheiro', () async {
      final g = await AreaGestor.abrir(pasta);
      expect(await g.adicionar([_imp('http://a.com/c/ 00:1A:79:00:00:01'), _imp('http://b.com/c/ 00:1A:79:00:00:01')]), 2);
      expect(await g.adicionar([_imp('http://A.com:80 00:1a:79:00:00:01', _u('funciona')),
          _imp('http://c.com/c/ 00:1A:79:00:00:01')]), 1);
      expect(g.listas.map((l) => l.nome), ['001A 161027', '002B', '003C']);
      await g.registarVerificacao(g.listas[1].id, _u('inconclusivo'));
      await g.remover([g.listas[2].id]);

      final r = await AreaGestor.abrir(pasta);
      expect(r.listas.map((l) => l.nomeMostrado), ['001A 161027', 'INC 002B 161027']);
      // o Gestor não mexe nas listas do Player
      expect((await Biblioteca.abrir(pasta)).listas, isEmpty);
      expect(File('${pasta.path}${Platform.pathSeparator}gestor.json').existsSync(), isTrue);

      await r.limpar();
      expect((await AreaGestor.abrir(pasta)).listas, isEmpty);
    });

    test('um ficheiro estragado fica em .bak e o Gestor começa vazio', () async {
      File('${pasta.path}${Platform.pathSeparator}gestor.json').writeAsStringSync('{lixo');
      final g = await AreaGestor.abrir(pasta);
      expect(g.listas, isEmpty);
      expect(File('${pasta.path}${Platform.pathSeparator}gestor.json.bak').existsSync(), isTrue);
    });

    test('M1: um bloqueio passageiro ao ler (antivírus) é repetido e as listas abrem', () async {
      final g = await AreaGestor.abrir(pasta);
      await g.adicionar([_imp('http://a.com/c/ 00:1A:79:00:00:01')]);
      var tentativas = 0;
      final r = await AreaGestor.abrir(pasta, ler: (f) async {
        if (++tentativas < 3) throw const FileSystemException('bloqueado');
        return f.readAsString();
      });
      expect(tentativas, 3);
      expect(r.listas, hasLength(1));
    });

    test('M1: bloqueado de vez, abre vazio sem lançar e não apaga o ficheiro bom', () async {
      final g = await AreaGestor.abrir(pasta);
      await g.adicionar([_imp('http://a.com/c/ 00:1A:79:00:00:01')]);
      final original = File('${pasta.path}${Platform.pathSeparator}gestor.json').readAsStringSync();
      final r = await AreaGestor.abrir(pasta, ler: (_) async => throw const FileSystemException('bloqueado'));
      expect(r.listas, isEmpty);
      // a 1.ª gravação guarda o ficheiro que não se conseguiu ler em .bak (nada se perde)
      await r.adicionar([_imp('http://b.com/c/ 00:1A:79:00:00:01')]);
      expect(File('${pasta.path}${Platform.pathSeparator}gestor.json.bak').readAsStringSync(), original);
      expect((await AreaGestor.abrir(pasta)).listas.map((l) => l.nome), ['001B']);
    });

    test('Importar do Player copia as listas com o último resultado, sem duplicar', () async {
      final b = await Biblioteca.abrir(pasta);
      await b.adicionar([_imp('http://a.com/c/ 00:1A:79:00:00:01', _u('funciona')), _imp('http://b.com/x.m3u')]);
      final g = await AreaGestor.abrir(pasta);
      await g.adicionar([_imp('http://a.com/c/ 00:1A:79:00:00:01')]);
      expect(await g.importarDoPlayer(b), 1);
      expect(g.listas, hasLength(2));
      expect(g.listas.first.ultima!.estado, 'funciona');
      expect(await g.importarDoPlayer(b), 0);
      expect(b.listas, hasLength(2));
    });

    test('o serviço grava os resultados na coleção que verifica (o Gestor), não no Player', () async {
      final b = await Biblioteca.abrir(pasta);
      await b.adicionar([_imp('http://a.com/c/ 00:1A:79:00:00:01')]);
      final g = await AreaGestor.abrir(pasta);
      await g.adicionar([_imp('http://a.com/c/ 00:1A:79:00:00:01'), _imp('http://b.com/c/ 00:1A:79:00:00:01')]);
      final s = ServicoVerificacao(b, colecao: g, verificador: _Falso({'a.com': EstadoV.funciona}));
      await s.verificarVarias(g.listas);
      expect(g.listas.map((l) => l.ultima?.estado), ['funciona', 'nao_funciona']);
      expect(b.listas.single.ultima, isNull);
      expect((await AreaGestor.abrir(pasta)).listas.first.ultima!.estado, 'funciona');
    });
  });

  group('Biblioteca.receber', () {
    late Biblioteca b;
    late AreaGestor g;

    /// Player: A funciona, B inconclusiva, C não funciona, D por verificar (com favoritos e cache).
    /// Gestor: A (agora não funciona) e E (funciona), as duas enviadas.
    setUp(() async {
      b = await Biblioteca.abrir(pasta);
      await b.adicionar([
        _imp('http://a.com/c/ 00:1A:79:00:00:01', _u('funciona')),
        _imp('http://b.com/c/ 00:1A:79:00:00:01', _u('inconclusivo')),
        _imp('http://c.com/c/ 00:1A:79:00:00:01', _u('nao_funciona')),
        _imp('http://d.com/x.m3u'),
      ]);
      for (final l in b.listas) {
        await b.alternarFavorito(l.id, 'fav');
        await b.guardarCanais(l.id, ConteudoLista(const ['G'], const [Canal(id: '1', nome: 'c', grupo: 'G', url: 'u')]));
      }
      g = await AreaGestor.abrir(pasta);
      await g.adicionar([
        _imp('http://a.com/c/ 00:1A:79:00:00:01', _u('nao_funciona', 9)),
        _imp('http://e.com/c/ 00:1A:79:00:00:01', _u('funciona', 9)),
      ]);
    });

    Future<List<String>> hosts(Biblioteca x) async => [for (final l in x.listas) hostDe(l.conta.endereco)];

    test('adicionar: junta sem duplicar e atualiza o resultado das que já existiam', () async {
      final r = await b.receber(g.listas, ModoEnvio.adicionar);
      expect((r.adicionadas, r.atualizadas, r.removidas), (1, 1, 0));
      expect(await hosts(b), ['a.com', 'b.com', 'c.com', 'd.com', 'e.com']);
      expect(b.listas.first.ultima!.estado, 'nao_funciona');
      expect(b.listas.first.favoritos, {'fav'}, reason: 'as que já existiam mantêm os favoritos');
      expect(await b.canaisEmCache(b.listas.first.id), isNotNull);
      // persiste
      expect(await hosts(await Biblioteca.abrir(pasta)), ['a.com', 'b.com', 'c.com', 'd.com', 'e.com']);
    });

    test('esmagar mantendo as que funcionam', () async {
      final removida = b.listas[1].id; // B (inconclusiva)
      final r = await b.receber(g.listas, ModoEnvio.substituir, manter: {ManterAoSubstituir.funcionam});
      // A é enviada (fica, atualizada); B, C e D saem
      expect((r.adicionadas, r.atualizadas, r.removidas), (1, 1, 3));
      expect(await hosts(b), ['a.com', 'e.com']);
      expect(await b.canaisEmCache(removida), isNull, reason: 'a cache das removidas sai');
    });

    test('esmagar mantendo as que funcionam e as inconclusivas', () async {
      final r = await b.receber(g.listas, ModoEnvio.substituir, manter: {ManterAoSubstituir.funcionam, ManterAoSubstituir.inconclusivas});
      expect((r.adicionadas, r.atualizadas, r.removidas), (1, 1, 2));
      expect(await hosts(b), ['a.com', 'b.com', 'e.com']);
      expect(b.listas[1].favoritos, {'fav'});
    });

    test('substituir mantendo as favoritas e as que funcionam: fica a união', () async {
      await b.alternarFavorita(b.listas[2].id); // C (não funciona) é favorita
      final r = await b.receber(g.listas, ModoEnvio.substituir,
          manter: {ManterAoSubstituir.favoritas, ManterAoSubstituir.funcionam});
      // A é enviada; C fica por ser favorita; B e D saem
      expect((r.adicionadas, r.atualizadas, r.removidas), (1, 1, 2));
      expect(await hosts(b), ['a.com', 'c.com', 'e.com']);
    });

    test('substituir mantendo só as favoritas ou só as inconclusivas', () async {
      await b.alternarFavorita(b.listas[3].id); // D (por verificar) é favorita
      final r = await b.receber(g.listas, ModoEnvio.substituir, manter: {ManterAoSubstituir.favoritas});
      expect(r.removidas, 2);
      expect(await hosts(b), ['a.com', 'd.com', 'e.com']);
      final r2 = await b.receber(g.listas, ModoEnvio.substituir, manter: {ManterAoSubstituir.inconclusivas});
      expect(r2.removidas, 1, reason: 'D sai: já não é inconclusiva nem pedida');
      expect(await hosts(b), ['a.com', 'e.com']);
    });

    test('substituir sem manter nada: uma enviada igual a uma favorita continua favorita', () async {
      await b.alternarFavorita(b.listas.first.id); // A é favorita e também vem do Gestor
      await b.receber(g.listas, ModoEnvio.substituir);
      expect(await hosts(b), ['a.com', 'e.com']);
      expect(b.listas.first.favorita, isTrue);
      expect((await Biblioteca.abrir(pasta)).listas.first.favorita, isTrue);
    });

    test('M2: se a gravação falhar, o Player fica como estava (memória = disco) e o erro chega', () async {
      final antes = [for (final l in b.listas) (hostDe(l.conta.endereco), l.ultima?.estado)];
      // o ficheiro passa a ser uma pasta: a troca atómica (rename) falha
      final f = File('${pasta.path}${Platform.pathSeparator}biblioteca.json');
      f.deleteSync();
      Directory(f.path).createSync();
      var avisos = 0;
      b.addListener(() => avisos++);
      await expectLater(b.receber(g.listas, ModoEnvio.substituir), throwsA(isA<FileSystemException>()));
      expect([for (final l in b.listas) (hostDe(l.conta.endereco), l.ultima?.estado)], antes);
      expect(avisos, greaterThan(0), reason: 'a interface volta a desenhar o estado antigo');
      for (final l in b.listas) {
        expect(await b.canaisEmCache(l.id), isNotNull, reason: 'a cache fica');
      }
    });

    test('esmagar todas: o Player fica só com as enviadas; favoritos e cache das removidas saem', () async {
      final ids = [for (final l in b.listas) l.id];
      final r = await b.receber([g.listas.last], ModoEnvio.substituir);
      expect((r.adicionadas, r.atualizadas, r.removidas), (1, 0, 4));
      expect(await hosts(b), ['e.com']);
      expect(b.listas.single.favoritos, isEmpty);
      for (final id in ids) {
        expect(await b.canaisEmCache(id), isNull);
      }
      final reaberta = await Biblioteca.abrir(pasta);
      expect(await hosts(reaberta), ['e.com']);
      // a mesma conta volta a entrar sem os favoritos antigos
      await reaberta.receber([g.listas.first], ModoEnvio.adicionar);
      expect(reaberta.listas.last.favoritos, isEmpty);
    });
  });
}
