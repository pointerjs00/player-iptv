/// Verifica uma lista: entra, procura os canais de teste e lê o stream de cada um.
/// As regras são as do verificador (`motor/verificador.py`, `candidatos.py`):
/// - funciona se um dos canais de teste der vídeo;
/// - não funciona só com prova (conta recusada/expirada, portal inexistente, DNS inexistente,
///   canal que não existe na lista, todos os candidatos a provar que não abrem);
/// - o resto é inconclusivo, e as inconclusivas são testadas outra vez (com o dobro do tempo).
library;

import 'dart:async';
import 'dart:io';

import '../importar/importar.dart';
import '../modelo/canal.dart';
import '../modelo/conta.dart';
import '../protocolos/protocolo.dart';
import '../rede/http.dart';
import 'canais_teste.dart';
import 'estado.dart';
import 'video.dart';

const maxCandidatos = 3;

/// Lê o stream de um canal (substituível nos testes).
typedef LerStream = Future<ResultadoVerificacao> Function(String url, Map<String, String> headers,
    {Duration timeout, Cancelamento? cancelamento, bool stream401Inc});

/// Resolve o nome do host (substituível nos testes): null = existe; senão o resultado.
typedef ResolverDns = Future<ResultadoVerificacao?> Function(String host);

// Só "o host não existe" é prova (11001 no Windows; EAI_NONAME/EAI_NODATA no Linux/Android).
const _dnsInexistente = {11001, -2, 7, 8};

Future<ResultadoVerificacao?> resolverDns(String host) async {
  if (host.isEmpty || InternetAddress.tryParse(host) != null) return null;
  try {
    await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
    return null;
  } on SocketException catch (e) {
    final codigo = e.osError?.errorCode;
    if (codigo != null && _dnsInexistente.contains(codigo)) {
      return ResultadoVerificacao(EstadoV.naoFunciona, 'DNS: $host não existe');
    }
    return const ResultadoVerificacao(EstadoV.inconclusivo, 'DNS sem resposta');
  } on TimeoutException {
    return const ResultadoVerificacao(EstadoV.inconclusivo, 'DNS sem resposta');
  }
}

class Verificador {
  Verificador({this.ler = lerStream, this.dns = resolverDns, this.espera = const Duration(seconds: 3),
      this.pausaReteste = const Duration(seconds: 5)});

  final LerStream ler;
  final ResolverDns dns;

  /// Antes da 2.ª leitura de um candidato que falhou.
  final Duration espera;

  /// Antes de voltar a testar uma conta inconclusiva.
  final Duration pausaReteste;

