# Motor de Xadrez CGD (com IA Alpha-Beta e Interface TUI)

Aplicação completa de xadrez escrita 100% em Delégua e compilada nativamente com o CGD.

## Recursos

- **Motor de regras completo**: tabuleiro 8×8, movimentação estritamente legal com verificação de segurança do rei, roque (com checagem de casas atacadas), en passant (incluindo pino horizontal), promoção, xeque, xeque-mate, afogamento, regra dos 50 lances, repetição tripla por hash Zobrist, material insuficiente, FEN, PGN e desfazer lances.
- **Engine de IA**: Negamax com poda Alpha-Beta, busca iterativa em profundidade, ordenação MVV-LVA, quiescence search, tabela de transposições com Zobrist 64-bit, Piece-Square Tables e controle de tempo.
- **Interface TUI (`cgd:interface/tui`)**: tabuleiro colorido Unicode com fallback ASCII (`--ascii`), navegação por teclado, destaque de movimentos legais, histórico, painel da engine (profundidade, avaliação, nós/s) e modos Humano×IA / Humano×Humano.

## Comandos

```sh
cd exemplos/jogos/xadrez
cgd testar
cgd rodar
cgd rodar -- --ascii
cgd rodar -- --perft 4
cgd rodar -- --auto 12 --profundidade 2
```
