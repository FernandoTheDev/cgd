; Mini-RISC Assembly — Programa executado pelo emulador de CPU em Delegua/CGD
; Registradores: r0 (zero), r1..r13 (uso geral), r14 (sp), r15 (lr)

    ; 1. MDC(252, 105) usando algoritmo de Euclides
    MOVI r1, 252
    MOVI r2, 105
    CALL mdc
    PRINT r1

    ; 2. Fatorial recursivo(8) usando pilha (PUSH/POP de lr e argumentos)
    MOVI r1, 8
    CALL fatorial
    PRINT r1

    ; 3. Bubble Sort in-place na RAM (enderecos 0..5): [42, 7, 19, 3, 25, 11]
    MOVI r10, 0
    MOVI r1, 42
    STORE r1, r10, 0
    MOVI r1, 7
    STORE r1, r10, 1
    MOVI r1, 19
    STORE r1, r10, 2
    MOVI r1, 3
    STORE r1, r10, 3
    MOVI r1, 25
    STORE r1, r10, 4
    MOVI r1, 11
    STORE r1, r10, 5

    MOVI r1, 0
    MOVI r2, 6
    CALL bubble_sort

    ; Imprime vetor ordenado
    MOVI r3, 0
    MOVI r4, 6
print_loop:
    CMP r3, r4
    JGE fim_programa
    LOAD r1, r3, 0
    PRINT r1
    ADDI r3, r3, 1
    JMP print_loop

fim_programa:
    HALT

; --- Sub-rotina mdc(r1, r2) -> r1 ---
mdc:
    CMP r2, zero
    JEQ mdc_fim
    MOD r3, r1, r2
    MOV r1, r2
    MOV r2, r3
    JMP mdc
mdc_fim:
    RET

; --- Sub-rotina fatorial(r1) -> r1 ---
fatorial:
    MOVI r2, 1
    CMP r1, r2
    JLE fat_base
    PUSH lr
    PUSH r1
    SUBI r1, r1, 1
    CALL fatorial
    POP r2
    POP lr
    MUL r1, r1, r2
    RET
fat_base:
    MOVI r1, 1
    RET

; --- Sub-rotina bubble_sort(r1 = base, r2 = n) ---
bubble_sort:
    MOVI r3, 0
bs_externo:
    SUBI r4, r2, 1
    CMP r3, r4
    JGE bs_fim
    MOVI r5, 0
    SUB r6, r4, r3
bs_interno:
    CMP r5, r6
    JGE bs_prox_ext
    ADD r7, r1, r5
    LOAD r8, r7, 0
    LOAD r9, r7, 1
    CMP r8, r9
    JLE bs_sem_troca
    STORE r9, r7, 0
    STORE r8, r7, 1
bs_sem_troca:
    ADDI r5, r5, 1
    JMP bs_interno
bs_prox_ext:
    ADDI r3, r3, 1
    JMP bs_externo
bs_fim:
    RET
