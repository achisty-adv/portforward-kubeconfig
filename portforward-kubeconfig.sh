#!/bin/bash
set -euo pipefail

# ==============================
# Defaults
# ==============================
NAMESPACE="default"
SA_NAME="portforward-sa"
KUBECONFIG_FILE="portforward.kubeconfig"

show_help() {
  echo "Usage:"
  echo "  $0 [--namespace <ns>] [--sa-name <name>] [--outfile <file>]"
  echo "  $0 [namespace] [sa-name] [outfile]"
  echo
  echo "Examples:"
  echo "  $0 --namespace production-database-backend --sa-name db-portforward --outfile devs-db.kubeconfig"
  echo "  $0 production-database-backend db-portforward devs-db.kubeconfig"
  exit 0
}

# ==============================
# Parse args (flags or positional)
# ==============================
parse_args() {
  if [[ $# -eq 0 ]]; then
    return
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        ;;
      --namespace|-n)
        NAMESPACE="$2"
        shift 2
        ;;
      --sa-name)
        SA_NAME="$2"
        shift 2
        ;;
      --outfile|-o)
        KUBECONFIG_FILE="$2"
        shift 2
        ;;
      --*)
        echo "❌ Unknown flag: $1"
        exit 1
        ;;
      *)
        # Positional arguments
        if [[ "$NAMESPACE" == "default" ]]; then
          NAMESPACE="$1"
        elif [[ "$SA_NAME" == "portforward-sa" ]]; then
          SA_NAME="$1"
        elif [[ "$KUBECONFIG_FILE" == "portforward.kubeconfig" ]]; then
          KUBECONFIG_FILE="$1"
        else
          echo "❌ Unknown argument: $1"
          exit 1
        fi
        shift
        ;;
    esac
  done
}

# ==============================
# Kubernetes operations
# ==============================
create_sa() {
  echo "[1/5] Creating ServiceAccount: $SA_NAME in namespace $NAMESPACE..."
  kubectl create sa "$SA_NAME" -n "$NAMESPACE" 2>/dev/null || true
}

create_role() {
  ROLE_NAME="${SA_NAME}-role"
  echo "[2/5] Creating Role + RoleBinding..."
  cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $ROLE_NAME
  namespace: $NAMESPACE
rules:
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/portforward"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${ROLE_NAME}-binding
  namespace: $NAMESPACE
subjects:
- kind: ServiceAccount
  name: $SA_NAME
  namespace: $NAMESPACE
roleRef:
  kind: Role
  name: $ROLE_NAME
  apiGroup: rbac.authorization.k8s.io
EOF
}

create_secret() {
  SECRET_NAME="${SA_NAME}-token"
  echo "[3/5] Creating Secret for token..."
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/service-account.name: $SA_NAME
type: kubernetes.io/service-account-token
EOF
}

generate_kubeconfig() {
  echo "[4/5] Fetching token and cluster info..."
  sleep 2
  SECRET_NAME="${SA_NAME}-token"
  TOKEN=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.token}' | base64 -d)
  CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
  CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  CLUSTER_CA=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath="{.data['ca\.crt']}" | base64 -d)

  echo "[5/5] Generating kubeconfig: $KUBECONFIG_FILE"
  kubectl config set-cluster "$CLUSTER_NAME" \
    --server="$CLUSTER_SERVER" \
    --certificate-authority=<(echo "$CLUSTER_CA") \
    --embed-certs=true \
    --kubeconfig="$KUBECONFIG_FILE" >/dev/null

  kubectl config set-credentials "${SA_NAME}-user" \
    --token="$TOKEN" \
    --kubeconfig="$KUBECONFIG_FILE" >/dev/null

  kubectl config set-context "${SA_NAME}-context" \
    --cluster="$CLUSTER_NAME" \
    --namespace="$NAMESPACE" \
    --user="${SA_NAME}-user" \
    --kubeconfig="$KUBECONFIG_FILE" >/dev/null

  kubectl config use-context "${SA_NAME}-context" --kubeconfig="$KUBECONFIG_FILE" >/dev/null

  echo "✅ kubeconfig created: $KUBECONFIG_FILE"
  echo "👉 Developers can use it like this:"
  echo "   KUBECONFIG=$KUBECONFIG_FILE kubectl port-forward svc/<your-service> 30000:5432 -n $NAMESPACE"
}

# ==============================
# Main
# ==============================
parse_args "$@"

echo "📦 Namespace: $NAMESPACE"
echo "👤 ServiceAccount: $SA_NAME"
echo "📄 Kubeconfig file: $KUBECONFIG_FILE"

create_sa
create_role
create_secret
generate_kubeconfig
