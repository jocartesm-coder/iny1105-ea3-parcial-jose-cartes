#!/bin/bash
# create-cluster.sh — Crea el cluster EKS en AWS Learner Lab
# Uso: bash commons/scripts/create-cluster.sh
#
# Requisitos:
#   - AWS CLI configurado con credenciales del Learner Lab
#   - Región: us-east-1
#   - Rol disponible: LabEksClusterRole

set -e

CLUSTER_NAME="iny1105-ea3-cluster"
REGION="us-east-1"
NODE_GROUP="standard-workers"
NODE_TYPE="t3.small"
NODES_DESIRED=2
NODES_MIN=1
NODES_MAX=3

echo "=================================================="
echo " Creando cluster EKS: $CLUSTER_NAME"
echo " Región: $REGION"
echo "=================================================="
echo ""

# Verificar que el AWS CLI está configurado
echo "[1/4] Verificando credenciales AWS..."
aws sts get-caller-identity --query "{Account:Account, Arn:Arn}" --output table
echo ""

# Verificar que LabEksClusterRole existe
echo "[2/4] Verificando que LabEksClusterRole existe..."
aws iam get-role --role-name LabEksClusterRole --query "Role.Arn" --output text
echo ""

# Verificar límite de instancias EC2 activas
echo "[3/4] Verificando instancias EC2 activas..."
RUNNING=$(aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=instance-state-name,Values=running" \
    --query "length(Reservations[].Instances[])" \
    --output text)
echo "Instancias EC2 corriendo actualmente: $RUNNING (límite del Learner Lab: 9)"
if [ "$RUNNING" -gt 7 ]; then
    echo "ADVERTENCIA: Tienes $RUNNING instancias activas. El Node Group agregará $NODES_DESIRED más."
    echo "Considera detener instancias no usadas antes de continuar."
    read -p "¿Continuar de todas formas? (s/N): " CONFIRM
    if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
        echo "Operación cancelada."
        exit 1
    fi
fi
echo ""

echo "[4/4] Creando cluster EKS desde AWS CLI..."
echo "Esto tardará 10-15 minutos. No cierres la terminal."
echo ""

# Crear el cluster
aws eks create-cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --kubernetes-version 1.31 \
    --role-arn "$(aws iam get-role --role-name LabEksClusterRole --query 'Role.Arn' --output text)" \
    --resources-vpc-config \
        subnetIds="$(aws ec2 describe-subnets --region $REGION --filters "Name=default-for-az,Values=true" --query 'Subnets[0:2].SubnetId' --output text | tr '\t' ',')",endpointPublicAccess=true,endpointPrivateAccess=false \
    --output table 2>/dev/null || true

echo "Esperando a que el cluster esté ACTIVE..."
aws eks wait cluster-active --name "$CLUSTER_NAME" --region "$REGION"
echo "✓ Cluster ACTIVE"
echo ""

# Crear el Node Group
echo "Creando Node Group: $NODE_GROUP..."
aws eks create-nodegroup \
    --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "$NODE_GROUP" \
    --region "$REGION" \
    --node-role "$(aws iam get-role --role-name LabEksClusterRole --query 'Role.Arn' --output text)" \
    --subnets $(aws ec2 describe-subnets --region $REGION --filters "Name=default-for-az,Values=true" --query 'Subnets[0:2].SubnetId' --output text) \
    --instance-types "$NODE_TYPE" \
    --scaling-config minSize=$NODES_MIN,maxSize=$NODES_MAX,desiredSize=$NODES_DESIRED \
    --output table 2>/dev/null || true

echo "Esperando a que los nodos estén ACTIVE (puede tardar 3-5 min adicionales)..."
aws eks wait nodegroup-active \
    --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "$NODE_GROUP" \
    --region "$REGION"
echo "✓ Node Group ACTIVE"
echo ""

# Configurar kubectl
echo "Configurando kubectl para apuntar al cluster..."
aws eks update-kubeconfig \
    --region "$REGION" \
    --name "$CLUSTER_NAME"
echo ""

echo "✓ Cluster listo. Verificando nodos:"
kubectl get nodes
echo ""
echo "=================================================="
echo " Cluster $CLUSTER_NAME listo para usar"
echo " RECUERDA: Al terminar la clase ejecuta:"
echo "   bash commons/scripts/delete-cluster.sh"
echo "=================================================="
