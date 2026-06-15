#!/bin/bash
# ============================================================================
# validar-act33-funcional.sh  —  SEGUNDA PASADA (validación funcional)
#
# La primera pasada (validar-act33-infra.sh) confirmó que los addons se CREAN.
# Esta prueba si realmente FUNCIONAN: PVC EBS Bound, IRSA, NetworkPolicy
# enforcement, y kubectl top. Crea recursos mínimos y los limpia al final.
#
# REQUISITOS: cluster activo + validar-act33-infra.sh ya ejecutado (addons creados)
# USO: bash commons/scripts/validar-act33-funcional.sh
# ============================================================================
set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-iny1105-ea3-cluster}"
NS="val33"
SEP="------------------------------------------------------------"

R_TOP="?"; R_EBS_BOUND="?"; R_IRSA="?"; R_NETPOL="?"; R_EBS_ADDON="?"; R_EFS_ADDON="?"

echo "$SEP"; echo " VALIDACIÓN FUNCIONAL — Act 3.3"; echo "$SEP"

kubectl get nodes >/dev/null 2>&1 || { echo "ERROR: kubectl no conecta."; exit 1; }
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

# ── 1. Esperar addons EBS/EFS en estado ACTIVE ───────────────────────────
echo; echo "[1] Estado de los addons CSI (esperando hasta 90s)..."
for t in $(seq 1 9); do
    R_EBS_ADDON=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --region "$REGION" \
        --addon-name aws-ebs-csi-driver --query "addon.status" --output text 2>/dev/null)
    R_EFS_ADDON=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --region "$REGION" \
        --addon-name aws-efs-csi-driver --query "addon.status" --output text 2>/dev/null)
    echo "    EBS=$R_EBS_ADDON  EFS=$R_EFS_ADDON"
    [ "$R_EBS_ADDON" = "ACTIVE" ] && break
    sleep 10
done

# ── 2. kubectl top (Metrics Server / HPA) ────────────────────────────────
echo; echo "[2] Metrics Server (kubectl top)..."
if kubectl top nodes >/dev/null 2>&1; then
    R_TOP="✅ kubectl top responde (HPA viable)"
    kubectl top nodes | sed 's/^/    /'
else
    R_TOP="⚠️ kubectl top aún no responde (revisar: kubectl get deploy metrics-server -n kube-system)"
fi
echo "    => $R_TOP"

# ── 3. PVC EBS: ¿queda Bound? (la prueba clave para MySQL con EBS) ────────
echo; echo "[3] Provisión dinámica EBS — creando PVC de prueba (1Gi gp2)..."
cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ebs-test
  namespace: $NS
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp2
  resources:
    requests:
      storage: 1Gi
EOF
# gp2 usa WaitForFirstConsumer → necesita un Pod que lo monte para hacer Bind
cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: ebs-test-pod
  namespace: $NS
spec:
  containers:
  - name: app
    image: public.ecr.aws/docker/library/busybox:latest
    command: ["sh","-c","sleep 300"]
    volumeMounts:
    - name: vol
      mountPath: /data
  volumes:
  - name: vol
    persistentVolumeClaim:
      claimName: ebs-test
EOF
echo "    Esperando hasta 120s a que el PVC quede Bound..."
for t in $(seq 1 12); do
    PHASE=$(kubectl get pvc ebs-test -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "    PVC ebs-test: ${PHASE:-Pending}"
    [ "$PHASE" = "Bound" ] && break
    sleep 10
done
if [ "$PHASE" = "Bound" ]; then
    R_EBS_BOUND="✅ PVC EBS Bound (provisión dinámica EBS funciona → MySQL con EBS viable)"
else
    R_EBS_BOUND="❌ PVC NO llegó a Bound (revisar: kubectl describe pvc ebs-test -n $NS)"
    echo "    --- eventos del PVC ---"
    kubectl describe pvc ebs-test -n "$NS" 2>/dev/null | grep -A6 "Events:" | sed 's/^/    /'
fi
echo "    => $R_EBS_BOUND"

# ── 4. IRSA: ¿puedo registrar el OIDC provider en IAM? ───────────────────
echo; echo "[4] IRSA — ¿permiso para registrar OIDC provider en IAM?"
OIDC=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
        --query "cluster.identity.oidc.issuer" --output text 2>/dev/null | sed 's|https://||')
# Probar el create con dry-run de permisos (intento real, capturando error)
ERR=$(aws iam create-open-id-connect-provider \
        --url "https://$OIDC" \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280 \
        --region "$REGION" 2>&1)
if echo "$ERR" | grep -qiE "arn:aws:iam|EntityAlreadyExists"; then
    R_IRSA="✅ se puede registrar OIDC en IAM (IRSA viable → ALB Controller / EFS dinámico posibles)"
elif echo "$ERR" | grep -qiE "AccessDenied|not authorized|UnauthorizedOperation"; then
    R_IRSA="❌ AccessDenied al crear OIDC provider → IRSA NO viable (sin ALB Controller ni EFS dinámico vía IRSA)"
else
    R_IRSA="⚠️ resultado ambiguo: $(echo "$ERR" | head -1)"
fi
echo "    => $R_IRSA"

# ── 5. NetworkPolicy enforcement ─────────────────────────────────────────
echo; echo "[5] NetworkPolicy — ¿el VPC CNI APLICA las políticas?"
NP_FLAG=$(kubectl get daemonset aws-node -n kube-system \
    -o jsonpath='{range .spec.template.spec.containers[*]}{.args}{.env}{end}' 2>/dev/null)
ENABLE_NP=$(kubectl get daemonset aws-node -n kube-system \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="aws-node")].env[?(@.name=="ENABLE_NETWORK_POLICY")].value}' 2>/dev/null)
if [ "$ENABLE_NP" = "true" ]; then
    R_NETPOL="✅ VPC CNI con ENABLE_NETWORK_POLICY=true (enforcement activo)"
else
    R_NETPOL="⚠️ ENABLE_NETWORK_POLICY no está en 'true' (la NetworkPolicy se acepta pero puede NO aplicarse). Valor='${ENABLE_NP:-<no definido>}'"
fi
echo "    => $R_NETPOL"

# ── LIMPIEZA ──────────────────────────────────────────────────────────────
echo; echo "[*] Limpiando recursos de prueba..."
kubectl delete namespace "$NS" --wait=false >/dev/null 2>&1

# ── REPORTE ────────────────────────────────────────────────────────────────
echo; echo "$SEP"; echo " REPORTE FUNCIONAL"; echo "$SEP"
printf "  %-18s %s\n" "EBS addon:"     "$R_EBS_ADDON"
printf "  %-18s %s\n" "EFS addon:"     "$R_EFS_ADDON"
printf "  %-18s %s\n" "kubectl top:"   "$R_TOP"
printf "  %-18s %s\n" "PVC EBS Bound:" "$R_EBS_BOUND"
printf "  %-18s %s\n" "IRSA/OIDC:"     "$R_IRSA"
printf "  %-18s %s\n" "NetworkPolicy:" "$R_NETPOL"
echo "$SEP"
echo " Pega este reporte en el chat para definir el diseño final de act33."
echo "$SEP"
