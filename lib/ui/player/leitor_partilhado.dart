/// As leituras de propriedades do mpv partilhadas entre quem as pede (a barra de controlos, a
/// barra de progresso, as estatísticas): o que foi lido há menos de [validade] vem da memória e o
/// que falta lê-se de uma vez (um só pedido fora da UI, ver `MotorForaDaUi.getProperties`).
class LeitorPartilhado {
  LeitorPartilhado(this._lerVarias, {this.validade = const Duration(milliseconds: 400), DateTime Function()? agora})
      : _agora = agora ?? DateTime.now;

  final Future<Map<String, String>> Function(List<String> propriedades) _lerVarias;
  final Duration validade;
  final DateTime Function() _agora;
  final _memoria = <String, (String, DateTime)>{};
  int _geracao = 0;

  /// As `propriedades` (texto; "" quando o mpv não sabe).
  Future<Map<String, String>> ler(List<String> propriedades) async {
    final agora = _agora();
    bool recente(String p) {
      final m = _memoria[p];
      return m != null && agora.difference(m.$2) < validade;
    }

    final falta = [for (final p in propriedades) if (!recente(p)) p];
    if (falta.isNotEmpty) {
      final geracao = _geracao;
      final lido = await _lerVarias(falta);
      final r = {for (final p in propriedades) p: lido[p] ?? _memoria[p]?.$1 ?? ''};
      if (geracao == _geracao) {
        for (final p in falta) {
          _memoria[p] = (lido[p] ?? '', agora);
        }
      }
      return r;
    }
    return {for (final p in propriedades) p: _memoria[p]!.$1};
  }

  /// A próxima leitura é nova (um seek mudou a posição, abriu-se outro canal).
  void esquecer() {
    _memoria.clear();
    _geracao++;
  }
}
