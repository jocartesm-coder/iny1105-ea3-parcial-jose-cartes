#!/bin/bash
# probar-secretsmanager.sh — Verifica si el Learner Lab permite usar
# AWS Secrets Manager por CLI (sin IAM roles).
# USO: bash commons/scripts/probar-secretsmanager.sh
set -uo pipefail
REGION="${AWS_REGION:-us-east-1}"
SECRET_NAME="iny1105/test-sm-$$"
SEP="------------------------------------------------------------"
R_CREATE="?"; R_GET="?"; R_DELETE="?"

echo "$SEP"; echo " PRUEBA AWS Secrets Manager (CLI, sin IAM)"; echo "$SEP"

echo; echo "[1] Crear un secreto de prueba..."
OUT=$(aws secretsmanager create-secret --region "$REGION" \
    --name "$SECRET_NAME" \
    --secret-string '{"usuario":"demo","password":"demo123"}' 2>&1)
if echo "$OUT" | grep -q "arn:aws:secretsmanager"; then
    R_CREATE="✅ create-secret OK"
    echo "    $(echo "$OUT" | grep -o '"ARN"[^,]*')"
elif echo "$OUT" | grep -qiE "AccessDenied|not authorized"; then
    R_CREATE="❌ AccessDenied al crear secreto (Secrets Manager NO disponible)"
else
    R_CREATE="⚠️ resultado ambiguo: $(echo "$OUT" | head -1)"
fi
echo "    => $R_CREATE"

if [ "${R_CREATE:0:1}" = "✅" ]; then
    echo; echo "[2] Leer el secreto (get-secret-value)..."
    VAL=$(aws secretsmanager get-secret-value --region "$REGION" \
        --secret-id "$SECRET_NAME" --query "SecretString" --output text 2>&1)
    if echo "$VAL" | grep -q "demo123"; then
        R_GET="✅ get-secret-value OK (devuelve el JSON del secreto)"
        echo "    valor: $VAL"
    else
        R_GET="❌ no se pudo leer: $(echo "$VAL" | head -1)"
    fi
    echo "    => $R_GET"

    echo; echo "[3] Demostración del flujo SM -> Secret de K8s..."
    echo "    Comando que usaría la actividad:"
    echo '      PASS=$(aws secretsmanager get-secret-value --secret-id <nombre> \'
    echo '             --query SecretString --output text | jq -r .password)'
    echo '      kubectl create secret generic mysql-secret -n wordpress \'
    echo '             --from-literal=MYSQL_PASSWORD="$PASS" ...'
    if command -v jq >/dev/null 2>&1; then
        echo "    jq disponible: ✅ (necesario para parsear el JSON del secreto)"
    else
        echo "    jq disponible: ⚠️ NO (en CloudShell suele estar; si no, usar python o --output)"
    fi

    echo; echo "[4] Limpiando secreto de prueba..."
    aws secretsmanager delete-secret --region "$REGION" \
        --secret-id "$SECRET_NAME" --force-delete-without-recovery >/dev/null 2>&1 \
        && R_DELETE="✅ eliminado" || R_DELETE="⚠️ no se pudo borrar (hazlo manual)"
    echo "    => $R_DELETE"
fi

echo; echo "$SEP"; echo " REPORTE"; echo "$SEP"
printf "  %-18s %s\n" "create-secret:"     "$R_CREATE"
printf "  %-18s %s\n" "get-secret-value:"  "$R_GET"
printf "  %-18s %s\n" "delete-secret:"     "$R_DELETE"
echo "$SEP"
echo " Si create y get son ✅, podemos integrar Secrets Manager en act33 por CLI."
echo "$SEP"
