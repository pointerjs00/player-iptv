import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../verificar/canais_teste.dart';
import '../../verificar/exportar.dart';
import '../../verificar/servico.dart';
import '../tema.dart';

/// Separador "Verificar": canais de teste, verificar listas, selecionar e exportar
/// (Accounts.json ou .ini), com as regras do verificador.
class TelaVerificar extends StatefulWidget {
  const TelaVerificar({super.key, required this.biblioteca, required this.servico});
  final Biblioteca biblioteca;
  final ServicoVerificacao servico;

  @override
  State<TelaVerificar> createState() => _TelaVerificarState();
}

class _TelaVerificarState extends State<TelaVerificar> {
  final _selecao = <String>{};
  String _formato = 'json';

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
            FilledButton.icon(
              onPressed: listas.isEmpty || s.ocupado ? null : () => s.verificarVarias(listas),
              icon: const Icon(Icons.playlist_add_check),
              label: Text('Verificar todas (${listas.length})'),
            ),
            OutlinedButton.icon(
              onPressed: _selecao.isEmpty || s.ocupado
                  ? null
                  : () => s.verificarVarias([for (final l in listas) if (_selecao.contains(l.id)) l]),
              icon: const Icon(Icons.checklist),
              label: Text('Verificar as selecionadas (${_selecao.length})'),
            ),
            if (s.ocupado)
              OutlinedButton.icon(onPressed: s.parar, icon: const Icon(Icons.stop), label: const Text('Parar')),
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
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'json', label: Text('Accounts.json (sfvip player)')),
              ButtonSegment(value: 'ini', label: Text('Ficheiros .ini (Stalker Portal Player)')),
            ],
            selected: {_formato},
            onSelectionChanged: (v) => setState(() => _formato = v.first),
          ),
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
    return CheckboxListTile(
      value: _selecao.contains(l.id),
      onChanged: (v) => setState(() => v == true ? _selecao.add(l.id) : _selecao.remove(l.id)),
      secondary: Icon(icone, color: cor),
      title: Text(l.nomeMostrado),
      subtitle: Text(passo ?? (l.ultima == null ? rotulo : '$rotulo · ${l.ultima!.motivo}'),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
    );
  }
}
