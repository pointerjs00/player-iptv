import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../design/barra_teclas.dart';
import '../design/design.dart';

const _mesesCurtos = ['jan.', 'fev.', 'mar.', 'abr.', 'mai.', 'jun.', 'jul.', 'ago.', 'set.', 'out.', 'nov.', 'dez.'];
const _mesesLongos = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro', //
];

/// "10 nov. 2026" (sem depender de `intl`).
String dataCurta(DateTime d) => '${d.day} ${_mesesCurtos[d.month - 1]} ${d.year}';

/// "10 de novembro de 2026", para os leitores de ecrã.
String _dataLonga(DateTime d) => '${d.day} de ${_mesesLongos[d.month - 1]} de ${d.year}';

DateTime _soDia(DateTime d) => DateTime(d.year, d.month, d.day);

/// Abre o calendário num ecrã inteiro. Devolve o intervalo ao carregar em «Procurar e juntar»,
/// ou `null` com Voltar.
Future<DateTimeRange?> escolherIntervalo(
  BuildContext context, {
  required DateTime inicio,
  required DateTime fim,
  required DateTime hoje,
  DateTime? primeiro,
}) =>
    Navigator.of(context).push<DateTimeRange>(MaterialPageRoute(
      builder: (_) => CalendarioIntervalo(inicio: inicio, fim: fim, hoje: hoje, primeiro: primeiro),
    ));

/// O calendário do stbstalker desenhado no próprio ecrã: funciona com as setas e o OK do comando
/// (o seletor do sistema não deixava o OK confirmar o dia), com o rato e com o toque.
class CalendarioIntervalo extends StatefulWidget {
  const CalendarioIntervalo({
    super.key,
    required this.inicio,
    required this.fim,
    required this.hoje,
    this.primeiro,
  });
  final DateTime inicio, fim, hoje;
  final DateTime? primeiro;

  @override
  State<CalendarioIntervalo> createState() => _CalendarioIntervaloState();
}

class _CalendarioIntervaloState extends State<CalendarioIntervalo> {
  late final DateTime _hoje = _soDia(widget.hoje);
  late final DateTime _primeiro = _soDia(widget.primeiro ?? DateTime(2015));
  late DateTime _foco;
  DateTime? _de, _ate;
  bool _gradeComFoco = false;
  final _noGrade = FocusNode(debugLabel: 'Calendário');
  final _noProcurar = FocusNode(debugLabel: 'Procurar e juntar');
  final _noRecomecar = FocusNode(debugLabel: 'Recomeçar');
  final _noAnterior = FocusNode(debugLabel: 'Mês anterior');
  final _noSeguinte = FocusNode(debugLabel: 'Mês seguinte');

  @override
  void initState() {
    super.initState();
    _de = _soDia(widget.inicio);
    _ate = _soDia(widget.fim);
    _foco = _ate!.isAfter(_hoje) ? _hoje : _ate!;
  }

  @override
  void dispose() {
    _noGrade.dispose();
    _noProcurar.dispose();
    _noRecomecar.dispose();
    _noAnterior.dispose();
    _noSeguinte.dispose();
    super.dispose();
  }

  bool _vale(DateTime d) => !d.isAfter(_hoje) && !d.isBefore(_primeiro);

  /// Move o dia focado. Um movimento para depois de hoje (que não há) leva o foco aos botões do
  /// painel, para o comando lá chegar só com as setas; ↑ na primeira semana visível leva ao mês.
  void _mover(int dias) {
    final d = DateTime(_foco.year, _foco.month, _foco.day + dias);
    if (d.isAfter(_hoje)) {
      (_ate != null && _de != null ? _noProcurar : _noRecomecar).requestFocus();
      return;
    }
    if (dias == -7) {
      final vazios = DateTime(_foco.year, _foco.month, 1).weekday - 1;
      if (_foco.day + vazios <= 7) {
        (_haMesAntes ? _noAnterior : _noSeguinte).requestFocus();
        return;
      }
    }
    if (_vale(d)) setState(() => _foco = d);
  }

  void _mudarMes(int delta) {
    final m = DateTime(_foco.year, _foco.month + delta);
    final ultimo = DateTime(m.year, m.month + 1, 0).day;
    var d = DateTime(m.year, m.month, _foco.day > ultimo ? ultimo : _foco.day);
    if (d.isAfter(_hoje)) d = _hoje;
    if (d.isBefore(_primeiro)) d = _primeiro;
    if (d.month != _foco.month || d.year != _foco.year) setState(() => _foco = d);
  }

