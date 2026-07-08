# Service Mesh for YAS - yas-dev

## 1. Mục tiêu

Triển khai Service Mesh cho ứng dụng YAS microservices trên Kubernetes bằng Istio.

Các phần đã cấu hình:

- Bật mTLS giữa các service trong namespace `yas-dev`.
- Cấu hình AuthorizationPolicy để giới hạn service-to-service communication.
- Cấu hình retry policy bằng VirtualService.
- Sử dụng Kiali để quan sát topology/traffic graph.

## 2. Namespace sử dụng

Ứng dụng YAS được triển khai trong namespace:

```bash
yas-dev
```

Kiểm tra namespace:

```bash
kubectl get namespace yas-dev --show-labels
```

Namespace cần có label:

```text
istio-injection=enabled
```

Nếu chưa có, bật bằng lệnh:

```bash
kubectl label namespace yas-dev istio-injection=enabled --overwrite
```

Restart lại deployment để inject Istio sidecar:

```bash
kubectl rollout restart deployment -n yas-dev
```

Kiểm tra pod đã được inject:

```bash
kubectl get pods -n yas-dev
```

Kết quả mong muốn:

```text
product-xxxxx        2/2 Running
cart-xxxxx           2/2 Running
order-xxxxx          2/2 Running
customer-xxxxx       2/2 Running
```

`2/2` nghĩa là pod có app container và Istio sidecar proxy.

## 3. Cấu trúc manifest

```text
k8s/service-mesh/yas-dev/
  01-mtls-strict.yaml
  02-authz-default-deny.yaml
  03-authz-product.yaml
  04-authz-inventory.yaml
  05-authz-order.yaml
  06-vs-product-retry.yaml
  README.md
```

## 4. Enable STRICT mTLS

Apply manifest:

```bash
kubectl apply -f 01-mtls-strict.yaml
```

File này gồm:

- `PeerAuthentication`: bật STRICT mTLS cho namespace `yas-dev`.
- `DestinationRule`: yêu cầu client sidecar sử dụng `ISTIO_MUTUAL` khi gọi service trong namespace.

Kiểm tra mTLS:

```bash
istioctl authn tls-check -n yas-dev
```

Hoặc:

```bash
istioctl proxy-status
```

## 5. AuthorizationPolicy

### 5.1. Default deny

Apply:

```bash
kubectl apply -f 02-authz-default-deny.yaml
```

Policy này chặn mặc định các request không được allow cụ thể.

### 5.2. Allow product

Apply:

```bash
kubectl apply -f 03-authz-product.yaml
```

Chỉ các service sau được gọi `product`:

```text
storefront-bff
backoffice-bff
cart
order
```

### 5.3. Allow inventory

Apply:

```bash
kubectl apply -f 04-authz-inventory.yaml
```

Chỉ các service sau được gọi `inventory`:

```text
backoffice-bff
order
```

### 5.4. Allow order

Apply:

```bash
kubectl apply -f 05-authz-order.yaml
```

Chỉ các service sau được gọi `order`:

```text
storefront-bff
backoffice-bff
```

## 6. Retry policy

Apply:

```bash
kubectl apply -f 06-vs-product-retry.yaml
```

VirtualService này cấu hình retry cho service `product`:

```text
attempts: 3
perTryTimeout: 2s
retryOn: 5xx, connect-failure, refused-stream, gateway-error
timeout: 5s
```

Ý nghĩa: nếu service `product` trả lỗi 5xx hoặc lỗi kết nối tạm thời, Envoy sidecar sẽ tự retry theo policy.

## 7. Apply tất cả manifest

Từ thư mục:

```bash
cd ~/projects/yas_cd/k8s/service-mesh/yas-dev
```

Apply toàn bộ:

```bash
kubectl apply -f .
```

Hoặc apply từng file:

```bash
kubectl apply -f 01-mtls-strict.yaml
kubectl apply -f 02-authz-default-deny.yaml
kubectl apply -f 03-authz-product.yaml
kubectl apply -f 04-authz-inventory.yaml
kubectl apply -f 05-authz-order.yaml
kubectl apply -f 06-vs-product-retry.yaml
```

## 8. Test AuthorizationPolicy

Tạo pod debug không có quyền gọi product:

```bash
kubectl run debug-curl \
  -n yas-dev \
  --image=curlimages/curl \
  --restart=Never \
  --command -- sleep 3600
```

Gọi product từ pod debug:

```bash
kubectl exec -n yas-dev debug-curl -c curl -- \
  curl -v http://product.yas-dev.svc.cluster.local/
```

Kết quả mong muốn:

```text
HTTP/1.1 403 Forbidden
RBAC: access denied
```

Điều này chứng minh pod không được allow sẽ bị Istio chặn.

## 9. Test allow policy

Tạo pod curl sử dụng service account `cart`:

```bash
kubectl run curl-as-cart \
  -n yas-dev \
  --image=curlimages/curl \
  --restart=Never \
  --overrides='
{
  "spec": {
    "serviceAccountName": "cart",
    "containers": [
      {
        "name": "curl",
        "image": "curlimages/curl",
        "command": ["sleep", "3600"]
      }
    ]
  }
}'
```

Gọi product:

```bash
kubectl exec -n yas-dev curl-as-cart -c curl -- \
  curl -v http://product.yas-dev.svc.cluster.local/
```

Kết quả mong muốn:

```text
Request được phép đi qua.
Không còn lỗi 403 RBAC: access denied.
```

## 10. Test retry policy

Gọi endpoint product:

```bash
kubectl exec -n yas-dev curl-as-cart -c curl -- \
  curl -v http://product.yas-dev.svc.cluster.local/
```

Nếu có endpoint test trả lỗi 500 tạm thời, ví dụ:

```text
/api/test/flaky
```

thì test:

```bash
kubectl exec -n yas-dev curl-as-cart -c curl -- \
  curl -v http://product.yas-dev.svc.cluster.local/api/test/flaky
```

Kết quả mong muốn:

```text
Envoy sidecar tự động retry khi upstream trả lỗi 5xx.
Client nhận response thành công nếu retry thành công.
```

Kiểm tra log sidecar:

```bash
kubectl logs -n yas-dev <product-pod> -c istio-proxy --tail=100
```

## 11. Quan sát Kiali topology

Mở Kiali:

```bash
kubectl port-forward -n istio-system svc/kiali 20001:20001 --address 0.0.0.0
```

Truy cập trên browser:

```text
http://localhost:20001/kiali
```

Trong Kiali:

```text
Graph -> Namespace: yas-dev
```

Chọn:

```text
Display traffic
Display security
```

Screenshot cần thể hiện:

- Các service YAS trong namespace `yas-dev`.
- Flow gọi giữa các service.
- Kết nối có security/mTLS indicator.

## 12. Kịch bản test nộp bài

### Test 1: mTLS

Lệnh:

```bash
istioctl authn tls-check -n yas-dev
```

Kết quả mong muốn:

```text
Các workload trong yas-dev sử dụng mTLS.
```

### Test 2: Authorization deny

Lệnh:

```bash
kubectl exec -n yas-dev debug-curl -c curl -- \
  curl -v http://product.yas-dev.svc.cluster.local/
```

Kết quả mong muốn:

```text
HTTP/1.1 403 Forbidden
RBAC: access denied
```

### Test 3: Authorization allow

Lệnh:

```bash
kubectl exec -n yas-dev curl-as-cart -c curl -- \
  curl -v http://product.yas-dev.svc.cluster.local/
```

Kết quả mong muốn:

```text
Request được phép đi qua.
```

### Test 4: Retry

Lệnh:

```bash
kubectl exec -n yas-dev curl-as-cart -c curl -- \
  curl -v http://product.yas-dev.svc.cluster.local/api/test/flaky
```

Kết quả mong muốn:

```text
Service trả lỗi 500 ở lần đầu.
Istio Envoy retry tự động.
Request cuối cùng thành công.
```

## 13. Ghi chú quan trọng

Các AuthorizationPolicy trong thư mục này đang dùng selector:

```yaml
selector:
  matchLabels:
    app: product
```

Nếu pod YAS không dùng label `app`, cần kiểm tra label thật bằng lệnh:

```bash
kubectl get pod -n yas-dev --show-labels
```

Ví dụ nếu pod dùng label:

```text
app.kubernetes.io/name=product
```

thì phải sửa selector thành:

```yaml
selector:
  matchLabels:
    app.kubernetes.io/name: product
```
