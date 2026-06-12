#!/bin/bash
# destroy.sh — Elimina todos los recursos del Learner Lab creados por Terraform
# Uso: bash terraform/destroy.sh
#
# Ejecutar desde la raíz del repositorio iny1105-ea3-base.
# IMPORTANTE: Ejecuta esto al terminar cada sesión para liberar presupuesto.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo " ELIMINAR RECURSOS — INY1105 EA3 Terraform"
echo " Esta operación eliminará:"
echo "   - Cluster EKS y Node Group"
echo "   - Repositorio ECR (incluyendo imágenes)"
echo "   - Todos los objetos Kubernetes"
echo "=================================================="
echo ""

read -p "¿Confirmas que quieres eliminar todo? (escribe 'eliminar' para confirmar): " CONFIRM
if [ "$CONFIRM" != "eliminar" ]; then
    echo "Operación cancelada."
    exit 0
fi
echo ""

# Eliminar objetos Kubernetes primero (más rápido que esperar terraform destroy en EKS)
echo "[1/2] Eliminando objetos Kubernetes..."
kubectl delete namespace monitoring --ignore-not-found=true 2>/dev/null || true
echo ""

# Terraform destroy
echo "[2/2] Ejecutando terraform destroy (puede tardar 15-20 min)..."
terraform destroy -auto-approve
echo ""

echo "=================================================="
echo " Todos los recursos eliminados correctamente."
echo " Verifica en la consola AWS → EKS que el cluster no aparece."
echo "=================================================="
