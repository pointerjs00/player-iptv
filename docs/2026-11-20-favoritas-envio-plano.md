# Listas favoritas, envio com filtros a manter, marcação por estado e «Ver TV» — plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Listas favoritas em Ver TV, envio com filtros a manter, marcação por estado no passo 3 e «Ver TV» em vez de «Player» no Gestor.

**Architecture:** Campo novo `Lista.favorita` na biblioteca; `Biblioteca.receber` passa a receber um conjunto de filtros a manter; chips de escolha múltipla no diálogo de envio e no passo 3; textos do Gestor revistos.

**Tech Stack:** Flutter 3.50 / Dart 3.14, `package:material_ui/material_ui.dart`, flutter_test.

**Spec:** docs/2026-11-20-favoritas-envio-design.md

## Global Constraints

- Textos exatos do spec; pt-PT; cores de `Tokens`; mensagens com `mostrarMensagem`.
- Foco sempre visível; tudo alcançável com setas + OK + Voltar (chips focáveis, OK liga/desliga).
- Listas guardadas antes desta mudança continuam a abrir (campo novo opcional).
- Nada de credenciais, MACs, tokens ou links em código, testes ou logs; nomes fictícios nos testes.
- `flutter analyze` sem avisos; `flutter test` verde; sem asserções de tempo de parede.

## Review Focus

1. Biblioteca antiga sem `favorita` abre igual e a cópia de segurança restaura as favoritas. — Task 1.
2. «Substituir» com «Favoritas» + «As que funcionam» mantém a união, não a interseção; uma enviada que já era favorita continua favorita. — Task 2.
3. Passo 3: desligar «Inconclusivas» depois de marcar à mão uma lista inconclusiva desmarca-a; «Todas» fica ligado só com tudo marcado. — Task 3.
4. Nenhum texto do Gestor (nem mensagens, nem resumos) ainda diz «Player» isolado. — Task 4.

---

### Task 1: Listas favoritas em Ver TV

**Files:** Modify `lib/dados/biblioteca.dart` (Lista + guardar/ler + `alternarFavorita(String id)`), `lib/ui/inicio/cartao_lista.dart`, `lib/ui/inicio/acoes_lista.dart`, `lib/ui/inicio/tela_inicio.dart`; Tests `test/dados/biblioteca_test.dart`, `test/ui/inicio_test.dart` (ou novo `inicio_favoritas_test.dart`).

**Interfaces:** Produces `bool Lista.favorita`; `Future<void> Biblioteca.alternarFavorita(String id)`.

- [ ] Testes que falham: guardar/reler mantém `favorita`; JSON antigo sem o campo → false; cópia de segurança restaura; no Início, «Pôr nas favoritas» no menu da lista põe a estrela e o chip «Favoritas» mostra só as favoritas; «Tirar das favoritas» tira; D-pad chega ao chip «Favoritas».
- [ ] FALHAM → implementar → PASSAM; suite + analyze.
- [ ] Commit `feat(ver tv): listas favoritas`

### Task 2: Envio — filtros a manter ao substituir

**Files:** Modify `lib/dados/biblioteca.dart` (`ModoEnvio`, `receber`), `lib/ui/verificar/dialogos_gestor.dart` (`perguntarEnvio`), `lib/ui/gestor/tela_gestor.dart` (quem chama); Tests do diálogo e da biblioteca.

**Interfaces:** Produces `enum ManterAoSubstituir { favoritas, funcionam, inconclusivas }`; `ModoEnvio { adicionar, substituir }`; `Biblioteca.receber(Iterable<Lista> doGestor, ModoEnvio modo, {Set<ManterAoSubstituir> manter = const {}})`; `perguntarEnvio(context, {required int n}) -> Future<(ModoEnvio, Set<ManterAoSubstituir>)?>`.

- [ ] Testes que falham: diálogo com «Substituir» mostra os chips «Nenhuma», «Favoritas», «As que funcionam», «As inconclusivas» com «Favoritas» ligado; «Nenhuma» desliga os outros e vice-versa; desligar o último liga «Nenhuma»; o texto descreve o que fica; `receber(substituir, {favoritas, funcionam})` mantém a união; enviadas iguais a uma favorita continuam favoritas; resumo com contagens.
- [ ] FALHAM → implementar → PASSAM; suite + analyze.
- [ ] Commit `feat(gestor): ao substituir, escolher o que manter (Favoritas por omissão)`

### Task 3: Passo 3 — marcação por estado

**Files:** Modify `lib/ui/gestor/passo_enviar.dart`; Tests `test/ui/passo_enviar_test.dart`.

- [ ] Testes que falham: chips «Funcionam (N)», «Inconclusivas (N)», «Não funcionam (N)», «Por verificar (N)», «Todas (N)», «Nenhuma»; ligar «Inconclusivas» marca as inconclusivas sem tocar nas outras; desligar desmarca-as; estado ligado = todas desse estado marcadas; marcar à mão a última que faltava liga o chip; «Todas» liga tudo e fica ligado; «Nenhuma» desmarca tudo; chip sem listas desativado; D-pad percorre os chips.
- [ ] FALHAM → implementar → PASSAM; suite + analyze.
- [ ] Commit `feat(gestor): passo 3 com marcação por estado, Todas e Nenhuma`

### Task 4: «Ver TV» em vez de «Player» no Gestor

**Files:** `lib/ui/gestor/*.dart`, `lib/ui/verificar/dialogos_gestor.dart`, e quem mostrar mensagens que vêm do Gestor; Tests que fixam os textos.

- [ ] Teste que falha: percorre os ecrãs do Gestor (resumo, importar com «De Ver TV», verificar, enviar, diálogo de envio, mensagens de fim) e falha se algum texto visível contiver «Player» que não seja «Player IPTV» ou «Stalker Portal Player».
- [ ] FALHA → trocar os textos (ver spec) → PASSA; atualizar testes que fixavam os textos antigos; suite + analyze.
- [ ] Commit `fix(gestor): «Ver TV» em vez de «Player» nos textos`
