#!/bin/bash
# probar-act33.sh — Aplica y valida los manifiestos de act33 en el cluster.
# Verifica: PVC Bound, MySQL y WordPress Running, Service NodePort, HPA con métricas.
# USO: bash commons/scripts/probar-act33.sh
set -uo pipefail
SEP="------------------------------------------------------------"
M="act33/manifests"
echo "$SEP"; echo " PRUEBA FUNCIONAL — Act 3.3 (WordPress + MySQL)"; echo "$SEP"

kubectl get nodes >/dev/null 2>&1 || { echo "ERROR: kubectl no conecta."; exit 1; }

echo; echo "[1] Aplicando manifiestos en orden..."
# 1. namespace
kubectl apply -f "$M/01-namespace.yaml" 2>&1 | sed 's/^/      /'
# 2. Secret desde AWS Secrets Manager (script, no YAML)
echo "    bash $M/02-mysql-secret-from-sm.sh"
bash "$M/02-mysql-secret-from-sm.sh" 2>&1 | sed 's/^/      /'
# 3..7 resto de manifiestos
for f in 03-mysql-storage 04-mysql 05-wordpress 06-wordpress-hpa 07-networkpolicy; do
    echo "    kubectl apply -f $M/$f.yaml"
    kubectl apply -f "$M/$f.yaml" 2>&1 | sed 's/^/      /'
done

echo; echo "[2] Esperando a que el PVC de MySQL quede Bound (hasta 60s)..."
for t in $(seq 1 6); do
    PH=$(kubectl get pvc mysql-pvc -n wordpress -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "    mysql-pvc: ${PH:-Pending}"
    [ "$PH" = "Bound" ] && break
    sleep 10
done

echo; echo "[3] Esperando Pods Running (hasta 3 min)..."
kubectl wait --for=condition=ready pod -l app=mysql -n wordpress --timeout=120s 2>&1 | sed 's/^/    /'
kubectl wait --for=condition=ready pod -l app=wordpress -n wordpress --timeout=120s 2>&1 | sed 's/^/    /'
kubectl get pods -n wordpress -o wide 2>&1 | sed 's/^/    /'

echo; echo "[4] Objetos del namespace:"
kubectl get all -n wordpress 2>&1 | sed 's/^/    /'

echo; echo "[5] PVC / PV:"
kubectl get pvc,pv -n wordpress 2>&1 | sed 's/^/    /'

echo; echo "[6] HPA (debe mostrar métricas de CPU, no <unknown>):"
sleep 15
kubectl get hpa -n wordpress 2>&1 | sed 's/^/    /'

echo; echo "[7] Acceso a WordPress por NodePort 30093:"
echo "    Abriendo el puerto 30093 en el Security Group de los nodos..."
bash "$(dirname "$0")/open-nodeport.sh" 30093 2>&1 | sed 's/^/      /'
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null)
echo "    URL externa: http://$NODE_IP:30093"
echo "    Prueba interna (desde un Pod temporal):"
kubectl run wp-curl --rm -i --restart=Never -n wordpress \
    --image=public.ecr.aws/docker/library/busybox:latest --timeout=60s \
    -- wget -qO- --timeout=10 http://wordpress 2>/dev/null | head -5 | sed 's/^/      /' \
    || echo "      (no respondió aún; WordPress puede tardar en inicializar)"

echo; echo "$SEP"
echo " Si MySQL y WordPress están Running, PVC Bound y HPA muestra CPU%, act33 funciona."
echo " Para LIMPIAR la prueba:  kubectl delete namespace wordpress"
echo "$SEP"
