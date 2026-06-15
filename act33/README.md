# Act 3.3 — Almacenamiento persistente en Kubernetes

## Archivos a completar

| Archivo | Qué completar |
|---|---|
| `manifests/namespace.yaml` | (ya configurado) crea el namespace `monitoring` |
| `manifests/pvc.yaml` | name, accessModes, storage, storageClassName |
| `manifests/deployment.yaml` | volumeMounts, volumes, claimName |
| `manifests/service.yaml` | name, selector, ports, type |

## Aplicar los manifiestos directamente

Aplica cada manifiesto con `kubectl apply -f`, **respetando este orden** (el
namespace debe existir antes que los objetos que viven dentro de él):

```bash
# 1. Crear el namespace (debe ir primero)
kubectl apply -f manifests/namespace.yaml

# 2. Crear el resto de objetos
kubectl apply -f manifests/pvc.yaml
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/service.yaml

# Verificar estado del PVC (debe estar en estado Bound)
kubectl get pvc -n monitoring

# Ver detalle del volumen
kubectl describe pvc <nombre> -n monitoring

# Verificar que el Pod montó el volumen
kubectl describe pod -n monitoring
```
