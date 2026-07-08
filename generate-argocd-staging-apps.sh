#!/usr/bin/env bash
set -eu

mkdir -p argocd/staging/applications

REPO_URL="https://github.com/mrDanh11/yas_cd.git"
TARGET_REVISION="main"
NAMESPACE="yas-staging"
PROJECT="yas-staging"
DOCKER_USER="mrdanh"
IMAGE_TAG="main"

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
cat > "argocd/staging/applications/${svc}.yaml" <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yas-staging-${svc}
  namespace: argocd
spec:
  project: ${PROJECT}

  source:
    repoURL: ${REPO_URL}
    targetRevision: ${TARGET_REVISION}
    path: k8s/charts/${svc}
    helm:
      releaseName: ${svc}
      parameters:
        - name: backend.image.repository
          value: ${DOCKER_USER}/yas-${svc}
        - name: backend.image.tag
          value: ${IMAGE_TAG}
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

cat > argocd/staging/applications/product.yaml <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yas-staging-product
  namespace: argocd
spec:
  project: yas-staging

  source:
    repoURL: https://github.com/mrDanh11/yas_cd.git
    targetRevision: main
    path: k8s/charts/product
    helm:
      releaseName: product
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
    namespace: yas-staging

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML

cat > argocd/staging/applications/storefront-ui.yaml <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yas-staging-storefront-ui
  namespace: argocd
spec:
  project: yas-staging

  source:
    repoURL: https://github.com/mrDanh11/yas_cd.git
    targetRevision: main
    path: k8s/charts/storefront-ui
    helm:
      releaseName: storefront-ui
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
    namespace: yas-staging

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML

cat > argocd/staging/applications/backoffice-ui.yaml <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yas-staging-backoffice-ui
  namespace: argocd
spec:
  project: yas-staging

  source:
    repoURL: https://github.com/mrDanh11/yas_cd.git
    targetRevision: main
    path: k8s/charts/backoffice-ui
    helm:
      releaseName: backoffice-ui
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
    namespace: yas-staging

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML

echo "Generated Argo CD staging applications successfully."
