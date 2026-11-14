# Exemplos executáveis

Cada arquivo possui um contrato de teste na primeira linha. Rode todos com
`python3 testes/exemplos.py`: cada exemplo é compilado com e sem otimização,
sem ignorar arquivos. O runner histórico `rdmd testes/unitario.d` também valida
o catálogo, incluindo a entrada padrão dos exemplos interativos.

```sh
mkdir -p out
./cgd exemplos/linguagem/14_classes.delegua -s out/classes
./out/classes
```

## Percurso pela linguagem

| Exemplo | Recurso |
| --- | --- |
| [01_tipos.delegua](linguagem/01_tipos.delegua) | Tipos e valores |
| [02_operadores.delegua](linguagem/02_operadores.delegua) | Operadores |
| [03_atribuicoes.delegua](linguagem/03_atribuicoes.delegua) | Atribuições múltiplas |
| [04_condicionais.delegua](linguagem/04_condicionais.delegua) | Condicionais e escolha |
| [05_lacos.delegua](linguagem/05_lacos.delegua) | Laços e controle |
| [06_lacos_resultado.delegua](linguagem/06_lacos_resultado.delegua) | Laços como expressões |
| [07_funcoes.delegua](linguagem/07_funcoes.delegua) | Parâmetros padrão e variáveis |
| [08_funcoes_valores.delegua](linguagem/08_funcoes_valores.delegua) | Funções como valores e callbacks |
| [09_vetores.delegua](linguagem/09_vetores.delegua) | Métodos de vetores |
| [10_compreensao_fatias.delegua](linguagem/10_compreensao_fatias.delegua) | Compreensão e fatias |
| [11_dicionarios.delegua](linguagem/11_dicionarios.delegua) | Dicionários e desestruturação |
| [12_tuplas.delegua](linguagem/12_tuplas.delegua) | Tuplas e contratos |
| [13_texto_unicode.delegua](linguagem/13_texto_unicode.delegua) | Texto e Unicode |
| [14_classes.delegua](linguagem/14_classes.delegua) | Classes |
| [15_heranca.delegua](linguagem/15_heranca.delegua) | Herança e métodos ligados |
| [16_privacidade_acessores.delegua](linguagem/16_privacidade_acessores.delegua) | Privacidade e acessores |
| [17_excecoes.delegua](linguagem/17_excecoes.delegua) | Exceções |
| [18_finalmente_retorno.delegua](linguagem/18_finalmente_retorno.delegua) | Finalmente em retornos e laços |
| [19_excecoes_tipadas.delegua](linguagem/19_excecoes_tipadas.delegua) | Exceções tipadas |
| [20_clonagem.delegua](linguagem/20_clonagem.delegua) | Clonagem e ciclos |
| [21_biblioteca.delegua](linguagem/21_biblioteca.delegua) | Biblioteca nativa |
| [22_contratos_aliases.delegua](linguagem/22_contratos_aliases.delegua) | Contratos através de aliases |
| [23_decoradores.delegua](linguagem/23_decoradores.delegua) | Decoradores |
| [24_assercoes.delegua](linguagem/24_assercoes.delegua) | Asserções |
| [25_escopos.delegua](linguagem/25_escopos.delegua) | Escopos e funções internas sem captura |
| [26_ctfe.delegua](linguagem/26_ctfe.delegua) | Avaliação em compilação |
| [27_entrada.delegua](linguagem/27_entrada.delegua) | Entrada padrão |

| [28_metodos_texto.delegua](linguagem/28_metodos_texto.delegua) | Métodos de texto |
| [29_metodos_numero.delegua](linguagem/29_metodos_numero.delegua) | Métodos de número |
| [30_metodos_vetor.delegua](linguagem/30_metodos_vetor.delegua) | Métodos de vetor |
| [31_metodos_dicionario.delegua](linguagem/31_metodos_dicionario.delegua) | Métodos de dicionário |
| [32_objeto_e_metodos.delegua](linguagem/32_objeto_e_metodos.delegua) | Métodos de Objeto |
| [33_aleatoriedade.delegua](linguagem/33_aleatoriedade.delegua) | Intervalos de aleatoriedade |
| [34_lacos_variantes.delegua](linguagem/34_lacos_variantes.delegua) | Variações de laços |
| [35_bits_e_atribuicoes.delegua](linguagem/35_bits_e_atribuicoes.delegua) | Bits e atribuições |

## Módulos

[Importação](modulos/01_importacao.delegua) usa a
[biblioteca local](modulos/lib/calculos.delegua). O caminho de importação é
relativo à fonte que o declara. A biblioteca também possui contrato e é validada
como unidade independente.

## Exemplos de falhas esperadas

Os arquivos em [seguranca/](seguranca/) são exemplos de proteção do compilador ou
do runtime: capturas, FFI, importação dinâmica, privacidade, contrato indireto,
imutabilidade de tuplas e overflow. Não devem encerrar com sucesso.

## Contratos

- `//! texto`: exige compilação bem-sucedida, status 0 e a saída indicada; `\n` representa nova linha.
- `//# N`: exige o status N na compilação ou execução, para compatibilidade com o catálogo histórico.
- `//? fase: compilacao` ou `execucao`: fixa a fase da falha nos exemplos novos.
- `//? erro: trecho`: exige que o diagnóstico contenha o trecho.
- `//? entrada: Ada\n`: fornece a entrada padrão, preservando testes reproduzíveis.
- `//$`: marcador histórico de otimização; o runner Python testa os dois modos independentemente dele.

Os exemplos históricos na raiz e em `ctfe/` continuam fazendo parte da suíte.
Nenhum exemplo demonstra carregamento nativo arbitrário como recurso permitido.
