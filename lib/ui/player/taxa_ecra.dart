import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

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

/// Pede ao Android TV / Fire TV o modo de ecrã que combina com o canal.
/// Usa o canal nativo `player_iptv/ecra` (MainActivity): `taxas` -> {atual, suportadas}
/// (para a resolução atual), `pedir` {hz}, `repor`.
///
/// Mudar de modo faz a TV piscar (ecrã preto uns segundos, a ligação HDMI volta a sincronizar).
/// Por isso, ao sair do player ([fechar]), o modo fica: sair é imediato e o canal seguinte com o
/// mesmo fps já não muda nada. O modo deixado é reposto quando a app vai para segundo plano
/// ([aoIrParaSegundoPlano]) ou herdado pelo player seguinte (que o repõe num erro).
///
/// Nunca deixa a TV presa no modo pedido fora da app: [repor] (canal com erro, app em segundo
/// plano) é idempotente, e um pedido que só responde depois de repor é desfeito logo.
class TaxaEcra {
  TaxaEcra({InvocarNativo? invocar}) : _invocar = invocar ?? _canal.invokeMethod {
    // o modo que o player anterior deixou passa a ser deste (repõe-o num erro ou em segundo plano)
    final deixada = _deixada;
    if (deixada != null) {
      _deixada = null;
      _pediu = deixada._pediu;
      deixada._pediu = false;
    }
  }

  static const _canal = MethodChannel('player_iptv/ecra');

  /// Regista `f` para quando a app for para segundo plano (ou fechar). Nos testes, um falso.
  static void Function(VoidCallback f) aoIrParaSegundoPlano =
      (f) => AppLifecycleListener(onHide: f, onDetach: f);

  /// O player que saiu com um modo pedido (fica até a app ir para segundo plano).
  static TaxaEcra? _deixada;
  static bool _comOuvinte = false;

  @visibleForTesting
  static void reiniciarGlobal() {
    _deixada = null;
    _comOuvinte = false;
  }

  static void _reporDeixada() {
    final d = _deixada;
    _deixada = null;
    d?._reporNativo();
  }

  final InvocarNativo _invocar;

  /// Há (ou pode haver, se ainda não respondeu) um modo pedido por nós.
  bool _pediu = false;
  bool _fechado = false;

  /// Muda a cada repor/fechar: um pedido de uma geração anterior que responda tarde é desfeito.
  int _geracao = 0;

  /// Os Hz atuais do ecrã segundo o sistema (null se não se sabe).
  Future<double?> hzAtual() async {
    try {
      final r = await _invocar('taxas');
      return r is Map ? (r['atual'] as num?)?.toDouble() : null;
    } catch (e) {
      debugPrint('taxa do ecrã: $e');
      return null;
    }
  }

  /// Pede o modo para `fps`; devolve os Hz pedidos (null se não pediu nada: já estava certo,
  /// nenhum modo serve, o player já fechou ou o canal nativo falhou).
  Future<double?> ajustarPara(double fps) async {
    if (_fechado) return null;
    final geracao = _geracao;
    try {
      final r = await _invocar('taxas');
      if (_fechado || geracao != _geracao || r is! Map) return null;
      final atual = (r['atual'] as num?)?.toDouble();
      final suportadas = [for (final v in (r['suportadas'] as List? ?? const [])) (v as num).toDouble()];
      final hz = escolherTaxa(fps, suportadas);
      if (hz == null || (atual != null && (atual - hz).abs() < 0.05)) return null;
      _pediu = true; // antes do await: um repor/fechar a meio já sabe que tem de desfazer
      await _invocar('pedir', {'hz': hz});
      if (geracao != _geracao) {
        // repôs-se enquanto o pedido estava a caminho: desfaz
        _pediu = true;
        await _reporNativo();
        return null;
      }
      if (_fechado) {
        // saiu-se enquanto o pedido estava a caminho: fica, como ao sair (ver [fechar])
        _deixar();
        return null;
      }
      return hz;
    } catch (e) {
      debugPrint('taxa do ecrã: $e');
      return null;
    }
  }

  /// Volta ao modo que o sistema escolher (só se tiver pedido algum). Pode voltar a pedir depois.
  Future<void> repor() async {
    _geracao++;
    await _reporNativo();
  }

  /// O player saiu: não volta a pedir. O modo pedido fica (sem piscar a TV ao sair) até a app ir
  /// para segundo plano ou o player seguinte o repor.
  Future<void> fechar() async {
    _fechado = true;
    if (_pediu) _deixar();
  }

  void _deixar() {
    _deixada = this;
    if (_comOuvinte) return;
    _comOuvinte = true;
    aoIrParaSegundoPlano(_reporDeixada);
  }

  Future<void> _reporNativo() async {
    if (!_pediu) return;
    _pediu = false;
    try {
      await _invocar('repor');
    } catch (e) {
      debugPrint('taxa do ecrã: $e');
    }
  }
}
