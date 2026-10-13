# Synaplan standalone deployment

Synaplan in its own namespace with MariaDB, Tika and a model backend, using Helmfile. The backend is Triton Inference Server, installed here, or an Ollama you already run.

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
- **Triton cache**: hostPath (Triton backends only)

### 4. GPU Requirements (for the `triton-gpu` backend)

Triton on GPU requires:
- **GPU**: 1x NVIDIA GPU per replica
- **CPU**: 2 cores minimum
- **Memory**: 24Gi minimum

Check GPU availability:
```bash
kubectl get nodes -o json | grep nvidia.com/gpu
```

The `triton-cpu` and `ollama` backends need no GPU in this deployment.

### 5. OIDC Identity Provider

You need an identity provider with a configured client for synaplan.

## Deployment

### Environment Configuration

This deployment uses **helmfile environments**. Each environment is configured in `environments/{environment-name}/values.yaml`. `default` is the example committed in this repo (local Triton on GPU); other environment directories are gitignored.

### Deploy to an Environment

```bash
# Name the cluster with --kube-context or --kubeconfig
helmfile -e default --kube-context my-cluster apply
helmfile -e default --kubeconfig /path/to/kubeconfig apply

# Layer a values file kept outside this repo over the environment's values
helmfile -e default --kube-context my-cluster --state-values-file /path/to/cluster-values.yaml apply
```

Without either flag, Helmfile uses the current kubectl context.

## Configuration

### Model backend

`services.backend` selects where chat and embedding models run:

| Backend | Installs | Notes |
| --- | --- | --- |
| `triton-gpu` (default) | Triton with TensorRT-LLM | Needs an NVIDIA GPU. Fast inference (<1s). Models: `mistral-7b-instruct-v0.3`, `mistral-streaming` |
| `triton-cpu` | Triton with the PyTorch backend | No GPU. Slow inference (5-30s). Model: `mistral-cpu` |
| `ollama` | nothing | Uses the Ollama at `services.synaplan.ollama.baseUrl` |

The default environment lists Triton models. With `ollama`, list that Ollama's models instead; an empty default is skipped:

```yaml
services:
  backend: ollama
  synaplan:
    ollama:
      baseUrl: http://ollama.example.svc.cluster.local:11434
    models:
      enabled:
        - "ollama:bge-m3"
        - "ollama:<your chat model>"
      defaults:
        chat: "ollama:<your chat model>"
        sort: "ollama:<your chat model>"
        vectorize: "ollama:bge-m3"
```

### Cloud providers

By default only models that run in the cluster are offered (the backend, Piper and Whisper), and the browser's Web Speech API is off because it sends audio to the browser vendor. A cloud provider that a later Synaplan release adds stays off too.

`services.cloudProviders: true` lifts both. API keys come from `services.synaplan.apiKeysSecretRef`.

### Speech-to-text

`services.stt.mode` is `""` (off, the default), `gpu`, or `cpu`.

- **Off**: Synaplan uses the whisper.cpp binary in its own pod.
- **GPU**: the `stt` release runs the CUDA image and requests one NVIDIA GPU.
  That is a second GPU beside Triton, unless the node time-slices or uses MIG.
- **CPU**: no GPU request. About two times real time on 8 threads.

Synaplan's `speech.whisperServerUrl` points at that Service. `services.stt.values`
is passed through to the chart. The helmfile sets `fullnameOverride` (default
`stt`), so the Service name is fixed and `nameOverride` does not change it;
set `fullnameOverride` or `service.port` there and the URL follows. The
NetworkPolicy admits Synaplan's web, worker and scheduler pods (not the
bundled redis or tts) and the chart's `helm test` pod.

### Custom Root CA

For clusters with custom certificate authorities, set `customRootCA: true`:

```yaml
cluster:
  customRootCA: true
```

(This deployment maps the flag to the chart's `customRootCA.secretRef`,
pointing at the cert-manager-issued `synaplan-tls` secret. The chart also
accepts an inline PEM via `customRootCA.crt`.)

This will:
- Mount the CA certificate from the `synaplan-tls` secret

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

# If no GPUs, switch the backend in your environment values:
services:
  backend: triton-cpu
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

### Switch the model backend

Change `services.backend` in your environment values and apply:

```bash
helmfile -e my-env apply
```

## Production Recommendations

1. **Use strong secrets** - Generate cryptographically secure passwords
2. **Enable TLS** - Configure cert-manager and ingress with valid certificates
3. **Configure backups** - Set up MariaDB backup schedules
4. **Monitor resources** - Set up Prometheus metrics and alerts
5. **Scale appropriately** - Adjust replica counts and resource limits
6. **Use the `triton-gpu` backend** - For production workloads requiring fast inference
7. **Separate environments** - Use different environments for dev/staging/prod

## Support

For issues and questions:
- Review pod logs: `kubectl logs -n synaplan <pod-name>`
- Check Kubernetes events: `kubectl get events -n synaplan`
