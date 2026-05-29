#!/bin/bash
# delete-cluster.sh — Elimina el cluster EKS para liberar presupuesto del Learner Lab
# Uso: bash commons/scripts/delete-cluster.sh
#
# IMPORTANTE: Ejecuta este script al terminar cada clase.
# El cluster EKS genera costo continuo aunque no lo estés usando.

set -e

CLUSTER_NAME="iny1105-ea3-cluster"
REGION="us-east-1"
NODE_GROUP="standard-workers"

echo "=================================================="
echo " ELIMINAR CLUSTER EKS: $CLUSTER_NAME"
echo " Esta operación liberará los recursos de AWS."
echo "=================================================="
echo ""

read -p "¿Confirmas que quieres eliminar el cluster? (escribe 'eliminar' para confirmar): " CONFIRM
if [ "$CONFIRM" != "eliminar" ]; then
    echo "Operación cancelada."
    exit 0
fi
echo ""

# Verificar que el cluster existe
echo "[1/3] Verificando cluster..."
STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query "cluster.status" --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$STATUS" == "NOT_FOUND" ]; then
    echo "El cluster $CLUSTER_NAME no existe o ya fue eliminado."
    exit 0
fi
echo "Estado actual: $STATUS"
echo ""

# Eliminar Node Group primero
echo "[2/3] Eliminando Node Group: $NODE_GROUP..."
aws eks delete-nodegroup \
    --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "$NODE_GROUP" \
    --region "$REGION" \
    --output table 2>/dev/null || echo "Node Group no encontrado o ya eliminado."

echo "Esperando a que el Node Group se elimine (puede tardar 3-5 min)..."
aws eks wait nodegroup-deleted \
    --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "$NODE_GROUP" \
    --region "$REGION" 2>/dev/null || true
echo "✓ Node Group eliminado"
echo ""

# Eliminar el cluster
echo "[3/3] Eliminando cluster: $CLUSTER_NAME..."
aws eks delete-cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --output table

echo "Esperando a que el cluster se elimine..."
aws eks wait cluster-deleted \
    --name "$CLUSTER_NAME" \
    --region "$REGION"
echo "✓ Cluster eliminado"
echo ""

echo "=================================================="
echo " Cluster $CLUSTER_NAME eliminado correctamente."
echo " Los recursos EC2 asociados también fueron liberados."
echo "=================================================="
