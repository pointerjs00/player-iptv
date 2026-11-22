import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../../verificar/canais_teste.dart';
import '../../verificar/servico.dart';
import '../design/design.dart';
import '../navegacao_blocos.dart';
import '../principal/tela_principal.dart';
import '../realce_foco.dart';
import '../../idioma/idioma.dart';

/// O sub-ecrã "Verificação" do Gestor: o que está a decorrer (barra por cor, contagens, o tempo
/// que falta) e uma linha por lista com o motivo do resultado.
///
/// Só mostra: quem decide o que verificar é o passo 2 ("Verificar mais (fila)" leva-o lá com
/// o filtro "Por verificar"). Sem verificação a decorrer, resume as listas do Gestor.
class TelaVerificacao extends StatelessWidget {
  const TelaVerificacao({
    super.key,
    required this.biblioteca,
    required this.area,
    required this.servico,
    required this.focoVerificarMais,
    required this.bloco,
    required this.aoVerificarMais,
    required this.aoVerificarTodas,
    required this.aoParar,
  });

  final Biblioteca biblioteca;
  final AreaGestor area;
  final ServicoVerificacao servico;

  /// O primeiro controlo (recebe o foco ao abrir o sub-ecrã).
  final FocusNode focoVerificarMais;

  /// O bloco para CIMA/BAIXO (ver [moverEntreBlocos]).
  final FocusNode bloco;

  /// "Verificar mais (fila)": vai ao passo 2, filtrado pelas "Por verificar".
  final VoidCallback aoVerificarMais;

  /// "Verificar todas": todas as listas do Gestor entram na fila (não mexe na seleção).
  final VoidCallback aoVerificarTodas;
  final VoidCallback aoParar;

  static String _n(int n, String um, String varios) => '$n ${tr(n == 1 ? um : varios)}';

  /// "faltam cerca de 3 min" (de 1 min para cima) ou "faltam cerca de 40 s". O ritmo real da ronda.
  static String textoEstimativa(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return tr('faltam cerca de {0} s', [s < 1 ? 1 : s]);
    return tr('faltam cerca de {0} min', [(s / 60).round()]);
  }

  /// O passo do serviço ("canal 2/3 · a pedir os canais") como "A testar canal 2 de 3".
  static String textoPasso(String passo) {
    final m = RegExp(r'^canal (\d+)/(\d+)(?: · (.*))?$').firstMatch(passo);
    if (m == null) return passo.isEmpty ? passo : passo[0].toUpperCase() + passo.substring(1);
    return tr('A testar canal {0} de {1}', [m[1], m[2]]);
  }

  /// O detalhe do passo (depois do "canal i/n · "), em letra mais pequena.
  static String detalhePasso(String passo) {
    final m = RegExp(r'^canal \d+/\d+ · (.*)$').firstMatch(passo);
    return m?[1] ?? '';
  }

