import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../guia/programa.dart';
import '../../guia/servico_guia.dart';
import '../../idioma/idioma.dart';
import '../../modelo/canal.dart';
import '../design/design.dart';

/// "20:30" (hora local) de um instante em segundos.
String horaCurta(int segundos) {
  final d = DateTime.fromMillisecondsSinceEpoch(segundos * 1000);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// "20:30 – 21:15".
String intervaloPrograma(Programa p) => '${horaCurta(p.inicio)} – ${horaCurta(p.fim)}';

/// Quanto falta para o fim: "faltam 25 min", "falta 1 h 05".
String faltaPara(Programa p, int agora) {
  final min = ((p.fim - agora) / 60).ceil().clamp(0, 24 * 60);
  if (min < 60) return min == 1 ? tr('falta 1 min') : tr('faltam {0} min', [min]);
  final h = min ~/ 60, m = min % 60;
  return tr('falta {0} h {1}', [h, m.toString().padLeft(2, '0')]);
}

/// O canal em destaque e a programação dele: na coluna à direita dos canais (TV e computador)
/// e na folha que o toque longo abre no telemóvel.
class PainelCanal extends StatefulWidget {
  const PainelCanal({super.key, required this.canal, required this.numero, required this.grupo, this.guia,
      this.favorito = false, this.compacto = false});

  final Canal canal;

  /// O nome do grupo para mostrar.
  final String grupo;

  /// O número mostrado (o do portal ou a posição na lista).
  final String numero;

  /// O guia da lista (null = o tipo da lista não tem guia).
  final ServicoGuia? guia;
  final bool favorito;

  /// Na folha do telemóvel: menos espaço e sem rolar (a folha rola).
  final bool compacto;

  /// Espera que o canal fique à vista este tempo antes de pedir a programação dele (a descer a
  /// lista com o comando, os canais por onde se passa não pedem nada).
  static const atraso = Duration(milliseconds: 700);

  @override
  State<PainelCanal> createState() => _PainelCanalState();
}

class _PainelCanalState extends State<PainelCanal> {
  Timer? _relogio;
  Timer? _atrasoPedido;

  @override
  void initState() {
    super.initState();
    widget.guia?.addListener(_mudou);
    // a barra de progresso e o "faltam" andam com o tempo
    _relogio = Timer.periodic(const Duration(seconds: 30), (_) => _mudou());
    _pedirDepois();
  }

  @override
  void didUpdateWidget(PainelCanal antes) {
    super.didUpdateWidget(antes);
    if (!identical(antes.guia, widget.guia)) {
      antes.guia?.removeListener(_mudou);
      widget.guia?.addListener(_mudou);
    }
    if (antes.canal.id != widget.canal.id || !identical(antes.guia, widget.guia)) _pedirDepois();
  }

  /// Sem programação para o canal, pede-se só a dele (o guia decide se é preciso).
  void _pedirDepois() {
    _atrasoPedido?.cancel();
    final g = widget.guia;
    if (g == null) return;
    _atrasoPedido = Timer(PainelCanal.atraso, () {
      if (mounted) unawaited(g.pedirCanal(widget.canal));
    });
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _atrasoPedido?.cancel();
    widget.guia?.removeListener(_mudou);
    super.dispose();
  }

  void _mudou() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final c = widget.canal;
    final g = widget.guia;
    final escala = tv ? 1.15 : 1.0;
    final cabecalho = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LogoCanal(c.logo, c.nome, tamanho: tv ? 80 : 64, chave: const Key('logo-detalhe')),
      const SizedBox(width: Tokens.e16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // RichText (não Text): o nome já está na linha do canal; aqui é só o destaque dele
          RichText(
            key: const Key('detalhe-nome'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textScaler: MediaQuery.textScalerOf(context),
            text: TextSpan(
              text: c.nome,
              style: TextStyle(
                  fontFamily: Tokens.letraTitulos,
                  fontSize: 20 * escala,
                  fontWeight: FontWeight.w700,
                  color: Tokens.texto,
                  height: 1.2),
            ),
          ),
          const SizedBox(height: Tokens.e4),
          Text(tr('Canal {0} · {1}', [widget.numero, widget.grupo]), maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13 * escala, color: Tokens.texto2)),
          if (widget.favorito) ...[
            const SizedBox(height: Tokens.e4),
            Row(children: [
              Icon(Icons.star_rounded, size: 16 * escala, color: Tokens.aviso),
              const SizedBox(width: Tokens.e4),
              Flexible(
                child: Text(tr('Nos favoritos'), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13 * escala, color: Tokens.texto2)),
              ),
            ]),
          ],
        ]),
      ),
    ]);
    final coluna = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      cabecalho,
      const SizedBox(height: Tokens.e16),
      const Divider(height: 1),
      const SizedBox(height: Tokens.e16),
      ..._programacao(g, escala),
    ]);
    // o número do canal em grande e quase transparente, por trás (só decoração: RichText, sem
    // semântica)
    final conteudo = Stack(clipBehavior: Clip.none, children: [
      Positioned(
        right: -6,
        top: -34,
        child: ExcludeSemantics(
          child: RichText(
            key: const Key('marca-dagua-canal'),
            text: TextSpan(
              text: widget.numero,
              style: TextStyle(
                fontFamily: Tokens.letraTitulos,
                fontSize: (widget.compacto ? 96 : 130) * escala,
                fontWeight: FontWeight.w800,
                letterSpacing: -6,
                height: 1,
                color: Tokens.anelFoco.withValues(alpha: .07),
              ),
            ),
          ),
        ),
      ),
      coluna,
    ]);
    if (widget.compacto) return conteudo;
    return SingleChildScrollView(padding: const EdgeInsets.all(Tokens.e16), child: conteudo);
  }

  List<Widget> _programacao(ServicoGuia? g, double escala) {
    Widget nota(String t, {Key? chave}) =>
        Text(t, key: chave, style: TextStyle(fontSize: 14 * escala, color: Tokens.texto2, height: 1.4));
    if (g == null) return [nota(tr('Esta lista não tem programação.'), chave: const Key('sem-guia'))];
    final ps = g.programas(widget.canal);
    final agora = g.agora();
    final (atual, seguinte) = agoraESeguinte(ps, agora);
    if (atual == null && seguinte == null) {
      final aCarregar = g.aPedir(widget.canal) || g.estado == EstadoGuia.aCarregar;
      return [
        nota(aCarregar ? tr('A carregar a programação…') : tr('Sem programação disponível.'),
            chave: Key(aCarregar ? 'guia-a-carregar' : 'sem-programacao')),
      ];
    }
    final rotulo = TextStyle(fontSize: 12 * escala, fontWeight: FontWeight.w700, letterSpacing: .8);
    final titulo = TextStyle(fontSize: 17 * escala, fontWeight: FontWeight.w600, color: Tokens.texto, height: 1.3);
    final horas = TextStyle(fontSize: 13 * escala, color: Tokens.texto2);
    final depois = [
      for (final p in ps)
        if (p.inicio > (seguinte ?? atual)!.inicio) p,
    ].take(3);
    return [
      if (atual != null) ...[
        // o programa a dar num painel azul, com o ponto do direto a pulsar
        Container(
          key: const Key('bloco-agora'),
          padding: const EdgeInsets.all(Tokens.e16),
          decoration: BoxDecoration(
            color: Tokens.acento.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(Tokens.raioCartao),
            border: Border.all(color: Tokens.anelFoco.withValues(alpha: .28)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const PontoDireto(),
          const SizedBox(width: Tokens.e8),
          Text(tr('AGORA'), style: rotulo.copyWith(color: Colors.white)),
        ]),
        const SizedBox(height: Tokens.e8),
        Text(atual.titulo, key: const Key('detalhe-agora'), maxLines: 3, overflow: TextOverflow.ellipsis, style: titulo),
        const SizedBox(height: Tokens.e4),
        Text('${intervaloPrograma(atual)} · ${faltaPara(atual, agora)}', style: horas),
        const SizedBox(height: Tokens.e8),
        ClipRRect(
          borderRadius: BorderRadius.circular(Tokens.raioPilula),
          child: LinearProgressIndicator(
            key: const Key('detalhe-progresso'),
            value: atual.progresso(agora),
            minHeight: 4,
            backgroundColor: Tokens.vidroForte,
            color: Tokens.acento,
          ),
        ),
        if (atual.descricao.isNotEmpty) ...[
          const SizedBox(height: Tokens.e12),
          Text(atual.descricao, key: const Key('detalhe-descricao'), maxLines: widget.compacto ? 4 : 8,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14 * escala, color: Tokens.texto2, height: 1.45)),
        ],
          ]),
        ),
        const SizedBox(height: Tokens.e16),
      ],
      if (seguinte != null) ...[
        Text(tr('A SEGUIR'), style: rotulo.copyWith(color: Tokens.texto2)),
        const SizedBox(height: Tokens.e4),
        Text(seguinte.titulo, key: const Key('detalhe-seguinte'), maxLines: 2, overflow: TextOverflow.ellipsis,
            style: titulo.copyWith(fontSize: 15 * escala)),
        const SizedBox(height: Tokens.e4),
        Text(intervaloPrograma(seguinte), style: horas),
      ],
      for (final p in depois) ...[
        const SizedBox(height: Tokens.e8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 52 * escala, child: Text(horaCurta(p.inicio), style: horas)),
          Expanded(
            child: Text(p.titulo, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14 * escala, color: Tokens.texto)),
          ),
        ]),
      ],
    ];
  }
}

