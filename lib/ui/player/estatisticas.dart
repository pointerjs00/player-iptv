import 'dart:async';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../design/componentes.dart';
import 'diagnostico.dart';
import 'motor_reproducao.dart';

/// Os desenhos da interface do Flutter (`SchedulerBinding.addTimingsCallback`): quantos por segundo
/// e quanto custa cada um (construção + rasterização). Conta pelos tempos das próprias imagens, não
/// pelo relógio da app.
class MedidorDesenho {
  /// Quantas imagens se guardam (mais do que as de um segundo a 120 Hz).
  static const maximo = 240;

  final _imagens = <({int inicio, int duracao})>[];

  int get amostras => _imagens.length;

  void registar(List<FrameTiming> tempos) {
    for (final t in tempos) {
      _imagens.add((
        inicio: t.timestampInMicroseconds(FramePhase.vsyncStart),
        duracao: (t.buildDuration + t.rasterDuration).inMicroseconds,
      ));
    }
    if (_imagens.length > maximo) _imagens.removeRange(0, _imagens.length - maximo);
  }

  /// Imagens desenhadas no último segundo (contado a partir da mais recente); null sem desenhos.
  double? get imagensPorSegundo {
    if (_imagens.isEmpty) return null;
    final fim = _imagens.last.inicio;
    return _imagens.where((i) => fim - i.inicio < 1000000).length.toDouble();
  }

  /// O tempo médio de desenho de cada imagem, em ms; null sem desenhos.
  double? get tempoMedioMs =>
      _imagens.isEmpty ? null : _imagens.fold<int>(0, (a, i) => a + i.duracao) / _imagens.length / 1000;
}

/// As duas linhas do desenho da interface. `soInterface` (ExoPlayer): o vídeo vai direto para uma
/// superfície do sistema, fora do Flutter; o que se mede é só a interface por cima dele.
List<(String, String)> linhasDesenho(MedidorDesenho m, {bool soInterface = false}) {
  final fps = m.imagensPorSegundo, ms = m.tempoMedioMs;
  final nota = soInterface ? ' (só a interface por cima do vídeo)' : '';
  return [
    ('Imagens desenhadas/s (interface)', '${fps == null ? '—' : fps.toStringAsFixed(0)}$nota'),
    ('Tempo de desenho', '${ms == null ? '—' : '${ms.toStringAsFixed(1)} ms'}$nota'),
  ];
}

/// A sobreposição "Estatísticas" do player: lê o mpv a cada `intervalo` (`ler` devolve as
/// [propriedadesDiagnostico] como texto) e mostra os valores e um veredicto simples sobre a
/// fluidez (rede / descodificação / ecrã / fluido). Peça independente: a Task 5 liga-a a partir
/// do painel de definições do player. Num motor sem mpv (o ExoPlayer) lê-se [lerMotor] em vez de
/// [ler].
class PainelEstatisticas extends StatefulWidget {
  const PainelEstatisticas({super.key, this.ler, this.lerMotor, this.hzEcra, this.geracao, this.soInterface = false, this.extra = const [],
      this.intervalo = const Duration(seconds: 1)})
      : assert((ler == null) != (lerMotor == null), 'ou o mpv ou o motor');

  final Future<Map<String, String>> Function()? ler;

  /// O retrato do motor ([MotorReproducao.estatisticas]), quando não há mpv.
  final Future<EstatisticasMotor> Function()? lerMotor;

  /// Os Hz do ecrã segundo o sistema (Android), para quando o mpv não os sabe.
  final double? hzEcra;

  /// Muda a cada canal aberto (zapping): as amostras recomeçam, para não comparar o buffer do
  /// canal anterior com o do novo.
  final Object? geracao;

  /// O vídeo não passa pelo Flutter (ExoPlayer): as linhas do desenho medem só a interface.
  final bool soInterface;

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

  /// A última leitura do motor (só com [PainelEstatisticas.lerMotor]).
  EstatisticasMotor? _motor;
  final _desenho = MedidorDesenho();
  Timer? _timer;
  bool _aLer = false;

  void _tempos(List<FrameTiming> t) => _desenho.registar(t);

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_tempos);
    _ler();
    _timer = Timer.periodic(widget.intervalo, (_) => _ler());
  }

  Future<void> _ler() async {
    if (_aLer) return;
    _aLer = true;
    try {
      final lerMotor = widget.lerMotor;
      final EstatisticasMotor? e = lerMotor == null ? null : await lerMotor();
      final amostra = e != null ? amostraDoMotor(e) : AmostraMpv.deMapa(await widget.ler!());
      if (!mounted) return;
      setState(() {
        _motor = e;
        _amostras.add(amostra);
        if (_amostras.length > _historia) _amostras.removeAt(0);
      });
    } catch (_) {
      // o player pode estar a fechar: fica a última leitura
    } finally {
      _aLer = false;
    }
  }

  @override
  void didUpdateWidget(PainelEstatisticas antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.geracao != widget.geracao) _amostras.clear();
  }

  @override
  void dispose() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_tempos);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ultima = _amostras.isEmpty ? const AmostraMpv() : _amostras.last;
    final v = diagnosticar(_amostras, hzEcra: widget.hzEcra);
    const rotulo = TextStyle(color: Colors.white60, fontSize: 13);
    const valor = TextStyle(color: Colors.white, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]);
    final motor = _motor;
    final linhas = [
      ...(widget.lerMotor != null
          ? linhasEstatisticasMotor(motor ?? const EstatisticasMotor(), hzEcra: widget.hzEcra)
          : linhasEstatisticas(ultima, hzEcra: widget.hzEcra)),
      ...linhasDesenho(_desenho, soInterface: widget.soInterface),
      ...widget.extra,
    ];
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
          Text('Veredicto: ${v != null ? textoVeredicto(v) : (ultima.largura > 0 ? 'a medir…' : '—')}',
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