  /// "3 de 3 canais com imagem" quando se sabe canal a canal; senão o motivo.
  static String detalheResultado(Lista l) {
    final u = l.ultima;
    if (u == null) return '';
    if (u.estado == 'funciona' && u.canais.isNotEmpty) {
      final ok = u.canais.where((c) => c['estado'] == 'funciona').length;
      return tr('{0} de {1} canais com imagem', [ok, u.canais.length]);
    }
    return u.motivo;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([biblioteca, area, servico]),
        builder: (context, _) {
          final s = servico;
          final ocupado = s.ocupado;
          // a ronda: a correr, depois à espera, depois as que já acabaram (a última primeiro)
          final aCorrer = <String>[], espera = <String>[];
          for (final e in s.passos.entries) {
            (e.value == 'na fila' || e.value.startsWith('inconclusiva: à espera') ? espera : aCorrer).add(e.key);
          }
          final acabadas = [for (final id in s.concluidas.reversed) if (area.porId(id) != null) id];
          final ids = <String>{
            for (final id in [...aCorrer, ...espera, ...acabadas])
              if (area.porId(id) != null) id
          }.toList();
          // com a ronda a decorrer ou já acabada (fica até começar outra)
          final temRonda = ocupado || acabadas.isNotEmpty;
          int deEstado(EstadoLista e) => acabadas.where((id) => estadoDe(area.porId(id)!) == e).length;
          final ok = deEstado(EstadoLista.funciona);
          final inc = deEstado(EstadoLista.inconclusiva);
          final mau = deEstado(EstadoLista.naoFunciona);
          final casca = SeccaoAtual.maybeOf(context) != null;
          final estimativa = s.estimativaRestante;

          final cabeca = <Widget>[
            CabecalhoSeccao(
              titulo: ocupado
                  ? tr('A verificar {0}', [_n(s.total, 'lista', 'listas')])
                  : acabadas.isNotEmpty
                      ? s.parada
                          ? tr('Verificação parada: {0}', [_n(acabadas.length, 'lista verificada', 'listas verificadas')])
                          : tr('Última verificação: {0}', [_n(acabadas.length, 'lista', 'listas')])
                      : s.parada && s.fimRonda != null
                          ? tr('Verificação parada: nenhuma lista chegou ao fim')
                          : tr('Verificação'),
              subtitulo: ocupado
                  ? tr('Pode sair, continua sozinha')
                  : area.listas.isEmpty
                      ? tr('Importe listas primeiro')
                      : [
                          if (acabadas.isNotEmpty && s.fimRonda != null)
                            tr('{0} às {1}', [s.parada ? tr('parou') : tr('terminou'), _hora(s.fimRonda!)]),
                          _resumoGeral(),
                        ].where((x) => x.isNotEmpty).join(' · '),
              icone: Icons.playlist_add_check,
            ),
            Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton.icon(
                focusNode: focoVerificarMais,
                onPressed: aoVerificarMais,
                icon: const Icon(Icons.playlist_add),
                label: Text(tr('Verificar mais (fila)')),
              ),
              OutlinedButton.icon(
                onPressed: aoVerificarTodas,
                icon: const Icon(Icons.playlist_add_check),
                label: Text(tr('Verificar todas ({0})', [area.listas.length])),
              ),
              if (ocupado)
                OutlinedButton.icon(onPressed: aoParar, icon: const Icon(Icons.stop), label: Text(tr('Parar'))),
            ]),
            if (temRonda) ...[
              const SizedBox(height: Tokens.e12),
              _Barra(
                  ok: ok,
                  inconclusivas: inc,
                  mau: mau,
                  feitas: ocupado ? s.feitas : acabadas.length,
                  total: ocupado ? s.total : acabadas.length),
              const SizedBox(height: Tokens.e8),
              if (ocupado)
                Wrap(spacing: Tokens.e12, runSpacing: Tokens.e4, children: [
                  Text(tr('{0} de {1} verificadas', [s.feitas, s.total]), style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (estimativa != null)
                    Text(textoEstimativa(estimativa), style: const TextStyle(color: Tokens.texto2)),
                ]),
              const SizedBox(height: Tokens.e4),
              Wrap(spacing: Tokens.e12, runSpacing: Tokens.e4, children: [
                _Contagem(EstadoLista.funciona, _n(ok, 'funciona', 'funcionam')),
                _Contagem(EstadoLista.inconclusiva, _n(inc, 'inconclusiva', 'inconclusivas')),
                _Contagem(EstadoLista.naoFunciona, _n(mau, 'não funciona', 'não funcionam')),
              ]),
            ],
            const SizedBox(height: Tokens.e12),
            Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(tr('Canais de teste: {0}', [perfisDe(biblioteca.canaisTeste).map((p) => p.nome).join(', ')]),
                  style: const TextStyle(color: Tokens.texto2)),
              if (casca)
                TextButton.icon(
                  onPressed: () => TelaPrincipal.irPara(context, Seccao.definicoes),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(tr('Alterar nas Definições')),
                ),
            ]),
          ];

          return Focus(
            canRequestFocus: false,
            skipTraversal: true,
            includeSemantics: false,
            onKeyEvent: (_, e) => moverEntreBlocos([bloco], e),
            child: Focus(
              focusNode: bloco,
              canRequestFocus: false,
              skipTraversal: true,
              includeSemantics: false,
              child: CustomScrollView(slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e16, Tokens.e16, 0),
                  sliver: SliverToBoxAdapter(
                    child: SuperficieVidro(
                      padding: const EdgeInsets.all(Tokens.e16 + 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: cabeca),
                    ),
                  ),
                ),
                // as linhas preguiçosas: uma ronda pode ter centenas de listas
                SliverPadding(
                  padding: const EdgeInsets.all(Tokens.e16),
                  sliver: SliverList.builder(
                    itemCount: ids.length,
                    itemBuilder: (_, i) {
                      final l = area.porId(ids[i])!;
                      return _LinhaVerificacao(
                          key: ValueKey(l.id),
                          lista: l,
                          passo: s.passos[l.id],
                          aoCancelar: () {
                            s.cancelar(l.id);
                            // a linha some com o botão: o foco volta ao primeiro controlo
                            focoVerificarMais.requestFocus();
                          });
                    },
                  ),
                ),
              ]),
            ),
          );
        },
      );

  static String _hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// O estado de todas as listas do Gestor: "8 funcionam · 2 inconclusivas · 1 não funciona · 3 por verificar".
  String _resumoGeral() {
    final c = <EstadoLista, int>{};
    for (final l in area.listas) {
      c.update(estadoDe(l), (n) => n + 1, ifAbsent: () => 1);
    }
    int n(EstadoLista e) => c[e] ?? 0;
    return [
      if (n(EstadoLista.funciona) > 0) _n(n(EstadoLista.funciona), 'funciona', 'funcionam'),
      if (n(EstadoLista.inconclusiva) > 0) _n(n(EstadoLista.inconclusiva), 'inconclusiva', 'inconclusivas'),
      if (n(EstadoLista.naoFunciona) > 0) _n(n(EstadoLista.naoFunciona), 'não funciona', 'não funcionam'),
      if (n(EstadoLista.porVerificar) > 0) tr('{0} por verificar', [n(EstadoLista.porVerificar)]),
    ].join(' · ');
  }
}

