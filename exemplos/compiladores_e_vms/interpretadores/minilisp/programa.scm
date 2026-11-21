; MiniLisp — Programa de demonstracao executado pelo interpretador em Delegua/CGD
; Demonstra recursao, closures lexicas com estado, currying, funcoes de alta ordem e quicksort.

; 1. Fatorial e Fibonacci
(define (fatorial n)
  (if (<= n 1)
      1
      (* n (fatorial (- n 1)))))

(define (fib n)
  (cond ((<= n 1) n)
        (else (+ (fib (- n 1)) (fib (- n 2))))))

(display (str-concat "Fatorial(10): " (fatorial 10)))
(display (str-concat "Fibonacci(12): " (fib 12)))

; 2. Closures lexicas com estado mutavel (set!)
(define (criar-contador inicio passo)
  (let ((atual inicio))
    (lambda ()
      (let ((valor atual))
        (set! atual (+ atual passo))
        valor))))

(define c1 (criar-contador 10 5))
(define c2 (criar-contador 1 1))
(display (str-concat "Contadores: " (list (c1) (c1) (c2) (c1) (c2))))

; 3. Currying e composicao de funcoes
(define (somador base)
  (lambda (x) (+ base x)))

(define (compor f g)
  (lambda (x) (f (g x))))

(define somar-10 (somador 10))
(define dobrar (lambda (x) (* x 2)))
(define dobrar-e-somar-10 (compor somar-10 dobrar))
(display (str-concat "Composicao(7): " (dobrar-e-somar-10 7)))

; 4. Funcoes de alta ordem (map, filter, foldl) escritas em MiniLisp
(define (map f xs)
  (if (null? xs)
      '()
      (cons (f (car xs)) (map f (cdr xs)))))

(define (filter pred xs)
  (if (null? xs)
      '()
      (if (pred (car xs))
          (cons (car xs) (filter pred (cdr xs)))
          (filter pred (cdr xs)))))

(define (foldl f acc xs)
  (if (null? xs)
      acc
      (foldl f (f acc (car xs)) (cdr xs))))

(define numeros '(1 2 3 4 5 6 7 8))
(define pares (filter (lambda (x) (= (mod x 2) 0)) numeros))
(define quadrados-pares (map (lambda (x) (* x x)) pares))
(define soma-quadrados (foldl + 0 quadrados-pares))

(display (str-concat "Quadrados pares: " quadrados-pares))
(display (str-concat "Soma dos quadrados pares: " soma-quadrados))

; 5. Quicksort funcional puro usando filter e append
(define (quicksort xs)
  (if (null? xs)
      '()
      (let* ((pivo (car xs))
             (resto (cdr xs))
             (menores (filter (lambda (x) (< x pivo)) resto))
             (maiores (filter (lambda (x) (>= x pivo)) resto)))
        (append (quicksort menores) (cons pivo (quicksort maiores))))))

(define desordenado '(9 3 7 1 8 2 6 4 5))
(display (str-concat "Quicksort: " (quicksort desordenado)))
