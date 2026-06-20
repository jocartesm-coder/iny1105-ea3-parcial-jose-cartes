#!/bin/bash
# ============================================================================
# probar-alb.sh — Prueba si el AWS Load Balancer Controller puede crear un ALB
# en este Learner Lab SIN que el usuario tenga acceso IAM.
#
# Estrategia: instalar el controller vía Helm SIN crear rol propio, dejándolo
# usar las credenciales del nodo (LabEksNodeRole). Luego crear un Ingress para
# WordPress y ver si nace un ALB real.
#
# Si el rol del nodo no tiene permisos ELB (lo más probable), el controller
# arrancará pero el ALB nunca se creará y veremos el error en los logs.
#
# USO: bash commons/scripts/probar-alb.sh
# REQUISITOS: cluster activo, helm, WordPress desplegado (Service "wordpress").
# ============================================================================
set -uo pipefail
REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-iny1105-ea3-cluster}"
NS="wordpress"
SEP="------------------------------------------------------------"
R_HELM="?"; R_CTRL="?"; R_NODE_PERM="?"; R_ING="?"

echo "$SEP"; echo " PRUEBA AWS Load Balancer Controller (sin IAM)"; echo "$SEP"
kubectl get nodes >/dev/null 2>&1 || { echo "ERROR: kubectl no conecta."; exit 1; }

# ── 0. ¿El rol del nodo tiene permisos de ELB? (lo determina todo) ───────
echo; echo "[0] Permisos de ELB en el rol del nodo (LabEksNodeRole)..."
NODE_ROLE=$(aws iam list-roles --query "Roles[?contains(RoleName,'LabEksNodeRole')].RoleName" --output text 2>/dev/null | head -1)
echo "    Rol de nodo: ${NODE_ROLE:-<no encontrado>}"
if [ -n "$NODE_ROLE" ]; then
    echo "    Políticas adjuntas:"
    aws iam list-attached-role-policies --role-name "$NODE_ROLE" \
        --query "AttachedPolicies[].PolicyName" --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/      /'
fi
# Prueba directa: ¿las credenciales del entorno pueden describir load balancers?
if aws elbv2 describe-load-balancers --region "$REGION" >/dev/null 2>&1; then
    R_NODE_PERM="✅ el entorno puede llamar a elbv2 (puede que el controller funcione)"
else
    R_NODE_PERM="⚠️ el entorno no lista ELBs (esto es CloudShell; el nodo puede diferir)"
fi
echo "    => $R_NODE_PERM"

# ── 1. Instalar el controller vía Helm (sin crear rol IAM) ───────────────
echo; echo "[1] Instalando AWS Load Balancer Controller vía Helm..."
if ! command -v helm >/dev/null 2>&1; then
    echo "    Instalando helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1
fi
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
    --query "cluster.resourcesVpcConfig.vpcId" --output text 2>/dev/null)

helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1
helm repo update >/dev/null 2>&1
# Instalar SIN serviceAccount.create con rol: usa el SA por defecto (credenciales del nodo)
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName="$CLUSTER_NAME" \
    --set region="$REGION" \
    --set vpcId="$VPC_ID" \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    2>&1 | tail -3 | sed 's/^/    /'
R_HELM="instalado (ver estado de pods abajo)"

echo "    Esperando 60s a que arranque el controller..."
sleep 60
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -o wide 2>&1 | sed 's/^/    /'
CTRL_READY=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller \
    -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null)
if echo "$CTRL_READY" | grep -qw "true"; then
    R_CTRL="✅ controller Ready"
else
    R_CTRL="⚠️ controller no Ready (ver logs)"
fi
echo "    => $R_CTRL"

# ── 2. Crear un Ingress para WordPress y ver si nace un ALB ───────────────
echo; echo "[2] Creando Ingress ALB para WordPress..."
cat <<EOF | kubectl apply -f - 2>&1 | sed 's/^/    /'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wordpress-alb-test
  namespace: $NS
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: wordpress
            port:
              number: 80
EOF

echo "    Esperando hasta 3 min a que el ALB obtenga dirección..."
ADDR=""
for t in $(seq 1 18); do
    ADDR=$(kubectl get ingress wordpress-alb-test -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    echo "      [$((t*10))s] address=${ADDR:-<pendiente>}"
    [ -n "$ADDR" ] && break
    sleep 10
done
if [ -n "$ADDR" ]; then
    R_ING="✅ ALB creado: $ADDR (el ALB Controller FUNCIONA sin IAM propio)"
else
    R_ING="❌ el ALB NO se creó (el controller no tiene permisos para crear el ALB)"
    echo "    --- logs del controller (errores) ---"
    kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=15 2>/dev/null \
        | grep -iE "error|denied|forbidden|unauthor" | head -8 | sed 's/^/      /'
fi
echo "    => $R_ING"

# ── LIMPIEZA ──────────────────────────────────────────────────────────────
echo; echo "[*] Limpiando Ingress de prueba..."
kubectl delete ingress wordpress-alb-test -n "$NS" --ignore-not-found >/dev/null 2>&1

echo; echo "$SEP"; echo " REPORTE ALB"; echo "$SEP"
printf "  %-18s %s\n" "Permisos ELB:"  "$R_NODE_PERM"
printf "  %-18s %s\n" "Helm install:"  "$R_HELM"
printf "  %-18s %s\n" "Controller:"    "$R_CTRL"
printf "  %-18s %s\n" "ALB creado:"    "$R_ING"
echo "$SEP"
echo " Si 'ALB creado' es ✅, podemos usar ALB en act33. Si ❌, NodePort se queda."
echo " (El controller instalado queda en el cluster; se elimina al borrar el cluster.)"
echo "$SEP"
