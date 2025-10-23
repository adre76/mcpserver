# Ollama FastMCP Server no Kubernetes

Este projeto demonstra como implantar um servidor FastMCP no Kubernetes para expor a API do Ollama como ferramentas MCP (Model Context Protocol). O objetivo é permitir que modelos de linguagem (LLMs) interajam com o Ollama de forma estruturada e eficiente, além de preparar o ambiente para futuras integrações com outras APIs.

## Visão Geral

O servidor FastMCP atua como uma camada de abstração, transformando os endpoints da API REST do Ollama em ferramentas MCP que podem ser consumidas por LLMs. A implantação é realizada em um cluster Kubernetes, utilizando os seguintes componentes:

- **Namespace**: `fastmcp-server` para isolar os recursos do projeto.
- **ConfigMap**: Contém o código Python do servidor FastMCP (`server.py`) e as dependências (`requirements.txt`).
- **Deployment**: Gerencia a implantação do servidor FastMCP, utilizando uma imagem Python leve e montando o ConfigMap e o PersistentVolumeClaim.
- **Service**: Expõe o servidor FastMCP dentro do cluster.
- **PersistentVolumeClaim (PVC)**: Provisão de armazenamento persistente usando `local-path` para dados do FastMCP (se necessário).
- **Ingress NGINX**: Roteia o tráfego externo para o serviço FastMCP através do hostname `mcpserver.local`.

## Pré-requisitos

Antes de implantar este projeto, certifique-se de que você tem:

- Um cluster Kubernetes (por exemplo, RKE2) com `kubectl` configurado.
- O Ingress NGINX Controller instalado e em execução no seu cluster.
- Um servidor Ollama em execução no seu cluster, acessível via `http://ollama.local:11434`.
- Um provisionador de volume `local-path` configurado no seu cluster para o PVC.

## Estrutura do Projeto

O projeto é organizado nos seguintes arquivos de manifesto do Kubernetes:

```
ollama-fastmcp-k8s/
├── namespace.yaml
├── configmap.yaml
├── pvc.yaml
├── deployment.yaml
├── service.yaml
└── ingress.yaml
```

## Manifestos do Kubernetes

### 1. `namespace.yaml`

