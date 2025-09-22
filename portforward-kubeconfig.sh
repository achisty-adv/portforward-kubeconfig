#!/bin/bash
set -euo pipefail

# No positional arguments supported. Use flags only.

# ==============================
# Help
# ==============================
show_help() {
  cat <<EOF
Usage:
  $0 --sa-name <sa> --outfile <file> --namespace <ns1,ns2,ns3>
  $0 --sa-name <sa> --outfile <file> -n ns1 ns2 ns3

Description:
  Creates one ServiceAccount (in the first namespace), Roles and RoleBindings in
  all provided namespaces, and generates a single kubeconfig with multiple
  contexts for port-forwarding only.

Arguments:
  --sa-name         ServiceAccount name (same across namespaces)
  --outfile, -o     Output kubeconfig file
  --namespace, -n   One or more Kubernetes namespaces (comma- or space-separated)

Examples:
  $0 --sa-name db-portforward --outfile devs.kubeconfig --namespace production-database,staging-db
  $0 --sa-name db-portforward --outfile devs.kubeconfig --namespace ns1 ns2 ns3
EOF
  exit 0
}

# Accumulators for parsed args
NAMESPACES_LIST=()
# ==============================
# Parse args (flags only)
# ==============================
parse_args() {
  if [[ $# -eq 0 ]]; then
    echo "❌ Missing arguments. Use --help for usage."
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        ;;
      --namespace|-n)
        if [[ "$#" -ge 2 && "$2" != -* ]]; then
          IFS=',' read -ra TMP <<< "$2"
          for ns in "${TMP[@]}"; do
            [[ -n "$ns" ]] && NAMESPACES_LIST+=("$ns")
          done
          shift 2
          while [[ "$#" -gt 0 && "$1" != -* ]]; do
            IFS=',' read -ra TMP2 <<< "$1"
            for ns in "${TMP2[@]}"; do
              [[ -n "$ns" ]] && NAMESPACES_LIST+=("$ns")
            done
            shift
          done
        else
          shift
        fi
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
        echo "❌ Positional arguments are not supported. Use flags."
        exit 1
        ;;
    esac
  done

  if [[ -z "${SA_NAME:-}" || -z "${KUBECONFIG_FILE:-}" || ${#NAMESPACES_LIST[@]} -eq 0 ]]; then
    echo "❌ Missing required arguments."
    echo "Usage:"
    echo "  $0 --namespace <ns1,ns2> --sa-name <sa> --outfile <file>"
    exit 1
  fi

  declare -A _seen
  UNIQUE_NAMESPACES=()
  for ns in "${NAMESPACES_LIST[@]}"; do
    if [[ -n "$ns" && -z "${_seen[$ns]:-}" ]]; then
      UNIQUE_NAMESPACES+=("$ns")
      _seen[$ns]=1
    fi
  done
  NAMESPACES_LIST=("${UNIQUE_NAMESPACES[@]}")
}

# ==============================
# Kubernetes operations
# ==============================

parse_args "$@"

HOME_NAMESPACE="${NAMESPACES_LIST[0]}"

echo "📦 Namespaces: ${NAMESPACES_LIST[*]}"
echo "🏠 SA home namespace: $HOME_NAMESPACE"
echo "👤 ServiceAccount: $SA_NAME"
echo "📄 Kubeconfig file: $KUBECONFIG_FILE"

# 1. Create SA
echo "[1/5] Creating ServiceAccount..."
kubectl create sa "$SA_NAME" -n "$HOME_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -


create_role() {
ROLE_NAME="${SA_NAME}-role"
echo "[2/5] Creating Role + RoleBinding..."
for NAMESPACE in "${NAMESPACES_LIST[@]}"; do
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $ROLE_NAME
  namespace: $NAMESPACE
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods/portforward"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${ROLE_NAME}-binding
  namespace: $NAMESPACE
subjects:
- kind: ServiceAccount
  name: $SA_NAME
  namespace: $HOME_NAMESPACE
roleRef:
  kind: Role
  name: $ROLE_NAME
  apiGroup: rbac.authorization.k8s.io
EOF
done
}

# 3. Create Secret for SA
create_secret() {
  SECRET_NAME="${SA_NAME}-token"
  echo "[3/5] Creating Secret for token..."
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $HOME_NAMESPACE
  annotations:
    kubernetes.io/service-account.name: $SA_NAME
type: kubernetes.io/service-account-token
EOF
}

generate_kubeconfig() {
  echo "[4/5] Fetching token and cluster info..."
  sleep 2
  SECRET_NAME="${SA_NAME}-token"
  TOKEN=$(kubectl get secret "$SECRET_NAME" -n "$HOME_NAMESPACE" -o jsonpath='{.data.token}' | base64 -d)
  CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
  CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  CLUSTER_CA=$(kubectl get secret "$SECRET_NAME" -n "$HOME_NAMESPACE" -o jsonpath="{.data['ca\.crt']}" | base64 -d)

  echo "[5/5] Generating kubeconfig: $KUBECONFIG_FILE"
  kubectl config set-cluster "$CLUSTER_NAME" \
    --server="$CLUSTER_SERVER" \
    --certificate-authority=<(echo "$CLUSTER_CA") \
    --embed-certs=true \
    --kubeconfig="$KUBECONFIG_FILE" >/dev/null

  kubectl config set-credentials "${SA_NAME}-user" \
    --token="$TOKEN" \
    --kubeconfig="$KUBECONFIG_FILE" >/dev/null

  for NAMESPACE in "${NAMESPACES_LIST[@]}"; do
    CONTEXT_NAME="${NAMESPACE}"
    kubectl config set-context "$CONTEXT_NAME" \
      --cluster="$CLUSTER_NAME" \
      --namespace="$NAMESPACE" \
      --user="${SA_NAME}-user" \
      --kubeconfig="$KUBECONFIG_FILE" >/dev/null
  done

  kubectl config use-context "${NAMESPACES_LIST[0]}" --kubeconfig="$KUBECONFIG_FILE" >/dev/null

  echo "✅ kubeconfig created: $KUBECONFIG_FILE (contexts: ${#NAMESPACES_LIST[@]})"
  echo "👉 Example: kubectl --kubeconfig=$KUBECONFIG_FILE --context ${NAMESPACES_LIST[0]} -n ${NAMESPACES_LIST[0]} get pods"
  echo "👉 Example: kubectl port-forward --kubeconfig=$KUBECONFIG_FILE --context ${NAMESPACES_LIST[0]} -n ${NAMESPACES_LIST[0]} svc/<your-service> 30000:5432"
}

# ==============================
# Main
# ==============================

create_role
create_secret
generate_kubeconfig


