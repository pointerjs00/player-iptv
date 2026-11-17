import 'package:material_ui/material_ui.dart';

import '../realce_foco.dart';
import '../tema.dart';
import 'movimento.dart';
import 'tokens.dart';

/// O fundo de todos os ecrãs: azul-noite com um gradiente radial subtil.
class FundoCinema extends StatelessWidget {
  const FundoCinema({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: Tokens.fundo,
          gradient: RadialGradient(
            center: Alignment(-.7, -1),
            radius: 1.5,
            colors: [Tokens.fundoBrilho, Tokens.fundo],
          ),
        ),
        child: child,
      );
}

/// Um painel de vidro fosco: fundo translúcido, borda de 1 px translúcida e sombra.
/// O conteúdo é recortado pelos cantos e pinta o "ink" (ListTile, InkWell) por cima do vidro.
class SuperficieVidro extends StatelessWidget {
  const SuperficieVidro({super.key, required this.child, this.padding = EdgeInsets.zero,
      this.raio = Tokens.raioCartao, this.elevacao = 1, this.cor = Tokens.vidro});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double raio;
  final int elevacao;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(raio);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cor,
        borderRadius: r,
        border: Border.all(color: Tokens.bordaVidro),
        boxShadow: Tokens.sombra(elevacao),
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: RoundedRectangleBorder(borderRadius: r),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Um cartão de vidro que se toca/abre (InkWell). Com o foco do comando (modo "traditional"):
/// aumenta para 1.04, ganha a borda de realce, um brilho violeta e a sombra sobe. Com o rato por
/// cima só a sombra sobe. No toque (telemóvel), o foco automático não muda nada.
class CartaoModerno extends StatefulWidget {
  const CartaoModerno({super.key, required this.child, this.onTap, this.autofocus = false,
      this.focusNode, this.padding = const EdgeInsets.all(Tokens.e16), this.raio = Tokens.raioCartao,
      this.escalaFoco = 1.04});

  final Widget child;
  final VoidCallback? onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry padding;
  final double raio;
  final double escalaFoco;

  @override
  State<CartaoModerno> createState() => _CartaoModernoState();
}

class _CartaoModernoState extends State<CartaoModerno> {
  bool _focado = false;
  bool _rato = false;

  void _foco(bool f) {
    if (mounted && f != _focado) setState(() => _focado = f);
  }

  void _hover(bool h) {
    if (mounted && h != _rato) setState(() => _rato = h);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // reconstrói quando o modo de realce muda (TemaConformeRealce troca o tema)
    final verFoco = _focado && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final r = BorderRadius.circular(widget.raio);
    return MolduraFoco(
      focado: _focado,
      raio: widget.raio,
      escala: widget.escalaFoco,
      child: AnimatedContainer(
        duration: duracaoAnimada(context, Tokens.duracaoRapida),
        curve: Tokens.curva,
        decoration: BoxDecoration(
          color: verFoco || _rato ? Tokens.vidroForte : Tokens.vidro,
          borderRadius: r,
          border: Border.all(color: Tokens.bordaVidro),
          boxShadow: verFoco ? Tokens.sombraFoco : (_rato ? Tokens.sombra2 : Tokens.sombra1),
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: RoundedRectangleBorder(borderRadius: r),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            autofocus: widget.autofocus,
            focusNode: widget.focusNode,
            onFocusChange: _foco,
            onHover: _hover,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// O estado da última verificação numa pílula colorida (verde, vermelho, âmbar ou cinzento).
class PilulaEstado extends StatelessWidget {
  const PilulaEstado(this.estado, {super.key, this.grande = false});

  /// 'funciona', 'nao_funciona', 'inconclusivo' ou null (por verificar).
  final String? estado;

  /// Maior (TV).
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final (cor, rotulo, icone) = visualEstado(estado);
    final tam = grande ? 15.0 : 12.5;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: grande ? 12 : 10, vertical: grande ? 5 : 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(Tokens.raioPilula),
        border: Border.all(color: cor.withValues(alpha: .4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icone, size: tam + 2, color: cor),
        const SizedBox(width: 6),
        Text(rotulo, style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: tam)),
      ]),
    );
  }
}

/// O título de uma secção (600–700), com subtítulo a 60 % e ações à direita.
class CabecalhoSeccao extends StatelessWidget {
  const CabecalhoSeccao({super.key, required this.titulo, this.subtitulo, this.icone, this.acoes = const [],
      this.padding = const EdgeInsets.only(bottom: Tokens.e12)});

  final String titulo;
  final String? subtitulo;
  final IconData? icone;
  final List<Widget> acoes;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (icone != null) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: Tokens.gradienteAcento,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icone, size: 18, color: Colors.white),
            ),
            const SizedBox(width: Tokens.e12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Tokens.texto)),
              if (subtitulo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitulo!, style: const TextStyle(fontSize: 12.5, color: Tokens.texto2)),
                ),
            ]),
          ),
          ...acoes,
        ]),
      );
}

/// O brilho a passar por cima de blocos (esqueleto enquanto carrega). `child` dá as formas
/// (por exemplo [BlocoEsqueleto]); com "reduzir movimento" fica parado.
class EsqueletoBrilho extends StatefulWidget {
  const EsqueletoBrilho({super.key, required this.child});
  final Widget child;

  @override
  State<EsqueletoBrilho> createState() => _EsqueletoBrilhoState();
}

class _EsqueletoBrilhoState extends State<EsqueletoBrilho> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  static const _base = Color(0x12FFFFFF);
  static const _luz = Color(0x2EFFFFFF);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (semAnimacoes(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, filho) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(
            colors: const [_base, _luz, _base],
            stops: const [.35, .5, .65],
            transform: _Deslizar(_c.isAnimating ? _c.value : -1),
          ).createShader(r),
          child: filho,
        ),
        child: widget.child,
      );
}

class _Deslizar extends GradientTransform {
  const _Deslizar(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

/// Um bloco do esqueleto (a forma; a cor vem do [EsqueletoBrilho]).
class BlocoEsqueleto extends StatelessWidget {
  const BlocoEsqueleto({super.key, this.largura, required this.altura, this.raio = 8});
  final double? largura;
  final double altura;
  final double raio;

  @override
  Widget build(BuildContext context) => Container(
        width: largura,
        height: altura,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(raio)),
      );
}
