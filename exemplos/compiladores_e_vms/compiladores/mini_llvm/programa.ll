; Mini-LLVM IR — Programa SSA executado e otimizado pelo Mini-LLVM em Delegua/CGD

define i64 @soma_ate(%n) {
entry:
    br label %loop
loop:
    %i = phi [1, %entry], [%i_next, %body]
    %acc = phi [0, %entry], [%acc_next, %body]
    %cond = icmp sle %i, %n
    br %cond, label %body, label %exit
body:
    %acc_next = add %acc, %i
    %i_next = add %i, 1
    br label %loop
exit:
    ret %acc
}

define i64 @fatorial(%n) {
entry:
    %base = icmp sle %n, 1
    br %base, label %caso_base, label %recursao
caso_base:
    ret 1
recursao:
    %n1 = sub %n, 1
    %sub = call @fatorial(%n1)
    %res = mul %n, %sub
    ret %res
}

define i64 @main() {
entry:
    %c1 = mul 6, 7
    %c2 = sub 10, 2
    %const_total = add %c1, %c2
    %lixo1 = mul %const_total, 99
    %lixo2 = add %lixo1, 123
    %sempre_falso = icmp slt 10, 5
    br %sempre_falso, label %bloco_morto, label %bloco_vivo
bloco_morto:
    %nunca = add 1, 2
    ret %nunca
bloco_vivo:
    %s = call @soma_ate(10)
    %f = call @fatorial(7)
    %parcial = add %const_total, %s
    %final = add %parcial, %f
    ret %final
}
