# App mais compacta e Verificar simples — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Interface mais pequena e arrumada na TV/Windows, topo nunca cortado, Verificar simples e dois filtros na lista aberta.

**Architecture:** Uma escala global no `MaterialApp.builder` (área lógica maior reduzida por `Transform.scale`), um vigia global do foco que repõe o scroll no início, e mudanças de estrutura nos ecrãs Verificar, lista aberta, Início, resumo/Enviar do Gestor e Definições.

**Tech Stack:** Flutter 3.50 / Dart 3.14, `package:material_ui/material_ui.dart`, flutter_test.

**Spec:** docs/2026-11-19-compacto-design.md

## Global Constraints

- Cores só de `Tokens`; nada de `Color(0x…)` novo fora de lib/ui/design/tokens.dart.
- Texto em pt-PT; nomes de listas nos testes fictícios (001ALFA…); nenhuma credencial, MAC, token ou link completo.
- Foco sempre visível; tudo alcançável só com setas + OK + Voltar (+ Menu como atalho, nunca como único caminho).
- Mensagens com `mostrarMensagem`; teclas no fundo com `BarraTeclas`; campos de texto com `CampoTv`.
- `flutter analyze` sem avisos novos e `flutter test` verde antes de cada commit.

## Review Focus

1. Com a escala a 80 %, toques/rato acertam no sítio certo e diálogos, mensagens e menus também ficam a 80 %. — Task 1.
2. Mudar «Tamanho da interface» com a app aberta não perde o foco nem o estado do ecrã. — Task 1.
3. O vigia do topo não puxa o scroll quando há um controlo focável acima (p. ex. a meio de uma lista longa). — Task 2.
4. No Verificar, chips de estado múltiplos + ☐ do cabeçalho com pesquisa ativa selecionam só as visíveis; uma lista que sai do Gestor sai da seleção. — Task 3.
5. Tecla Menu com o foco num campo de texto não rouba a tecla ao campo; o menu «Ações» fecha com Voltar e devolve o foco. — Task 3.

---

### Task 1: Escala da interface

**Files:** Create `lib/ui/design/escala_interface.dart`; Modify `lib/dados/preferencias.dart`, `lib/main.dart` (builders das janelas da app; não a do vídeo do player), `lib/ui/definicoes/tela_definicoes.dart`; Test `test/ui/escala_interface_test.dart`, `test/dados/preferencias_test.dart`.

**Interfaces:**
- Produces: `enum TamanhoInterface { compacto, normal }`; `Preferencias.tamanhoInterface` (omissão `compacto`, chave `tamanhoInterface`, persistido com `_mudar`).
- Produces: `EscalaInterface({required double escala, required Widget child})` — com `escala < 1`, desenha o filho numa área de `tamanho / escala` (MediaQuery `size`, `padding`, `viewInsets`, `viewPadding` divididos) e reduz com `Transform.scale(alignment: Alignment.topLeft)`; com 1, devolve o filho.
- Produces: `double escalaPara(BuildContext context, TamanhoInterface t)` — 0,8 para compacto na TV (`ecraTv`) e no Windows/desktop; 1 no telemóvel e no modo normal.

- [ ] Testes que falham: `EscalaInterface(0.8)` numa janela 960×540 dá ao filho `MediaQuery.size == 1200×675`; um toque no centro de um botão no canto inferior direito ativa-o; um diálogo aberto dentro fica com o mesmo tamanho relativo; prefs: omissão compacto, persiste; Definições › Imagem e som mostra «Tamanho da interface» com «Compacto» / «Normal» como primeira opção e mudar aplica logo (o foco fica na opção).
- [ ] Correr → FALHAM. Implementar. Correr → PASSAM; suite + analyze.
- [ ] Commit `feat(interface): tamanho da interface (compacto a 80 % na TV e no Windows)`

### Task 2: Topo nunca cortado

**Files:** Create `lib/ui/design/revelar_topo.dart`; Modify `lib/main.dart` (instalar uma vez); Test `test/ui/revelar_topo_test.dart`.

**Interfaces:**
- Produces: `void instalarRevelarTopo()` / `RevelarTopo` — escuta `FocusManager.instance` (mudança do foco primário); se o novo foco está dentro de um `Scrollable` vertical e não existe nenhum nó focável (alcançável) desse mesmo `Scrollable` com `rect.top` acima do do foco, anima esse `Scrollable` para `minScrollExtent` (`Tokens.duracaoRapida`). Só com navegação por teclas (não ao tocar).

- [ ] Testes que falham: ecrã com título + chips + 50 linhas: descer até à linha 30, subir até ao primeiro chip → `offset == 0` e o título visível; subir da linha 30 à 29 → offset não vai a 0; um `Scrollable` horizontal (fila de filtros) não é mexido.
- [ ] Correr → FALHAM. Implementar. PASSAM; suite + analyze (atenção aos testes de D-pad existentes).
- [ ] Commit `fix(navegação): ao chegar ao primeiro controlo, a página volta ao topo`

### Task 3: Verificar simples

**Files:** Modify `lib/ui/gestor/passo_verificar.dart`, `lib/ui/gestor/tela_gestor.dart` (topo do passo 2 e indicador); Test `test/ui/passo_verificar_test.dart`, `test/ui/gestor_resumo_test.dart`.