  /// Verifica com uma 2.ª volta se o resultado for inconclusivo.
  Future<ResultadoVerificacao> verificar(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso}) async {
    final r1 = await verificarUmaVez(conta, canaisTeste, timeout: timeout, cancelamento: cancelamento, aviso: aviso);
    if (r1.estado != EstadoV.inconclusivo) return r1;
    aviso?.call('inconclusiva: a testar outra vez');
    await Future<void>.delayed(pausaReteste);
    cancelamento?.verificar();
    final r2 = await verificarUmaVez(conta, canaisTeste, timeout: timeout * 2, cancelamento: cancelamento, aviso: aviso);
    return r2.validade.isEmpty && r1.validade.isNotEmpty ? r2.com(validade: r1.validade) : r2;
  }

  Future<ResultadoVerificacao> verificarUmaVez(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso}) async {
    aviso?.call('a resolver o DNS');
    final rDns = await dns(hostDe(conta.endereco));
    if (rDns != null) return rDns;
    final ConteudoLista conteudo;
    final proto = Protocolo.para(conta);
    try {
      conteudo = await proto.abrir(conta, cancelamento: cancelamento, aviso: aviso);
    } on Cancelado {
      rethrow;
    } on ErroLista catch (e) {
      return ResultadoVerificacao(e.definitivo ? EstadoV.naoFunciona : EstadoV.inconclusivo, e.mensagem);
    } catch (e) {
      return classificarFalha(e);
    }
    final perfis = perfisDe(canaisTeste);
    final porCanal = <(PerfilCanal, ResultadoVerificacao)>[];
    for (final p in perfis) {
      porCanal.add((p, await _testarPerfil(conta, proto, conteudo, p, timeout, cancelamento, aviso)));
    }
    final r = porCanal.length == 1 ? porCanal.single.$2 : juntar(porCanal);
    return r.com(validade: conteudo.validade);
  }

  Future<ResultadoVerificacao> _testarPerfil(Conta conta, Protocolo proto, ConteudoLista conteudo, PerfilCanal p,
      Duration timeout, Cancelamento? can, Aviso? aviso) async {
    final cands = candidatos(p, conteudo.canais, (c) => c.nome, (c) => c.id).take(maxCandidatos).toList();
    if (cands.isEmpty) {
      return ResultadoVerificacao(EstadoV.naoFunciona,
          '${p.nome} não existe na ${conta.tipo == Tipo.m3u ? 'lista' : 'conta'}');
    }
    final resultados = <ResultadoVerificacao>[];
    for (var k = 0; k < cands.length; k++) {
      final c = cands[k];
      aviso?.call('${p.nome} · variante ${k + 1}/${cands.length} · ${c.nome}');
      final r = await _comRepeticao(conta, proto, c, timeout, can);
      if (r.estado == EstadoV.funciona) return r;
      resultados.add(r);
    }
    return resultados.firstWhere((r) => r.estado == EstadoV.inconclusivo, orElse: () => resultados.first);
  }

  /// Lê; se falhar, espera e lê outra vez (pede o link de novo: no Stalker expira).
  Future<ResultadoVerificacao> _comRepeticao(Conta conta, Protocolo proto, Canal c, Duration timeout,
      Cancelamento? can) async {
    Future<ResultadoVerificacao> uma() async {
      final FonteVideo f;
      try {
        f = await proto.fonte(conta, c, cancelamento: can);
      } on Cancelado {
        rethrow;
      } catch (e) {
        // uma recusa do create_link é problema de sessão, não prova sobre o stream
        return ResultadoVerificacao(EstadoV.inconclusivo, 'o link do canal falhou: $e');
      }
      return ler(f.url, f.headers, timeout: timeout, cancelamento: can, stream401Inc: conta.tipo == Tipo.xtream);
    }

    final r1 = await uma();
    if (r1.estado == EstadoV.funciona) return r1.com(canal: c.nome);
    await Future<void>.delayed(espera);
    can?.verificar();
    final r2 = await uma();
    if (r2.estado == EstadoV.funciona) {
      return ResultadoVerificacao(EstadoV.funciona, '${r2.motivo} (2.ª tentativa)', canal: c.nome);
    }
    if (r1.estado == EstadoV.naoFunciona && r2.estado == EstadoV.naoFunciona) return r2.com(canal: c.nome);
    final duvida = r2.estado == EstadoV.inconclusivo ? r2 : r1;
    return ResultadoVerificacao(EstadoV.inconclusivo, duvida.motivo, canal: c.nome);
  }
}

/// Vários canais: funciona se um abrir; não funciona se nenhum existir/abrir; senão INC.
ResultadoVerificacao juntar(List<(PerfilCanal, ResultadoVerificacao)> rs) {
  final estados = rs.map((e) => e.$2.estado);
  final estado = estados.contains(EstadoV.funciona)
      ? EstadoV.funciona
      : estados.every((e) => e == EstadoV.naoFunciona) ? EstadoV.naoFunciona : EstadoV.inconclusivo;
  final melhor = rs.firstWhere((e) => e.$2.estado == estado, orElse: () => rs.first).$2;
  return ResultadoVerificacao(
    estado,
    rs.map((e) => '${e.$1.nome}: ${e.$2.motivo}').join(' · '),
    canal: melhor.canal,
    canais: [
      for (final (p, r) in rs) {'id': p.id, 'nome': p.nome, 'estado': r.estado.valor, 'motivo': r.motivo},
    ],
  );
}

/// O resultado no formato guardado na biblioteca.
UltimaVerificacao paraUltima(ResultadoVerificacao r, [DateTime? quando]) => UltimaVerificacao(
      estado: r.estado.valor, motivo: r.estado == EstadoV.funciona && r.canal.isNotEmpty ? 'abriu ${r.canal}' : r.motivo,
      data: quando ?? DateTime.now(), validade: r.validade, canais: r.canais,
    );
