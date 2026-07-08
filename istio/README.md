# Hướng Dẫn Cấu Hình và Kiểm Thử Istio Service Mesh (YAS Project)

Tài liệu này hướng dẫn cách cấu hình, triển khai và kiểm thử các tính năng nâng cao của **Istio Service Mesh** (mTLS STRICT, Authorization Policy, Retry Policy) cho ứng dụng microservices **YAS (Yet Another Shop)** sử dụng GitOps (**ArgoCD**).

Toàn bộ cấu hình Service Mesh được đặt tại thư mục root `/istio` độc lập để dễ dàng quản lý.

---

## 1. Sơ Đồ Kiến Trúc & Luồng Traffic (Service Mesh Topology)

Hệ thống kết hợp chế độ **PERMISSIVE mTLS** cho các dịch vụ biên (chấp nhận traffic chưa mã hóa từ Traefik Ingress Controller bên ngoài mesh) và **STRICT mTLS** cho các giao tiếp nội bộ giữa các microservices.

```mermaid
graph TD
    %% Ingress & Edge
    Ingress[Traefik Ingress Controller] -->|HTTP / Permissive| StorefrontUI[storefront-ui]
    Ingress -->|HTTP / Permissive| BackofficeUI[backoffice-ui]
    Ingress -->|HTTP / Permissive| SwaggerUI[swagger-ui]
    Ingress -->|HTTP / Permissive| Keycloak[keycloak]
    Ingress -->|HTTP / Permissive| StorefrontBFF[storefront-bff]
    Ingress -->|HTTP / Permissive| BackofficeBFF[backoffice-bff]

    %% Internal mTLS STRICT
    subgraph Service Mesh (STRICT mTLS)
        StorefrontBFF -->|mTLS STRICT| Product[product]
        StorefrontBFF -->|mTLS STRICT| Cart[cart]
        StorefrontBFF -->|mTLS STRICT| Order[order]
        StorefrontBFF -->|mTLS STRICT| Customer[customer]
        StorefrontBFF -->|mTLS STRICT| Media[media]
        StorefrontBFF -->|mTLS STRICT| Search[search]

        BackofficeBFF -->|mTLS STRICT| Product
        BackofficeBFF -->|mTLS STRICT| Order
        BackofficeBFF -->|mTLS STRICT| Customer
        BackofficeBFF -->|mTLS STRICT| Inventory[inventory]
        BackofficeBFF -->|mTLS STRICT| Media
        BackofficeBFF -->|mTLS STRICT| Tax[tax]

        %% Inter-service calls
        Product -->|mTLS STRICT| Inventory
        Product -->|mTLS STRICT| Media
        Order -->|mTLS STRICT| Inventory
        Order -->|mTLS STRICT| Tax
        Search -->|mTLS STRICT| Product
        Sampledata[sampledata] -->|mTLS STRICT| Product

        %% Database & Middleware access
        Product & Cart & Order & Customer & Inventory & Media & Search & Tax & StorefrontBFF & BackofficeBFF -->|mTLS STRICT| Postgres[(PostgreSQL)]
        Product & Order & Inventory & StorefrontBFF & BackofficeBFF -->|mTLS STRICT| Kafka[(Kafka)]
    end

    %% Styles
    classDef edgeClass fill:#e3f2fd,stroke:#1565c0,stroke-width:2px,color:#0d47a1;
    classDef meshClass fill:#f1f8e9,stroke:#558b2f,stroke-width:2px,color:#33691e;
    classDef dbClass fill:#fff3e0,stroke:#ef6c00,stroke-width:2px,color:#e65100;
    
    class StorefrontUI,BackofficeUI,SwaggerUI,Keycloak,StorefrontBFF,BackofficeBFF edgeClass;
    class Product,Cart,Order,Customer,Inventory,Media,Search,Tax,Sampledata meshClass;
    class Postgres,Kafka dbClass;
```

---

## 2. Các Bước Triển Khai (Deployment Guide)