**Interfaces:**
- Consumes: Task 1/2 (nada a chamar; só não lutar contra elas).
- Produces: `PassoVerificar` mantém `aoVerificar`, `aoVerificarTodas`, `aoRemover`, `aoVerVerificacao`; o estado do filtro passa a `Set<EstadoLista>` (vazio = todas); `PassoVerificarState.filtrar(Set<EstadoLista>)` substitui a versão de um estado (atualizar quem a chama).

- [ ] Testes que falham:
  - uma linha com a pesquisa e os chips `Funcionam · N`, `Inconclusivas · N`, `Não funcionam · N`, `Por verificar · N` (escolha múltipla; nenhum ligado mostra todas); não existe `Selecionar:` nem `Todas · N`;
  - ligar `Inconclusivas` + `Não funcionam` mostra só essas; a ☐ do cabeçalho seleciona exatamente as visíveis (com pesquisa também) e volta a desselecionar; estado misto mostra o traço;
  - botão `Ações (2)` no topo direito; abre um menu com `Verificar selecionadas`, `Verificar todas`, `Remover do gestor` (as de seleção desativadas com 0); Voltar fecha e o foco volta ao botão;
  - tecla Menu (`LogicalKeyboardKey.contextMenu`) numa linha abre o menu; num campo de texto a escrever não abre;
  - não há barra em baixo; o indicador no topo diz `nada a decorrer` sem verificação e `A verificar 2/5` a correr; OK nele chama `aoVerVerificacao` (só ativo se houve verificação);
  - na TV (960×540, com a escala da Task 1 a 0,8) cabem pelo menos 12 linhas visíveis; linhas com altura fixa baixa.
- [ ] Correr → FALHAM. Implementar (manter linhas preguiçosas; foco ao esvaziar a seleção cai no botão `Ações`).
- [ ] PASSAM; suite + analyze.
- [ ] Commit `feat(gestor): verificar simples — estados múltiplos, ☐ no cabeçalho e um botão Ações`

### Task 4: Lista aberta com filtro de grupos e pesquisa de canais

**Files:** Modify `lib/ui/conteudo/tela_conteudo.dart`; Test `test/ui/conteudo_pesquisa_test.dart` (atualizar) e testes de navegação do conteúdo.

- [ ] Testes que falham: campo `Filtrar grupos` (Key `filtro-grupos`) no topo da coluna dos grupos e campo `Pesquisar canais ou número` (Key `pesquisa-canais`) no topo da coluna dos canais; não existe a escolha `Tudo · Canais · Grupos`; filtrar grupos `desp` mostra só esses grupos e não mexe nos canais; pesquisar canais procura em todos os grupos (como antes da variante C) e mostra `Canais · N` completo com scroll; ↑ no primeiro grupo → filtro dos grupos; ↑ no primeiro canal → pesquisa dos canais; Voltar num campo com texto limpa-o; ecrã estreito (sem coluna dos grupos): só a pesquisa de canais; o teste dos 100 mil canais continua.
- [ ] Correr → FALHAM. Implementar (reaproveitar `_gruposSemAcentos` e o destaque `Tokens.anelFoco`). PASSAM; suite + analyze.
- [ ] Commit `feat(ver tv): filtro de grupos e pesquisa de canais separados`

### Task 5: Início e Gestor (resumo e Enviar) compactos

**Files:** Modify `lib/ui/inicio/tela_inicio.dart`, `lib/ui/inicio/cartao_lista.dart`, `lib/ui/inicio/cartao_continuar.dart`, `lib/ui/gestor/tela_gestor.dart` (resumo), `lib/ui/gestor/passo_enviar.dart`; Tests dos mesmos ecrãs.

- [ ] Testes que falham: Início na TV 960×540 (escala 0,8): «Continuar a ver» com altura ≤ 72 lógicos; pesquisa e filtros numa só linha; pelo menos 3 cartões por linha; resumo do Gestor: cartões com altura ≤ 160 e sem o texto de rodapé «Nenhum passo está aberto…»; Enviar: linhas com a mesma altura das do Verificar, chips de marcar numa linha, os dois destinos continuam alcançáveis com →.
- [ ] Correr → FALHAM. Implementar. PASSAM; suite + analyze (os testes de D-pad do Início e do Gestor continuam verdes).
- [ ] Commit `feat(interface): Início e Gestor mais compactos`

### Task 6: Definições em linhas

**Files:** Modify `lib/ui/definicoes/tela_definicoes.dart`, `lib/ui/definicoes/seletor_numero.dart` se preciso; Tests das Definições.

- [ ] Testes que falham: em cada categoria as opções são linhas (título + descrição à esquerda, controlo à direita, separador entre linhas, sem caixa/vidro à volta de cada opção); na TV 960×540 (escala 0,8) a categoria «Imagem e som» mostra pelo menos 5 opções sem scroll; os chips de escolha (desentrelaçamento, formato) ficam numa linha à direita ou por baixo do título quando não cabem.
- [ ] Correr → FALHAM. Implementar. PASSAM; suite + analyze.
- [ ] Commit `feat(definições): opções em linhas simples`
