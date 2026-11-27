import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../../dados/copia_seguranca.dart';
import '../../dados/estatisticas.dart';
import '../../dados/guardar_ficheiro.dart';
import '../../dados/novidades.dart';
import '../../dados/preferencias.dart';
import '../../edicao.dart';
import '../../desporto/preferencias_jogos.dart';
import '../../marca.dart';
import '../../rede/http.dart';
import '../../verificar/canais_teste.dart';
import '../../verificar/servico.dart';
import '../campo_tv.dart';
import '../design/design.dart';
import '../design/escala_interface.dart';
import '../design/mensagens.dart';
import '../player/configuracao_mpv.dart';
import '../atualizar/fluxo_atualizar.dart';
import '../novidades.dart';
import '../principal/tela_principal.dart';
import 'linha_opcao.dart';
import 'secao_jogos.dart';
import '../verificar/dialogos_gestor.dart' show confirmar;
import 'seletor_numero.dart';
import '../realce_foco.dart';
import '../../idioma/idioma.dart';

/// Escolhe um ficheiro e devolve o seu texto (null = cancelado).
typedef EscolherCopia = Future<String?> Function();

/// O tamanho máximo de uma cópia que se aceita ler.
const _maxCopia = 64 * 1024 * 1024;

Future<String?> _escolherCopiaNativo() async {
  final ficheiros = await FilePicker.pickFiles(dialogTitle: tr('Escolher a cópia de segurança'));
  if (ficheiros.isEmpty) return null;
  final f = ficheiros.first;
  final bytes = await f.readAsBytes();
  if (bytes.length > _maxCopia) throw ErroCopia(tr('O ficheiro é demasiado grande para ser uma cópia de segurança.'));
  return utf8.decode(bytes, allowMalformed: true);
}

/// As categorias das Definições: cada opção está numa delas.
enum _Categoria {
  imagemSom('Imagem e som', Icons.tune_rounded),
  verificacao('Verificação', Icons.timer_outlined),
  ligacao('Ligação', Icons.wifi_rounded),
  jogos('Jogos', Icons.sports_soccer_rounded),
  copia('Cópia de segurança', Icons.cloud_download_outlined),
  // em português diz também "Language", para quem procura o inglês
  idioma('Idioma · Language', Icons.translate_rounded),
  sobre('Sobre e licenças', Icons.info_outline_rounded);

  const _Categoria(this._titulo, this.icone);
  final String _titulo;
  String get titulo => tr(_titulo);
  final IconData icone;
}

/// O que se diz ao mudar uma opção: as do player só valem a partir do próximo canal.
String get _guardado => tr('Guardado');
/// A verificação lê as definições ao começar cada lista: o que muda vale para as que ainda não começaram.
String get _guardadoListas => tr('Guardado · vale para as próximas listas');
String get _guardadoPlayer => tr('Guardado · vale a partir do próximo canal');

/// A nota das opções que só o mpv tem, com o ExoPlayer escolhido.
String get _soNoMpv => tr('só no motor mpv');

