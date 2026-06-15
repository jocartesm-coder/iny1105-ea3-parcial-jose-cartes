#!/bin/bash
# ============================================================================
# validar-act33-infra.sh
#
# Valida en el Learner Lab qué componentes de infraestructura necesarios para
# la Act 3.3 (WordPress + MySQL, EBS + EFS, ALB, autoscaling) realmente
# funcionan en el entorno restringido.
#
# REQUISITOS PREVIOS:
#   - Cluster EKS creado (bash commons/scripts/create-cluster.sh)
#   - kubectl conectado (kubectl get nodes responde)
#   - Ejecutar desde AWS CloudShell
#
# USO:
#   bash ea3/_admin/validar-act33-infra.sh
#
# El script NO crea recursos pesados; solo verifica permisos y disponibilidad
# de addons/controladores. Imprime un reporte ✅/❌ al final.
# ============================================================================
set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-iny1105-ea3-cluster}"
SEP="------------------------------------------------------------"

# Resultados (se rellenan durante las pruebas)
R_KUBECTL="?"; R_METRICS="?"; R_EBS_ADDON="?"; R_EFS_FS="?"
R_EFS_ADDON="?"; R_ALB_IAM="?"; R_OIDC="?"; R_HPA="?"; R_NETPOL="?"

echo "$SEP"
echo " VALIDACIÓN DE INFRAESTRUCTURA — Act 3.3"
echo " Región: $REGION | Cluster: $CLUSTER_NAME"
echo "$SEP"

# ── 0. Conexión al cluster ──────────────────────────────────────────────
echo; echo "[0] Conexión al cluster..."
if ! kubectl get nodes >/dev/null 2>&1; then
    echo "    kubectl no conecta. Configurando kubeconfig..."
    aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" 2>&1 | sed 's/^/    /'
fi
if kubectl get nodes >/dev/null 2>&1; then
    R_KUBECTL="✅"
    kubectl get nodes -o wide
else
    echo "ERROR: kubectl sigue sin conectar al cluster '$CLUSTER_NAME' en $REGION."
    echo "       Verifica que el cluster exista:  aws eks list-clusters --region $REGION"
    echo "       Si no existe, créalo:            bash commons/scripts/create-cluster.sh"
    exit 1
fi

# ── 1. OIDC provider (necesario para IRSA: EFS CSI, ALB Controller) ──────
echo; echo "$SEP"; echo "[1] ¿El cluster tiene OIDC provider asociado? (necesario para IRSA)"
OIDC=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
        --query "cluster.identity.oidc.issuer" --output text 2>/dev/null)
echo "    OIDC issuer: ${OIDC:-<ninguno>}"
if [ -n "$OIDC" ] && [ "$OIDC" != "None" ]; then
    # ¿Está registrado como IAM OIDC provider?
    OIDC_ID=$(echo "$OIDC" | sed 's|https://||')
    if aws iam list-open-id-connect-providers 2>/dev/null | grep -q "$OIDC_ID"; then
        R_OIDC="✅ registrado"
    else
        R_OIDC="⚠️ existe pero NO registrado en IAM (IRSA no funcionará sin registrarlo, y eso requiere iam:CreateOpenIDConnectProvider)"
    fi
else
    R_OIDC="❌ sin OIDC"
fi
echo "    => $R_OIDC"

# ── 2. Metrics Server (necesario para HPA / autoscaling) ─────────────────
echo; echo "$SEP"; echo "[2] Metrics Server (para autoscaling HPA)..."
if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    R_METRICS="✅ ya instalado"
else
    echo "    No instalado. Intentando instalar (no requiere IAM)..."
    if kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null 2>&1; then
        echo "    Aplicado. Esperando 30s a que arranque..."
        sleep 30
        if kubectl top nodes >/dev/null 2>&1; then
            R_METRICS="✅ instalado y funcionando (kubectl top responde)"
        else
            R_METRICS="⚠️ instalado pero 'kubectl top' aún no responde (puede tardar 1-2 min)"
        fi
    else
        R_METRICS="❌ no se pudo aplicar"
    fi
fi
echo "    => $R_METRICS"

# ── 3. EBS CSI Driver (addon gestionado) ─────────────────────────────────
echo; echo "$SEP"; echo "[3] EBS CSI Driver como addon EKS..."
EBS_STATUS=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --region "$REGION" \
              --addon-name aws-ebs-csi-driver --query "addon.status" --output text 2>/dev/null)
if [ -n "$EBS_STATUS" ] && [ "$EBS_STATUS" != "None" ]; then
    R_EBS_ADDON="✅ ya instalado ($EBS_STATUS)"
else
    echo "    No instalado. Intentando instalar addon (sin service-account-role)..."
    if aws eks create-addon --cluster-name "$CLUSTER_NAME" --region "$REGION" \
         --addon-name aws-ebs-csi-driver >/dev/null 2>&1; then
        sleep 20
        EBS_STATUS=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --region "$REGION" \
                      --addon-name aws-ebs-csi-driver --query "addon.status" --output text 2>/dev/null)
        R_EBS_ADDON="⚠️ creado, estado=$EBS_STATUS (verificar que un PVC quede Bound; necesita permisos EBS en LabEksNodeRole)"
    else
        R_EBS_ADDON="❌ no se pudo crear el addon"
    fi
