# Act 3.4 — Networking en Kubernetes

## Archivos a completar

| Archivo | Qué completar |
|---|---|
| `manifests/deployment.yaml` | name, replicas, labels, image, ports |
| `manifests/service.yaml` | name, selector, ports, type |
| `manifests/ingress.yaml` | name, ingress.class, service name, port |

## Comandos de esta actividad

```bash
# Aplicar manifiestos
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
