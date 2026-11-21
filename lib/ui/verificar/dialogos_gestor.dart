import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../design/design.dart';

/// Uma opção de um [escolherOpcao]: um cartão com ícone, título e descrição.
class OpcaoDialogo<T> {
  const OpcaoDialogo(this.valor, this.icone, this.titulo, this.descricao);
  final T valor;
  final IconData icone;
  final String titulo;
  final String descricao;
}

/// Um diálogo com opções em cartões (CIMA/BAIXO mudam, OK escolhe, Voltar ou "Cancelar" cancela).
/// O foco começa na primeira opção. Devolve o valor escolhido ou null.
Future<T?> escolherOpcao<T>(BuildContext context,
    {required IconData icone, required String titulo, required String texto, required List<OpcaoDialogo<T>> opcoes}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) {
      final tv = ecraTv(ctx);
      // ecrã baixo (a TV a 1080p tem 540 lógicos): sem o ícone de cima e cartões mais baixos,
      // para as opções caberem todas sem deslizar
      final baixo = MediaQuery.sizeOf(ctx).height < 640;
      return AlertDialog(
        icon: baixo ? null : Icon(icone, color: Tokens.acento2, size: 32),
        insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: baixo ? 8 : 24),
        title: Text(titulo),
        content: SizedBox(
          width: tv ? 560 : 480,
          child: SingleChildScrollView(
            // margem para o cartão focado crescer sem ser cortado
            padding: EdgeInsets.symmetric(horizontal: Tokens.e8, vertical: baixo ? Tokens.e4 : Tokens.e8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(texto, style: const TextStyle(color: Tokens.texto2)),
              SizedBox(height: baixo ? Tokens.e12 : Tokens.e16),
              for (final (i, o) in opcoes.indexed) ...[
                if (i > 0) SizedBox(height: baixo ? Tokens.e8 : Tokens.e12),
                CartaoModerno(
                  autofocus: i == 0,
                  escalaFoco: 1.02,
                  raio: Tokens.raioBotao,
                  padding: EdgeInsets.symmetric(horizontal: Tokens.e16, vertical: baixo ? 10 : Tokens.e16),
                  onTap: () => Navigator.pop(ctx, o.valor),
                  child: Row(children: [
                    Icon(o.icone, color: Tokens.acento2, size: tv ? 30 : 26),
                    const SizedBox(width: Tokens.e16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o.titulo, style: TextStyle(fontSize: tv && !baixo ? 17 : 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(o.descricao,
                            style: TextStyle(color: Tokens.texto2, fontSize: tv && !baixo ? 14 : 12.5)),
                      ]),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))],
      );
    },
  );
}

/// Um cartão de escolha única (como um botão de rádio): o título, a descrição e a marca de escolhido.
class _CartaoEscolha extends StatelessWidget {
  const _CartaoEscolha({
    required this.titulo,
    required this.escolhido,
    required this.aoEscolher,
    this.descricao,
    this.icone,
    this.autofocus = false,
    this.compacto = false,
  });
  final String titulo;
  final String? descricao;
  final bool escolhido;
  final VoidCallback aoEscolher;
  final IconData? icone;
  final bool autofocus;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: escolhido,
      child: CartaoModerno(
        autofocus: autofocus,
        escalaFoco: 1.02,
        raio: Tokens.raioBotao,
        padding: EdgeInsets.symmetric(horizontal: Tokens.e16, vertical: compacto ? 8 : Tokens.e12),
        onTap: aoEscolher,
        child: Row(children: [
          Icon(escolhido ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: escolhido ? Tokens.acento2 : Tokens.texto2, size: tv ? 26 : 22),
          if (icone != null) ...[
            const SizedBox(width: Tokens.e12),
            Icon(icone, color: Tokens.acento2, size: tv ? 28 : 24),
          ],
          const SizedBox(width: Tokens.e12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: TextStyle(fontSize: tv && !compacto ? 17 : 15, fontWeight: FontWeight.w600)),
              if (descricao != null) ...[
                const SizedBox(height: 2),
                Text(descricao!, style: TextStyle(color: Tokens.texto2, fontSize: tv && !compacto ? 14 : 12.5)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

String _listas(int n) => n == 1 ? '1 lista' : '$n listas';

/// O resultado de um envio, com o que mudou em Ver TV ([ResumoEnvio]):
/// "8 listas enviadas para Ver TV · 5 novas, 3 atualizadas, 2 removidas · 1 ainda a verificar".
/// As contagens a zero não aparecem.
String textoResultadoEnvio(int n, ResumoEnvio r, {int aDecorrer = 0}) {
  String c(int v, String um, String varios) => '$v ${v == 1 ? um : varios}';
  final partes = [
    if (r.adicionadas > 0) c(r.adicionadas, 'nova', 'novas'),
    if (r.atualizadas > 0) c(r.atualizadas, 'atualizada', 'atualizadas'),
    if (r.removidas > 0) c(r.removidas, 'removida', 'removidas'),
  ];
  return '${n == 1 ? '1 lista enviada' : '$n listas enviadas'} para Ver TV'
      ' · ${partes.isEmpty ? 'já lá estavam iguais' : partes.join(', ')}'
      '${aDecorrer > 0 ? ' · $aDecorrer ainda a verificar' : ''}';
}

/// "Enviar n listas para Ver TV": como — adicionar, ou substituir (e o que manter das que já lá
/// estão, com filtros que se ligam e desligam). As listas já vêm escolhidas do passo 3. Devolve o
/// modo e o que manter (vazio ao adicionar, ou ao substituir sem manter nada); null = cancelado.
Future<(ModoEnvio, Set<ManterAoSubstituir>)?> perguntarEnvio(BuildContext context, {required int n}) {
  return showDialog<(ModoEnvio, Set<ManterAoSubstituir>)>(context: context, builder: (_) => _DialogoEnvio(n: n));
}

class _DialogoEnvio extends StatefulWidget {
  const _DialogoEnvio({required this.n});
  final int n;

  @override
  State<_DialogoEnvio> createState() => _DialogoEnvioState();
}

class _DialogoEnvioState extends State<_DialogoEnvio> {
  var _substituir = false;
  // «Nenhuma» é o conjunto vazio: ligá-lo desliga os outros; desligar o último volta a ligá-lo
  final _manter = {ManterAoSubstituir.favoritas};

  void _alternar(ManterAoSubstituir m) => setState(() {
        if (!_manter.remove(m)) _manter.add(m);
      });

  String get _descricaoSubstituir {
    final partes = [
      if (_manter.contains(ManterAoSubstituir.favoritas)) 'as favoritas',
      if (_manter.contains(ManterAoSubstituir.funcionam)) 'as que funcionam',
      if (_manter.contains(ManterAoSubstituir.inconclusivas)) 'as inconclusivas',
    ];
    if (partes.isEmpty) return 'Ver TV fica só com estas.';
    final juntas = partes.length == 1 ? partes.single : '${partes.take(partes.length - 1).join(', ')} e ${partes.last}';
    return 'Ver TV fica com estas e com $juntas.';
  }

  /// O que o diálogo devolve com a escolha de agora.
  (ModoEnvio, Set<ManterAoSubstituir>) get _escolha =>
      _substituir ? (ModoEnvio.substituir, {..._manter}) : (ModoEnvio.adicionar, <ManterAoSubstituir>{});

  /// Os filtros «manter» (ao substituir).
  List<Widget> _chipsManter() => [
        FilterChip(
          label: const Text('Nenhuma'),
          selected: _manter.isEmpty,
          showCheckmark: true,
          onSelected: (_) => setState(_manter.clear),
        ),
        for (final (m, rotulo) in [
          (ManterAoSubstituir.favoritas, 'Favoritas'),
          (ManterAoSubstituir.funcionam, 'As que funcionam'),
          (ManterAoSubstituir.inconclusivas, 'As inconclusivas'),
        ])
          FilterChip(
            label: Text(rotulo),
            selected: _manter.contains(m),
            showCheckmark: true,
            onSelected: (_) => _alternar(m),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    if (ecraTelemovel(context)) return _ecraInteiro(context);
    final n = widget.n;
    final baixo = MediaQuery.sizeOf(context).height < 640;
    final espaco = SizedBox(height: baixo ? Tokens.e8 : Tokens.e12);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: baixo ? 8 : 24),
      title: Text('Enviar ${_listas(n)} para Ver TV'),
      content: SizedBox(
        width: ecraTv(context) ? 560 : 480,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.e8, vertical: Tokens.e4),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _CartaoEscolha(
              autofocus: true,
              compacto: baixo,
              icone: Icons.playlist_add_rounded,
              titulo: 'Adicionar às listas de Ver TV',
              descricao: 'As que já lá estão ficam. Repetidas não se duplicam.',
              escolhido: !_substituir,
              aoEscolher: () => setState(() => _substituir = false),
            ),
            espaco,
            _CartaoEscolha(
              compacto: baixo,
              icone: Icons.delete_sweep_outlined,
              titulo: 'Substituir as listas de Ver TV',
              descricao: _descricaoSubstituir,
              escolhido: _substituir,
              aoEscolher: () => setState(() => _substituir = true),
            ),
            if (_substituir) ...[
              espaco,
              const Text('Das listas que já estão em Ver TV, manter:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: Tokens.e8),
              Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: _chipsManter()),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _escolha),
          child: Text('Enviar ${_listas(n)}'),
        ),
      ],
    );
  }

  /// No telemóvel, em ecrã inteiro (no diálogo pequeno os «manter» ficavam escondidos por baixo
  /// do deslizar): ✕ e o título em cima, as duas opções como botões de rádio, os «manter» à vista
  /// e «Enviar N listas» fixo em baixo.
  Widget _ecraInteiro(BuildContext context) {
    final n = widget.n;
    const fraco = TextStyle(color: Tokens.texto2);
    return Dialog.fullscreen(
      backgroundColor: Tokens.superficie,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Tokens.e4, Tokens.e4, Tokens.e16, 0),
            child: Row(children: [
              IconButton(tooltip: 'Cancelar', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              const SizedBox(width: Tokens.e4),
              Expanded(
                child: Text('Enviar ${_listas(n)} para Ver TV',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Tokens.texto)),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: Tokens.e8),
              child: RadioGroup<bool>(
                groupValue: _substituir,
                onChanged: (v) => setState(() => _substituir = v ?? false),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  RadioListTile<bool>(
                    value: false,
                    autofocus: true,
                    title: const Text('Adicionar às listas de Ver TV'),
                    subtitle: const Text('As que já lá estão ficam. Repetidas não se duplicam.', style: fraco),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    title: const Text('Substituir as listas de Ver TV'),
                    subtitle: Text(_descricaoSubstituir, style: fraco),
                  ),
                  if (_substituir)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e8, Tokens.e16, 0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Das listas que já estão em Ver TV, manter:',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: Tokens.e4),
                        Wrap(spacing: Tokens.e8, children: _chipsManter()),
                      ]),
                    ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Tokens.e16),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Tokens.alvoToque)),
              onPressed: () => Navigator.pop(context, _escolha),
              child: Text('Enviar ${_listas(n)}'),
            ),
          ),
        ]),
      ),
    );
  }
}