/// A barra: um troço por cor (funcionam, inconclusivas, não funcionam) e o que falta em neutro.
class _Barra extends StatelessWidget {
  const _Barra(
      {required this.ok, required this.inconclusivas, required this.mau, required this.feitas, required this.total});

  final int ok, inconclusivas, mau, feitas, total;

  @override
  Widget build(BuildContext context) {
    final feitasCor = ok + inconclusivas + mau;
    // o que falta (e, sem nada feito, a barra inteira neutra)
    final falta = total - feitasCor > 0 ? total - feitasCor : (feitasCor == 0 ? 1 : 0);
    Widget troco(int flex, Color cor) =>
        flex <= 0 ? const SizedBox.shrink() : Expanded(flex: flex, child: ColoredBox(color: cor));
    return Semantics(
      label: tr('Progresso da verificação: {0} de {1}', [feitas, total]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Tokens.raioPilula),
        child: SizedBox(
          height: 8,
          child: Row(children: [
            troco(ok, Tokens.ok),
            troco(inconclusivas, Tokens.aviso),
            troco(mau, Tokens.mau),
            troco(falta, Tokens.fundoNeutro),
          ]),
        ),
      ),
    );
  }
}

class _Contagem extends StatelessWidget {
  const _Contagem(this.estado, this.texto);

  final EstadoLista estado;
  final String texto;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(estado.icone, size: 16, color: estado.cor),
        const SizedBox(width: 6),
        Text(texto, style: TextStyle(color: estado.cor)),
      ]);
}

/// Uma lista da ronda: a correr ("A testar canal 2 de 3"), à espera ou com o resultado e o motivo.
/// Tem foco para o comando poder andar pela lista (o ecrã desliza até ela).
class _LinhaVerificacao extends StatefulWidget {
  const _LinhaVerificacao({super.key, required this.lista, required this.passo, required this.aoCancelar});

  final Lista lista;

  /// O passo do serviço; null = já acabou.
  final String? passo;

  /// "Cancelar" (só nas que estão a correr ou na fila).
  final VoidCallback aoCancelar;

  @override
  State<_LinhaVerificacao> createState() => _LinhaVerificacaoState();
}

class _LinhaVerificacaoState extends State<_LinhaVerificacao> {
  bool _focado = false;

  @override
  Widget build(BuildContext context) {
    final l = widget.lista;
    final passo = widget.passo;
    final Widget estado;
    String? subtitulo;
    if (passo == null) {
      estado = Align(
          alignment: Alignment.centerLeft,
          child: PilulaEstado(estadoDe(l), detalhe: TelaVerificacao.detalheResultado(l)));
    } else if (passo == 'na fila') {
      estado = Text(tr('Na fila'), style: TextStyle(color: Tokens.texto2, fontWeight: FontWeight.w600));
    } else {
      estado = Text(TelaVerificacao.textoPasso(passo),
          style: const TextStyle(color: Tokens.anelFoco, fontWeight: FontWeight.w600));
      final d = TelaVerificacao.detalhePasso(passo);
      if (d.isNotEmpty) subtitulo = d;
    }
    return Focus(
      // as acabadas focam-se a si próprias; as outras focam o "Cancelar"
      canRequestFocus: passo == null,
      onFocusChange: (f) => setState(() => _focado = f),
      child: MolduraFoco(
        focado: _focado,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.e12, vertical: Tokens.e8),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.nomeMostrado,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: Tokens.e4),
            estado,
            if (subtitulo != null)
              Text(subtitulo,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Tokens.texto2, fontSize: 12.5)),
            ])),
            if (passo != null)
              TextButton(onPressed: widget.aoCancelar, child: Text(tr('Cancelar'))),
          ]),
        ),
      ),
    );
  }
}
