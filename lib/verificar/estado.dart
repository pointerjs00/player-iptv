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

class ResultadoVerificacao {
  const ResultadoVerificacao(this.estado, this.motivo,
      {this.canal = '', this.validade = '', this.canais = const []});
  final EstadoV estado;
  final String motivo;

  /// O nome do canal que abriu (ou que se tentou).
  final String canal;
  final String validade;

  /// Com vários canais de teste: [{"id","nome","estado","motivo"}].
  final List<Map<String, dynamic>> canais;

  ResultadoVerificacao com({String? canal, String? validade}) => ResultadoVerificacao(
      estado, motivo, canal: canal ?? this.canal, validade: validade ?? this.validade, canais: canais);
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
    return ResultadoVerificacao(EstadoV.inconclusivo, _httpInconclusivos[e.status] ?? 'erro do servidor (${e.status})');
  }
  if (e is TimeoutException) return const ResultadoVerificacao(EstadoV.inconclusivo, 'tempo esgotado');
  if (e is SocketException) {
    return ResultadoVerificacao(EstadoV.inconclusivo, 'ligação falhou (${e.osError?.message ?? e.message})');
  }
  if (e is HttpException) return ResultadoVerificacao(EstadoV.inconclusivo, 'ligação cortada (${e.message})');
  return ResultadoVerificacao(EstadoV.inconclusivo, 'falha: $e');
}
