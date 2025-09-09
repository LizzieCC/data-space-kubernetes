# IDS Deployment on Kubernetes (2025)

Este documento describe los pasos necesarios para desplegar un **IDS (International Data Spaces) testbed** en Kubernetes. Incluye la creación de namespaces, configuración de seguridad (TLS), despliegue de un Ingress Controller, y despliegue de los componentes principales (Broker, Connectors, Omejdn, UIs).  

## 1. Crear el Namespace

```bash
kubectl create namespace ids-2
```

> Nota: asegúrate de que el nombre del namespace sea consistente (`ids-2`) en todos los comandos.

---

## 2. Configurar resolución local en `/etc/hosts`

Agregar las siguientes entradas para resolver localmente los conectores:

```
127.0.0.1 connectora.localhost
127.0.0.1 connectorb.localhost
```

---

## 3. Generar Certificado TLS (X.509)

Generar un certificado autofirmado para pruebas locales:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt
```

Crear el secreto en Kubernetes:

```bash
kubectl create secret tls tls-secret --key tls.key --cert tls.crt -n ids-2
```

---

## 4. Desplegar Ingress Controller (NGINX)

Aplicar el manifiesto oficial de Ingress NGINX:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.2.0/deploy/static/provider/cloud/deploy.yaml
```

Aplicar configuración específica del testbed:

```bash
kubectl apply -f ./Nginx/4-ingress-connection-nginx.yaml -n ids-2
```

---

## 5. Despliegue de los Componentes IDS

### 5.1 Broker

```bash
kubectl apply -f ./idsa_manifest_local/Broker/0-broker-core-services.yaml -n ids-2
kubectl apply -f ./idsa_manifest_local/Broker/1-broker-core-deployment.yaml -n ids-2
kubectl apply -f ./idsa_manifest_local/Broker/2-daps-broker-configmap.yaml -n ids-2
kubectl apply -f ./idsa_manifest_local/Broker/2-daps-broker-secret.yaml -n ids-2
```

---

### 5.2 Connectors  

> Requiere al menos **11 GB de memoria asignada** al cluster Docker/Kubernetes.

```bash
kubectl apply -f ./idsa_manifest_local/Connectors/0-connectors-services.yaml -n ids-2
kubectl apply -f ./idsa_manifest_local/Connectors/3-connectors-secrets.yaml -n ids-2
kubectl apply -f ./idsa_manifest_local/Connectors/1-connectorA.yaml -n ids-2
kubectl apply -f ./idsa_manifest_local/Connectors/1-connectorB.yaml -n ids-2
kubectl apply -f ./idsa_manifest_local/Connectors/2-connectors-configmap.yaml -n ids-2
```

---

### 5.3 Omejdn (Authorization Server)

```bash
kubectl apply -f ./idsa_manifest_local/Omejdn/0-omejdn-services.yaml -n ids-2
kubectl apply -f ./idsa_manifest_local/Omejdn/1-omejdn-deployments.yaml -n ids-2
kubectl apply -f ./idsa_manifest_local/Omejdn/2-omejdn-configmap.yaml -n ids-2
```

---

## 6. Despliegue de las Interfaces de Usuario (UIs)

```bash
kubectl apply -f ./idsa_manifest_local/Connectors/4-connectorA-ui.yaml -n ids-2
kubectl apply -f ./idsa_manifest_local/Connectors/4-connectorB-ui.yaml -n ids-2
```

---

## 7. Verificación del despliegue

1. Verificar que todos los pods están corriendo:
   ```bash
   kubectl get pods -n ids-2
   ```

2. Probar acceso vía los hosts configurados:
   - [https://connectora.localhost](https://connectora.localhost)  
   - [https://connectorb.localhost](https://connectorb.localhost)  

3. Revisar logs en caso de fallos:
   ```bash
   kubectl logs <pod-name> -n ids-2
   ```

---

## 8. Notas finales

- Para producción se recomienda integrar certificados válidos (ej. Let’s Encrypt) y ajustar políticas de seguridad en `Ingress` y `NetworkPolicies`.  
- Solo el directorio *idsa_manifest_local* esta actualizado.