/// O logótipo do canal num quadrado de vidro (ou as iniciais do nome, sem logótipo).
class LogoCanal extends StatelessWidget {
  const LogoCanal(this.url, this.nome, {super.key, required this.tamanho, this.chave = const Key('logo-canal')});
  final String url;
  final String nome;
  final double tamanho;
  final Key chave;

  /// "PT: RTP 1 HD" → "PR": a 1.ª letra de até duas palavras (uma só palavra: as duas primeiras).
  static String iniciais(String nome) {
    final alfanum = RegExp(r'[^\p{L}\p{N}]', unicode: true);
    final palavras = [
      for (final p in nome.split(RegExp(r'\s+')))
        if (p.replaceAll(alfanum, '').isNotEmpty) p.replaceAll(alfanum, ''),
    ];
    if (palavras.isEmpty) return '';
    final r = palavras.length == 1
        ? palavras.first.characters.take(2).toString()
        : '${palavras[0].characters.first}${palavras[1].characters.first}';
    return r.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final ini = iniciais(nome);
    final vazio = ini.isEmpty
        ? Icon(Icons.tv_rounded, color: Tokens.texto2, size: tamanho * .5)
        // RichText (não Text): as iniciais são só decoração, o nome já está ao lado
        : Center(child: ExcludeSemantics(child: RichText(maxLines: 1, text: TextSpan(text: ini,
            style: TextStyle(color: Tokens.texto2, fontSize: tamanho * .36, fontWeight: FontWeight.w700)))));
    return Container(
      key: chave,
      width: tamanho,
      height: tamanho,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Tokens.vidro, borderRadius: BorderRadius.circular(tamanho * .22)),
      child: url.startsWith('http')
          ? Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => vazio,
              // descodificado no tamanho mostrado (poupa memória com muitos logótipos)
              cacheWidth: (tamanho * MediaQuery.devicePixelRatioOf(context)).round())
          : vazio,
    );
  }
}
