import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../../dados/copia_seguranca.dart';
import '../../dados/guardar_ficheiro.dart';
import '../../dados/preferencias.dart';
import '../../rede/http.dart';
import '../../verificar/canais_teste.dart';
import '../../verificar/servico.dart';
import '../campo_tv.dart';
import '../design/design.dart';
import '../player/configuracao_mpv.dart';

/// Escolhe um ficheiro e devolve o seu texto (null = cancelado).
typedef EscolherCopia = Future<String?> Function();

/// O tamanho máximo de uma cópia que se aceita ler.
const _maxCopia = 64 * 1024 * 1024;

Future<String?> _escolherCopiaNativo() async {
  final ficheiros = await FilePicker.pickFiles(dialogTitle: 'Escolher a cópia de segurança');
  if (ficheiros.isEmpty) return null;
  final f = ficheiros.first;
  final bytes = await f.readAsBytes();
  if (bytes.length > _maxCopia) throw ErroCopia('O ficheiro é demasiado grande para ser uma cópia de segurança.');
  return utf8.decode(bytes, allowMalformed: true);
}

/// Definições: canais de teste, verificação, preferências do player, user-agent e cópia de
/// segurança. Tudo se grava logo ao mudar.
class TelaDefinicoes extends StatefulWidget {
  const TelaDefinicoes({
    super.key,
    required this.biblioteca,
    required this.area,
    required this.preferencias,
    this.servico,
    this.escolherCopia,
    this.guardarCopia,
    this.android,
  });

  final Biblioteca biblioteca;
  final AreaGestor area;
  final Preferencias preferencias;

  /// Enquanto verifica, os canais de teste não mudam.
  final ServicoVerificacao? servico;

  /// Para testes: em vez do seletor de ficheiros / do "Guardar como".
  final EscolherCopia? escolherCopia;
  final Future<ResultadoGuardar> Function(String nome, List<int> bytes)? guardarCopia;

  /// Para testes: mostra as opções do Android.
  final bool? android;

  @override
  State<TelaDefinicoes> createState() => _TelaDefinicoesState();
}

class _TelaDefinicoesState extends State<TelaDefinicoes> {
  late final _ua = TextEditingController(text: widget.preferencias.userAgent);
  bool _ocupado = false;

  Preferencias get _p => widget.preferencias;
  bool get _android => widget.android ?? Platform.isAndroid;

  @override
  void dispose() {
    _ua.dispose();
    super.dispose();
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  void _mudou(VoidCallback f) {
    f();
    _p.guardar().catchError((Object _) {}); // as chaves ficam por gravar e voltam a tentar-se
  }

  Future<void> _exportar() async {
    setState(() => _ocupado = true);
    try {
      final bytes = codificarCopia(widget.biblioteca, widget.area, _p);
      final nome = nomeFicheiroCopia();
      final r = widget.guardarCopia != null
          ? await widget.guardarCopia!(nome, bytes)
          : await guardarFicheiro(nome, bytes, 'application/json');
      _aviso(r.cancelado ? 'Exportação cancelada.' : 'Cópia guardada em ${r.destino}');
    } catch (e) {
      _aviso(e is ErroGuardar ? e.mensagem : 'Não foi possível exportar: ${descreverErro(e)}');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _importar() async {
    setState(() => _ocupado = true);
    try {
      final texto = await (widget.escolherCopia ?? _escolherCopiaNativo)();
      if (texto == null) return;
      final copia = lerCopia(texto);
      if (!mounted) return;
      final modo = await _perguntarModo(copia);
      if (modo == null) return;
      final r = await restaurarCopia(copia, modo,
          biblioteca: widget.biblioteca, area: widget.area, preferencias: _p);
      _aviso('Cópia importada: ${r.listasPlayer} no Player, ${r.listasGestor} no Gestor'
          '${r.atualizadas > 0 ? ', ${r.atualizadas} atualizadas' : ''}'
          '${r.removidas > 0 ? ', ${r.removidas} removidas' : ''}.');
      _ua.text = _p.userAgent;
    } on ErroCopia catch (e) {
      _aviso(e.alterou ? e.mensagem : '${e.mensagem} Nada foi alterado.');
    } catch (e) {
      _aviso('Não foi possível importar (${descreverErro(e)}). Nada foi alterado.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<ModoRestauro?> _perguntarModo(CopiaLida c) => showDialog<ModoRestauro>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.settings_backup_restore_rounded, color: Tokens.acento2, size: 32),
          title: const Text('Importar cópia de segurança'),
          content: Text('A cópia tem ${c.player.length} listas do Player e ${c.gestor.length} do Gestor'
              '${c.preferencias != null ? ', mais as definições' : ''}.\n\n'
              'Juntar: acrescenta o que falta, sem duplicar, e une favoritos e resultados.\n'
              'Substituir: apaga as listas atuais e fica só com as da cópia.'),
          actions: [
            TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            OutlinedButton(
                onPressed: () => Navigator.pop(ctx, ModoRestauro.substituir), child: const Text('Substituir tudo')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ModoRestauro.juntar), child: const Text('Juntar')),
          ],
        ),
      );

  Widget _seccao(String titulo, String sub, IconData icone, List<Widget> filhos) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.e16),
        child: SuperficieVidro(
          padding: const EdgeInsets.all(Tokens.e16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CabecalhoSeccao(titulo: titulo, subtitulo: sub, icone: icone),
            ...filhos,
          ]),
        ),
      );

