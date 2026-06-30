#!/usr/bin/env bash
set -e

# Config
export FIDES_SERVER_URL="http://localhost:8191"
export FIDES_ENCRYPTION_KEY="passphrase-secret-passphrase-secret"
export ORG_ID="5d57b8c7-4328-4e1b-93df-4161b9a918a3"
export FLOW_ID="f83b3e8c-8dc7-4a0b-ae95-716d1ba1f122"
export COMMIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "mock-commit-sha-999")

CLI="../evidance-vault/fides"

echo "=========================================="
echo "🚀 Running Local Fides CI/CD Test Pipeline"
echo "=========================================="

# 1. Start trail
echo "Step 1: Starting Trail run..."
RESPONSE=$($CLI trail start \
  --flow $FLOW_ID \
  --trail "build-$COMMIT_SHA-$(date +%s)" \
  --repository "https://github.com/olafkfreund/fides-testing" \
  --commit $COMMIT_SHA \
  --branch "main" \
  --message "chore: local deployment testing run")

echo "Server Response: $RESPONSE"
TRAIL_UUID=$(echo "$RESPONSE" | grep -o '{.*}' | jq -r '.id')
echo "Extracted Trail UUID: $TRAIL_UUID"

# 2. Build Docker container image and push to AWS ECR
echo "Step 2: Authenticating with AWS ECR and building image..."
aws ecr get-login-password --region eu-west-2 --profile Synechron | docker login --username AWS --password-stdin 796973489124.dkr.ecr.eu-west-2.amazonaws.com

docker build -t 796973489124.dkr.ecr.eu-west-2.amazonaws.com/fides-testing-service:latest .
docker push 796973489124.dkr.ecr.eu-west-2.amazonaws.com/fides-testing-service:latest

IMAGE_DIGEST=$(docker inspect --format='{{index .Id 0}}' 796973489124.dkr.ecr.eu-west-2.amazonaws.com/fides-testing-service:latest)
echo "Captured Image SHA256: $IMAGE_DIGEST"

# 3. Report Artifact
echo "Step 3: Registering Artifact..."
$CLI artifact report \
  --org $ORG_ID \
  --trail $TRAIL_UUID \
  --sha256 $IMAGE_DIGEST \
  --name "fides-testing-service" \
  --type "docker"

# 4. Attest unit tests
echo "Step 4.1: Attesting unit tests..."
echo '{"tests": 10, "failures": 0, "errors": 0}' > junit-summary.json
$CLI attest \
  --trail $TRAIL_UUID \
  --artifact-sha $IMAGE_DIGEST \
  --name "unit-tests" \
  --type "junit" \
  --payload junit-summary.json \
  --encrypt

# 5. Attest security scan (Snyk)
echo "Step 4.2: Attesting security scan..."
echo '{"vulnerabilities": {"critical": 0}}' > scan-summary.json
$CLI attest \
  --trail $TRAIL_UUID \
  --artifact-sha $IMAGE_DIGEST \
  --name "snyk-scan" \
  --type "snyk-scan" \
  --payload scan-summary.json \
  --encrypt

# 6. Attest secret scan
echo "Step 4.3: Attesting secret scan..."
echo '{"leaks": 0}' > secret-summary.json
$CLI attest \
  --trail $TRAIL_UUID \
  --artifact-sha $IMAGE_DIGEST \
  --name "secret-scan" \
  --type "secret-scan" \
  --payload secret-summary.json \
  --encrypt

# 7. Assert Policy Gate
echo "Step 5: Verifying policy rules assertion gate..."
$CLI assert \
  --sha256 $IMAGE_DIGEST \
  --policy "production-release-rules"

# 8. Apply K8s namespaces and deploy application
echo "Step 6: Deploying to Kubernetes namespaces..."
kubectl apply -f kubernetes/namespaces.yaml
kubectl apply -f kubernetes/deployment.yaml -n dev
kubectl apply -f kubernetes/deployment.yaml -n uat
kubectl apply -f kubernetes/deployment.yaml -n prod

# 9. Update Runtime State snapshot
echo "Step 7: Capturing environment runtime snapshot..."
$CLI snapshot k8s --env 9f3c7ea1-420a-4288-ae31-716d1ba1f021

# Clean up temp files
rm -f junit-summary.json scan-summary.json secret-summary.json

echo "=========================================="
echo "🎉 Compliance Assert and Deploy succeeded!"
echo "=========================================="