  bool get _haMesAntes => !DateTime(_foco.year, _foco.month, 0).isBefore(_primeiro);
  bool get _haMesDepois => !DateTime(_foco.year, _foco.month + 1, 1).isAfter(_hoje);

  void _marcar(DateTime d) {
    if (!_vale(d)) return;
    var fechou = false;
    setState(() {
      _foco = d;
      if (_de == null || _ate != null) {
        _de = d;
        _ate = null;
      } else {
        if (d.isBefore(_de!)) {
          _ate = _de;
          _de = d;
        } else {
          _ate = d;
        }
        fechou = true;
      }
    });
    // com as duas datas, o foco vai para «Procurar e juntar»: o comando chega lá sem sair da grelha
    if (fechou) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _noProcurar.requestFocus();
      });
    }
  }

  void _recomecar() {
    setState(() {
      _de = null;
      _ate = null;
    });
    _noGrade.requestFocus();
  }

  void _procurar() {
    if (_de == null || _ate == null) return;
    Navigator.of(context).pop(DateTimeRange(start: _de!, end: _ate!));
  }

  static final _teclasOk = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  KeyEventResult _tecla(FocusNode no, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _mover(-1);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _mover(1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _mover(-7);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _mover(7);
    } else if (_teclasOk.contains(k)) {
      if (e is KeyDownEvent) _marcar(_foco);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// ‹ › do mês: ← → andam entre os dois; ↓ volta à grelha.
  KeyEventResult _teclaMes(FocusNode no, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _noGrade.requestFocus();
    } else if (_teclasOk.contains(k)) {
      // o OK do comando muda de mês (não depender do InkWell para isto)
      if (e is KeyDownEvent) {
        if (_noAnterior.hasFocus && _haMesAntes) _mudarMes(-1);
        if (_noSeguinte.hasFocus && _haMesDepois) _mudarMes(1);
      }
    } else if (k == LogicalKeyboardKey.arrowRight && _noAnterior.hasFocus && _haMesDepois) {
      _noSeguinte.requestFocus();
    } else if (k == LogicalKeyboardKey.arrowLeft && _noSeguinte.hasFocus && _haMesAntes) {
      _noAnterior.requestFocus();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Botões do painel: ↑ ↓ andam entre «Procurar e juntar» e «Recomeçar»; ← volta à grelha.
  KeyEventResult _teclaPainel(FocusNode no, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final pronto = _de != null && _ate != null;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _noGrade.requestFocus();
    } else if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      if (_noProcurar.hasFocus) {
        _noRecomecar.requestFocus();
      } else if (pronto) {
        _noProcurar.requestFocus();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------- construção

  Widget _seta(String texto, String rotulo, FocusNode no, VoidCallback? aoTocar) => Semantics(
        button: true,
        label: rotulo,
        enabled: aoTocar != null,
        excludeSemantics: true,
        child: Material(
          color: Tokens.superficie3,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            focusNode: no,
            canRequestFocus: aoTocar != null,
            onTap: aoTocar,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Text(texto,
                    style: TextStyle(
                        color: aoTocar == null ? Tokens.texto2.withValues(alpha: .4) : Tokens.texto,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      );

  Widget _celula(DateTime d, double altura) {
    final valido = _vale(d);
    final extremo = d == _de || d == _ate;
    final dentro = _de != null && _ate != null && d.isAfter(_de!) && d.isBefore(_ate!);
    final comFoco = _gradeComFoco && d == _foco;
    return Semantics(
      button: true,
      enabled: valido,
      selected: extremo,
      label: _dataLonga(d),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: valido
            ? () {
                _noGrade.requestFocus();
                _marcar(d);
              }
            : null,
        child: Container(
          height: altura,
          margin: const EdgeInsets.all(3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: extremo ? Tokens.acento : (dentro ? Tokens.superficie3 : null),
            borderRadius: BorderRadius.circular(10),
            border: comFoco ? Border.all(color: Tokens.anelFoco, width: 4) : null,
          ),
          child: Text('${d.day}',
              style: TextStyle(
                  color: valido ? Tokens.texto : Tokens.texto2.withValues(alpha: .45),
                  fontSize: 17,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _calendario(double altura) {
    final primeiroDia = DateTime(_foco.year, _foco.month, 1);
    final nDias = DateTime(_foco.year, _foco.month + 1, 0).day;
    final vazios = primeiroDia.weekday - 1; // a semana começa à segunda
    final linhas = ((vazios + nDias) / 7).ceil();
    return Container(
      padding: const EdgeInsets.all(Tokens.e16 + 4),
      decoration: BoxDecoration(color: Tokens.superficie2, borderRadius: BorderRadius.circular(Tokens.raioCartao)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _teclaMes,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _seta('‹', 'Mês anterior', _noAnterior, _haMesAntes ? () => _mudarMes(-1) : null),
          Text('${_mesesLongos[_foco.month - 1]} ${_foco.year}',
              style: const TextStyle(color: Tokens.texto, fontSize: 20, fontWeight: FontWeight.w700)),
          _seta('›', 'Mês seguinte', _noSeguinte, _haMesDepois ? () => _mudarMes(1) : null),
        ])),
        const SizedBox(height: Tokens.e8),
        Row(children: [
          for (final s in const ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(s,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Tokens.texto2, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
        for (var l = 0; l < linhas; l++)
          Row(children: [
            for (var c = 0; c < 7; c++)
              Expanded(
                child: () {
                  final n = l * 7 + c - vazios + 1;
                  if (n < 1 || n > nDias) return SizedBox(height: altura + 6);
                  return _celula(DateTime(_foco.year, _foco.month, n), altura);
                }(),
              ),
          ]),
      ]),
    );
  }

  Widget _valor(String rotulo, DateTime? d, {bool destaque = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: Tokens.e16),
        decoration: BoxDecoration(
          color: Tokens.superficie2,
          borderRadius: BorderRadius.circular(14),
          border: destaque ? Border.all(color: Tokens.acento, width: 2) : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(rotulo, style: const TextStyle(color: Tokens.texto, fontSize: 17, fontWeight: FontWeight.w600)),
          Text(d == null ? '—' : dataCurta(d),
              style: const TextStyle(color: Tokens.texto, fontSize: 17, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _lateral() {
    final pronto = _de != null && _ate != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        canRequestFocus: false,
        onTap: () => Navigator.of(context).maybePop(),
        child: const Text('‹ Importar · Listas do stbstalker',
            style: TextStyle(color: Tokens.texto2, fontSize: 15, fontWeight: FontWeight.w500)),
      ),
      const SizedBox(height: 4),
      const Text('Escolhe o início e o fim',
          style: TextStyle(color: Tokens.texto, fontSize: 26, fontWeight: FontWeight.w700)),
      const SizedBox(height: Tokens.e16),
      _valor('De', _de, destaque: _de == null || _ate != null),
      const SizedBox(height: Tokens.e12),
      _valor('Até', _ate, destaque: _de != null && _ate == null),
      const SizedBox(height: Tokens.e16),
      const Text('1.º OK marca o início, 2.º OK marca o fim. Os dias depois de hoje não se escolhem.',
          style: TextStyle(color: Tokens.texto2, fontSize: 15, fontWeight: FontWeight.w500)),
      const SizedBox(height: Tokens.e24),
      Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _teclaPainel,
        child: Wrap(spacing: Tokens.e12, runSpacing: Tokens.e12, children: [
          FilledButton(focusNode: _noProcurar, onPressed: pronto ? _procurar : null, child: const Text('Procurar e juntar')),
          OutlinedButton(focusNode: _noRecomecar, onPressed: _recomecar, child: const Text('Recomeçar')),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final altura = MediaQuery.sizeOf(context).height >= 640 ? 54.0 : 40.0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        backgroundColor: Tokens.fundo,
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final largo = c.maxWidth >= 760;
                final cal = Focus(
                  focusNode: _noGrade,
                  autofocus: true,
                  onKeyEvent: _tecla,
                  onFocusChange: (f) => setState(() => _gradeComFoco = f),
                  child: _calendario(altura),
                );
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: Tokens.e24),
                  child: largo
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: (c.maxWidth - 128) * .56 > 560 ? 560 : (c.maxWidth - 128) * .56, child: cal),
                          const SizedBox(width: Tokens.e32),
                          Expanded(child: _lateral()),
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _lateral(),
                          const SizedBox(height: Tokens.e16),
                          cal,
                        ]),
                );
              }),
            ),
            const BarraTeclas([('←↑↓→', 'dias'), ('OK', 'marcar'), ('Voltar', 'sair sem mudar')]),
          ]),
        ),
      ),
    );
  }
}
