import 'dart:io';

/// O que mudou numa versão (as novidades que a app mostra depois de atualizar).
class Novidades {
  const Novidades(this.versao, this.itens);

  /// "1.0.9" (a `version` do pubspec.yaml, sem o número da compilação).
  final String versao;

  /// As correções e novidades, em linguagem simples.
  final List<String> itens;
}

/// Todas as versões, a mais recente primeiro. A primeira é a versão da app: ao mudar a versão no
/// pubspec.yaml, junta-se aqui a entrada dela (um teste confirma que batem certo).
const historicoNovidades = <Novidades>[
  Novidades('1.0.10', [
    'Ver TV: → num grupo vai sempre ao primeiro canal desse grupo.',
    'Ver TV: sempre que o grupo muda (também ao esconder o grupo aberto), a lista dos canais volta '
        'ao topo.',
    'Gestor › Nova lista: os campos de cada tipo aparecem logo ao passar pelo botão do tipo, sem '
        'ser preciso carregar nele.',
  ]),
  Novidades('1.0.9', [
    'Gestor: no passo "Verificar", o botão da atividade abre a Atividade com todos os relatórios, '
        'como nos outros passos.',
    'Atividade: todos os cartões têm "Ver detalhe", também o de uma verificação parada.',
    'Durante a verificação, o "Parar" fica junto do indicador "A verificar".',
    'Ver TV: ao escolher um grupo, os canais aparecem a partir do primeiro.',
    'Novidades: este resumo aparece depois de cada atualização e pode ser visto de novo em '
        'Definições › Sobre e licenças.',
  ]),
  Novidades('1.0.8', [
    'Gestor: "Parar" no passo "Verificar", na barra de cima e no menu Ações.',
    'Ao ver um canal: barra de volume com botão de silêncio, em todas as plataformas. No comando, OK e '
        'depois ← → mudam o volume.',
  ]),
  Novidades('1.0.7', [
    'Gestor: o "i" da verificação fica no canto da barra de cima.',
    'Atividade: depois de parar ou terminar, a verificação fica com o resumo e o relatório.',
    'As janelas de confirmação ficaram mais estreitas e fáceis de ler.',
  ]),
  Novidades('1.0.6', [
    'Parar a verificação pede confirmação e mostra o relatório das listas que chegaram ao fim.',
    'Novo ecrã "Como é feita a verificação" (o botão "i").',
    'O passo 3 do Gestor passa a chamar-se "Exportar".',
    '"Adicionar lista": Portal MAC, Xtream (link ou servidor e conta), lista M3U ou várias coladas.',
    'Definições de verificação na TV: carregar em OK para mudar um valor; ← vai ao menu lateral.',
  ]),
  Novidades('1.0.5', [
    'A verificação das listas inconclusivas ficou mais rápida e já não atrasa as outras.',
  ]),
];

/// A versão da app ("1.0.9").
String get versaoApp => historicoNovidades.first.versao;

/// O ficheiro com a última versão cujas novidades se mostraram.
const ficheiroNovidadesVistas = 'novidades_vistas.txt';

/// As novidades da versão atual estão por ver? Só uma vez por versão: marca-as logo como vistas.
/// Numa instalação nova (`instalacaoNova`: sem listas e sem registo) não há nada a mostrar.
Future<bool> novidadesPorVer(Directory pasta, {required bool instalacaoNova}) async {
  final f = File('${pasta.path}${Platform.pathSeparator}$ficheiroNovidadesVistas');
  String? vista;
  try {
    if (await f.exists()) vista = (await f.readAsString()).trim();
  } on FileSystemException {
    vista = null;
  }
  if (vista == versaoApp) return false;
  try {
    await f.writeAsString(versaoApp, flush: true);
  } on FileSystemException {
    // sem gravar, mostra-se na mesma (na próxima abertura volta a aparecer)
  }
  return vista != null || !instalacaoNova;
}
