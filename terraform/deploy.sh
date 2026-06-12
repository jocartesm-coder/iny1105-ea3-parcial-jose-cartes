#!/bin/bash
# deploy.sh — Despliega act31 y act32 en el Learner Lab
# Uso: bash terraform/deploy.sh
#
# Flujo:
#   Paso 1 — crea el cluster EKS con el script bash (requiere credenciales de usuario)
#   Paso 2 — Terraform crea ECR, construye/sube imagen y aplica manifiestos K8s
#
# Ejecutar desde la raíz del repositorio iny1105-ea3-base.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
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
        echo "ERROR: '$cmd' no está instalado."
        exit 1
    fi
done

echo "[prereq] Verificando credenciales AWS..."
aws sts get-caller-identity --query "{Account:Account, Arn:Arn}" --output table || {
    echo "ERROR: AWS CLI no está configurado con credenciales del Learner Lab."
    exit 1
}

echo "[prereq] Verificando Docker daemon..."
docker info > /dev/null 2>&1 || {
    echo "ERROR: Docker no está corriendo."
    exit 1
}
echo ""

# ── Paso 1: Cluster EKS ───────────────────────────────────────────────────────
# La creación del cluster requiere iam:PassRole, que solo está disponible
# con las credenciales de usuario del Learner Lab (no desde el rol de la EC2).
# Usamos el script bash existente que ya está validado para el Learner Lab.

echo "=================================================="
echo " Paso 1/3 — Cluster EKS"
echo "=================================================="

# Verificar si el cluster ya existe
CLUSTER_STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
    --query "cluster.status" --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    echo "✓ Cluster $CLUSTER_NAME ya existe y está ACTIVE — omitiendo creación."
elif [ "$CLUSTER_STATUS" == "CREATING" ]; then
    echo "El cluster está en estado CREATING. Esperando..."
    bash "$REPO_ROOT/commons/scripts/create-cluster.sh" --skip-create 2>/dev/null || true
else
    echo "Creando cluster EKS con create-cluster.sh..."
    bash "$REPO_ROOT/commons/scripts/create-cluster.sh"
fi
echo ""

# ── Verificar nodos ───────────────────────────────────────────────────────────

echo "Verificando nodos del cluster..."
TIMEOUT=300
ELAPSED=0
while true; do
    READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo 0)
    if [ "$READY" -ge 1 ]; then
        echo "✓ $READY nodo(s) Ready"
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

# ── Paso 2: Terraform — ECR + imagen + manifiestos K8s ───────────────────────

echo "=================================================="
echo " Paso 2/3 — ECR + imagen Docker + manifiestos K8s"
echo "=================================================="

echo "terraform init..."
terraform init -upgrade -input=false

echo ""
echo "terraform apply..."
terraform apply -auto-approve -input=false
echo ""

# ── Paso 3: Verificación ─────────────────────────────────────────────────────

echo "=================================================="
echo " Paso 3/3 — Verificación"
echo "=================================================="

echo "Pods en namespace monitoring:"
kubectl get pods -n monitoring
echo ""

echo "Services en namespace monitoring:"
kubectl get svc -n monitoring
echo ""

echo "ConfigMap prometheus-config:"
kubectl get configmap prometheus-config -n monitoring -o jsonpath='{.data}' | python3 -m json.tool 2>/dev/null || \
    kubectl describe configmap prometheus-config -n monitoring | grep -A10 "^Data"
echo ""

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "")
if [ -n "$NODE_IP" ]; then
    echo "=================================================="
    echo " URLs de acceso:"
    echo "   Act 3.1 — Prometheus:    http://$NODE_IP:30090"
    echo "   Act 3.2 — Prometheus-v2: http://$NODE_IP:30092"
    echo "=================================================="
    echo ""
    echo "Si no puedes acceder, agrega estas reglas al Security Group de los nodos:"
    echo "  TCP 30090 desde 0.0.0.0/0"
    echo "  TCP 30092 desde 0.0.0.0/0"
else
    echo "Ejecuta 'kubectl get nodes -o wide' para obtener la IP externa."
fi
echo ""
echo "Al terminar la sesión: bash terraform/destroy.sh"