Define o namespace `fastmcp-server` para agrupar todos os recursos relacionados a este projeto.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: fastmcp-server
```

### 2. `configmap.yaml`

Contém o código Python para o servidor FastMCP (`server.py`) e o arquivo de requisitos (`requirements.txt`). O `server.py` utiliza FastAPI para criar os endpoints e o FastMCP2 para registrar as ferramentas da API do Ollama. Ele se comunica com o servidor Ollama através da variável de ambiente `OLLAMA_SERVER_URL`.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fastmcp-config
  namespace: fastmcp-server
data:
  requirements.txt: |
    fastmcp2
    requests
    uvicorn
    fastapi
  server.py: |
    from fastapi import FastAPI, HTTPException
    from fastapi.responses import JSONResponse
    from fastmcp2 import Tool, ToolManager, ToolType, ToolTransportType
    import requests
    import os

    app = FastAPI()
    tool_manager = ToolManager(transport_type=ToolTransportType.HTTP)

    OLLAMA_SERVER_URL = os.getenv("OLLAMA_SERVER_URL", "http://ollama.local:11434")

    # Helper function to make requests to Ollama API
    def call_ollama_api(endpoint, method=\'POST\', json_data=None, stream=False):
        url = f"{OLLAMA_SERVER_URL}{endpoint}"
        headers = {\'Content-Type\': \'application/json\'}
        try:
            if method == \'POST\':
                response = requests.post(url, headers=headers, json=json_data, stream=stream)
            elif method == \'GET\':
                response = requests.get(url, headers=headers, stream=stream)
            else:
                raise ValueError("Unsupported HTTP method")
            response.raise_for_status()
            if stream:
                return response.iter_content(chunk_size=8192)
            return response.json()
        except requests.exceptions.RequestException as e:
            raise HTTPException(status_code=500, detail=f"Ollama API error: {e}")

    # Endpoints da API do Ollama como Tools
    # ... (código dos endpoints do Ollama conforme definido anteriormente)
    @tool_manager.tool(
        name="generate_completion",
        description="Gera uma conclusão para um dado prompt com um modelo Ollama.",
        tool_type=ToolType.FUNCTION,
        parameters={
            "type": "object",
            "properties": {
                "model": {"type": "string", "description": "O nome do modelo Ollama (obrigatório)."},
                "prompt": {"type": "string", "description": "O prompt para gerar uma resposta."},
                "stream": {"type": "boolean", "description": "Se true, a resposta será transmitida como uma série de objetos JSON. Padrão: false.", "default": False},
                "options": {"type": "object", "description": "Parâmetros adicionais do modelo, como temperatura."}
            },
            "required": ["model", "prompt"]
        }
    )
    async def generate_completion(model: str, prompt: str, stream: bool = False, options: dict = None):
        payload = {"model": model, "prompt": prompt, "stream": stream}
        if options: payload["options"] = options
        return call_ollama_api("/api/generate", json_data=payload, stream=stream)

    @tool_manager.tool(
        name="generate_chat_completion",
        description="Gera a próxima mensagem em um chat com um modelo Ollama, mantendo o histórico de mensagens.",
        tool_type=ToolType.FUNCTION,
        parameters={
            "type": "object",
            "properties": {
                "model": {"type": "string", "description": "O nome do modelo Ollama (obrigatório)."},
                "messages": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "role": {"type": "string", "enum": ["system", "user", "assistant", "tool"]},
                            "content": {"type": "string"},
                            "images": {"type": "array", "items": {"type": "string"}, "description": "Lista de imagens codificadas em base64."}
                        },
                        "required": ["role", "content"]
                    },
                    "description": "O histórico de mensagens do chat."},
                "stream": {"type": "boolean", "description": "Se true, a resposta será transmitida como uma série de objetos JSON. Padrão: false.", "default": False},
                "options": {"type": "object", "description": "Parâmetros adicionais do modelo, como temperatura."}
            },
            "required": ["model", "messages"]
        }
    )
    async def generate_chat_completion(model: str, messages: list, stream: bool = False, options: dict = None):
        payload = {"model": model, "messages": messages, "stream": stream}
        if options: payload["options"] = options
        return call_ollama_api("/api/chat", json_data=payload, stream=stream)

    @tool_manager.tool(
        name="create_model",
        description="Cria um modelo Ollama a partir de outro modelo, diretório safetensors ou arquivo GGUF.",
        tool_type=ToolType.FUNCTION,
        parameters={
            "type": "object",
            "properties": {
                "model": {"type": "string", "description": "Nome do modelo a ser criado (obrigatório)."},
                "from_model": {"type": "string", "description": "Nome de um modelo existente para criar o novo modelo (opcional)."},
                "quantize": {"type": "string", "description": "Tipo de quantização a ser aplicada (opcional)."},
                "system": {"type": "string", "description": "Prompt do sistema para o modelo (opcional)."}
            },
            "required": ["model"]
        }
    )
    async def create_model(model: str, from_model: str = None, quantize: str = None, system: str = None):
        payload = {"model": model}
        if from_model: payload["from"] = from_model
        if quantize: payload["quantize"] = quantize
        if system: payload["system"] = system
        return call_ollama_api("/api/create", json_data=payload)

    @tool_manager.tool(
        name="list_local_models",
        description="Lista os modelos Ollama disponíveis localmente.",
        tool_type=ToolType.FUNCTION,
        parameters={
            "type": "object",
            "properties": {}
        }
    )
    async def list_local_models():
        return call_ollama_api("/api/tags", method=\'GET\')

    @tool_manager.tool(
        name="show_model_information",
        description="Mostra informações sobre um modelo Ollama, incluindo detalhes, modelfile, template, parâmetros, licença e prompt do sistema.",
        tool_type=ToolType.FUNCTION,
        parameters={
            "type": "object",
            "properties": {
                "model": {"type": "string", "description": "Nome do modelo para mostrar (obrigatório)."},
                "verbose": {"type": "boolean", "description": "Se true, retorna dados completos para campos de resposta detalhados. Padrão: false.", "default": False}
            },
            "required": ["model"]
        }
    )
    async def show_model_information(model: str, verbose: bool = False):
        payload = {"model": model, "verbose": verbose}
        return call_ollama_api("/api/show", json_data=payload)

    @tool_manager.tool(
        name="copy_model",
        description="Copia um modelo Ollama existente para um novo nome.",
        tool_type=ToolType.FUNCTION,
        parameters={
            "type": "object",
            "properties": {
                "source_model": {"type": "string", "description": "Nome do modelo de origem (obrigatório)."},
                "destination_model": {"type": "string", "description": "Nome do modelo de destino (obrigatório)."}
            },
            "required": ["source_model", "destination_model"]
        }
    )
    async def copy_model(source_model: str, destination_model: str):
        payload = {"source": source_model, "destination": destination_model}
        return call_ollama_api("/api/copy", json_data=payload)

    @tool_manager.tool(
        name="delete_model",
        description="Exclui um modelo Ollama.",
        tool_type=ToolType.FUNCTION,
        parameters={
            "type": "object",
            "properties": {
                "model": {"type": "string", "description": "Nome do modelo a ser excluído (obrigatório)."}
            },
            "required": ["model"]
        }
    )
    async def delete_model(model: str):
        payload = {"name": model}
        return call_ollama_api("/api/delete", method=\'DELETE\', json_data=payload)

    @tool_manager.tool(
        name="pull_model",
        description="Baixa um modelo Ollama do registro.",
        tool_type=ToolType.FUNCTION,
        parameters={
            "type": "object",
            "properties": {
                "model": {"type": "string", "description": "Nome do modelo a ser baixado (obrigatório)."},
                "insecure": {"type": "boolean", "description": "Permitir pull de registros não seguros. Padrão: false.", "default": False},
                "stream": {"type": "boolean", "description": "Se true, a resposta será transmitida. Padrão: false.", "default": False}
            },
            "required": ["model"]
        }
    )
    async def pull_model(model: str, insecure: bool = False, stream: bool = False):
        payload = {"name": model, "insecure": insecure, "stream": stream}
        return call_ollama_api("/api/pull", json_data=payload, stream=stream)

    @tool_manager.tool(
        name="push_model",
        description="Envia um modelo Ollama para um registro.",
        tool_type=ToolType.FUNCTION,
        parameters={
            "type": "object",
            "properties": {
                "model": {"type": "string", "description": "Nome do modelo a ser enviado (obrigatório)."},
                "insecure": {"type": "boolean", "description": "Permitir push para registros não seguros. Padrão: false.", "default": False},
                "stream": {"type": "boolean", "description": "Se true, a resposta será transmitida. Padrão: false.", "default": False}
            },
            "required": ["model"]
        }
    )
    async def push_model(model: str, insecure: bool = False, stream: bool = False):
        payload = {"name": model, "insecure": insecure, "stream": stream}
        return call_ollama_api("/api/push", json_data=payload, stream=stream)

    @tool_manager.tool(
        name="generate_embeddings",
        description="Gera embeddings a partir de um modelo Ollama.",
        tool_type=ToolType.FUNCTION,
        parameters={
            "type": "object",
            "properties": {
                "model": {"type": "string", "description": "Nome do modelo para gerar embeddings (obrigatório)."},
                "prompt": {"type": "string", "description": "Texto para gerar embeddings (obrigatório)."}
            },
            "required": ["model", "prompt"]
        }
    )
    async def generate_embeddings(model: str, prompt: str):
        payload = {"model": model, "prompt": prompt}
        return call_ollama_api("/api/embeddings", json_data=payload)

    @tool_manager.tool(
        name="list_running_models",
        description="Lista os modelos Ollama que estão atualmente carregados na memória.",
        tool_type=ToolType.FUNCTION,
        parameters={
            "type": "object",
            "properties": {}
        }
    )
    async def list_running_models():
        return call_ollama_api("/api/ps", method=\'GET\')

    @tool_manager.tool(
        name="get_ollama_version",
        description="Recupera a versão do Ollama.",
        tool_type=ToolType.FUNCTION,
        parameters={
            "type": "object",
            "properties": {}
        }
    )
    async def get_ollama_version():
        return call_ollama_api("/api/version", method=\'GET\')

    @app.get("/tools.json")
    async def get_tools_json():
        return JSONResponse(tool_manager.get_tools_json())

    @app.get("/tools")
    async def get_tools_yaml():
        return tool_manager.get_tools_yaml()

    @app.post("/tool_call/{tool_name}")
    async def tool_call(tool_name: str, args: dict):
        return await tool_manager.handle_tool_call(tool_name, args)

    if __name__ == "__main__":
        import uvicorn
        uvicorn.run(app, host="0.0.0.0", port=8000)
```

