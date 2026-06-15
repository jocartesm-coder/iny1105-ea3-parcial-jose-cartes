#!/bin/bash
# diag-ebs.sh — Diagnostica por qué el EBS CSI driver no provisiona volúmenes.
# USO: bash commons/scripts/diag-ebs.sh
set -uo pipefail
REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-iny1105-ea3-cluster}"
SEP="------------------------------------------------------------"

echo "$SEP"; echo " DIAGNÓSTICO EBS CSI"; echo "$SEP"

echo; echo "[1] Estado del addon EBS CSI:"
aws eks describe-addon --cluster-name "$CLUSTER_NAME" --region "$REGION" \
    --addon-name aws-ebs-csi-driver \
    --query "addon.{status:status,health:health}" --output json 2>&1 | sed 's/^/    /'

echo; echo "[2] Pods del controller EBS CSI (kube-system):"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver -o wide 2>&1 | sed 's/^/    /'

echo; echo "[3] ¿Por qué no arrancan? (describe del primer pod controller):"
POD=$(kubectl get pods -n kube-system -l app=ebs-csi-controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD" ]; then
    kubectl describe pod "$POD" -n kube-system 2>/dev/null | grep -A8 "Events:" | sed 's/^/    /'
    echo; echo "    --- logs del contenedor csi-provisioner (últimas 15 líneas) ---"
    kubectl logs "$POD" -n kube-system -c csi-provisioner --tail=15 2>/dev/null | sed 's/^/    /'
    echo; echo "    --- logs del contenedor ebs-plugin (últimas 15 líneas) ---"
    kubectl logs "$POD" -n kube-system -c ebs-plugin --tail=15 2>/dev/null | sed 's/^/    /'
else
    echo "    No se encontró pod del controller (puede que el addon aún no despliegue pods)."
fi

echo; echo "[4] Service account del controller y su rol IAM anotado:"
kubectl get sa ebs-csi-controller-sa -n kube-system -o jsonpath='{.metadata.annotations}' 2>/dev/null | sed 's/^/    /'
echo

echo; echo "[5] ¿El rol del nodo (LabEksNodeRole) tiene permisos EBS?"
NODE_ROLE=$(aws iam list-roles --query "Roles[?contains(RoleName,'LabEksNodeRole')].RoleName" --output text 2>/dev/null | head -1)
echo "    Rol de nodo: ${NODE_ROLE:-<no encontrado>}"
if [ -n "$NODE_ROLE" ]; then
    echo "    Políticas administradas adjuntas:"
    aws iam list-attached-role-policies --role-name "$NODE_ROLE" \
        --query "AttachedPolicies[].PolicyName" --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/      /'
fi

echo; echo "$SEP"; echo " Pega esta salida en el chat."; echo "$SEP"