  Widget _interruptor(String titulo, String sub, bool valor, ValueChanged<bool> aoMudar) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(titulo),
        subtitle: Text(sub, style: const TextStyle(color: Tokens.texto2)),
        value: valor,
        onChanged: (v) => _mudou(() => aoMudar(v)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Definições')),
        body: ListenableBuilder(
          listenable: Listenable.merge([_p, widget.biblioteca, if (widget.servico != null) widget.servico!]),
          builder: (context, _) {
            final b = widget.biblioteca;
            final ocupado = widget.servico?.ocupado ?? false;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(padding: const EdgeInsets.all(Tokens.e16), children: [
                  _seccao('Canais de teste', 'A lista funciona se um deles abrir.', Icons.live_tv_outlined, [
                    Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                      for (final p in perfisCanais.values)
                        FilterChip(
                          autofocus: p.id == perfisCanais.keys.first,
                          label: Text(p.nome),
                          selected: b.canaisTeste.contains(p.id),
                          onSelected: ocupado
                              ? null
                              : (on) {
                                  final novo = [
                                    for (final id in perfisCanais.keys)
                                      if (id == p.id ? on : b.canaisTeste.contains(id)) id
                                  ];
                                  if (novo.isEmpty) return _aviso('Escolha pelo menos um canal.');
                                  b.definirCanaisTeste(novo);
                                },
                        ),
                    ]),
                    if (ocupado)
                      const Padding(
                        padding: EdgeInsets.only(top: Tokens.e8),
                        child: Text('Não se mudam durante uma verificação.', style: TextStyle(color: Tokens.texto2)),
                      ),
                  ]),
                  _seccao('Verificação', 'Quanto tempo se espera por cada canal.', Icons.timer_outlined, [
                    Text('Tempo limite: ${_p.timeoutVerificacao} s'),
                    DeslizadorTv(
                      min: Preferencias.minTimeoutVerificacao.toDouble(),
                      max: Preferencias.maxTimeoutVerificacao.toDouble(),
                      divisions: Preferencias.maxTimeoutVerificacao - Preferencias.minTimeoutVerificacao,
                      value: _p.timeoutVerificacao.toDouble(),
                      label: '${_p.timeoutVerificacao} s',
                      onChanged: (v) => _mudou(() => _p.timeoutVerificacao = v.round()),
                    ),
                    const Text('Entre 5 e 30 segundos. As inconclusivas voltam a ser testadas com o dobro.',
                        style: TextStyle(color: Tokens.texto2, fontSize: 12.5)),
                  ]),
                  _seccao('Preferências do player', 'Valem para todos os canais.', Icons.tune_rounded, [
                    _interruptor('Desentrelaçamento', 'Limpa as linhas das imagens entrelaçadas.', _p.desentrelacar,
                        (v) => _p.desentrelacar = v),
                    _interruptor('Descodificação por hardware', 'Desligue se a imagem falhar.', _p.hardware,
                        (v) => _p.hardware = v),
                    if (_android) ...[
                      _interruptor('Ajustar a taxa do ecrã ao canal', 'Evita soluços nas imagens.',
                          _p.ajustarTaxaEcra, (v) => _p.ajustarTaxaEcra = v),
                      const SizedBox(height: Tokens.e8),
                      const Text('Descodificação no Android'),
                      const SizedBox(height: Tokens.e8),
                      Wrap(spacing: Tokens.e8, children: [
                        for (final m in ModoDescodificacao.values)
                          ChoiceChip(
                            label: Text(m.rotulo),
                            selected: _p.modoAndroid == m,
                            onSelected: (_) => _mudou(() => _p.modoAndroid = m),
                          ),
                      ]),
                    ],
                    const SizedBox(height: Tokens.e12),
                    const Text('Formato da imagem'),
                    const SizedBox(height: Tokens.e8),
                    Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                      for (final f in FormatoImagem.values)
                        ChoiceChip(
                          label: Text(f.rotulo),
                          selected: _p.formato == f,
                          onSelected: (_) => _mudou(() => _p.formato = f),
                        ),
                    ]),
                    const SizedBox(height: Tokens.e12),
                    Text('Volume: ${_p.volume.round()} %'),
                    DeslizadorTv(
                      min: 0,
                      max: 100,
                      divisions: 20,
                      value: _p.volume,
                      label: '${_p.volume.round()} %',
                      onChanged: (v) => _mudou(() => _p.volume = v),
                    ),
                  ]),
                  _seccao('User-agent', 'Opcional: nos pedidos das listas M3U e Xtream (o Stalker mantém o da box MAG).',
                      Icons.badge_outlined, [
                    CampoTv(
                      controller: _ua,
                      decoration: const InputDecoration(labelText: 'User-agent personalizado', hintText: 'Em branco: o do VLC'),
                      onChanged: (v) => _mudou(() => _p.userAgent = v),
                    ),
                    const SizedBox(height: Tokens.e8),
                    OutlinedButton.icon(
                      onPressed: () {
                        _ua.clear();
                        _mudou(() => _p.userAgent = '');
                      },
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Repor o por omissão'),
                    ),
                  ]),
                  _seccao('Cópia de segurança',
                      'Guarda as listas, favoritos, resultados, o Gestor e as definições num ficheiro .json.',
                      Icons.cloud_download_outlined, [
                    const Text('O ficheiro inclui as credenciais das listas: guarde-o em local seguro.',
                        style: TextStyle(color: Tokens.texto2, fontSize: 12.5)),
                    const SizedBox(height: Tokens.e12),
                    Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                      FilledButton.icon(
                        onPressed: () {
                          if (!_ocupado) _exportar();
                        },
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text('Exportar cópia'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          if (!_ocupado) _importar();
                        },
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Importar cópia'),
                      ),
                    ]),
                  ]),
                ]),
              ),
            );
          },
        ),
      );
}
