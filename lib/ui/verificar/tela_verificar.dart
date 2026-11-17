import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../importar/importar.dart';
import '../../importar/stbstalker.dart';
import '../../modelo/conta.dart';
import '../../rede/http.dart';
import '../../verificar/canais_teste.dart';
import '../../verificar/exportar.dart';
import '../../verificar/servico.dart';
import '../realce_foco.dart';
import '../tema.dart';

/// Separador "Verificar": canais de teste, verificar listas, selecionar e exportar
/// (Accounts.json ou .ini), com as regras do verificador.
class TelaVerificar extends StatefulWidget {
  const TelaVerificar({super.key, required this.biblioteca, required this.servico, this.baseStb = stbBase});
  final Biblioteca biblioteca;
  final ServicoVerificacao servico;

  /// O blog a pesquisar (injetável para os testes).
  final String baseStb;

  @override
  State<TelaVerificar> createState() => _TelaVerificarState();
}

class _TelaVerificarState extends State<TelaVerificar> {
  final _selecao = <String>{};
  String _formato = 'json';
  late DateTime _inicio = _hoje(), _fim = _hoje();
  bool _pesquisando = false;

  /// "Parar" desaparece quando carregado: o foco passa para "Verificar todas".
  final _focoVerificarTodas = FocusNode();

  @override
  void dispose() {
    _focoVerificarTodas.dispose();
    super.dispose();
  }
  String? _resultadoStb;

  static DateTime _hoje() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _dd(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _escolherData(bool inicio) async {
    final hoje = _hoje();
    final atual = inicio ? _inicio : _fim;
    final d = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: inicio ? DateTime(2015) : _inicio,
      lastDate: inicio ? _fim : hoje,
      helpText: inicio ? 'Data de início' : 'Data de fim',
    );
    if (d == null || !mounted) return;
    setState(() {
      if (inicio) {
        _inicio = d;
      } else {
        _fim = d;
      }
    });
  }

  Future<void> _pesquisarStb() async {
    if (_pesquisando) return; // o botão fica ligado (não perde o foco do comando)
    setState(() {
      _pesquisando = true;
      _resultadoStb = null;
    });
    String msg;
    try {
      final r = await importarEntre(_inicio, _fim, base: widget.baseStb);
      if (r.erro != null) {
        msg = r.erro!;
      } else {
        final novas = await _b.adicionar([
          for (final l in r.linhas)
            if (contaDeLinha(l) case final c?) Importada(c),
        ]);
        final periodo = _inicio == _fim ? 'Em ${_dd(_inicio)}' : 'De ${_dd(_inicio)} a ${_dd(_fim)}';
        final np = r.posts.length;
        msg = '$periodo: ${r.total} ${r.total == 1 ? 'linha' : 'linhas'} em $np '
            '${np == 1 ? 'post' : 'posts'}, $novas ${novas == 1 ? 'lista nova' : 'listas novas'}.';
      }
    } catch (e) {
      msg = 'Não foi possível pesquisar: ${descreverErro(e)}';
    }
    if (!mounted) return;
    setState(() {
      _pesquisando = false;
      _resultadoStb = msg;
    });
  }

