# Synaplan with Triton Deployment

Complete deployment of Synaplan with Triton Inference Server and MariaDB using Helmfile.

## Prerequisites

### 1. Kubernetes Cluster
- Kubernetes 1.24+
- kubectl configured
- Helm 3.14+
- Helmfile installed
- OIDC provider like Keycloak

### 2. Required Secrets

**Before deploying**, you must create the required Kubernetes secrets:

```bash
# Create namespace
kubectl create namespace synaplan

# 1. Database credentials (both user password and root password)
kubectl create secret generic mariadb-credentials \
  --namespace synaplan \
  --from-literal=password="$(openssl rand -base64 32)" \
  --from-literal=root-password="$(openssl rand -base64 32)"

# 2. OIDC client secret (get from your identity provider)
kubectl create secret generic synaplan-oidc-credentials \
  --namespace synaplan \
  --from-literal=client-secret='YOUR_OIDC_CLIENT_SECRET'
```

### 3. Storage

The deployment requires persistent storage:
- **Synaplan uploads**: 10Gi (ReadWriteMany)
- **MariaDB data**: Managed by operator
- **Triton cache**: hostPath

### 4. GPU Requirements (for GPU mode)

Triton GPU mode requires:
- **GPU**: 1x NVIDIA GPU per replica
- **CPU**: 2 cores minimum
- **Memory**: 24Gi minimum

Check GPU availability:
```bash
kubectl get nodes -o json | grep nvidia.com/gpu
```

For CPU-only deployments, no GPU is required.

### 5. OIDC Identity Provider

You need an identity provider with a configured client for synaplan.

## Deployment

### Environment Configuration

This deployment uses **helmfile environments**. Each environment is configured in `environments/{environment-name}/values.yaml`.

**Important**: The helmfile assumes the **kubeContext name matches the environment name**. For example:
- Environment `default` → kubeContext `default`

Check your available contexts:
```bash
kubectl config get-contexts
```

If your context name differs, either:
- Rename your context: `kubectl config rename-context old-name new-name`
- Or override the kubeContext in `helmfile.yaml.gotmpl`

Included environments:
- **default** - Template environment with GPU mode

### Deploy to an Environment

```bash
# Deploy to default environment
helmfile -e default apply
```

## Configuration

### Triton Modes

**GPU Mode** (`mode: gpu`):
- Uses TensorRT-LLM for optimized inference
- Requires NVIDIA GPU
- Fast inference (<1s response times)
- Models: `mistral-7b-instruct-v0.3`, `mistral-streaming`

**CPU Mode** (`mode: cpu`):
- Uses PyTorch backend with vLLM
- No GPU required
- Slower inference (5-30s response times)
- Model: `mistral-cpu`

### Custom Root CA

For clusters with custom certificate authorities, set `customRootCA: true`:

```yaml
cluster:
  customRootCA: true
```

This will:
- Mount the CA certificate from the `synaplan-tls` secret

### Realtime & Async Processing (optional, app image >= 2.5)

Synaplan's realtime release adds Redis, a Centrifugo WebSocket gateway, and a
Symfony Messenger worker. All three are **disabled by default** (safe for
2.4.x images). Enable them per environment under `services:`:

```yaml
services:
  redis:
    enabled: true
  centrifugo:
    enabled: true
    secretRef: "synaplan-realtime"   # api-key, token-hmac-secret-key, admin-password, admin-secret
    allowedOrigins: "https://synaplan.example.com"
  worker:
    enabled: true
```

Create the realtime secret first:

```bash
kubectl create secret generic synaplan-realtime -n synaplan \
  --from-literal=api-key=$(openssl rand -hex 32) \
  --from-literal=token-hmac-secret-key=$(openssl rand -hex 32) \
  --from-literal=admin-password=$(openssl rand -hex 16) \
  --from-literal=admin-secret=$(openssl rand -hex 32)
```

