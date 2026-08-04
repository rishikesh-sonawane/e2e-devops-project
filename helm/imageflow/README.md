# helm/imageflow

Helm chart for deploying the **ImageFlow API** to **Floci EKS** (a real k3s
cluster — Phase 11, ADR-04). Contains Deployment, Service, ConfigMap, Secret,
HPA, and an optional Ingress.

## Prerequisites

- Floci running: `floci start && eval $(floci env)`
- An EKS cluster (real k3s): `aws eks create-cluster --name imageflow-test
  --role-arn arn:aws:iam::000000000000:role/ImageFlowAPIRole
  --resources-vpc-config '{}'` → wait ACTIVE, then
  `aws eks update-kubeconfig --name imageflow-test --region us-east-1`
- The API image in Floci ECR: `./scripts/push-api.sh`

## Deploy

```bash
./scripts/push-api.sh                        # build + push API image to ECR (:5100)
helm install imageflow ./helm/imageflow      # Deploy + Service + ConfigMap + Secret + HPA
kubectl rollout status deployment/imageflow  # wait for Ready
kubectl port-forward svc/imageflow 8000:8000 # expose locally
curl http://127.0.0.1:8000/health            # {"status":"ok",...}
```

Upgrade after `values.yaml` changes:

```bash
helm upgrade imageflow ./helm/imageflow
```

## Configuration (values.yaml)

| Key | Default | Notes |
|---|---|---|
| `config.awsEndpointUrl` | `http://host.docker.internal:4566` | Floci reachable from inside pods (localhost is the pod). **Emulator-specific** — real k8s/AWS would use real service endpoints + private-registry pull secrets |
| `config.imageProcessingTrigger` | `direct` | Processor trigger mode |
| `secret.awsAccessKeyId/awsSecretAccessKey` | base64("test") | Dummy Floci creds (ADR-02); real AWS → external secrets |
| `autoscaling` | enabled, 1–3, 70% CPU | HorizontalPodAutoscaler |
| `image.repository` | `…localhost:5100/imageflow-api` | Floci ECR (real registry) |

## Known Floci quirk (image pull DNS)

Floci pre-wires the k3s node's containerd to mirror `…localhost:5100` →
`http://floci-ecr-registry:5000`, but on Docker's default `bridge` network the
container name does **not** resolve from the node (Docker embedded DNS only
works on user-defined networks). Until Floci ships a fix, add one hosts entry
on the node after creating the cluster:

```bash
NODE=$(docker ps --format '{{.Names}}' | grep floci-eks | head -1)
REG_IP=$(docker inspect floci-ecr-registry --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
docker exec "$NODE" sh -c "echo '$REG_IP floci-ecr-registry' >> /etc/hosts"
kubectl rollout restart deployment/imageflow
```

(Without it the pod hits `ImagePullBackOff` → `dial tcp: lookup
floci-ecr-registry: no such host`.)

## Resources

- Deployment: non-root (uid 1000), readOnlyRootFilesystem, liveness/readiness
  on `/health`, ConfigMap + Secret via `envFrom` (checksum annotation forces
  rollout on config change)
- Service: ClusterIP :8000
- ConfigMap: AWS endpoint/region, buckets, table, SNS topic, trigger
- Secret: dummy credentials (base64 in values.yaml)
- HPA: CPU-based autoscaling 1–3 replicas
- Ingress: disabled by default (k3s here ships no ingress controller)
