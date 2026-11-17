import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// O modo de ecrã (Hz) para mostrar um canal de `fps` imagens por segundo sem judder: um dos
/// `suportadas` que seja múltiplo inteiro do fps (cada imagem fica o mesmo número de
/// refrescamentos). Entre os exatos, o mais alto até 60 Hz (25 fps -> 50 Hz); 59.94 ganha a
/// 60 para 29.97. Nenhum compatível (ou fps desconhecido) -> null (não mexer no ecrã).
double? escolherTaxa(double fps, Iterable<double> suportadas) {
  if (fps.isNaN || fps <= 0) return null;
  double? melhor;
  double melhorErro = double.infinity;
  for (final hz in suportadas) {
    if (hz <= 0) continue;
    final k = (hz / fps).round();
    if (k < 1) continue;
    final erro = (hz - k * fps).abs() / hz;
    if (erro > 0.005) continue;
    final e = (erro * 1e4).round(); // erros quase iguais contam como iguais
    if (melhor == null || e < melhorErro || (e == melhorErro && _preferir(hz, melhor))) {
      melhor = hz;
      melhorErro = e.toDouble();
    }
  }
  return melhor;
}

/// Até 60 Hz, o mais alto; acima, o mais baixo (um ecrã a 120 Hz não ajuda e gasta mais).
bool _preferir(double a, double b) {
  const teto = 61.0;
  if (a <= teto && b <= teto) return a > b;
  if (a <= teto) return true;
  if (b <= teto) return false;
  return a < b;
}

typedef InvocarNativo = Future<Object?> Function(String metodo, [Object? argumentos]);

/// Pede ao Android TV / Fire TV o modo de ecrã que combina com o canal, e repõe-no ao sair.
/// Usa o canal nativo `player_iptv/ecra` (MainActivity): `taxas` -> {atual, suportadas}
/// (para a resolução atual), `pedir` {hz}, `repor`.
class TaxaEcra {
  TaxaEcra({InvocarNativo? invocar}) : _invocar = invocar ?? _canal.invokeMethod;

  static const _canal = MethodChannel('player_iptv/ecra');
  final InvocarNativo _invocar;
  bool _pediu = false;

  /// Pede o modo para `fps`; devolve os Hz pedidos (null se não pediu nada: já estava certo,
  /// nenhum modo serve ou o canal nativo falhou).
  Future<double?> ajustarPara(double fps) async {
    try {
      final r = await _invocar('taxas');
      if (r is! Map) return null;
      final atual = (r['atual'] as num?)?.toDouble();
      final suportadas = [for (final v in (r['suportadas'] as List? ?? const [])) (v as num).toDouble()];
      final hz = escolherTaxa(fps, suportadas);
      if (hz == null || (atual != null && (atual - hz).abs() < 0.05)) return null;
      await _invocar('pedir', {'hz': hz});
      _pediu = true;
      return hz;
    } catch (e) {
      debugPrint('taxa do ecrã: $e');
      return null;
    }
  }

  /// Volta ao modo que o sistema escolher (só se tiver pedido algum).
  Future<void> repor() async {
    if (!_pediu) return;
    _pediu = false;
    try {
      await _invocar('repor');
    } catch (e) {
      debugPrint('taxa do ecrã: $e');
    }
  }
}
