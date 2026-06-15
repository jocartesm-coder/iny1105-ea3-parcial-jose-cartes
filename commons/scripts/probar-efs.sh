#!/bin/bash
# probar-efs.sh — Prueba si EFS es usable en este Learner Lab SIN permisos IAM.
#
# Prueba 2 vías:
#   A) EFS CSI dinámico  (StorageClass efs-sc + PVC) — requiere el controller EFS
#   B) EFS por NFS nativo (volumen tipo nfs, sin CSI) — montaje por el kernel
#
# Crea un sistema EFS temporal, monta-target en las subnets del cluster, prueba,
# y LIMPIA todo al final.
#
# USO:  bash commons/scripts/probar-efs.sh
set -uo pipefail
REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-iny1105-ea3-cluster}"
NS="efs-test"
SEP="------------------------------------------------------------"
R_CONTROLLER="?"; R_FS="?"; R_NFS_MOUNT="?"

echo "$SEP"; echo " PRUEBA EFS (sin IAM)"; echo "$SEP"
kubectl get nodes >/dev/null 2>&1 || { echo "ERROR: kubectl no conecta."; exit 1; }
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

# ── 1. ¿El controller del EFS CSI arranca, o crashea como el de EBS? ──────
echo; echo "[1] Estado de los pods del EFS CSI controller..."
kubectl get pods -n kube-system -l app=efs-csi-controller -o wide 2>&1 | sed 's/^/    /'
CTRL_READY=$(kubectl get pods -n kube-system -l app=efs-csi-controller \
    -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null)
if echo "$CTRL_READY" | grep -q "false"; then
    R_CONTROLLER="❌ controller EFS CSI NO está Ready (probable falta de IAM, igual que EBS)"
elif [ -n "$CTRL_READY" ]; then
    R_CONTROLLER="✅ controller EFS CSI Ready"
else
    R_CONTROLLER="⚠️ no hay pods de controller EFS CSI desplegados"
fi
echo "    => $R_CONTROLLER"

# ── 2. Crear un sistema EFS temporal + mount targets en subnets del cluster ─
echo; echo "[2] Creando sistema EFS temporal..."
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
    --query "cluster.resourcesVpcConfig.vpcId" --output text 2>/dev/null)
SUBNETS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
    --query "cluster.resourcesVpcConfig.subnetIds" --output text 2>/dev/null)
echo "    VPC: $VPC_ID"
echo "    Subnets: $SUBNETS"

FS_ID=$(aws efs create-file-system --region "$REGION" \
    --tags Key=Name,Value=iny1105-efs-test \
    --query "FileSystemId" --output text 2>&1)
if ! echo "$FS_ID" | grep -q "^fs-"; then
    R_FS="❌ no se pudo crear EFS: $(echo "$FS_ID" | head -1)"
    echo "    => $R_FS"
else
    R_FS="✅ EFS creado: $FS_ID"
    echo "    => $R_FS"
    echo "    Esperando a que el EFS esté disponible..."
    for t in $(seq 1 12); do
        ST=$(aws efs describe-file-systems --file-system-id "$FS_ID" --region "$REGION" \
            --query "FileSystems[0].LifeCycleState" --output text 2>/dev/null)
        [ "$ST" = "available" ] && break
        sleep 5
    done
    echo "    Estado EFS: $ST"

    # Security group: permitir NFS (2049) desde la VPC
    SG_ID=$(aws ec2 describe-security-groups --region "$REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" \
        --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)
    aws ec2 authorize-security-group-ingress --region "$REGION" \
        --group-id "$SG_ID" --protocol tcp --port 2049 --cidr 172.31.0.0/16 >/dev/null 2>&1 || true

    # Mount targets en cada subnet
    echo "    Creando mount targets (NFS) en las subnets del cluster..."
    for SUBNET in $SUBNETS; do
        aws efs create-mount-target --region "$REGION" \
            --file-system-id "$FS_ID" --subnet-id "$SUBNET" \
            --security-groups "$SG_ID" >/dev/null 2>&1 \
            && echo "      mount target en $SUBNET ✅" \
            || echo "      mount target en $SUBNET (ya existe o error)"
    done
    echo "    Esperando 60s a que los mount targets estén 'available'..."
    sleep 60

    # ── 3. Prueba B: montar EFS como volumen NFS nativo (sin CSI) ──────────
    echo; echo "[3] Prueba NFS nativo — Pod que monta el EFS por NFS..."
    EFS_DNS="${FS_ID}.efs.${REGION}.amazonaws.com"
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: efs-nfs-test
  namespace: $NS
spec:
  containers:
  - name: app
    image: public.ecr.aws/docker/library/busybox:latest
    command: ["sh","-c","echo hola-efs > /data/test.txt && cat /data/test.txt && sleep 60"]
    volumeMounts:
    - name: efs-vol
      mountPath: /data
  volumes:
  - name: efs-vol
    nfs:
      server: $EFS_DNS
      path: /
EOF
    echo "    Esperando 45s a que el Pod monte el NFS..."
    sleep 45
    PHASE=$(kubectl get pod efs-nfs-test -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)
    LOGS=$(kubectl logs efs-nfs-test -n "$NS" 2>/dev/null)
    echo "    Pod phase: $PHASE | logs: $LOGS"
    if echo "$LOGS" | grep -q "hola-efs"; then
        R_NFS_MOUNT="✅ EFS montado por NFS nativo SIN IAM (viable para act33)"
    else
        R_NFS_MOUNT="❌ no se montó (ver: kubectl describe pod efs-nfs-test -n $NS)"
        kubectl describe pod efs-nfs-test -n "$NS" 2>/dev/null | grep -A6 "Events:" | sed 's/^/      /'
    fi
    echo "    => $R_NFS_MOUNT"

    # ── LIMPIEZA del EFS ────────────────────────────────────────────────
    echo; echo "[*] Limpiando EFS temporal..."
    for MT in $(aws efs describe-mount-targets --file-system-id "$FS_ID" --region "$REGION" \
                 --query "MountTargets[].MountTargetId" --output text 2>/dev/null); do
        aws efs delete-mount-target --mount-target-id "$MT" --region "$REGION" >/dev/null 2>&1
    done
    echo "    Esperando 30s antes de borrar el file system..."
    sleep 30
    aws efs delete-file-system --file-system-id "$FS_ID" --region "$REGION" >/dev/null 2>&1 \
        && echo "    EFS $FS_ID eliminado ✅" \
        || echo "    ⚠️ no se pudo borrar $FS_ID — bórralo manual en la consola EFS"
fi

kubectl delete namespace "$NS" --wait=false >/dev/null 2>&1

echo; echo "$SEP"; echo " REPORTE EFS"; echo "$SEP"
printf "  %-22s %s\n" "Controller EFS CSI:" "$R_CONTROLLER"
printf "  %-22s %s\n" "Crear sistema EFS:"  "$R_FS"
printf "  %-22s %s\n" "Montaje NFS nativo:" "$R_NFS_MOUNT"
echo "$SEP"
echo " Si 'Montaje NFS nativo' es ✅, podemos usar EFS en act33 vía volumen nfs"
echo " (sin CSI driver, sin IAM). Pega este reporte en el chat."
echo "$SEP"