fi
echo "    => $R_EBS_ADDON"
echo "    StorageClasses disponibles:"
kubectl get storageclass 2>/dev/null | sed 's/^/      /'

# ── 4. EFS: ¿puedo crear/listar sistemas de archivos EFS? ────────────────
echo; echo "$SEP"; echo "[4] Permisos EFS (¿puedo listar/crear sistemas de archivos?)..."
if aws efs describe-file-systems --region "$REGION" >/dev/null 2>&1; then
    echo "    ✅ puedo LISTAR sistemas EFS."
    # Probar addon EFS CSI
    EFS_ADDON=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --region "$REGION" \
                 --addon-name aws-efs-csi-driver --query "addon.status" --output text 2>/dev/null)
    if [ -n "$EFS_ADDON" ] && [ "$EFS_ADDON" != "None" ]; then
        R_EFS_ADDON="✅ addon ya instalado ($EFS_ADDON)"
    else
        if aws eks create-addon --cluster-name "$CLUSTER_NAME" --region "$REGION" \
             --addon-name aws-efs-csi-driver >/dev/null 2>&1; then
            R_EFS_ADDON="⚠️ addon creado (verificar montaje real con un PVC EFS)"
        else
            R_EFS_ADDON="❌ no se pudo crear addon aws-efs-csi-driver"
        fi
    fi
    R_EFS_FS="✅ acceso a API EFS"
else
    R_EFS_FS="❌ sin permisos para la API de EFS"
    R_EFS_ADDON="❌ (no aplica — sin acceso EFS)"
fi
echo "    => describe-file-systems: $R_EFS_FS"
echo "    => addon EFS CSI: $R_EFS_ADDON"

# ── 5. ALB: ¿puedo manejar Elastic Load Balancing? ───────────────────────
echo; echo "$SEP"; echo "[5] Permisos ALB / Elastic Load Balancing..."
if aws elbv2 describe-load-balancers --region "$REGION" >/dev/null 2>&1; then
    R_ALB_IAM="✅ puedo listar ALBs (el AWS LB Controller PODRÍA funcionar si se instala vía IRSA)"
else
    R_ALB_IAM="❌ sin permisos elbv2 / no puedo listar ALBs"
fi
echo "    => $R_ALB_IAM"

# ── 6. NetworkPolicy: ¿el VPC CNI aplica políticas de red? ────────────────
echo; echo "$SEP"; echo "[6] Soporte de NetworkPolicy (VPC CNI)..."
R_NETPOL="?"
# El VPC CNI (aws-node) soporta NetworkPolicy si tiene habilitado el flag.
NP_ENABLED=$(kubectl get daemonset aws-node -n kube-system \
    -o jsonpath='{.spec.template.spec.containers[*].args}' 2>/dev/null | grep -o "enable-network-policy=true" || true)
if [ -n "$NP_ENABLED" ]; then
    R_NETPOL="✅ VPC CNI con network policy habilitada"
else
    # Probar creando una NetworkPolicy de prueba (objeto API, se acepta aunque el CNI no la aplique)
    if kubectl get crd 2>/dev/null | grep -q "policyendpoints.networking.k8s.aws"; then
        R_NETPOL="⚠️ CRD de network policy presente pero flag no detectado — verificar enforcement real"
    else
        cat <<'NPEOF' | kubectl apply --dry-run=server -f - >/dev/null 2>&1 && R_NETPOL="⚠️ la API acepta NetworkPolicy, pero el VPC CNI puede NO aplicarla (enforcement) sin enable-network-policy=true" || R_NETPOL="❌ la API rechaza NetworkPolicy"
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-netpol-dryrun
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
NPEOF
    fi
fi
echo "    => $R_NETPOL"

# ── REPORTE FINAL ─────────────────────────────────────────────────────────
echo; echo "$SEP"; echo " REPORTE FINAL"; echo "$SEP"
printf "  %-22s %s\n" "kubectl/cluster:"   "$R_KUBECTL"
printf "  %-22s %s\n" "OIDC (IRSA):"        "$R_OIDC"
printf "  %-22s %s\n" "Metrics Server/HPA:" "$R_METRICS"
printf "  %-22s %s\n" "EBS CSI addon:"      "$R_EBS_ADDON"
printf "  %-22s %s\n" "EFS API:"            "$R_EFS_FS"
printf "  %-22s %s\n" "EFS CSI addon:"      "$R_EFS_ADDON"
printf "  %-22s %s\n" "ALB (elbv2):"        "$R_ALB_IAM"
printf "  %-22s %s\n" "NetworkPolicy:"      "$R_NETPOL"
echo "$SEP"
echo " Copia este reporte completo y pégalo en el chat para diseñar la actividad."
echo "$SEP"