/// Definições por categorias (a lista à esquerda, as opções da categoria à direita; no telemóvel,
/// uma lista que abre cada categoria). Cada opção explica-se e grava logo ao mudar.
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
    this.jogos,
    this.atualizador,
  });

  /// Para testes: o que «Procurar atualizações» usa (null: o da app).
  final Atualizador? atualizador;

  /// As preferências dos «Jogos» (null: sem a secção, como na edição de partilha).
  final PreferenciasJogos? jogos;

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
  /// A partir desta largura a lista de categorias fica ao lado das opções.
  static const _larguraDuasColunas = 640.0;

  late final _ua = TextEditingController(text: widget.preferencias.userAgent);
  bool _ocupado = false;
  _Categoria _cat = _Categoria.imagemSom;

  /// Estreito: a categoria está aberta (senão vê-se a lista de categorias).
  bool _aberta = false;
  bool _estreito = false;

  final _focosCat = [for (final c in _Categoria.values) FocusNode(debugLabel: 'Categoria ${c.name}')];

  /// A área das opções (não recebe foco: serve para saber onde ele está).
  final _focoPainel = FocusNode(debugLabel: 'Opções', canRequestFocus: false, skipTraversal: true);

  /// A opção onde se estava ao ir para a categoria (DIREITA volta a ela).
  FocusNode? _ultimaOpcao;
  VoidCallback? _tirarVoltar;

  Preferencias get _p => widget.preferencias;

  /// As categorias à vista («Jogos» só com as preferências dele).
  List<_Categoria> get _categorias => [for (final c in _Categoria.values) if (c != _Categoria.jogos || (!edicaoPartilha && widget.jogos != null)) c];
  bool get _android => widget.android ?? Platform.isAndroid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tirarVoltar ??= TelaPrincipal.aoVoltar(context, _voltar);
  }

  @override
  void dispose() {
    _tirarVoltar?.call();
    _ua.dispose();
    for (final f in [..._focosCat, _focoPainel]) {
      f.dispose();
    }
    super.dispose();
  }

  /// Voltar, com uma categoria aberta no telemóvel, volta à lista de categorias.
  bool _voltar() {
    if (!_aberta || !_estreito) return false;
    _fechar();
    return true;
  }

  void _fechar() {
    setState(() => _aberta = false);
    final f = _focosCat[_cat.index];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) f.requestFocus();
    });
  }

  void _escolher(_Categoria c, {bool abrir = false}) {
    if (c == _cat && (!abrir || _aberta)) return;
    setState(() {
      if (c != _cat) _ultimaOpcao = null;
      _cat = c;
      if (abrir) _aberta = true;
    });
  }

  void _aviso(String texto) {
    if (!mounted) return;
    mostrarMensagem(context, texto);
  }

  /// Muda uma opção, grava e confirma ("Guardado"). Não mexe no foco.
  void _mudou(VoidCallback f, {bool player = false, String? mensagem}) {
    f();
    _p.guardar().catchError((Object _) {}); // as chaves ficam por gravar e voltam a tentar-se
    if (mounted) mostrarMensagem(context, mensagem ?? (player ? _guardadoPlayer : _guardado), tipo: MensagemTipo.sucesso);
  }

  Future<void> _exportar() async {
    setState(() => _ocupado = true);
    try {
      // as preferências dos Jogos também (não existem na edição de partilha)
      final bytes = codificarCopia(widget.biblioteca, widget.area, _p, jogos: edicaoPartilha ? null : widget.jogos);
      final nome = nomeFicheiroCopia();
      final r = widget.guardarCopia != null
          ? await widget.guardarCopia!(nome, bytes)
          : await guardarFicheiro(nome, bytes, 'application/json', tv: EcraTv.nativo);
      _aviso(r.cancelado ? tr('Exportação cancelada.') : tr('Cópia guardada em {0}', [r.destino]));
    } catch (e) {
      _aviso(e is ErroGuardar ? e.mensagem : tr('Não foi possível exportar: {0}', [descreverErro(e)]));
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
          biblioteca: widget.biblioteca,
          area: widget.area,
          preferencias: _p,
          jogos: edicaoPartilha ? null : widget.jogos);
      _aviso(tr('Cópia importada: {0} em Ver TV, {1} no Gestor{2}{3}.', [r.listasPlayer, r.listasGestor, r.atualizadas > 0 ? ', ${r.atualizadas} atualizadas' : '', r.removidas > 0 ? ', ${r.removidas} removidas' : '']));
      _ua.text = _p.userAgent;
    } on ErroCopia catch (e) {
      _aviso(e.alterou ? e.mensagem : tr('{0} Nada foi alterado.', [e.mensagem]));
    } catch (e) {
      _aviso(tr('Não foi possível importar ({0}). Nada foi alterado.', [descreverErro(e)]));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<ModoRestauro?> _perguntarModo(CopiaLida c) => showDialog<ModoRestauro>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.settings_backup_restore_rounded, color: Tokens.acento2, size: 32),
          title: Text(tr('Importar cópia de segurança')),
          content: Text(tr('A cópia tem {0} listas de Ver TV e {1} do Gestor{2}.\n\nJuntar: acrescenta o que falta, sem duplicar, e une favoritos e resultados.\nSubstituir: apaga as listas atuais e fica só com as da cópia.', [c.player.length, c.gestor.length, c.preferencias != null ? tr(', mais as definições') : ''])),
          actions: [
            TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
            OutlinedButton(
                onPressed: () => Navigator.pop(ctx, ModoRestauro.substituir), child: Text(tr('Substituir tudo'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, ModoRestauro.juntar), child: Text(tr('Juntar'))),
          ],
        ),
      );

  // ---- teclado / comando ----

  bool _haMais(FocusNode atual, bool Function(Rect o, Rect r) conta) => _focoPainel.traversalDescendants.any((n) {
        if (n == atual || !n.canRequestFocus || n.skipTraversal || n.context == null) return false;
        return conta(n.rect, atual.rect);
      });

  /// ESQUERDA numa opção sem mais nada à esquerda: vai à categoria.
  KeyEventResult _teclaPainel(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent || _estreito || e.logicalKey != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
    final atual = FocusManager.instance.primaryFocus;
    if (atual == null || !atual.ancestors.contains(_focoPainel)) return KeyEventResult.ignored;
    if (_haMais(atual, (o, r) => o.center.dx <= r.left && o.top < r.bottom && o.bottom > r.top)) {
      return KeyEventResult.ignored;
    }
    _ultimaOpcao = atual;
    _focosCat[_cat.index].requestFocus();
    return KeyEventResult.handled;
  }

  /// DIREITA numa categoria: volta à opção onde se estava (ou à primeira).
  KeyEventResult _teclaCategorias(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent || _estreito || e.logicalKey != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
    final antes = _ultimaOpcao;
    FocusNode? alvo = antes != null &&
            antes.context?.mounted == true &&
            antes.canRequestFocus &&
            antes.ancestors.contains(_focoPainel)
        ? antes
        : null;
    if (alvo == null) {
      for (final n in _focoPainel.traversalDescendants) {
        if (!n.canRequestFocus || n.skipTraversal || n.context == null) continue;
        final m = alvo?.rect;
        if (m == null || n.rect.top < m.top - 4 || ((n.rect.top - m.top).abs() <= 4 && n.rect.left < m.left)) alvo = n;
      }
    }
    if (alvo == null) return KeyEventResult.ignored;
    alvo.requestFocus();
    return KeyEventResult.handled;
  }

  // ---- peças ----

  /// Uma opção: uma linha simples (ver [LinhaOpcao]). Com `nota` está desativada (a nota diz
  /// porquê) e é a linha que recebe o foco (ver [_desativada]).
  Widget _opcao(String titulo, String explicacao, {Widget? controlo, bool empilhar = false, String? nota}) =>
      _desativada(
          nota != null,
          LinhaOpcao(titulo: titulo, explicacao: explicacao, controlo: controlo, empilhar: empilhar, nota: nota));

  /// Uma opção desativada continua a receber o foco (no comando, CIMA/BAIXO passam por ela e lê-se
  /// a nota; sem isso, várias seguidas deixavam um buraco que a procura direcional não salta).
  Widget _desativada(bool sim, Widget linha) => !sim
      ? linha
      : RealceFoco(
          raio: Tokens.raioBotao,
          construir: (context, aoMudarFoco) => Focus(onFocusChange: aoMudarFoco, child: linha),
        );

  Future<void> _apagarEstatisticas() async {
    final ok = await confirmar(context,
        icone: Icons.delete_outline_rounded,
        titulo: tr('Apagar as estatísticas?'),
        texto: tr('O tempo de visualização guardado neste aparelho é apagado. Não se pode desfazer.'),
        acao: tr('Apagar'));
    if (!ok || !mounted) return;
    await Estatisticas.atual.apagar();
    if (mounted) mostrarMensagem(context, tr('Estatísticas apagadas'));
  }

  /// Uma opção ligada/desligada: a linha toda é o interruptor. Com `nota` fica desativada (a nota
  /// diz porquê), mas continua a receber o foco (ver [_desativada]).
  Widget _interruptor(String titulo, String explicacao, bool valor, ValueChanged<bool> aoMudar, {String? nota}) =>
      RealceFoco(
        raio: Tokens.raioBotao,
        construir: (context, aoMudarFoco) => Focus(
          // desativado, o SwitchListTile não recebe o foco: recebe-o a linha
          canRequestFocus: nota != null,
          skipTraversal: nota == null,
          onFocusChange: nota != null ? aoMudarFoco : null,
          child: SwitchListTile(
            contentPadding: paddingLinhaOpcao,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.raioBotao)),
            title: Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(explicacao, style: const TextStyle(fontSize: 13.5, color: Tokens.texto2)),
              if (nota != null) NotaOpcao(nota),
            ]),
            value: valor,
            onFocusChange: aoMudarFoco,
            onChanged: nota != null ? null : (v) => _mudou(() => aoMudar(v), player: true),
          ),
        ),
      );

  /// `ativo` falso: as opções veem-se mas não mudam.
  Widget _escolhas<T>(List<T> valores, String Function(T) rotulo, T atual, ValueChanged<T> aoEscolher,
          {bool ativo = true}) =>
      Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
        for (final v in valores)
          ChoiceChip(
              label: Text(rotulo(v)), selected: atual == v, onSelected: ativo ? (_) => aoEscolher(v) : null),
      ]);

  Widget _deslizador(
          {required double min,
          required double max,
          required int divisions,
          required double value,
          required String texto,
          required ValueChanged<double> aoMudar}) =>
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Row(children: [
          Expanded(
              child: DeslizadorTv(
                  min: min, max: max, divisions: divisions, value: value, label: texto, onChanged: aoMudar)),
          const SizedBox(width: Tokens.e8),
          Text(texto, style: const TextStyle(color: Tokens.texto2)),
        ]),
      );

  /// As opções de cada categoria.
  List<Widget> _opcoes(_Categoria c, bool ocupado) {
    final b = widget.biblioteca;
    switch (c) {
      case _Categoria.imagemSom:
        // no Android com o ExoPlayer, o que só o mpv tem fica à vista mas desativado
        final soMpv = _android && _p.motorAndroid == MotorAndroid.exoplayer ? _soNoMpv : null;
        return [
          // no telemóvel a escala é sempre 100 %: a opção não faria nada
          if (escalaPara(context, TamanhoInterface.compacto) != 1)
            _opcao(tr('Tamanho da interface'), tr('Compacto mostra mais em cada ecrã (80 % na TV e no Windows).'),
                controlo: _escolhas(TamanhoInterface.values, (t) => t.rotulo, _p.tamanhoInterface,
                    (t) => _mudou(() => _p.tamanhoInterface = t))),
          if (_android) ...[
            _opcao(tr('Motor do player'),
                tr('O ExoPlayer é o mais fluido. Se um canal não abrir nele, abre sozinho no mpv.'),
                controlo: _escolhas(MotorAndroid.values, (m) => m.rotulo, _p.motorAndroid,
                    (m) => _mudou(() => _p.motorAndroid = m, player: true))),
            _interruptor(tr('Modo túnel'),
                tr('Só em aparelhos que o suportam. Pode ajudar a fluidez; se a imagem falhar, desliga.'),
                _p.modoTunel, (v) => _p.modoTunel = v),
          ],
          _opcao(
              tr('Desentrelaçamento'),
              tr('Evita riscas nos canais entrelaçados. Automático só o liga quando é preciso.{0}', [_android ? tr(' Na descodificação Direta, um direto entrelaçado reabre em Compatível.') : '']),
              nota: soMpv,
              controlo: _escolhas(ModoDesentrelacamento.values, (m) => m.rotulo, _p.modoDesentrelacamento,
                  (m) => _mudou(() => _p.modoDesentrelacamento = m, player: true),
                  ativo: soMpv == null)),
          _interruptor(tr('Descodificação por hardware'), tr('Mais leve. Desliga se a imagem falhar.'), _p.hardware,
              (v) => _p.hardware = v, nota: soMpv),
          if (_android) ...[
            // só na TV: no telemóvel não há taxa do ecrã a ajustar
            if (ecraTv(context))
              _interruptor(tr('Ajustar a taxa do ecrã ao canal'), tr('Evita soluços nas imagens (Android TV)'),
                  _p.ajustarTaxaEcra, (v) => _p.ajustarTaxaEcra = v),
            _opcao(tr('Descodificação no Android'),
                tr('Direta é a mais leve. Compatível serve se o direto mostrar ecrã preto ou cores erradas.'),
                nota: soMpv,
                controlo: _escolhas(ModoDescodificacao.values, (m) => m.rotulo, _p.modoAndroid,
                    (m) => _mudou(() => _p.modoAndroid = m, player: true),
                    ativo: soMpv == null)),
          ],
          _opcao(tr('Formato da imagem'), tr('Vale para todos os canais'),
              empilhar: true,
              controlo: _escolhas(FormatoImagem.values, (f) => f.rotulo, _p.formato,
                  (f) => _mudou(() => _p.formato = f, player: true))),
          // no telemóvel Android o volume é sempre o do sistema (a barra do canal e os deslizes
          // mudam-no): o do player não se escolhe
          if (!_android || EcraTv.nativo)
            _opcao(tr('Volume ao abrir'), tr('O volume com que cada canal começa.'),
                controlo: _deslizador(
                    min: 0,
                    max: 100,
                    divisions: 20,
                    value: _p.volume,
                    texto: '${_p.volume.round()} %',
                    aoMudar: (v) => _mudou(() => _p.volume = v, player: true))),
          // a explicação é a da escolha atual
          _opcao(tr('Recuar no direto'), _p.recuoDireto.descricao,
              controlo: _escolhas(RecuoDireto.values, (r) => r.rotulo, _p.recuoDireto,
                  (r) => _mudou(() => _p.recuoDireto = r, player: true))),
          // só o Armazenamento grava
          if (_p.recuoDireto == RecuoDireto.armazenamento)
            _opcao(tr('Espaço reservado'), tr('Quanto do armazenamento interno se usa, no máximo.'),
                controlo: _escolhas(
                    [for (var g = Preferencias.minReservaDiretoGb; g <= Preferencias.maxReservaDiretoGb; g++) g],
                    (g) => '$g GB',
                    _p.reservaDiretoGb,
                    (g) => _mudou(() => _p.reservaDiretoGb = g, player: true))),
          // as estatísticas do Início («A tua semana»): só neste aparelho
          _interruptor(
              tr('Contar o tempo de visualização'),
              tr('Para as estatísticas do Início (horas vistas, canais mais vistos). Ficam só neste aparelho.'),
              _p.contarTempo,
              (v) => _p.contarTempo = v),
          _opcao(tr('Apagar as estatísticas'), tr('Esquece todo o tempo de visualização guardado.'),
              controlo: OutlinedButton.icon(
                  key: const Key('apagar-estatisticas'),
                  onPressed: _apagarEstatisticas,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(tr('Apagar')),
                )),
        ];
      case _Categoria.verificacao:
        return [
          SeletorNumero(
              titulo: tr('Listas ao mesmo tempo'),
              descricao: tr('Quantas listas se verificam em simultâneo (1 a 20). Mais é mais rápido, mas pesa na rede.'),
              valor: _p.listasEmSimultaneo,
              min: Preferencias.minListasEmSimultaneo,
              max: Preferencias.maxListasEmSimultaneo,
              aoMudar: (v) => _mudou(() => _p.listasEmSimultaneo = v, mensagem: _guardadoListas)),
          SeletorNumero(
              titulo: tr('Tempo limite por lista'),
              descricao: tr('Se uma lista não acabar neste tempo, fica inconclusiva e passa à seguinte.'),
              valor: _p.tempoLimiteLista,
              min: Preferencias.minTempoLimiteLista,
              max: Preferencias.maxTempoLimiteLista,
              passo: 10,
              formatar: (v) => '$v s',
              aoMudar: (v) => _mudou(() => _p.tempoLimiteLista = v, mensagem: _guardadoListas)),
          SeletorNumero(
              titulo: tr('Tempo por canal'),
              descricao: tr('Quanto se espera por cada canal de teste.'),
              valor: _p.timeoutVerificacao,
              min: Preferencias.minTimeoutVerificacao,
              max: Preferencias.maxTimeoutVerificacao,
              formatar: (v) => '$v s',
              aoMudar: (v) => _mudou(() => _p.timeoutVerificacao = v, mensagem: _guardadoListas)),
          _opcao(tr('Canais de teste'), tr('A lista funciona se um deles abrir.'),
              empilhar: true,
              controlo: Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                for (final p in perfisCanais.values)
                  FilterChip(
                    label: Text(p.nome),
                    selected: b.canaisTeste.contains(p.id),
                    onSelected: (on) {
                      final novo = [
                        for (final id in perfisCanais.keys)
                          if (id == p.id ? on : b.canaisTeste.contains(id)) id
                      ];
                      if (novo.isEmpty) return _aviso(tr('Escolha pelo menos um canal.'));
                      _mudou(() => b.definirCanaisTeste(novo));
                    },
                  ),
              ])),
          Padding(
            padding: const EdgeInsets.fromLTRB(Tokens.e8, Tokens.e12, Tokens.e8, 0),
            child: Text(
                tr('Com uma verificação a decorrer, as mudanças valem para as próximas listas.{0}', [mostrarDicasComando(context) ? tr(' OK para mudar um valor, depois ← →; ↑ ↓ mudam de opção.') : '']),
                style: const TextStyle(fontSize: 13, color: Tokens.texto2)),
          ),
        ];
      case _Categoria.ligacao:
        return [
          // só no telemóvel Android (a TV e o computador estão quase sempre numa rede fixa)
          if (_android && !EcraTv.nativo)
            _interruptor(
                tr('Poupar dados móveis'),
                tr('Com dados móveis ou numa rede limitada, pergunta antes de descarregar a programação de todos os canais, carregar os canais de uma lista ou verificar listas.'),
                _p.pouparDados,
                (v) => _p.pouparDados = v),
          _opcao(tr('User-agent'), tr('Opcional: nos pedidos das listas M3U e Xtream (o Stalker mantém o da box MAG).'),
              empilhar: true,
              controlo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CampoTv(
                  controller: _ua,
                  decoration:
                      InputDecoration(labelText: tr('User-agent personalizado'), hintText: tr('Em branco: o do VLC')),
                  onChanged: (v) => _mudou(() => _p.userAgent = v),
                ),
                const SizedBox(height: Tokens.e8),
                OutlinedButton.icon(
                  onPressed: () {
                    _ua.clear();
                    _mudou(() => _p.userAgent = '');
                  },
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(tr('Repor o por omissão')),
                ),
              ])),
        ];
      case _Categoria.jogos:
        final j = widget.jogos;
        return [if (!edicaoPartilha && j != null) SecaoJogos(preferencias: j)];
      case _Categoria.copia:
        return [
          _opcao(tr('Exportar e importar'),
              tr('Guarda as listas, favoritos, resultados, o Gestor e as definições num ficheiro .json. O ficheiro inclui as credenciais das listas: guarde-o em local seguro.'),
              empilhar: true,
              controlo: Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                FilledButton.icon(
                  onPressed: () {
                    if (!_ocupado) _exportar();
                  },
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(tr('Exportar cópia')),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    if (!_ocupado) _importar();
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: Text(tr('Importar cópia')),
                ),
              ])),
        ];
      case _Categoria.idioma:
        return [
          _opcao(tr('Idioma da aplicação'), tr('Os textos de todos os ecrãs mudam logo.'),
              controlo: _escolhas(Idioma.values, (i) => i.rotulo, _p.idioma, (i) => _mudou(() => _p.idioma = i))),
        ];
      case _Categoria.sobre:
        return [
          _opcao(tr('Novidades'), tr('O que mudou em cada versão. Esta é a {0}.', [versaoApp]),
              controlo: OutlinedButton.icon(
                onPressed: () => abrirNovidades(context),
                icon: const Icon(Icons.new_releases_outlined),
                label: Text(tr('Ver novidades')),
              )),
          _opcao(tr('Atualizações'), tr('Ver se há uma versão nova da app e instalá-la.'),
              controlo: OutlinedButton.icon(
                onPressed: () => procurarAtualizacoes(context, a: widget.atualizador),
                icon: const Icon(Icons.system_update_rounded),
                label: Text(tr('Procurar atualizações')),
              )),
          _opcao(tr('Licenças'), tr('O player usa o mpv e o ffmpeg (GPLv3).'),
              controlo: OutlinedButton.icon(
                onPressed: () => showLicensePage(context: context, applicationName: nomeApp),
                icon: const Icon(Icons.description_outlined),
                label: Text(tr('Ver licenças')),
              )),
        ];
    }
  }

  /// Um separador fino entre cada duas linhas.
  List<Widget> _comSeparadores(List<Widget> linhas) =>
      [for (var i = 0; i < linhas.length; i++) ...[if (i > 0) const SeparadorOpcao(), linhas[i]]];

  Widget _painel(_Categoria c, bool ocupado) => Focus(
        focusNode: _focoPainel,
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: _teclaPainel,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              key: ValueKey(c),
              padding: const EdgeInsets.all(Tokens.e16),
              children: _comSeparadores(_opcoes(c, ocupado)),
            ),
          ),
        ),
      );

  /// Uma categoria na lista: com a barra azul à esquerda quando é a ativa.
  Widget _linhaCategoria(_Categoria c, {required bool largo}) {
    final ativa = largo && c == _cat;
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.e8),
      child: Stack(children: [
        RealceFoco(
          raio: Tokens.raioBotao,
          construir: (context, aoMudarFoco) => ListTile(
            focusNode: _focosCat[c.index],
            selected: ativa,
            selectedColor: Colors.white,
            selectedTileColor: Tokens.acento2,
            iconColor: Tokens.texto2,
            textColor: Tokens.texto2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.raioBotao)),
            leading: Icon(c.icone),
            title: Text(c.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: largo ? null : const Icon(Icons.chevron_right_rounded),
            onFocusChange: (f) {
              aoMudarFoco(f);
              if (f && largo) _escolher(c);
            },
            onTap: () => _escolher(c, abrir: !largo),
          ),
        ),
        if (ativa)
          Positioned(
            left: 0,
            top: Tokens.e8,
            bottom: Tokens.e8,
            child: Container(
                width: 4,
                decoration: BoxDecoration(color: Tokens.anelFoco, borderRadius: BorderRadius.circular(2))),
          ),
      ]),
    );
  }

  Widget _listaCategorias({required bool largo}) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: _teclaCategorias,
        child: ListView(
          padding: const EdgeInsets.all(Tokens.e16),
          children: [for (final c in _categorias) _linhaCategoria(c, largo: largo)],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: ListenableBuilder(
          listenable: Listenable.merge([_p, widget.biblioteca, if (widget.servico != null) widget.servico!]),
          builder: (context, _) {
            final ocupado = widget.servico?.ocupado ?? false;
            return LayoutBuilder(builder: (context, c) {
              _estreito = c.maxWidth < _larguraDuasColunas;
              if (!_estreito) {
                return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(width: 260, child: _listaCategorias(largo: true)),
                  Expanded(child: _painel(_cat, ocupado)),
                ]);
              }
              if (!_aberta) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(Tokens.e16, Tokens.e16, Tokens.e16, 0),
                    child: Text(tr('Definições'), style: TextStyle(fontFamily: Tokens.letraTitulos, fontSize: 24, fontWeight: FontWeight.w700)),
                  ),
                  Expanded(child: _listaCategorias(largo: false)),
                ]);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Tokens.e8, Tokens.e8, Tokens.e16, 0),
                  child: Row(children: [
                    IconButton(onPressed: _fechar, tooltip: tr('Voltar'), icon: const Icon(Icons.arrow_back)),
                    Expanded(
                      child: Text(_cat.titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: Tokens.letraTitulos, fontSize: 21, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
                Expanded(child: _painel(_cat, ocupado)),
              ]);
            });
          },
        ),
      );
}
