// Exemplo para o MiniJS em Delegua / CGD.
function fibonacci(n) {
  if (n <= 1) {
    return n;
  }
  return fibonacci(n - 1) + fibonacci(n - 2);
}

function quadrado(x) {
  return x * x;
}

const usuario = { nome: 'Fernando', idade: 17 };
let numeros = [2, 4, 6];

console.log('MiniJS:', usuario.nome);
console.log('Fibonacci(10):', fibonacci(10));
console.log('Quadrado(9):', quadrado(9));
console.log('Array original:', numeros);

numeros[1] = 40;
usuario.idade = usuario.idade + 1;
console.log('Idade:', usuario.idade);
console.log('Array atualizado:', numeros);

let soma = 0;
for (let i = 0; i < numeros.length; i++) {
  soma = soma + numeros[i];
}
console.log('Soma:', soma);

let contador = 0;
while (contador < 3) {
  console.log('Contador:', contador);
  contador++;
}

{
  let soma = 999;
  console.log('Soma local:', soma);
}
console.log('Soma global:', soma);
console.log('Booleano:', true && !false);
console.log('Resto:', 17 % 5);
