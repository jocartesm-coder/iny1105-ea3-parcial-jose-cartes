# Act 3.4 — Networking en Kubernetes

## Archivos a completar

| Archivo | Qué completar |
|---|---|
| `manifests/namespace.yaml` | (ya configurado) crea el namespace `monitoring` |
| `manifests/deployment.yaml` | name, replicas, labels, image, ports |
| `manifests/service.yaml` | name, selector, ports, type |
| `manifests/ingress.yaml` | name, ingress.class, service name, port |

## Aplicar los manifiestos directamente

Aplica cada manifiesto con `kubectl apply -f`, **respetando este orden** (el
namespace debe existir antes que los objetos que viven dentro de él):

```bash
# 1. Crear el namespace (debe ir primero)
kubectl apply -f manifests/namespace.yaml

# 2. Crear el resto de objetos
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/service.yaml
kubectl apply -f manifests/ingress.yaml

# Verificar el Ingress
kubectl get ingress -n monitoring

# Ver políticas de red
kubectl get networkpolicy -n monitoring

# Describir el Ingress para ver eventos y dirección
kubectl describe ingress <nombre> -n monitoring
```
