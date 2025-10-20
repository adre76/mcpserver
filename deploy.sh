#!/bin/bash

# Script para deploy automatizado do MCP Server no Kubernetes

NAMESPACE="mcp-server"

# Cores para a saída do terminal
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Função para verificar se um recurso foi criado
wait_for_resource() {
  local resource_type=$1
  local resource_name=$2
  local namespace=$3
  local status_check_cmd=$4
  local timeout=${5:-300} # Default timeout de 5 minutos
  local interval=5
  local elapsed=0

  echo -e "${GREEN}Aguardando que o recurso $resource_type/$resource_name no namespace $namespace esteja pronto...${NC}"

  while ! eval "$status_check_cmd" &>/dev/null && [ $elapsed -lt $timeout ]; do
    printf "."
    sleep $interval
    elapsed=$((elapsed + interval))
  done

  if [ $elapsed -ge $timeout ]; then
    echo -e "\nErro: Tempo limite excedido para $resource_type/$resource_name."
    exit 1
  fi
  echo -e "\n${GREEN}Recurso $resource_type/$resource_name pronto.${NC}"
}

# 1. Verificar pré-requisitos
echo -e "\n${GREEN}=== 1. Verificando pré-requisitos ===${NC}"
if ! command -v kubectl &> /dev/null
then
    echo "Erro: kubectl não encontrado. Por favor, instale e configure o kubectl."
    exit 1
fi
echo "kubectl encontrado."

# 2. Aplicar Namespace
echo -e "\n${GREEN}=== 2. Aplicando Namespace ===${NC}"
echo "Aplicando '01 - namespace.yaml'..."
kubectl apply -f "01 - namespace.yaml"
wait_for_resource "namespace" "$NAMESPACE" "" "kubectl get namespace $NAMESPACE"

# 3. Aplicar ConfigMap
echo -e "\n${GREEN}=== 3. Aplicando ConfigMap ===${NC}"
echo "Aplicando '03 - configmap.yaml'..."
kubectl apply -f "03 - configmap.yaml" -n $NAMESPACE
wait_for_resource "configmap" "mcp-app-code" "$NAMESPACE" "kubectl get configmap mcp-app-code -n $NAMESPACE"

# 4. Aplicar Persistent Volume Claim (PVC)
echo -e "\n${GREEN}=== 4. Aplicando Persistent Volume Claim (PVC) ===${NC}"
echo "Aplicando '02 - pvc.yaml'..."
kubectl apply -f "02 - pvc.yaml" -n $NAMESPACE
# Para local-path, o PVC fica em WaitForFirstConsumer até o Deployment ser aplicado.
# Não vamos esperar aqui, mas sim após o Deployment.

# 5. Aplicar Deployment
echo -e "\n${GREEN}=== 5. Aplicando Deployment ===${NC}"
echo "Aplicando '04 - deployment.yaml'..."
kubectl apply -f "04 - deployment.yaml" -n $NAMESPACE
wait_for_resource "deployment" "mcp-server-deployment" "$NAMESPACE" "kubectl rollout status deployment/mcp-server-deployment -n $NAMESPACE --timeout=0s"

# 6. Verificando Persistent Volume Claim (PVC)
echo -e "\n${GREEN}=== 6. Verificando Persistent Volume Claim (PVC) ===${NC}"
# Agora que o Deployment está ativo, o PVC deve estar 'Bound'
wait_for_resource "pvc" "mcp-data-pvc" "$NAMESPACE" "kubectl get pvc mcp-data-pvc -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q 'Bound'"

# 7. Aplicar Service
echo -e "\n${GREEN}=== 7. Aplicando Service ===${NC}"
echo "Aplicando '05 - service.yaml'..."
kubectl apply -f "05 - service.yaml" -n $NAMESPACE
wait_for_resource "service" "mcp-server-service" "$NAMESPACE" "kubectl get service mcp-server-service -n $NAMESPACE"

# 8. Aplicar Ingress
echo -e "\n${GREEN}=== 8. Aplicando Ingress ===${NC}"
echo "Aplicando '06 - ingress.yaml'..."
kubectl apply -f "06 - ingress.yaml" -n $NAMESPACE
wait_for_resource "ingress" "mcp-server-ingress" "$NAMESPACE" "kubectl get ingress mcp-server-ingress -n $NAMESPACE"

echo -e "\n${GREEN}Deploy do MCP Server concluído com sucesso no namespace \'$NAMESPACE\'.${NC}"
echo "Verifique o status dos recursos com: kubectl get all -n $NAMESPACE"
echo "Lembre-se de configurar seu arquivo /etc/hosts para 'mcpserver.local' apontando para o IP do seu Ingress Controller."