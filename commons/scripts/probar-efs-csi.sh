#!/bin/bash
# ============================================================================
# probar-efs-csi.sh — Prueba EFS con PROVISIONING ESTÁTICO vía el EFS CSI
# driver (no NFS crudo). El driver estático monta un EFS existente sin crear
# access points, por lo que NO debería necesitar permisos IAM de escritura.
#
# Crea un EFS temporal + mount targets, define PV/PVC con driver efs.csi.aws.com,
# monta en un Pod, verifica escritura, y LIMPIA todo.
#
# USO: bash commons/scripts/probar-efs-csi.sh
# ============================================================================
set -uo pipefail
REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-iny1105-ea3-cluster}"
NS="efs-csi-test"
SEP="------------------------------------------------------------"
R_CTRL="?"; R_FS="?"; R_PVC="?"; R_WRITE="?"

echo "$SEP"; echo " PRUEBA EFS CSI ESTÁTICO (sin IAM de escritura)"; echo "$SEP"
kubectl get nodes >/dev/null 2>&1 || { echo "ERROR: kubectl no conecta."; exit 1; }
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

# ── 0. Verificar que el driver EFS CSI está instalado y Ready ─────────────
echo; echo "[0] Estado del EFS CSI controller..."
CTRL=$(kubectl get pods -n kube-system -l app=efs-csi-controller \
    -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null)
kubectl get pods -n kube-system -l app=efs-csi-controller 2>&1 | sed 's/^/    /'
if echo "$CTRL" | grep -q "false" || [ -z "$CTRL" ]; then
    R_CTRL="⚠️ controller no Ready — instalando addon aws-efs-csi-driver..."
    aws eks create-addon --cluster-name "$CLUSTER_NAME" --region "$REGION" \
        --addon-name aws-efs-csi-driver >/dev/null 2>&1 || true
    echo "    esperando 60s al driver..."; sleep 60
else
    R_CTRL="✅ controller EFS CSI Ready"
fi
echo "    => $R_CTRL"

# ── 1. Crear EFS temporal + mount targets ────────────────────────────────
echo; echo "[1] Creando EFS temporal..."
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
    --query "cluster.resourcesVpcConfig.vpcId" --output text)
SUBNETS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
    --query "cluster.resourcesVpcConfig.subnetIds" --output text)
SG_ID=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME" \
              "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" --output text)
echo "    VPC=$VPC_ID  SG_nodos=$SG_ID"

FS_ID=$(aws efs create-file-system --region "$REGION" \
    --tags Key=Name,Value=iny1105-efs-csi-test \
    --query "FileSystemId" --output text 2>&1)
if ! echo "$FS_ID" | grep -q "^fs-"; then
    R_FS="❌ no se pudo crear EFS: $(echo "$FS_ID" | head -1)"
    echo "    => $R_FS"; kubectl delete ns "$NS" --wait=false >/dev/null 2>&1; exit 1
fi
R_FS="✅ EFS creado: $FS_ID"
echo "    => $R_FS"

# Permitir NFS (2049) desde el SG de los nodos hacia el EFS
aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_ID" --protocol tcp --port 2049 --source-group "$SG_ID" >/dev/null 2>&1 || true

for t in $(seq 1 12); do
    ST=$(aws efs describe-file-systems --file-system-id "$FS_ID" --region "$REGION" \
        --query "FileSystems[0].LifeCycleState" --output text 2>/dev/null)
    [ "$ST" = "available" ] && break; sleep 5
done
echo "    EFS estado: $ST. Creando mount targets..."
for SUBNET in $SUBNETS; do
    aws efs create-mount-target --region "$REGION" --file-system-id "$FS_ID" \
        --subnet-id "$SUBNET" --security-groups "$SG_ID" >/dev/null 2>&1 \
        && echo "      mount target en $SUBNET ✅" || echo "      $SUBNET (ya existe/err)"
