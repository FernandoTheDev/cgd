<p align="center">
  <img src="docs/assets/logo.png" width="150" alt="cgd logo"/>
</p>

[![Versão](https://img.shields.io/badge/versão-v0.0.6-blue.svg)](https://github.com/fernandothedev/cgd)

# CGD - Compilador Geral Delégua

Compilador para a linguagem de programação [Delegua](https://github.com/DesignLiquido/delegua).

## ⚠️ AVISO - Branch LLVM (Experimental)

**Esta é a branch `llvm` - uma reescrita completa do core do compilador!**

### O que mudou

- **Reescrita total**: Todo o backend foi reescrito para usar LLVM diretamente
- **100% Instável**: Esta branch está em desenvolvimento ativo e pode quebrar a qualquer momento

### Vantagens do novo backend LLVM

- **Performance superior**: Otimizações LLVM de nível industrial
- **Compilação direta**: Sem transpilação intermediária para D
- **Controle granular**: Otimizações personalizadas para Delegua
- **Melhor debugging**: Informações de debug nativas
- **Multi-plataforma**: Suporte nativo para mais arquiteturas

### Use por sua conta e risco

- Funcionalidades podem estar incompletas
- Quebras de compatibilidade frequentes
- Documentação desatualizada
- Para produção, use a branch `main` ou alguma tag disponível

---

## Licença

Este projeto está licenciado sob a Licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.

## Links úteis

- [Site oficial do CGD](https://fernandothedev.github.io/cgd/)
- [Linguagem Delegua](https://github.com/DesignLiquido/delegua)
- [LDC Compiler](https://github.com/ldc-developers/ldc)
- [DUB Package Manager](https://dub.pm/)
- [Documentação do D](https://dlang.org/)
