#!/bin/bash
# apply-manifests.sh — Aplica todos los manifiestos YAML de una actividad
# Uso: bash commons/scripts/apply-manifests.sh <actividad>
# Ejemplo: bash commons/scripts/apply-manifests.sh act31

set -e

ACTIVIDAD="${1:-}"

if [ -z "$ACTIVIDAD" ]; then
    echo "Uso: bash commons/scripts/apply-manifests.sh <actividad>"
    echo "Ejemplo: bash commons/scripts/apply-manifests.sh act31"
    echo ""
    echo "Actividades disponibles:"
    for d in act31 act32 act33 act34; do
        if [ -d "$d/manifests" ]; then
            echo "  $d"
        fi
    done
    exit 1
fi

MANIFESTS_DIR="${ACTIVIDAD}/manifests"

if [ ! -d "$MANIFESTS_DIR" ]; then
    echo "ERROR: No se encontró el directorio $MANIFESTS_DIR"
    echo "Asegúrate de ejecutar este script desde la raíz del repositorio."
    exit 1
fi

# Verificar que kubectl está conectado al cluster
echo "Verificando conexión al cluster..."
kubectl cluster-info --request-timeout=5s > /dev/null 2>&1 || {
    echo "ERROR: kubectl no está conectado a ningún cluster."
    echo "Ejecuta primero: bash commons/scripts/create-cluster.sh"
    exit 1
}

echo "=================================================="
echo " Aplicando manifiestos de: $ACTIVIDAD"
echo " Directorio: $MANIFESTS_DIR"
echo "=================================================="
echo ""

# Aplicar en orden: namespace → configmap → pvc → deployment → service → ingress
ORDER="namespace configmap pvc deployment service ingress"

for KIND in $ORDER; do
    FILE=$(find "$MANIFESTS_DIR" -name "${KIND}.yaml" 2>/dev/null | head -1)
    if [ -n "$FILE" ]; then
        echo "Aplicando: $FILE"
        kubectl apply -f "$FILE"
    fi
done

# Aplicar cualquier otro YAML que no esté en el orden definido
for FILE in "$MANIFESTS_DIR"/*.yaml; do
    BASENAME=$(basename "$FILE" .yaml)
    if ! echo "$ORDER" | grep -qw "$BASENAME"; then
        echo "Aplicando: $FILE"
        kubectl apply -f "$FILE"
    fi
done

echo ""
echo "=================================================="
echo " Manifiestos aplicados. Estado actual:"
echo "=================================================="
NAMESPACE=$(grep -r "namespace:" "$MANIFESTS_DIR"/*.yaml 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"')
if [ -n "$NAMESPACE" ] && [ "$NAMESPACE" != "default" ]; then
    kubectl get pods,svc -n "$NAMESPACE"
else
    kubectl get pods,svc
fi