### 3. `pvc.yaml`

Define um PersistentVolumeClaim para fornecer armazenamento persistente ao servidor FastMCP. Ele utiliza a `storageClassName: local-path`, que deve ser configurada no seu cluster.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fastmcp-pvc
  namespace: fastmcp-server
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: local-path
```

### 4. `deployment.yaml`

Define o Deployment para o servidor FastMCP. Ele cria um pod com a imagem `python:3.11-slim-bookworm`, instala as dependências do `requirements.txt` e executa o `server.py` com Uvicorn. A variável de ambiente `OLLAMA_SERVER_URL` é configurada para apontar para o seu servidor Ollama local.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastmcp-server
  namespace: fastmcp-server
  labels:
    app: fastmcp-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fastmcp-server
  template:
    metadata:
      labels:
        app: fastmcp-server
    spec:
      containers:
      - name: fastmcp-server
        image: python:3.11-slim-bookworm # Usar uma imagem Python mais recente
        ports:
        - containerPort: 8000
        env:
        - name: OLLAMA_SERVER_URL
          value: "http://ollama.local:11434"
        volumeMounts:
        - name: fastmcp-config-volume
          mountPath: /app/config
        - name: fastmcp-data-volume
          mountPath: /app/data
        command: ["/bin/bash", "-c"]
        args: 
          - |-
            pip install --no-cache-dir -r /app/config/requirements.txt && \
            uvicorn server:app --host 0.0.0.0 --port 8000
        workingDir: /app/config
      volumes:
      - name: fastmcp-config-volume
        configMap:
          name: fastmcp-config
      - name: fastmcp-data-volume
        persistentVolumeClaim:
          claimName: fastmcp-pvc
```

