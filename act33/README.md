# Act 3.3 — WordPress + MySQL: almacenamiento, secretos, networking y autoscaling

Actividad integradora de cierre de la EA3. Desplegarás una aplicación real de
dos capas (WordPress + MySQL) en Kubernetes, aplicando todo lo aprendido:
gestión de secretos, almacenamiento persistente, acceso externo, aislamiento de
red y escalado automático.

## Arquitectura

```
                Internet  →  NodePort 30093
                              │
                ┌─────────────▼─────────────┐
                │  WordPress (frontend)      │  Deployment + HPA (1→5 réplicas)
                └─────────────┬─────────────┘
                              │  (NetworkPolicy: solo WordPress → MySQL)
                ┌─────────────▼─────────────┐
                │  MySQL (base de datos)     │  Deployment + PV/PVC (datos)
                └────────────────────────────┘
                     namespace: wordpress
```

## Manifiestos

| Archivo | Objeto | Qué hace |
|---|---|---|
| `01-namespace.yaml` | Namespace | aísla la app en `wordpress` |
| `02-mysql-secret-from-sm.sh` | (script) | crea el secreto en **AWS Secrets Manager** y genera el Secret de K8s desde él |
| `03-mysql-storage.yaml` | PV + PVC | almacenamiento persistente (`hostPath`) para MySQL |
| `04-mysql.yaml` | Deployment + Service | base de datos MySQL (ClusterIP, interno) |
| `05-wordpress.yaml` | Deployment + Service | frontend WordPress (NodePort 30093) |
| `06-wordpress-hpa.yaml` | HorizontalPodAutoscaler | escala WordPress por CPU |
| `07-networkpolicy.yaml` | NetworkPolicy | solo WordPress puede hablar con MySQL |
| `08-stress-test.sh` | (script) | genera carga para experimentar el autoscaling |

## Requisitos previos

```bash
# El cluster debe estar creado (instala también el Metrics Server, necesario
# para el autoscaling).
bash commons/scripts/create-cluster.sh
```

## Fase 1 — Gestión de secretos con AWS Secrets Manager

En vez de versionar las contraseñas en un YAML (mala práctica), las guardamos en
AWS Secrets Manager y desde ahí generamos el Secret de Kubernetes.

```bash
# Crea el namespace primero
kubectl apply -f act33/manifests/01-namespace.yaml

# Crea el secreto en Secrets Manager y el Secret de K8s a partir de él
bash act33/manifests/02-mysql-secret-from-sm.sh

# Verifica
kubectl get secret mysql-secret -n wordpress
```

## Fase 2 — Almacenamiento persistente

```bash
# PV + PVC con hostPath (disco del nodo)
kubectl apply -f act33/manifests/03-mysql-storage.yaml

# El PVC debe quedar en estado Bound
kubectl get pvc -n wordpress
```

> **Almacenamiento en este laboratorio:** usamos `hostPath` (un directorio del
> disco del nodo). Los datos sobreviven a la recreación del Pod si vuelve al
> mismo nodo. En **producción** una base de datos usaría **EBS**
> (ReadWriteOnce, el volumen sigue al Pod entre nodos) y el contenido
> compartido entre réplicas usaría **EFS** (ReadWriteMany). EBS y EFS requieren
> permisos IAM no disponibles en el Learner Lab.

## Fase 3 — Desplegar MySQL y WordPress

```bash
# Base de datos (consume el Secret y monta el PVC)
kubectl apply -f act33/manifests/04-mysql.yaml

# Frontend (se conecta a MySQL por el Service "mysql")
kubectl apply -f act33/manifests/05-wordpress.yaml

# Espera a que ambos Pods estén Running
kubectl get pods -n wordpress -w
```

Acceder a WordPress desde el navegador:

```bash
# Abre el puerto 30093 en el Security Group de los nodos (automático)
bash commons/scripts/open-nodeport.sh 30093

# Obtén la IP pública de un nodo
kubectl get nodes -o wide
# Abre en el navegador: http://<EXTERNAL-IP>:30093
```

## Fase 4 — Aislamiento de red con NetworkPolicy

```bash
# Solo WordPress podrá conectarse a MySQL (puerto 3306)
kubectl apply -f act33/manifests/07-networkpolicy.yaml
kubectl describe networkpolicy mysql-allow-wordpress -n wordpress
```

## Fase 5 — Autoscaling bajo carga

```bash
# Aplica el HPA (escala WordPress de 1 a 5 réplicas según CPU)
kubectl apply -f act33/manifests/06-wordpress-hpa.yaml
kubectl get hpa -n wordpress      # debe mostrar "cpu: X%/50%", no <unknown>

# Genera carga para disparar el escalado
bash act33/manifests/08-stress-test.sh

# Observa el autoscaling en vivo (en otra terminal)
kubectl get hpa -n wordpress -w
kubectl get pods -n wordpress -l app=wordpress -w

# Detén la carga al terminar
bash act33/manifests/08-stress-test.sh stop
```

## Verificación general

```bash
kubectl get all -n wordpress
kubectl get pvc,pv -n wordpress
kubectl top pods -n wordpress
```

## Al terminar — OBLIGATORIO

```bash
bash commons/scripts/delete-cluster.sh
```

> El secreto en AWS Secrets Manager persiste entre sesiones. Puedes conservarlo
> para la próxima clase o eliminarlo (el script de borrado del cluster te
> recuerda el comando).
