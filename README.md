# 🎯 Kubernetes Port-Forward Access Script

This script helps you generate a **restricted kubeconfig** that only allows developers to use  
`kubectl port-forward` to access a service (e.g., PostgreSQL) inside Kubernetes.  

It does **not** give full cluster access — only the minimal permissions required.

---

## ✨ Features

- Creates a **ServiceAccount** in the target namespace  
- Assigns a **minimal Role** with only:
  - `get`, `list` on Services and Pods  
  - `create` on `pods/portforward`  
- Generates a **ServiceAccount token** (works with Kubernetes v1.24+)  
- Builds a ready-to-use **kubeconfig file**  
- Developers can only **port-forward** services — nothing else  

---

## 📦 Usage

### ❗**Important:** Make sure you are running this script on the **correct Kubernetes context**.  
 The script will create ServiceAccounts, Roles, and Secrets in the current cluster context.  
 You can check your current context with:
 ```bash
 kubectl config current-context
 ```

You can run the script in **two ways**:  
1. With **flags** (`--namespace`, `--sa-name`, `--outfile`)  
2. With **positional arguments** (`$1 $2 $3`)  

If no arguments are provided, the script uses defaults:
- Namespace: `default`
- ServiceAccount: `portforward-sa`
- Output kubeconfig: `portforward.kubeconfig`

## 🆘 Help

You can get a quick usage instruction directly from the script:

```bash
./portforward-kubeconfig.sh --help
# or
./portforward-kubeconfig.sh -h
```
### Arguments

You can pass options either with flags (`--namespace`, `--sa-name`, etc.) or as positional arguments (`$1`, `$2`, …).

| Option            | Positional | Description                                    | Default                |
|-------------------|------------|------------------------------------------------|------------------------|
| `--namespace, -n` | `$1`       | Namespace where ServiceAccount will be created | `default`              |
| `--sa-name`       | `$2`       | Name of the ServiceAccount                     | `portforward-sa`       |
| `--outfile, -o`   | `$3`       | Output kubeconfig filename                     | `portforward.kubeconfig` |

### 1. Examples of running a script

#### ▶️ Using flags

```bash
./portforward-kubeconfig.sh \
  --namespace database-backend \
  --sa-name db-portforward \
  --outfile devs.kubeconfig
```
#### ▶️ Using positional arguments

```bash
./portforward-kubeconfig.sh database-backend db-portforward devs.kubeconfig
```

#### ▶️ With defaults
```bash
./portforward-kubeconfig.sh
```

### 2. Share kubeconfig with developers
Developers can use the generated kubeconfig like this:

```bash
KUBECONFIG=devs.kubeconfig kubectl port-forward svc/backend-postgres-postgresql 30000:5432 -n database-backend
```
Now the PostgreSQL service will be available locally at:

```Makefile
localhost:30000
```


## 🔍 Verifying Access

You can test the generated kubeconfig to make sure it has **only the expected permissions**.

### ✅ Allowed commands

These should work:

```bash
KUBECONFIG=devs.kubeconfig kubectl get pods -n database-backend
KUBECONFIG=devs.kubeconfig kubectl get svc -n database-backend
```
### ❌ Forbidden commands

The following commands **must fail** with `Error from server (Forbidden)`:

```bash
KUBECONFIG=devs.kubeconfig kubectl logs <pod-name>
KUBECONFIG=devs.kubeconfig kubectl exec -it <pod-name> -- sh
KUBECONFIG=devs.kubeconfig kubectl apply -f some-deployment.yaml
```

## ✅ Benefits

- No need to expose databases or services publicly  
- Fine-grained RBAC permissions for safety  
- Works with **Kubernetes 1.24+** (manual ServiceAccount token creation)  
- Secure and auditable way to provide developers access  
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
