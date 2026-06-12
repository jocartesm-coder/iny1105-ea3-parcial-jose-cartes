#!/bin/bash
# deploy.sh — Despliega act31 y act32 completos en el Learner Lab usando Terraform
# Uso: bash terraform/deploy.sh
#
# Ejecutar desde la raíz del repositorio iny1105-ea3-base.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REGION="us-east-1"
CLUSTER_NAME="iny1105-ea3-cluster"

echo "=================================================="
echo " INY1105 — EA3 — Deploy con Terraform"
echo " Act 3.1 + Act 3.2"
echo "=================================================="
echo ""

# ── Prerequisitos ─────────────────────────────────────────────────────────────

echo "[prereq] Verificando herramientas..."
for cmd in terraform aws docker kubectl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' no está instalado. Instálalo antes de continuar."
        exit 1
    fi
done

echo "[prereq] Verificando credenciales AWS..."
aws sts get-caller-identity --query "{Account:Account}" --output table || {
    echo "ERROR: AWS CLI no está configurado con credenciales del Learner Lab."
    exit 1
}

echo "[prereq] Verificando LabEksClusterRole..."
aws iam get-role --role-name LabEksClusterRole --query "Role.Arn" --output text || {
    echo "ERROR: No se encontró LabEksClusterRole. Verifica que estás en el Learner Lab."
    exit 1
}

echo "[prereq] Verificando Docker daemon..."
docker info > /dev/null 2>&1 || {
    echo "ERROR: Docker no está corriendo. Inicia Docker antes de continuar."
    exit 1
}
echo ""

# ── Terraform init ────────────────────────────────────────────────────────────

echo "[1/4] terraform init..."
terraform init -upgrade
echo ""

# ── Fase 1: Crear el cluster EKS ──────────────────────────────────────────────
# Se aplica solo el cluster y el node group primero.
# El provider kubernetes necesita que el cluster exista para planificar.

echo "[2/4] Creando cluster EKS (puede tardar 15-20 min)..."
terraform apply \
    -target=aws_eks_cluster.main \
    -target=aws_eks_node_group.workers \
    -target=null_resource.update_kubeconfig \
    -auto-approve
echo ""

# ── Verificar nodos ───────────────────────────────────────────────────────────

echo "[3/4] Verificando nodos del cluster..."
echo "Esperando a que los nodos estén Ready..."
TIMEOUT=300
ELAPSED=0
while true; do
    READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo 0)
    if [ "$READY" -ge 2 ]; then
        echo "✓ $READY nodos Ready"
        break
    fi
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "TIMEOUT esperando nodos. Verifica con: kubectl get nodes"
        exit 1
    fi
    echo "  Nodos Ready: $READY — esperando... ($ELAPSED s)"
    sleep 15
    ELAPSED=$((ELAPSED + 15))
done
echo ""

# ── Fase 2: ECR + imagen + manifiestos K8s ────────────────────────────────────

echo "[4/4] Desplegando ECR, imagen Docker y manifiestos Kubernetes..."
terraform apply -auto-approve
echo ""

# ── Verificación final ────────────────────────────────────────────────────────

echo "=================================================="
echo " Verificación del despliegue"
echo "=================================================="
echo ""

echo "Pods en namespace monitoring:"
kubectl get pods -n monitoring
echo ""

echo "Services en namespace monitoring:"
kubectl get svc -n monitoring
echo ""

echo "ConfigMap prometheus-config:"
kubectl describe configmap prometheus-config -n monitoring 2>/dev/null | grep -A5 "Data"
echo ""

# Obtener IP de un nodo
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "")
if [ -n "$NODE_IP" ]; then
    echo "=================================================="
    echo " URLs de acceso:"
    echo "   Act 3.1 — Prometheus:    http://$NODE_IP:30090"
    echo "   Act 3.2 — Prometheus-v2: http://$NODE_IP:30092"
    echo "=================================================="
    echo ""
    echo "IMPORTANTE: Si no puedes acceder, agrega reglas al Security Group de los nodos:"
    echo "  TCP 30090 desde 0.0.0.0/0"
    echo "  TCP 30092 desde 0.0.0.0/0"
else
    echo "NOTA: No se pudo obtener IP externa de los nodos automáticamente."
    echo "Ejecuta: kubectl get nodes -o wide"
fi
echo ""

echo "terraform output  ← para ver todos los outputs"
echo ""
echo "Al terminar:  bash terraform/destroy.sh"