  Widget _secaoStb() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Listas do stbstalker', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Junta as listas publicadas no blog entre duas datas.',
          style: TextStyle(color: Cores.texto2, fontSize: 12)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _campoData('Data de início', _inicio, () => _escolherData(true)),
        _campoData('Data de fim', _fim, () => _escolherData(false)),
        FilledButton.icon(
          onPressed: _pesquisarStb,
          icon: _pesquisando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.search),
          label: const Text('Iniciar pesquisa'),
        ),
      ]),
      if (_resultadoStb != null) ...[
        const SizedBox(height: 8),
        Text(_resultadoStb!),
      ],
      const Divider(height: 32),
    ]);
  }

  Widget _campoData(String rotulo, DateTime d, VoidCallback aoTocar) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rotulo, style: const TextStyle(color: Cores.texto2, fontSize: 12)),
          OutlinedButton.icon(
            onPressed: _pesquisando ? null : aoTocar,
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(_dd(d)),
          ),
        ],
      );

  Biblioteca get _b => widget.biblioteca;

  void _selecionar(bool Function(Lista) criterio) =>
      setState(() => _selecao..clear()..addAll([for (final l in _b.listas) if (criterio(l)) l.id]));

  Future<void> _exportar() async {
    final listas = [for (final l in _b.listas) if (_selecao.contains(l.id)) l];
    if (listas.isEmpty) return _aviso('Selecione as listas a exportar.');
    if (_formato == 'json') {
      final uri = await FilePicker.saveFile(fileName: 'Accounts.json', bytes: exportarAccountsJson(listas),
          mimeType: 'application/json', dialogTitle: 'Guardar Accounts.json');
      if (uri != null) _aviso('${listas.length} listas exportadas para o Accounts.json.');
      return;
    }
    final (zip, ignoradas) = exportarZipIni(listas);
    if (zip == null) return _aviso('Nenhuma das listas selecionadas é Stalker (portal + MAC).');
    final uri = await FilePicker.saveFile(fileName: 'listas_stalker.zip', bytes: zip, mimeType: 'application/zip',
        dialogTitle: 'Guardar os ficheiros .ini');
    if (uri != null) {
      _aviso('Listas exportadas.${ignoradas > 0 ? ' $ignoradas sem MAC (Xtream/M3U) ficaram de fora.' : ''}');
    }
  }

  void _aviso(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_b, widget.servico]),
      builder: (context, _) {
        final s = widget.servico;
        final listas = _b.listas;
        _selecao.removeWhere((id) => _b.porId(id) == null);
        return ListView(padding: const EdgeInsets.all(16), children: [
          _secaoStb(),
          const Text('Canais a testar', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('A lista funciona se um deles abrir.', style: TextStyle(color: Cores.texto2, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final p in perfisCanais.values)
              FilterChip(
                label: Text(p.nome),
                selected: _b.canaisTeste.contains(p.id),
                onSelected: s.ocupado
                    ? null
                    : (on) {
                        final novo = [for (final id in perfisCanais.keys)
                          if (id == p.id ? on : _b.canaisTeste.contains(id)) id];
                        if (novo.isEmpty) return _aviso('Escolha pelo menos um canal.');
                        _b.definirCanaisTeste(novo);
                      },
              ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            // ligados enquanto verifica (desligar um botão com o foco deixa o comando sem foco)
            FilledButton.icon(
              focusNode: _focoVerificarTodas,
              onPressed: listas.isEmpty
                  ? null
                  : () {
                      if (!s.ocupado) s.verificarVarias(listas);
                    },
              icon: const Icon(Icons.playlist_add_check),
              label: Text('Verificar todas (${listas.length})'),
            ),
            OutlinedButton.icon(
              onPressed: _selecao.isEmpty
                  ? null
                  : () {
                      if (!s.ocupado) s.verificarVarias([for (final l in listas) if (_selecao.contains(l.id)) l]);
                    },
              icon: const Icon(Icons.checklist),
              label: Text('Verificar as selecionadas (${_selecao.length})'),
            ),
            if (s.ocupado)
              OutlinedButton.icon(
                  onPressed: () {
                    final tinhaFoco = FocusManager.instance.primaryFocus?.context?.widget is! EditableText;
                    s.parar();
                    if (tinhaFoco) _focoVerificarTodas.requestFocus();
                  },
                  icon: const Icon(Icons.stop),
                  label: const Text('Parar')),
            if (s.ocupado) Text('${s.feitas} de ${s.total} verificadas'),
          ]),
          if (s.ocupado) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: s.total == 0 ? null : s.feitas / s.total),
          ],
          const Divider(height: 32),
          const Text('Exportar', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(label: const Text('Funcionam + INC'),
                onPressed: () => _selecionar((l) => const {'funciona', 'inconclusivo'}.contains(l.ultima?.estado))),
            ActionChip(label: const Text('Só as que funcionam'), onPressed: () => _selecionar((l) => l.ultima?.estado == 'funciona')),
            ActionChip(label: const Text('Todas'), onPressed: () => _selecionar((_) => true)),
            ActionChip(label: const Text('Nenhuma'), onPressed: () => _selecionar((_) => false)),
          ]),
          const SizedBox(height: 8),
          // chips (e não um SegmentedButton): com o comando, cada opção mostra o seu realce de foco
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (v, t) in const [
              ('json', 'Accounts.json (sfvip player)'),
              ('ini', 'Ficheiros .ini (Stalker Portal Player)'),
            ])
              ChoiceChip(label: Text(t), selected: _formato == v, onSelected: (_) => setState(() => _formato = v)),
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _selecao.isEmpty ? null : _exportar,
              icon: const Icon(Icons.download),
              label: Text('Exportar ${_selecao.length} selecionadas'),
            ),
          ),
          const SizedBox(height: 12),
          for (final l in listas) _linha(l, s),
        ]);
      },
    );
  }

  Widget _linha(Lista l, ServicoVerificacao s) {
    final (cor, rotulo, icone) = visualEstado(l.ultima?.estado);
    final passo = s.passos[l.id];
    return RealceFoco(
      construir: (_, aoMudarFoco) => CheckboxListTile(
        onFocusChange: aoMudarFoco,
        value: _selecao.contains(l.id),
        onChanged: (v) => setState(() => v == true ? _selecao.add(l.id) : _selecao.remove(l.id)),
        secondary: Icon(icone, color: cor),
        title: Text(l.nomeMostrado),
        subtitle: Text(passo ?? (l.ultima == null ? rotulo : '$rotulo · ${l.ultima!.motivo}'),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
      ),
    );
  }
}
