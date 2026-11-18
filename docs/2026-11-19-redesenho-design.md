# Redesenho da app — desenho

Data: 2026-11-19 · Mockups aprovados: https://claude.ai/artifact/7BUwpd195zP4MpvFCsDw3F (ecrãs 1–12 e 10b)

## Intenção

Tornar a app mais clara, coerente e fácil no comando (TV/Fire TV), no Windows e no telemóvel,
sem perder nenhuma funcionalidade. Cada ação dá sempre uma resposta visível. O Gestor nunca obriga
a esperar: tudo o que demora corre em segundo plano e pode-se navegar para qualquer ecrã.

## Objetivos

- Cores à volta do azul (tokens novos, contraste ≥ 4,5:1 para texto).
- Três secções fixas: **Ver TV**, **Gestor**, **Definições** — barra lateral (largura ≥ 900 px)
  ou barra em baixo (telemóvel). Cada secção guarda o seu estado ao trocar.
- Ver TV: Início (continuar a ver, favoritos de todas as listas, listas com estado) → lista aberta
  (grupos à esquerda; canais **um por linha**: número, logótipo, nome, estrela; sem bloco à direita)
  → player. Opções da lista com OK mantido.
- Player: número + nome + "Lista › Grupo · em direto"; ← painel de canais; → ajustes rápidos
  (áudio, legendas, formato, desentrelaçamento Automático/Ligado/Desligado, volume, modo compatível);
  cartão de erro com Tentar de novo / Modo compatível / Canal visto antes / Voltar à lista.
- Gestor: ecrã principal (passos 1 Importar · 2 Verificar · 3 Enviar ou exportar sempre visíveis,
  filtros por estado, seleção múltipla, barra de ações, indicador de atividade), Importar (4 origens
  + resumo), Verificação (progresso por cor, contagens, motivo por lista, fila), Enviar/Exportar,
  Atividade (tarefas em curso e terminadas).
- Mesmo vocabulário de estados em todo o lado: Funciona · Inconclusiva · Não funciona · Por verificar.
- "Vistos há pouco" (persistido) como grupo na lista aberta.
- Mensagens no canto superior direito, com "Desfazer" onde se pode (favorito, esconder grupo).
- Barra de teclas no fundo dos ecrãs de TV.

## Não-objetivos

- Guia de programação (EPG): fora — não existe nos protocolos atuais; fase própria se se quiser.
- Pré-visualização ao vivo na lista: fora — gasta a única ligação de muitas contas e pesa no Fire TV.
- Estado por canal (além dos canais de teste): fora.
- Filmes e séries.

## Anti-objetivos

- Um botão desligado "à espera" no Gestor.
- Perder o progresso/resultado de uma tarefa por mudar de ecrã.
- Credenciais, MACs ou links completos visíveis em mensagens, registos ou mockups.

## Restrições

- Flutter 3.50 / Dart 3.14; `package:material_ui/material_ui.dart`; media_kit vendorizado.
- Todas as cores via `Tokens` (nada de cores soltas).
- D-pad: o foco vê-se sempre (anel azul-claro), nada fica preso; os testes de D-pad existentes
  (test/ui/dpad_regressoes_test.dart, ajuda_dpad.dart) continuam a passar.
- "Copiar link" só no Windows (leva os dados de acesso).
- Esperas que ficam: o seletor de ficheiros do sistema e as confirmações de remover/limpar/substituir.

## Abordagens consideradas

1. **Refazer só o aspeto (tokens + estilos)** — barato, mas não resolve a navegação nem as esperas do Gestor.
2. **Nova casca de navegação + ecrãs refeitos sobre os serviços atuais + serviço de tarefas** — escolhida:
   reaproveita Biblioteca, AreaGestor, ServicoVerificacao, importar/exportar; muda a UI e põe o
   trabalho longo fora dos widgets.
3. **Reescrever a app de raiz** — risco alto, perde as correções de D-pad/player acumuladas.

## Decisões do desenho (do utilizador)

Azul; mockups A simplificados → estrutura completa; só canais em direto; canais um por linha sem
bloco à direita; Gestor sempre navegável sem esperas.

## Deixado ao implementador

Animações, tamanhos exatos fora dos tokens, textos de ajuda secundários (pt-PT, frases curtas).
