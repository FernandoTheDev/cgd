\ MiniForth — Programa de demonstracao em linguagem concatenativa
\ Executado pelo compilador/VM MiniForth escrito em Delegua/CGD

( 1. Definicao de palavras compostas )
: QUADRADO ( n -- n^2 ) DUP * ;
: SOMA-QUADRADOS ( a b -- a^2+b^2 ) QUADRADO SWAP QUADRADO + ;

." Soma dos quadrados (3, 4): " 3 4 SOMA-QUADRADOS . CR

( 2. Fatorial iterativo usando DO ... LOOP e I )
: FATORIAL ( n -- n! )
    1 SWAP 1 + 1 DO
        I *
    LOOP ;

." Fatorial(7): " 7 FATORIAL . CR

( 3. Fibonacci recursivo usando RECURSE e IF ... ELSE ... THEN )
: FIB ( n -- fib[n] )
    DUP 2 < IF
        \ caso base: retorna n
    ELSE
        DUP 1 - RECURSE
        SWAP 2 - RECURSE
        +
    THEN ;

." Fibonacci(11): " 11 FIB . CR

( 4. Teste de primalidade com BEGIN ... WHILE ... REPEAT e VARIABLE )
: PRIMO? ( n -- flag )
    DUP 2 < IF DROP 0 ELSE
        2 ( pilha: n d )
        BEGIN
            2DUP DUP * >= ( d*d <= n )
        WHILE
            2DUP MOD 0= IF
                DROP DROP 0 EXIT
            THEN
            1 +
        REPEAT
        DROP DROP -1
    THEN ;

VARIABLE TOTAL-PRIMOS
0 TOTAL-PRIMOS !

." Primos ate 30:"
31 2 DO
    I PRIMO? IF
        I .
        TOTAL-PRIMOS @ 1 + TOTAL-PRIMOS !
    THEN
LOOP CR
." Quantidade de primos: " TOTAL-PRIMOS @ . CR
