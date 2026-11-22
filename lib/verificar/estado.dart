/// Os três estados da verificação e a classificação das falhas. Porta de `motor/estados.py`.
library;

import 'dart:async';
import 'dart:io';

import '../rede/http.dart';

enum EstadoV {
  funciona('funciona'),
  naoFunciona('nao_funciona'),
  inconclusivo('inconclusivo');

  const EstadoV(this.valor);
  final String valor;
}

/// Se vale a pena testar outra vez uma lista inconclusiva.
enum Repeticao {
  /// O motivo não muda em minutos ("conta sem canais", a página não é uma lista): fica o 1.º.
  inutil,

  /// Servidor lento, ligação cortada, erro 5xx...: a 2.ª volta pode dar outra resposta.
  imediata,

  /// O servidor recusou por limite (ligações, 429, MAC em uso): a 2.ª volta espera um pouco antes.
  depoisDePausa,
}

class ResultadoVerificacao {
  const ResultadoVerificacao(this.estado, this.motivo,
      {this.canal = '', this.validade = '', this.canais = const [], this.tempoEsgotado = false,
      this.repeticao = Repeticao.imediata});
  final EstadoV estado;
  final String motivo;

  /// O nome do canal que abriu (ou que se tentou).
  final String canal;
  final String validade;

  /// Com vários canais de teste: [{"id","nome","estado","motivo"}].
  final List<Map<String, dynamic>> canais;

  /// INC porque se esgotou o tempo limite (da lista ou da conta), não por uma resposta.
  final bool tempoEsgotado;

  /// Só conta nas inconclusivas: se a 2.ª volta pode mudar o resultado.
  final Repeticao repeticao;

  ResultadoVerificacao com({String? canal, String? validade, Repeticao? repeticao}) =>
      ResultadoVerificacao(estado, motivo,
          canal: canal ?? this.canal, validade: validade ?? this.validade, canais: canais,
          tempoEsgotado: tempoEsgotado, repeticao: repeticao ?? this.repeticao);
}

const _httpDefinitivos = {
  401: 'credenciais ou acesso recusados (401)',
  403: 'acesso proibido (403)',
  404: 'não encontrado (404)',
  410: 'removido (410)',
};
const _httpInconclusivos = {
  429: 'servidor a limitar pedidos (429)',
  456: 'o painel recusa todos os canais (456) — MAC em uso noutro aparelho?',
  458: 'servidor recusou temporariamente (458)',
  459: 'limite de ligações simultâneas atingido (459)',
  461: 'servidor recusou temporariamente (461)',
};

ResultadoVerificacao classificarFalha(Object e) {
  if (e is ErroHttp) {
    final d = _httpDefinitivos[e.status];
    if (d != null) return ResultadoVerificacao(EstadoV.naoFunciona, d);
    final limite = _httpInconclusivos[e.status];
    return limite != null
        ? ResultadoVerificacao(EstadoV.inconclusivo, limite, repeticao: Repeticao.depoisDePausa)
        : ResultadoVerificacao(EstadoV.inconclusivo, 'erro do servidor (${e.status})');
  }
  if (e is TimeoutException) return const ResultadoVerificacao(EstadoV.inconclusivo, 'tempo esgotado');
  if (e is ErroTamanho) {
    return ResultadoVerificacao(EstadoV.inconclusivo, 'resposta grande demais (mais de ${e.maxBytes ~/ (1024 * 1024)} MB)');
  }
  if (e is SocketException) {
    return ResultadoVerificacao(EstadoV.inconclusivo, 'ligação falhou (${semSegredos(e.osError?.message ?? e.message)})');
  }
  if (e is HttpException) return const ResultadoVerificacao(EstadoV.inconclusivo, 'ligação cortada pelo servidor');
  return ResultadoVerificacao(EstadoV.inconclusivo, descreverErro(e));
}