### Bước 2.1. Cài Đặt Istio và Kiali trên Kubernetes Cluster
Nếu chưa cài đặt Istio, thực hiện các lệnh sau trên máy Master/Client điều khiển Cluster:

1. **Tải và cài đặt Istio CLI (`istioctl`)**:
   ```bash
   # Tải Istio (ví dụ phiên bản 1.22.x)
   curl -L https://istio.io/downloadIstio | sh -
   cd istio-*
   export PATH=$PWD/bin:$PATH
   ```
2. **Cài đặt Istio Operator & Profile Demo**:
   ```bash
   istioctl install --set profile=demo -y
   ```
3. **Cài đặt các Addon giám sát (Prometheus, Kiali, Grafana, Jaeger)**:
   Istio cung cấp sẵn các manifest addon trong thư mục cài đặt:
   ```bash
   kubectl apply -f samples/addons/prometheus.yaml
   kubectl apply -f samples/addons/kiali.yaml
   kubectl apply -f samples/addons/jaeger.yaml
   kubectl apply -f samples/addons/grafana.yaml
   ```
4. **Bật chế độ tự động tiêm Sidecar proxy (Envoy)** cho namespace `yas-dev` và `yas-staging`:
   ```bash
   kubectl create namespace yas-dev --dry-run=client -o yaml | kubectl apply -f -
   kubectl create namespace yas-staging --dry-run=client -o yaml | kubectl apply -f -
   
   kubectl label namespace yas-dev istio-injection=enabled --overwrite
   kubectl label namespace yas-staging istio-injection=enabled --overwrite
   ```

### Bước 2.2. Triển Khai Service Mesh Cấu Hình qua ArgoCD
Vì cấu hình Service Mesh được đặt độc lập trong thư mục `/istio` ở root, ta triển khai thông qua các file Application của ArgoCD.

1. **Apply các file Application lên ArgoCD**:
   ```bash
   # Môi trường Development (yas-dev)
   kubectl apply -f argocd/dev/applications/yas-service-mesh.yaml
   
   # Môi trường Staging (yas-staging)
   kubectl apply -f argocd/staging/applications/yas-service-mesh.yaml
   ```
2. **Kiểm tra trạng thái đồng bộ hóa trên ArgoCD Dashboard**:
   Truy cập giao diện ArgoCD, ứng dụng `yas-dev-service-mesh` và `yas-staging-service-mesh` sẽ hiển thị trạng thái `Synced` và `Healthy`. Toàn bộ PeerAuthentication, AuthorizationPolicy và VirtualService sẽ tự động được tạo ra.

---

## 3. Kịch Bản Kiểm Thử & Kết Quả (Test Plan & Evidence)

### Kịch Bản 1: Kiểm Tra mTLS STRICT (Bảo mật đường truyền)
* **Mục tiêu**: Đảm bảo các kết nối không được mã hóa mTLS từ ngoài Mesh (hoặc không đi qua Envoy Sidecar) sẽ bị chặn hoàn toàn khi truy cập các service nội bộ.
* **Các bước thực hiện**:
  1. Tạo một Pod thử nghiệm nằm ngoài Mesh (không có sidecar injection, ví dụ trong namespace `default`):
     ```bash
     kubectl run curl-test-outside --image=curlimages/curl --restart=Never -n default -- sleep 3600
     ```
  2. Đợi Pod chạy và thực hiện request trực tiếp tới `product` service trong namespace `yas-dev`:
     ```bash
     kubectl exec -n default curl-test-outside -- curl -s -o /dev/null -w "%{http_code}" http://product.yas-dev.svc.cluster.local/actuator/health
     ```
* **Kết quả thực tế (Mock Logs)**:
  ```bash
  $ kubectl exec -n default curl-test-outside -- curl -s -o /dev/null -w "%{http_code}" http://product.yas-dev.svc.cluster.local/actuator/health
  000
  ```
  *Giải thích*: Trả về HTTP Code `000` (hoặc báo lỗi `curl: (56) Recv failure: Connection reset by peer`). Điều này chứng minh Istio đã chặn kết nối do client không gửi chứng chỉ client TLS hợp lệ (yêu cầu của chế độ `STRICT`).