/// "Exportar n listas": o formato. Devolve `'json'` (Accounts.json) ou `'ini'` (zip de .ini); null = cancelado.
Future<String?> perguntarExportacao(BuildContext context, int n) {
  return showDialog<String>(context: context, builder: (_) => _DialogoExportacao(n: n));
}

class _DialogoExportacao extends StatefulWidget {
  const _DialogoExportacao({required this.n});
  final int n;

  @override
  State<_DialogoExportacao> createState() => _DialogoExportacaoState();
}

class _DialogoExportacaoState extends State<_DialogoExportacao> {
  var _formato = 'json';

  @override
  Widget build(BuildContext context) {
    final baixo = MediaQuery.sizeOf(context).height < 640;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: baixo ? 8 : 24),
      title: Text('Exportar ${_listas(widget.n)}'),
      content: SizedBox(
        width: ecraTv(context) ? 560 : 480,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.e8, vertical: Tokens.e4),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _CartaoEscolha(
              autofocus: true,
              compacto: baixo,
              icone: Icons.description_outlined,
              titulo: 'Accounts.json',
              descricao: 'Para o sfvip player',
              escolhido: _formato == 'json',
              aoEscolher: () => setState(() => _formato = 'json'),
            ),
            SizedBox(height: baixo ? Tokens.e8 : Tokens.e12),
            _CartaoEscolha(
              compacto: baixo,
              icone: Icons.folder_zip_outlined,
              titulo: 'Ficheiros .ini num zip',
              descricao: 'Para o Stalker Portal Player',
              escolhido: _formato == 'ini',
              aoEscolher: () => setState(() => _formato = 'ini'),
            ),
            SizedBox(height: baixo ? Tokens.e8 : Tokens.e16),
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_rounded, color: Tokens.aviso, size: 20),
              SizedBox(width: Tokens.e8),
              Expanded(
                child: Text('O ficheiro leva os dados de acesso das listas. Guarda-o num sítio seguro.',
                    style: TextStyle(color: Tokens.texto2)),
              ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _formato), child: const Text('Escolher onde guardar')),
      ],
    );
  }
}

/// Uma confirmação simples (o foco começa em "Cancelar"). true = confirmado.
Future<bool> confirmar(BuildContext context,
    {required IconData icone, required String titulo, required String texto, required String acao}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(icone, color: Tokens.mau, size: 32),
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(acao)),
      ],
    ),
  );
  return ok == true;
}
