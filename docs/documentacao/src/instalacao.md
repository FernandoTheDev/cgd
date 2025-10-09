# Instalação

> ⚠️ **Sem suporte ao Windows**

Guia completo para instalar o CGD (Compilador Geral Delégua) em diferentes sistemas operacionais.

## Instalação Automática (Recomendada)

A forma mais rápida e simples de instalar o CGD:

### Linux/macOS

```bash
# Instalar CGD automaticamente
curl -fsSL https://raw.githubusercontent.com/FernandoTheDev/cgd/main/install.sh | sh

# Verificar instalação
cgd --help
```

> **O que o script faz:**
> - Detecta seu sistema operacional automaticamente
> - Instala dependências necessárias (LDC e DUB)
> - Baixa e compila o CGD com otimizações
> - Instala o binário em `~/.local/bin/` (sem necessidade de sudo)
> - Configura o PATH automaticamente

## Instalação Manual

### Pré-requisitos

Para usar o CGD, você precisa ter instalado:

- **[LDC (LLVM D Compiler)](https://github.com/ldc-developers/ldc/releases)** - Compilador D baseado em LLVM
- **[DUB (D Package Manager)](https://dub.pm/getting-started/install/)** - Gerenciador de pacotes do D

### Instalação das Dependências

#### Ubuntu/Debian

```bash
# Atualizar repositórios
sudo apt update

# Instalar LDC e DUB
sudo apt install -y ldc dub

# Verificar instalação
ldc2 --version && dub --version
```

#### Fedora

```bash
# Instalar dependências
sudo dnf install -y ldc dub

# Verificar instalação
ldc2 --version && dub --version
```

#### CentOS/RHEL

```bash
# Habilitar repositório EPEL
sudo dnf install -y epel-release

# Instalar dependências
sudo dnf install -y ldc dub

# Verificar instalação
ldc2 --version && dub --version
```

#### macOS

```bash
# Instalar via Homebrew (recomendado)
brew install ldc dub

# Verificar instalação
ldc2 --version && dub --version
```

### Compilação e Instalação

```bash
# 1. Clonar o repositório
git clone https://github.com/FernandoTheDev/cgd.git
cd cgd

# 2. Compilar com otimizações
dub build --build=release

# 3. Testar o executável
./cgd --help

# 4. Instalar localmente
mkdir -p ~/.local/bin
cp cgd ~/.local/bin/
chmod +x ~/.local/bin/cgd

# 5. Atualizar PATH (escolha seu shell)
# Para Bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Para Zsh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Para Fish
echo 'set -gx PATH $HOME/.local/bin $PATH' >> ~/.config/fish/config.fish
```

## Verificação da Instalação

Após a instalação, verifique se tudo está funcionando:

```bash
# Verificar versão do CGD
cgd --version

# Verificar dependências
ldc2 --version
dub --version

# Testar ajuda
cgd --help
```

## Solução de Problemas

### Comando não encontrado

Se você receber erro de "comando não encontrado":

```bash
# Verificar se ~/.local/bin está no PATH
echo $PATH | grep -q "$HOME/.local/bin" && echo "PATH OK" || echo "PATH precisa ser configurado"

# Adicionar ao PATH temporariamente
export PATH="$HOME/.local/bin:$PATH"

# Adicionar permanentemente (escolha seu shell)
# Bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc

# Zsh  
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc

# Fish
echo 'set -gx PATH $HOME/.local/bin $PATH' >> ~/.config/fish/config.fish
```

### Dependências não encontradas

#### Ubuntu 18.04/20.04 (versões antigas do LDC)

```bash
# Adicionar PPA com versão mais recente
sudo add-apt-repository ppa:dlang/ldc
sudo apt update
sudo apt install ldc dub
```

#### macOS com Apple Silicon

```bash
# Para M1/M2, use:
arch -arm64 brew install ldc dub

# Se houver problemas, tente a versão x86_64:
arch -x86_64 brew install ldc dub
```

#### Instalação manual do LDC (se necessário)

```bash
# Linux x86_64
wget https://github.com/ldc-developers/ldc/releases/latest/download/ldc2-*-linux-x86_64.tar.xz
tar -xf ldc2-*-linux-x86_64.tar.xz
sudo cp -r ldc2-*/bin/* /usr/local/bin/
sudo cp -r ldc2-*/lib/* /usr/local/lib/
sudo cp -r ldc2-*/include/* /usr/local/include/
```

### Problemas de permissão

```bash
# Instalação local (recomendada - sem sudo)
mkdir -p ~/.local/bin
cp cgd ~/.local/bin/
chmod +x ~/.local/bin/cgd

# Ou instalação global (com sudo)
sudo cp cgd /usr/local/bin/
sudo chmod +x /usr/local/bin/cgd
```

### Problemas de SELinux (Fedora/CentOS/RHEL)

```bash
# Se SELinux bloquear a execução
sudo setsebool -P allow_execheap 1
sudo restorecon -R ~/.local/bin/cgd
```

## Desinstalação

### Remover CGD

```bash
# Instalação local
rm ~/.local/bin/cgd

# Instalação global
sudo rm /usr/local/bin/cgd

# Código fonte (se instalou manualmente)
rm -rf ~/cgd
```

### Remover dependências (opcional)

```bash
# Ubuntu/Debian
sudo apt remove ldc dub

# Fedora/CentOS/RHEL
sudo dnf remove ldc dub

# macOS
brew uninstall ldc dub
```

## Atualização

### Via script automático

```bash
# Re-executar o script de instalação
curl -fsSL https://raw.githubusercontent.com/FernandoTheDev/cgd/main/install.sh | sh
```

### Manual

```bash
cd cgd
git pull origin main
dub build --build=release
cp cgd ~/.local/bin/
```

## Próximos Passos

Após a instalação bem-sucedida:

1. **Teste básico**: Execute `cgd --help` para ver todas as opções
2. **Primeiro programa**: Crie um arquivo `.delegua` e compile com `cgd compilar arquivo.delegua`
3. **Documentação**: Consulte a documentação completa da linguagem
4. **Exemplos**: Explore o diretório de exemplos no repositório

## Suporte

Se encontrar problemas durante a instalação:

1. Verifique se todas as dependências estão instaladas corretamente
2. Consulte a seção de solução de problemas acima
3. Abra uma [issue no GitHub](https://github.com/FernandoTheDev/cgd/issues) com detalhes do seu sistema operacional e erro encontrado

---

**Sistemas testados:**
- Ubuntu 20.04+ ✅
- Debian 11+ ✅  
- Fedora 40+ ✅
- CentOS/RHEL 8+ ✅
- macOS 11+ (Intel/Apple Silicon) ✅