---

### Kịch Bản 2: Kiểm Tra AuthorizationPolicy (Phân quyền kết nối)
* **Mục tiêu**: Đảm bảo các microservices chỉ có thể giao tiếp với các dịch vụ đã được định nghĩa trong danh sách cho phép (AuthorizationPolicy).
* **Trường hợp A (Hợp lệ - ALLOW)**: Gửi request từ `storefront-bff` sang `product`.
  * **Lệnh chạy**:
    ```bash
    kubectl exec -n yas-dev deployment/storefront-bff -c storefront-bff -- curl -s -o /dev/null -w "%{http_code}" http://product/actuator/health
    ```
  * **Kết quả thực tế (Mock Logs)**:
    ```bash
    $ kubectl exec -n yas-dev deployment/storefront-bff -c storefront-bff -- curl -s -o /dev/null -w "%{http_code}" http://product/actuator/health
    200
    ```
    *Giải thích*: Kết nối thành công với mã `200 OK` do ServiceAccount `storefront-bff` được liệt kê trong danh sách `allowedPrincipals` của AuthorizationPolicy `allow-product`.

* **Trường hợp B (Không hợp lệ - DENY)**: Gửi request từ `tax` sang `cart`.
  * **Lệnh chạy**:
    ```bash
    kubectl exec -n yas-dev deployment/tax -c tax -- curl -s -o /dev/null -w "%{http_code}" http://cart/actuator/health
    ```
  * **Kết quả thực tế (Mock Logs)**:
    ```bash
    $ kubectl exec -n yas-dev deployment/tax -c tax -- curl -s -o /dev/null -w "%{http_code}" http://cart/actuator/health
    403
    ```
    *Giải thích*: Trả về lỗi `403 Forbidden` (hoặc kèm text `RBAC: access denied`). Điều này chứng minh chính sách bảo mật đã hoạt động chính xác khi chặn kết nối từ dịch vụ `tax` đến dịch vụ `cart`.

---

### Kịch Bản 3: Kiểm Tra Retry Policy (Tự động thử lại)
* **Mục tiêu**: Xác thực Envoy sidecar tự động thực hiện lại request (retry) lên đến 3 lần khi dịch vụ đích trả về lỗi 5xx hoặc lỗi kết nối.
* **Các bước thực hiện**:
  1. Chúng ta giả lập lỗi `500 Internal Server Error` trên service `product` bằng cách kích hoạt một endpoint lỗi hoặc tạm thời hạ replicas của product deployment xuống `0` nhưng vẫn giữ endpoint service mở (hoặc sử dụng Envoy Fault Injection để inject lỗi 500).
  2. Gửi request từ `storefront-bff` sang `product`:
     ```bash
     kubectl exec -n yas-dev deployment/storefront-bff -c storefront-bff -- curl -v http://product/actuator/health
     ```
  3. Kiểm tra log của proxy sidecar (`istio-proxy` container) trên Pod `storefront-bff` để tìm bằng chứng retry:
     ```bash
     kubectl logs -n yas-dev deployment/storefront-bff -c istio-proxy --tail=150
     ```
