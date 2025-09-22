# 📖 Granting Limited Kubernetes Access

This script creates a **ServiceAccount**, **Role**, and **RoleBinding** that grant developers **limited access** to Kubernetes.  
It generates a dedicated **kubeconfig** file, allowing developers to:

- 🔍 View pods and services  
- 📜 View pod logs (`kubectl logs`)  
- 🚪 Use `kubectl port-forward` to connect to services  

All other actions (creating/deleting resources) are blocked.  

---

## ✨ Features

- Supports **one or multiple namespaces** in a single kubeconfig  
- Creates a **minimal RBAC Role** for:
  - `pods`, `services` → `get`, `list`  
  - `pods/log` → `get`, `list`  
  - `pods/portforward` → `create` 
- Generates a **ServiceAccount token** (works with Kubernetes v1.24+)  
- Builds a ready-to-use **kubeconfig file**  
- Generates kubeconfig with **separate contexts per namespace** (works with Kubernetes v1.24+)

---

## 📦 Usage

### ❗**Important:** Make sure you are running this script on the **correct Kubernetes context**.  
 The script will create ServiceAccounts, Roles, and Secrets in the current cluster context.  
 You can check your current context with:
 ```bash
 kubectl config current-context
 ```


## 🆘 Help

You can get a quick usage instruction directly from the script:

```bash
./portforward-kubeconfig.sh --help
# or
./portforward-kubeconfig.sh -h
```
### ⚙️ xArguments

Arguments can be passed as flags:

| Option            | Description                                    |
|-------------------|------------------------------------------------|
| `--namespace, -n` | One or more namespaces                         |
| `--sa-name`       | Name of the ServiceAccount                     |
| `--outfile, -o`   | Output kubeconfig filename                     |


### ▶️ 1. Example of running a script

```bash
./portforward-kubeconfig.sh \
  --namespace database-backend \
  --sa-name db-portforward \
  --outfile devs.kubeconfig
```

### 🔍  2. Verifying Access

After creating devs.kubeconfig can be context switched and checked:

```bash
kubectl --kubeconfig=devs.kubeconfig config get-contexts
kubectl --kubeconfig=devs.kubeconfig config use-context staging-db 
kubectl --kubeconfig=devs.kubeconfig get service -n staging-db get service
kubectl --kubeconfig=devs.kubeconfig port-forward svc/backend-postgres-postgresql 30000:5432 -n database-backend
```
Now the PostgreSQL service will be available locally at:

```Makefile
localhost:30000
```

You can test the generated kubeconfig to make sure it has **only the expected permissions**.

### ✅ Allowed commands

These should work:

```bash
kubectl --kubeconfig=devs.kubeconfig get pods -n database-backend
kubectl --kubeconfig=devs.kubeconfig get svc -n database-backend
kubectl --kubeconfig=devs.kubeconfig logs <pod-name>
```
### ❌ Forbidden commands

The following commands **must fail** with `Error from server (Forbidden)`:

```bash
kubectl --kubeconfig=devs.kubeconfig exec -it <pod-name> -- sh
kubectl --kubeconfig=devs.kubeconfig apply -f some-deployment.yaml
kubectl --kubeconfig=devs.kubeconfig edit svc <service>
kubectl --kubeconfig=devs.kubeconfig delete pod <pod>
```

## ✅ Benefits

- No need to expose databases or services publicly  
- Fine-grained RBAC permissions for safety
- Works across multiple namespaces
- Works with **Kubernetes 1.24+** (manual ServiceAccount token creation)  
- Secure and auditable way to provide access  
- Easy to automate and distribute with a single script  

---

## ⚠️ Security Notes

- The generated kubeconfig should be shared **securely** (not over email or Slack in plain text).  
- ServiceAccount tokens are **long-lived** by default. Rotate them periodically or consider short-lived tokens with an identity provider (e.g., OIDC).  
- Restrict access to the correct namespace — don’t grant permissions cluster-wide unless necessary.  
- Always test permissions before distributing the kubeconfig to developers.  

---

## 📜 License

MIT License — feel free to use, share, and adapt this script for your needs.