Notes: enable all three together; the worker needs `persistence.uploads`
(ReadWriteMany) to read uploaded files; WebSockets ride the normal app
ingress at `/connection/websocket` (ensure idle timeouts >= 60s). See the
[synaplan chart README](../../charts/synaplan/README.md) for all options.

## Access the Application

After deployment, access Synaplan at the configured URL (e.g., `https://synaplan.example.com`).

## Create Admin User

After deployment, create an initial admin user:

```bash
NS=synaplan              # adjust to your namespace
MAIL=admin@example.com   # adjust to your email
PW=CHANGE-ME-NOW         # use a strong password

kubectl exec -n "$NS" deployment/synaplan -- php -r "
\$pdo = new PDO('mysql:host=mariadb-cluster.$NS.svc.cluster.local;dbname=synaplan', 'synaplan', getenv('DB_PASSWORD'));
\$pdo->exec(\"INSERT INTO BUSER (BCREATED, BINTYPE, BMAIL, BPW, BPROVIDERID, BUSERLEVEL, BEMAILVERIFIED, BUSERDETAILS, BPAYMENTDETAILS) VALUES ('\" . date('Y-m-d H:i:s') . \"', 'WEB', '$MAIL', '\" . password_hash('$PW', PASSWORD_BCRYPT) . \"', 'local', 'ADMIN', 1, '{}', '{}')\");
echo \"Admin user created\n\";
"
```

## Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n synaplan

# Expected output:
# NAME                                READY   STATUS    RESTARTS   AGE
# mariadb-cluster-0                   1/1     Running   0          5m
# mariadb-operator-xxx                1/1     Running   0          5m
# synaplan-xxx                        1/1     Running   0          3m
# triton-xxx                          1/1     Running   0          3m

# Check services
kubectl get svc -n synaplan

# Check ingress (if enabled)
kubectl get ingress -n synaplan
```

## Troubleshooting

### Pods Not Starting

Check pod status and events:
```bash
kubectl get pods -n synaplan
kubectl describe pod <pod-name> -n synaplan
```

### Secret Not Found Errors

Verify all required secrets exist:
```bash
kubectl get secrets -n synaplan
```

Expected secrets:
- `mariadb-credentials` (database password)
- `synaplan-oidc-credentials` (OIDC client secret)
- `synaplan-tls` (TLS certificate, if using ingress)

### Triton Pod Pending (Insufficient GPU)

If deploying in GPU mode without GPUs:
```bash
# Check GPU availability
kubectl get nodes -o json | grep nvidia.com/gpu

# If no GPUs, switch to CPU mode in environment values:
services:
  triton:
    mode: cpu
```

### OIDC Authentication Fails

1. Verify OIDC secret exists and is correct
2. Check issuer URI is accessible from the cluster
3. Verify client ID matches your identity provider
4. Review Synaplan logs for detailed errors:
   ```bash
   kubectl logs -n synaplan deployment/synaplan
   ```

## Advanced Configuration

### Switch Between GPU and CPU Modes

Simply change the mode in your environment values:

```yaml
services:
  triton:
    mode: cpu  # Change to "gpu" or "cpu"
```

Then apply:
```bash
helmfile -e my-env apply
```

The helmfile will automatically use the correct Triton configuration file.

## Production Recommendations

1. **Use strong secrets** - Generate cryptographically secure passwords
2. **Enable TLS** - Configure cert-manager and ingress with valid certificates
3. **Configure backups** - Set up MariaDB backup schedules
4. **Monitor resources** - Set up Prometheus metrics and alerts
5. **Scale appropriately** - Adjust replica counts and resource limits
6. **Use GPU mode** - For production workloads requiring fast inference
7. **Separate environments** - Use different environments for dev/staging/prod

## Support

For issues and questions:
- Review pod logs: `kubectl logs -n synaplan <pod-name>`
- Check Kubernetes events: `kubectl get events -n synaplan`
