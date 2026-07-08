#!/usr/bin/env bash
set -eu

mkdir -p argocd/dev/applications

REPO_URL="https://github.com/mrDanh11/yas_cd.git"
TARGET_REVISION="main"
NAMESPACE="yas-dev"
PROJECT="yas-dev"
DOCKER_USER="mrdanh"

BACKEND_SERVICES="
tax
cart
customer
inventory
media
order
storefront-bff
backoffice-bff
"

for svc in ${BACKEND_SERVICES}; do
cat > "argocd/dev/applications/${svc}.yaml" <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yas-dev-${svc}
  namespace: argocd
spec:
  project: ${PROJECT}

  source:
    repoURL: ${REPO_URL}
    targetRevision: ${TARGET_REVISION}
    path: k8s/charts/${svc}
    helm:
      parameters:
        - name: backend.image.repository
          value: ${DOCKER_USER}/yas-${svc}
        - name: backend.image.tag
          value: main
        - name: backend.image.pullPolicy
          value: Always
        - name: backend.ingress.className
          value: traefik
        - name: backend.resources.requests.memory
          value: 200Mi
        - name: backend.resources.requests.cpu
          value: 100m
        - name: backend.resources.limits.memory
          value: 350Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML
done

cat > argocd/dev/applications/product.yaml <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yas-dev-product
  namespace: argocd
spec:
  project: yas-dev

  source:
    repoURL: https://github.com/mrDanh11/yas_cd.git
    targetRevision: main
    path: k8s/charts/product
    helm:
      parameters:
        - name: backend.image.repository
          value: mrdanh/yas-product
        - name: backend.image.tag
          value: main
        - name: backend.image.pullPolicy
          value: Always
        - name: backend.ingress.className
          value: traefik
        - name: backend.resources.requests.memory
          value: 400Mi
        - name: backend.resources.requests.cpu
          value: 100m
        - name: backend.resources.limits.memory
          value: 800Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: yas-dev

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML

cat > argocd/dev/applications/storefront-ui.yaml <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yas-dev-storefront-ui
  namespace: argocd
spec:
  project: yas-dev

  source:
    repoURL: https://github.com/mrDanh11/yas_cd.git
    targetRevision: main
    path: k8s/charts/storefront-ui
    helm:
      parameters:
        - name: ui.image.repository
          value: mrdanh/yas-storefront-ui
        - name: ui.image.tag
          value: main
        - name: ui.image.pullPolicy
          value: Always
        - name: ui.ingress.className
          value: traefik
        - name: ui.resources.requests.memory
          value: 200Mi
        - name: ui.resources.requests.cpu
          value: 100m
        - name: ui.resources.limits.memory
          value: 350Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: yas-dev

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML

cat > argocd/dev/applications/backoffice-ui.yaml <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yas-dev-backoffice-ui
  namespace: argocd
spec:
  project: yas-dev

  source:
    repoURL: https://github.com/mrDanh11/yas_cd.git
    targetRevision: main
    path: k8s/charts/backoffice-ui
    helm:
      parameters:
        - name: ui.image.repository
          value: mrdanh/yas-backoffice-ui
        - name: ui.image.tag
          value: main
        - name: ui.image.pullPolicy
          value: Always
        - name: ui.ingress.className
          value: traefik
        - name: ui.resources.requests.memory
          value: 200Mi
        - name: ui.resources.requests.cpu
          value: 100m
        - name: ui.resources.limits.memory
          value: 350Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: yas-dev

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML

echo "Generated Argo CD dev applications successfully."