### 5. `service.yaml`

Define um Service do tipo `ClusterIP` para expor o Deployment do FastMCP internamente no cluster na porta 80, roteando para a porta 8000 do contêiner.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: fastmcp-service
  namespace: fastmcp-server
spec:
  selector:
    app: fastmcp-server
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8000
  type: ClusterIP
```

### 6. `ingress.yaml`

Configura um Ingress NGINX para expor o serviço `fastmcp-service` externamente através do hostname `mcpserver.local`. As anotações `nginx.ingress.kubernetes.io/proxy-read-timeout` e `nginx.ingress.kubernetes.io/proxy-send-timeout` são definidas para 300 segundos para lidar com possíveis operações de longa duração.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fastmcp-ingress
  namespace: fastmcp-server
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
spec:
  ingressClassName: nginx
  rules:
  - host: mcpserver.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: fastmcp-service
            port:
              number: 80
```

## Como Implantar

Para implantar o servidor FastMCP no seu cluster Kubernetes, siga estes passos:

1.  **Crie o namespace:**
    ```bash
    kubectl apply -f namespace.yaml
    ```

2.  **Crie o ConfigMap:**
    ```bash
    kubectl apply -f configmap.yaml
    ```

3.  **Crie o PersistentVolumeClaim:**
    ```bash
    kubectl apply -f pvc.yaml
    ```

4.  **Implante o servidor FastMCP:**
    ```bash
    kubectl apply -f deployment.yaml
    ```

5.  **Crie o Service:**
    ```bash
    kubectl apply -f service.yaml
    ```

6.  **Crie o Ingress:**
    ```bash
    kubectl apply -f ingress.yaml
    ```

Após a implantação, você poderá acessar as ferramentas MCP do Ollama através de `http://mcpserver.local/tools` (para o esquema YAML) ou `http://mcpserver.local/tools.json` (para o esquema JSON).

## Extensibilidade Futura

O design atual do `server.py` no ConfigMap foi pensado para ser facilmente extensível. Para adicionar novas ferramentas para outras APIs, você pode:

1.  **Modificar `configmap.yaml`**: Adicione novas funções decoradas com `@tool_manager.tool` no `server.py` para cada endpoint da nova API que você deseja expor.
2.  **Atualizar o Deployment**: Se as novas APIs exigirem dependências Python adicionais, atualize o `requirements.txt` no ConfigMap e reinicie o pod do Deployment para que as novas dependências sejam instaladas.
3.  **Variáveis de Ambiente**: Se a nova API precisar de uma URL base diferente, adicione uma nova variável de ambiente ao Deployment e utilize-a em suas novas funções de ferramenta.

Este projeto serve como uma base robusta para construir um hub de ferramentas MCP para suas LLMs, integrando diversas APIs de forma centralizada e escalável no Kubernetes.

## Contribuição

Contribuições são bem-vindas! Sinta-se à vontade para abrir issues ou pull requests para melhorar este projeto.

## Licença

Este projeto está licenciado sob a licença MIT. Veja o arquivo `LICENSE` para mais detalhes.