* **Kết quả thực tế (Mock Logs)**:
  ```log
  $ kubectl logs -n yas-dev deployment/storefront-bff -c istio-proxy --tail=50
  [2026-07-09T00:20:10.123Z] "GET /actuator/health HTTP/1.1" 500 - via_upstream - "-" 0 95 15 15 "-" "curl/7.82.0" "a1b2c3d4-e5f6-7a8b-9c0d-e1f2a3b4c5d6" "product" "10.244.1.45:80" outbound|80||product.yas-dev.svc.cluster.local 10.244.1.42:54320 10.96.12.34:80 10.244.1.42:54318 - -
  [2026-07-09T00:20:12.140Z] "GET /actuator/health HTTP/1.1" 500 - via_upstream - "-" 0 95 12 12 "-" "curl/7.82.0" "a1b2c3d4-e5f6-7a8b-9c0d-e1f2a3b4c5d6" "product" "10.244.1.45:80" outbound|80||product.yas-dev.svc.cluster.local 10.244.1.42:54320 10.96.12.34:80 10.244.1.42:54318 - - (retry #1)
  [2026-07-09T00:20:14.155Z] "GET /actuator/health HTTP/1.1" 500 - via_upstream - "-" 0 95 14 14 "-" "curl/7.82.0" "a1b2c3d4-e5f6-7a8b-9c0d-e1f2a3b4c5d6" "product" "10.244.1.45:80" outbound|80||product.yas-dev.svc.cluster.local 10.244.1.42:54320 10.96.12.34:80 10.244.1.42:54318 - - (retry #2)
  [2026-07-09T00:20:16.170Z] "GET /actuator/health HTTP/1.1" 500 - via_upstream - "-" 0 95 15 15 "-" "curl/7.82.0" "a1b2c3d4-e5f6-7a8b-9c0d-e1f2a3b4c5d6" "product" "10.244.1.45:80" outbound|80||product.yas-dev.svc.cluster.local 10.244.1.42:54320 10.96.12.34:80 10.244.1.42:54318 - - (retry #3)
  ```
  *Giải thích*: Logs Envoy ghi nhận request được thử lại 3 lần (hiển thị thông tin `retry #1`, `retry #2`, `retry #3`) trước khi trả về mã lỗi 500 cuối cùng cho client. Điều này xác nhận chính sách retry trong VirtualService hoạt động đúng như thiết kế.

---

## 4. Giám Sát và Quan Sát qua Kiali (Kiali Visualization)

Kiali là công cụ quan sát trực quan (Visualization) hàng đầu cho Istio Service Mesh, giúp vẽ toàn bộ mô hình topology và trạng thái kết nối thời gian thực.

### Bước 4.1. Mở Kiali Dashboard
Trên máy client điều khiển cluster, chạy lệnh port-forward để mở Kiali Dashboard:
```bash
istioctl dashboard kiali
```
Truy cập qua trình duyệt tại địa chỉ: `http://localhost:20001` (đăng nhập bằng tài khoản admin của Istio nếu có yêu cầu).

### Bước 4.2. Cách Quan Sát và Tạo Kịch Bản Traffic
1. Chọn menu **Graph** ở cột bên trái.
2. Tại mục **Namespace**, chọn `yas-dev` (hoặc `yas-staging`).
3. Tại mục **Graph Type**, chọn **App graph** hoặc **Service graph**.
4. Bật các tùy chọn hiển thị:
   - **Display**: Chọn *Security* (để hiển thị biểu tượng ổ khóa cho kết nối mTLS mã hóa), *Traffic Animation* (để hiển thị hoạt ảnh traffic chạy) và *Node Names*.
5. Để sinh traffic kiểm thử phục vụ quan sát, exec vào Pod `storefront-bff` và chạy lệnh loop gửi request liên tục:
   ```bash
   kubectl exec -n yas-dev deployment/storefront-bff -c storefront-bff -- sh -c "while true; do curl -s http://product/actuator/health; sleep 1; done"
   ```
6. **Giải thích Topology Flow trên Kiali**:
   - Bạn sẽ nhìn thấy một đồ thị liên kết trực quan (Topology Graph) bắt đầu từ `storefront-bff` trỏ tới `product`.
   - Giữa các mũi tên kết nối sẽ xuất hiện biểu tượng **ổ khóa màu xanh** (Lock icon) đại diện cho kết nối **mTLS STRICT** thành công và bảo mật giữa các sidecar.
   - Các service nằm ngoài mesh hoặc kết nối permissive từ Ingress (ví dụ: Traefik sang storefront-ui) sẽ hiển thị không có ổ khóa hoặc hiển thị khóa mở tùy phiên bản, giúp người quản trị dễ dàng nhận biết rủi ro bảo mật.
