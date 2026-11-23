/// Poupar dados móveis (Definições › Ligação): no telemóvel Android, com dados móveis ou numa
/// rede limitada, a app pergunta antes do que pode gastar muitos dados.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../dados/preferencias.dart';
import '../idioma/idioma.dart';
import 'design/design.dart';

/// O que pode gastar muitos dados.
enum AcaoDados {
  /// A programação (EPG) de todos os canais de uma lista: pode ter dezenas de MB.
  guia,

  /// Os canais de uma lista, pedidos ao servidor: uma lista grande tem vários MB.
  canais,

  /// Verificar listas: cada uma descarrega os canais e testa alguns.
  verificacao,
}

/// Como está a ligação: por dados móveis e/ou numa rede limitada (a cobrar por MB).
typedef EstadoLigacao = ({bool movel, bool limitada});

const _canal = MethodChannel('player_iptv/rede');

Future<EstadoLigacao> _lerLigacao() async {
  try {
    final r = await _canal.invokeMapMethod<String, Object?>('ligacao');
    return (movel: r?['movel'] == true, limitada: r?['limitada'] == true);
  } catch (_) {
    return (movel: false, limitada: false); // sem resposta: não se incomoda
  }
}

/// Só num aparelho Android a sério (não a simulação dos testes), fora da TV e com a opção ligada.
bool _ativaPorOmissao() => Preferencias.atual.pouparDados && Platform.isAndroid && !EcraTv.nativo;

class PoupancaDados {
  PoupancaDados({Future<EstadoLigacao> Function()? ligacao, bool Function()? ativa})
      : _ligacao = ligacao ?? _lerLigacao,
        _ativa = ativa ?? _ativaPorOmissao;

  /// A da app (substituível nos testes).
  static PoupancaDados atual = PoupancaDados();

  final Future<EstadoLigacao> Function() _ligacao;
  final bool Function() _ativa;

  /// O que já se aceitou nesta sessão (não se volta a perguntar até a app fechar).
  final _aceites = <AcaoDados>{};

  /// O que se recusou nesta sessão: o que é automático (o guia) não volta a perguntar.
  final _recusadas = <AcaoDados>{};

  /// Pode fazer `acao` agora? Fora do telemóvel, sem a opção ou sem dados móveis: sim. Senão
  /// pergunta (uma vez por sessão, se aceitar). `automatico` = a app é que ia fazer (não o
  /// utilizador): depois de um «Agora não», não volta a perguntar até a app fechar.
  /// `quantas`: as listas a verificar.
  Future<bool> autorizar(BuildContext context, AcaoDados acao, {bool automatico = false, int quantas = 1}) async {
    if (!_ativa() || _aceites.contains(acao)) return true;
    final l = await _ligacao();
    if (!l.movel && !l.limitada) return true;
    if (automatico && _recusadas.contains(acao)) return false;
    if (!context.mounted) return false;
    final sim = await _perguntar(context, acao, l, quantas) ?? false;
    (sim ? _aceites : _recusadas).add(acao);
    if (sim) _recusadas.remove(acao);
    return sim;
  }

  Future<bool?> _perguntar(BuildContext context, AcaoDados acao, EstadoLigacao l, int quantas) {
    final (pergunta, botao) = switch (acao) {
      AcaoDados.guia => (
          tr('Descarregar a programação de todos os canais desta lista? Pode gastar dezenas de MB. Sem ela, a programação de um canal só é pedida quando o escolhe (poucos dados), e a pesquisa é só pelo nome.'),
          tr('Descarregar'),
        ),
      AcaoDados.canais => (
          tr('Carregar os canais desta lista do servidor? Uma lista grande pode gastar vários MB.'),
          tr('Carregar'),
        ),
      AcaoDados.verificacao => (
          quantas == 1
              ? tr('Verificar a lista? Descarrega os canais dela e testa alguns: pode gastar vários MB.')
              : tr('Verificar {0} listas? Cada uma descarrega os canais e testa alguns: pode gastar muitos MB.', [quantas]),
          tr('Verificar'),
        ),
    };
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('pergunta-dados-moveis'),
        icon: const Icon(Icons.signal_cellular_alt_rounded, color: Tokens.aviso, size: 32),
        title: Text(l.movel ? tr('Está a usar dados móveis') : tr('Está numa rede limitada')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pergunta, style: const TextStyle(height: 1.4)),
              const SizedBox(height: Tokens.e12),
              Text(tr('Pode desligar este aviso em Definições › Ligação › Poupar dados móveis.'),
                  style: const TextStyle(fontSize: 13, color: Tokens.texto2)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Agora não'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(botao)),
        ],
      ),
    );
  }
}
