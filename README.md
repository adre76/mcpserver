# MCP Server

## Visão Geral

O **MCP Server** é uma solução para implantar e gerenciar um servidor de Modelo de Contexto de Protocolo (MCP) em um ambiente Kubernetes. Este projeto fornece todos os arquivos de configuração necessários para configurar um namespace, Persistent Volume Claim (PVC), ConfigMap, Deployment, Service e Ingress, permitindo uma implantação robusta e escalável do servidor MCP.

### Propósito

O objetivo principal deste repositório é simplificar a orquestração do MCP Server, abstraindo a complexidade da infraestrutura subjacente e permitindo que os desenvolvedores se concentrem na lógica da aplicação. Ao utilizar o Kubernetes, o projeto garante alta disponibilidade, escalabilidade e gerenciamento eficiente de recursos.

## Tecnologias Utilizadas

Este projeto faz uso das seguintes tecnologias e ferramentas:

*   **Kubernetes**: Plataforma de orquestração de contêineres para automação de implantação, escalonamento e gerenciamento de aplicações.
*   **Docker (ou similar)**: Para conteinerização da aplicação do MCP Server (assumindo que a imagem do servidor MCP já existe).
*   **YAML**: Linguagem de serialização de dados utilizada para os arquivos de configuração do Kubernetes.
*   **Bash Scripting**: Para automatizar o processo de implantação.

## Estrutura do Projeto

O repositório está organizado da seguinte forma:

```
mcpserver/
├── deploy.sh
├── 01 - namespace.yaml
├── 02 - pvc.yaml
├── 03 - configmap.yaml
├── 04 - deployment.yaml
├── 05 - service.yaml
├── 06 - ingress.yaml
└── README.md (Este arquivo)
```

*   `deploy.sh`: Um script shell para automatizar a aplicação das configurações do Kubernetes.
*   `01 - namespace.yaml`: Define o namespace Kubernetes para isolar os recursos do MCP Server.
*   `02 - pvc.yaml`: Configura um Persistent Volume Claim para armazenamento persistente de dados.
*   `03 - configmap.yaml`: Gerencia dados de configuração para o servidor MCP.
*   `04 - deployment.yaml`: Define o deployment do servidor MCP, especificando a imagem do contêiner, réplicas e recursos.
*   `05 - service.yaml`: Expõe o servidor MCP dentro do cluster Kubernetes.
*   `06 - ingress.yaml`: Configura o acesso externo ao servidor MCP via HTTP/HTTPS.

## Implantação (Deployment)

Para implantar o MCP Server em seu cluster Kubernetes, siga os passos abaixo:

### Pré-requisitos

*   Um cluster Kubernetes em funcionamento.
*   `kubectl` configurado para se comunicar com seu cluster.
*   Uma imagem Docker do MCP Server disponível em um registro de contêineres acessível pelo seu cluster.
*   Um controlador de Ingress (como Nginx Ingress Controller) instalado no seu cluster, se você pretende usar o `ingress.yaml`.

### Passos para Implantação

1.  **Clone o Repositório**:

    ```bash
    git clone https://github.com/adre76/mcpserver.git
    cd mcpserver
    ```

2.  **Revise e Ajuste as Configurações**:

    Antes de implantar, revise os arquivos `.yaml` e `deploy.sh` para garantir que as configurações (como nomes de imagem, recursos, nomes de host do Ingress, etc.) estejam alinhadas com suas necessidades e ambiente.

    *   No `04 - deployment.yaml`, certifique-se de que a `image` do contêiner aponta para a imagem correta do seu MCP Server.
    *   No `06 - ingress.yaml`, atualize o `host` e o `path` para corresponder ao seu domínio e caminho desejados.

3.  **Execute o Script de Implantação**:

    O script `deploy.sh` aplica todos os arquivos de configuração na ordem correta:

    ```bash
    ./deploy.sh
    ```

    Este script executará os seguintes comandos:

    ```bash
    kubectl apply -f 01 - namespace.yaml
    kubectl apply -f 02 - pvc.yaml
    kubectl apply -f 03 - configmap.yaml
    kubectl apply -f 04 - deployment.yaml
    kubectl apply -f 05 - service.yaml
    kubectl apply -f 06 - ingress.yaml
    ```

4.  **Verifique a Implantação**:

    Após a execução do script, você pode verificar o status dos seus recursos Kubernetes:

    ```bash
    kubectl get all -n mcpserver
    kubectl get ingress -n mcpserver
    ```

    Aguarde até que todos os pods estejam em estado `Running` e o Ingress esteja configurado corretamente.

## Uso

Uma vez que o MCP Server esteja implantado e acessível via Ingress, você poderá interagir com ele através do endereço configurado no `06 - ingress.yaml`.

Por exemplo, se o seu Ingress estiver configurado para `mcp.example.com`:

*   Acesse `http://mcp.example.com` (ou `https://mcp.example.com` se TLS estiver configurado) através do seu navegador ou cliente API.

## Contribuição

Contribuições são bem-vindas! Se você tiver sugestões, melhorias ou encontrar problemas, por favor, abra uma issue ou envie um pull request. Certifique-se de seguir as melhores práticas de código e documentação.

## Licença

Este projeto está licenciado sob a [Licença MIT](LICENSE).
