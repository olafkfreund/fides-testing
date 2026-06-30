#!/usr/bin/env bash
set -e

# Config
export FIDES_SERVER_URL="http://localhost:8191"
export FIDES_ENCRYPTION_KEY="passphrase-secret-passphrase-secret"
export ORG_ID="5d57b8c7-4328-4e1b-93df-4161b9a918a3"
export FLOW_ID="f83b3e8c-8dc7-4a0b-ae95-716d1ba1f122"
export TRAIL_ID=$(git rev-parse HEAD 2>/dev/null || echo "mock-commit-sha-999")

CLI="../evidance-vault/fides"

echo "=========================================="
echo "🚀 Running Local Fides CI/CD Test Pipeline"
echo "=========================================="

# 1. Start trail
echo "Step 1: Starting Trail run..."
$CLI trail start \
  --flow $FLOW_ID \
  --trail $TRAIL_ID \
  --repository "https://github.com/olafkfreund/fides-testing" \
  --commit $TRAIL_ID \
  --branch "main" \
  --message "chore: local deployment testing run"

# 2. Build Docker container image locally
echo "Step 2: Building container image..."
docker build -t fides-testing-service:latest .
IMAGE_DIGEST=$(docker inspect --format='{{index .Id}}' fides-testing-service:latest)
echo "Captured Image SHA256: $IMAGE_DIGEST"

# 3. Report Artifact
echo "Step 3: Registering Artifact..."
$CLI artifact report \
  --org $ORG_ID \
  --trail $TRAIL_ID \
  --sha256 $IMAGE_DIGEST \
  --name "fides-testing-service" \
  --type "docker"

# 4. Attest security scan
echo "Step 4: Creating security scan attestation..."
echo "{\"vulnerabilities\": {\"critical\": 0}}" > scan-summary.json
$CLI attest \
  --trail $TRAIL_ID \
  --artifact-sha $IMAGE_DIGEST \
  --name "snyk-scan" \
  --type "snyk-scan" \
  --payload scan-summary.json \
  --encrypt

# 5. Assert Policy Gate
echo "Step 5: Verifying policy rules assertion gate..."
$CLI assert \
  --sha256 $IMAGE_DIGEST \
  --policy "production-release-rules"

# 6. Apply K8s namespaces and deploy application
echo "Step 6: Deploying to Kubernetes namespaces..."
kubectl apply -f kubernetes/namespaces.yaml
kubectl apply -f kubernetes/deployment.yaml -n dev
kubectl apply -f kubernetes/deployment.yaml -n uat
kubectl apply -f kubernetes/deployment.yaml -n prod

echo "=========================================="
echo "🎉 Compliance Assert and Deploy succeeded!"
echo "=========================================="
