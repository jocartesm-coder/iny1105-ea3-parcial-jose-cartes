# Act 3.2 — Objetos de Kubernetes: Deployments, Services y ConfigMaps

## Archivos a completar

| Archivo | Qué completar |
|---|---|
| `manifests/deployment.yaml` | name, replicas, labels, image, resources |
| `manifests/service.yaml` | name, selector, ports, type |
| `manifests/configmap.yaml` | name, variables de configuración |

## Comandos de esta actividad

```bash
# Aplicar manifiestos
kubectl apply -f manifests/configmap.yaml
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/service.yaml

# Escalar réplicas
kubectl scale deployment <nombre> -n monitoring --replicas=3

# Verificar rollout
kubectl rollout status deployment/<nombre> -n monitoring

# Ver detalle del ConfigMap
kubectl describe configmap <nombre> -n monitoring
```