done
echo "    Esperando a que los mount targets estén available..."
for t in $(seq 1 30); do
    STATES=$(aws efs describe-mount-targets --file-system-id "$FS_ID" --region "$REGION" \
        --query "MountTargets[].LifeCycleState" --output text 2>/dev/null)
    if [ -n "$STATES" ] && ! echo "$STATES" | grep -qvw "available"; then
        echo "      todos available ✅"; break; fi
    sleep 10
done

# ── 2. PV/PVC estáticos con el driver EFS CSI ────────────────────────────
echo; echo "[2] Creando PV/PVC con driver efs.csi.aws.com (estático)..."
cat <<EOF | kubectl apply -f - 2>&1 | sed 's/^/    /'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-csi-pv
spec:
  capacity:
    storage: 5Gi
  volumeMode: Filesystem
  accessModes: [ReadWriteMany]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-sc
  csi:
    driver: efs.csi.aws.com
    volumeHandle: $FS_ID
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-csi-pvc
  namespace: $NS
spec:
  accessModes: [ReadWriteMany]
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi
EOF

# ── 3. Pod que monta el PVC y escribe ────────────────────────────────────
echo; echo "[3] Pod que monta el PVC EFS y escribe un archivo..."
cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: efs-csi-app
  namespace: $NS
spec:
  containers:
  - name: app
    image: public.ecr.aws/docker/library/busybox:latest
    command: ["sh","-c","echo hola-efs-csi > /data/test.txt && cat /data/test.txt && sleep 600"]
    volumeMounts:
    - name: efs
      mountPath: /data
  volumes:
  - name: efs
    persistentVolumeClaim:
      claimName: efs-csi-pvc
EOF
echo "    Esperando montaje (hasta 3 min)..."
LOGS=""
for t in $(seq 1 18); do
    PH=$(kubectl get pod efs-csi-app -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)
    PVCPH=$(kubectl get pvc efs-csi-pvc -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)
    LOGS=$(kubectl logs efs-csi-app -n "$NS" 2>/dev/null)
    echo "      [$((t*10))s] pod=$PH pvc=$PVCPH"
    echo "$LOGS" | grep -q "hola-efs-csi" && break
    sleep 10
done
if echo "$LOGS" | grep -q "hola-efs-csi"; then
    R_PVC="✅ PVC EFS montado por el CSI driver"
    R_WRITE="✅ escritura/lectura OK ($LOGS)"
else
    R_PVC="❌ no montó"
    R_WRITE="❌ sin escritura"
    kubectl describe pod efs-csi-app -n "$NS" 2>/dev/null | grep -A8 "Events:" | sed 's/^/      /'
fi

# ── LIMPIEZA ──────────────────────────────────────────────────────────────
echo; echo "[*] Limpiando..."
kubectl delete ns "$NS" --wait=false >/dev/null 2>&1
kubectl delete pv efs-csi-pv --wait=false >/dev/null 2>&1
kubectl delete storageclass efs-sc >/dev/null 2>&1
for MT in $(aws efs describe-mount-targets --file-system-id "$FS_ID" --region "$REGION" \
             --query "MountTargets[].MountTargetId" --output text 2>/dev/null); do
    aws efs delete-mount-target --mount-target-id "$MT" --region "$REGION" >/dev/null 2>&1
done
sleep 30
aws efs delete-file-system --file-system-id "$FS_ID" --region "$REGION" >/dev/null 2>&1 \
    && echo "    EFS $FS_ID eliminado ✅" || echo "    ⚠️ borra $FS_ID manual en consola EFS"

echo; echo "$SEP"; echo " REPORTE EFS CSI"; echo "$SEP"
printf "  %-16s %s\n" "Controller:"  "$R_CTRL"
printf "  %-16s %s\n" "Crear EFS:"   "$R_FS"
printf "  %-16s %s\n" "PVC montado:" "$R_PVC"
printf "  %-16s %s\n" "Escritura:"   "$R_WRITE"
echo "$SEP"
echo " Si 'PVC montado' es ✅, EFS CSI estático funciona y podemos usarlo en act33."
echo "$SEP"
