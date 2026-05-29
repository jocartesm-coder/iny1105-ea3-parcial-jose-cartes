# Act 3.3 — Almacenamiento persistente en Kubernetes

## Archivos a completar

| Archivo | Qué completar |
|---|---|
| `manifests/pvc.yaml` | name, accessModes, storage, storageClassName |
| `manifests/deployment.yaml` | volumeMounts, volumes, claimName |
| `manifests/service.yaml` | name, selector, ports, type |

## Comandos de esta actividad

```bash
# Aplicar manifiestos en orden
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
