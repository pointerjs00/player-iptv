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

/// O resultado de um envio, com o que mudou no Player ([ResumoEnvio]):
/// "8 listas enviadas para o Player · 5 novas, 3 atualizadas, 2 removidas · 1 ainda a verificar".
/// As contagens a zero não aparecem.
String textoResultadoEnvio(int n, ResumoEnvio r, {int aDecorrer = 0}) {
  String c(int v, String um, String varios) => '$v ${v == 1 ? um : varios}';
  final partes = [
    if (r.adicionadas > 0) c(r.adicionadas, 'nova', 'novas'),
    if (r.atualizadas > 0) c(r.atualizadas, 'atualizada', 'atualizadas'),
    if (r.removidas > 0) c(r.removidas, 'removida', 'removidas'),
  ];
  return '${n == 1 ? '1 lista enviada' : '$n listas enviadas'} para o Player'
      ' · ${partes.isEmpty ? 'já lá estavam iguais' : partes.join(', ')}'
      '${aDecorrer > 0 ? ' · $aDecorrer ainda a verificar' : ''}';
}

/// Que listas selecionadas vão para o Player.
enum QueEnviar {
  funcionam,
  funcionamEInconclusivas,

  /// Todas as selecionadas, seja qual for o estado (por verificar, não funciona…).
  todas,
}

/// "Enviar n listas para o Player": como (adicionar ou substituir) e que listas (só as que funcionam,
/// também as inconclusivas, ou todas as selecionadas). `funcionam`, `inconclusivas` e `todas` contam
/// só as selecionadas que não estão a ser verificadas. Devolve o modo e que listas; null = cancelado.
/// "Substituir" deixa o Player só com as enviadas ([ModoEnvio.esmagarTodas]).
Future<(ModoEnvio, QueEnviar)?> perguntarEnvio(BuildContext context,
    {required int funcionam, required int inconclusivas, required int todas}) {
  return showDialog<(ModoEnvio, QueEnviar)>(
    context: context,
    builder: (_) => _DialogoEnvio(funcionam: funcionam, inconclusivas: inconclusivas, todas: todas),
  );
}

class _DialogoEnvio extends StatefulWidget {
  const _DialogoEnvio({required this.funcionam, required this.inconclusivas, required this.todas});
  final int funcionam, inconclusivas, todas;

  @override
  State<_DialogoEnvio> createState() => _DialogoEnvioState();
}

class _DialogoEnvioState extends State<_DialogoEnvio> {
  var _substituir = false;
  var _manter = ModoEnvio.esmagarTodas;
  late var _que = widget.funcionam > 0
      ? QueEnviar.funcionam
      : widget.inconclusivas > 0
          ? QueEnviar.funcionamEInconclusivas
          : QueEnviar.todas;

  @override
  Widget build(BuildContext context) {
    final f = widget.funcionam, i = widget.inconclusivas, todas = widget.todas;
    final outras = todas - f - i;
    final baixo = MediaQuery.sizeOf(context).height < 640;
    final n = switch (_que) {
      QueEnviar.funcionam => f,
      QueEnviar.funcionamEInconclusivas => f + i,
      QueEnviar.todas => todas,
    };
    final espaco = SizedBox(height: baixo ? Tokens.e8 : Tokens.e12);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: baixo ? 8 : 24),
      title: Text('Enviar ${_listas(todas)} para o Player'),
      content: SizedBox(
        width: ecraTv(context) ? 560 : 480,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.e8, vertical: Tokens.e4),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                '${f == 1 ? '1 funciona' : '$f funcionam'} e '
                '${i == 1 ? '1 é inconclusiva' : '$i são inconclusivas'}',
                style: const TextStyle(color: Tokens.texto2)),
            // na TV o espaço é curto: a contagem já está na opção "Todas as selecionadas"
            if (outras > 0 && !baixo)
              Text(
                  outras == 1
                      ? '1 está por verificar ou não funciona'
                      : '$outras estão por verificar ou não funcionam',
                  style: const TextStyle(color: Tokens.texto2)),
            SizedBox(height: baixo ? Tokens.e8 : Tokens.e16),
            _CartaoEscolha(
              autofocus: true,
              compacto: baixo,
              icone: Icons.playlist_add_rounded,
              titulo: 'Adicionar às listas do Player',
              descricao: 'As que já lá estão ficam. Repetidas não se duplicam.',
              escolhido: !_substituir,
              aoEscolher: () => setState(() => _substituir = false),
            ),
            espaco,
            _CartaoEscolha(
              compacto: baixo,
              icone: Icons.delete_sweep_outlined,
              titulo: 'Substituir as listas do Player',
              descricao: switch (_manter) {
                ModoEnvio.esmagarMantendoFuncionais => 'O Player fica com estas e com as que já lá funcionam.',
                ModoEnvio.esmagarMantendoFuncionaisEInc =>
                  'O Player fica com estas e com as que já lá funcionam ou são inconclusivas.',
                _ => 'O Player fica só com estas. Os favoritos das que saem perdem-se.',
              },
              escolhido: _substituir,
              aoEscolher: () => setState(() => _substituir = true),
            ),
            if (_substituir) ...[
              SizedBox(height: baixo ? Tokens.e8 : Tokens.e12),
              const Text('Das listas que já estão no Player, manter:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: Tokens.e8),
              for (final (modo, rotulo) in [
                (ModoEnvio.esmagarTodas, 'nenhuma'),
                (ModoEnvio.esmagarMantendoFuncionais, 'as que funcionam'),
                (ModoEnvio.esmagarMantendoFuncionaisEInc, 'as que funcionam e as inconclusivas'),
              ]) ...[
                _CartaoEscolha(
                  compacto: true,
                  titulo: rotulo,
                  escolhido: _manter == modo,
                  aoEscolher: () => setState(() => _manter = modo),
                ),
                const SizedBox(height: Tokens.e8),
              ],
            ],
            SizedBox(height: baixo ? Tokens.e12 : Tokens.e16),
            const Text('Que listas enviar?', style: TextStyle(fontWeight: FontWeight.w600)),
            espaco,
            _CartaoEscolha(
              compacto: true,
              titulo: 'Só as que funcionam ($f)',
              escolhido: _que == QueEnviar.funcionam,
              aoEscolher: () => setState(() => _que = QueEnviar.funcionam),
            ),
            SizedBox(height: baixo ? Tokens.e4 : Tokens.e8),
            _CartaoEscolha(
              compacto: true,
              titulo: 'Funcionam + inconclusivas (${f + i})',
              escolhido: _que == QueEnviar.funcionamEInconclusivas,
              aoEscolher: () => setState(() => _que = QueEnviar.funcionamEInconclusivas),
            ),
            SizedBox(height: baixo ? Tokens.e4 : Tokens.e8),
            _CartaoEscolha(
              compacto: true,
              titulo: 'Todas as selecionadas ($todas)',
              escolhido: _que == QueEnviar.todas,
              aoEscolher: () => setState(() => _que = QueEnviar.todas),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: n == 0
              ? null
              : () => Navigator.pop(
                  context, (_substituir ? _manter : ModoEnvio.adicionar, _que)),
          child: Text('Enviar ${_listas(n)}'),
        ),
      ],
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
