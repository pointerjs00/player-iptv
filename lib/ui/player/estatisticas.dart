import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../design/componentes.dart';
import 'diagnostico.dart';

/// A sobreposição "Estatísticas" do player: lê o mpv a cada `intervalo` (`ler` devolve as
/// [propriedadesDiagnostico] como texto) e mostra os valores e um veredicto simples sobre a
/// fluidez (rede / descodificação / ecrã / fluido). Peça independente: a Task 5 liga-a a partir
/// do painel de definições do player.
class PainelEstatisticas extends StatefulWidget {
  const PainelEstatisticas({super.key, required this.ler, this.reamostra = false, this.extra = const [],
      this.intervalo = const Duration(seconds: 1)});

  final Future<Map<String, String>> Function() ler;

  /// O mpv acerta o ritmo do vídeo ao do ecrã (Windows: `display-resample`).
  final bool reamostra;

  /// Linhas a mais (ex.: o modo de descodificação, a taxa do ecrã pedida).
  final List<(String, String)> extra;
  final Duration intervalo;

  @override
  State<PainelEstatisticas> createState() => _PainelEstatisticasState();
}

class _PainelEstatisticasState extends State<PainelEstatisticas> {
  /// ~5 s de história: chega para ver o buffer a cair ou as perdas a subir.
  static const _historia = 5;
  final _amostras = <AmostraMpv>[];
  Timer? _timer;
  bool _aLer = false;

  @override
  void initState() {
    super.initState();
    _ler();
    _timer = Timer.periodic(widget.intervalo, (_) => _ler());
  }

  Future<void> _ler() async {
    if (_aLer) return;
    _aLer = true;
    try {
      final m = await widget.ler();
      if (!mounted) return;
      setState(() {
        _amostras.add(AmostraMpv.deMapa(m));
        if (_amostras.length > _historia) _amostras.removeAt(0);
      });
    } catch (_) {
      // o player pode estar a fechar: fica a última leitura
    } finally {
      _aLer = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ultima = _amostras.isEmpty ? const AmostraMpv() : _amostras.last;
    final v = diagnosticar(_amostras, reamostra: widget.reamostra);
    const rotulo = TextStyle(color: Colors.white60, fontSize: 13);
    const valor = TextStyle(color: Colors.white, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]);
    final linhas = [...linhasEstatisticas(ultima), ...widget.extra];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SuperficieVidro(
        cor: const Color(0xD90B0F17),
        raio: 14,
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Estatísticas', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final (r, val) in linhas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 5, child: Text(r, style: rotulo)),
                Expanded(flex: 4, child: Text(val, style: valor)),
              ]),
            ),
          const SizedBox(height: 8),
          Text('Veredicto: ${v == null ? '—' : textoVeredicto(v)}',
              style: TextStyle(color: _cor(v), fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  static Color _cor(Veredicto? v) => switch (v) {
        Veredicto.fluido => const Color(0xFF5BD68A),
        Veredicto.rede || Veredicto.descodificacao || Veredicto.ecra => const Color(0xFFFFC857),
        null => Colors.white70,
      };
}
