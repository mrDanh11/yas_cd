# Hướng Dẫn Cấu Hình GitOps & Service Mesh YAS (14 Services)

Tài liệu này cung cấp toàn bộ sơ đồ kiến trúc, quy trình deploy và hướng dẫn kiểm thử các tính năng nâng cao **GitOps (ArgoCD)** và **Service Mesh (Istio)** trên hệ thống microservices **YAS (Yet Another Shop)** đã được tối ưu hóa xuống **14 dịch vụ thiết yếu**.

---

## 1. Sơ Đồ Kiến Trúc & Luồng Traffic (Service Mesh)

Hệ thống sử dụng mô hình kết hợp:
1. **Edge Services** (Dịch vụ biên) chấp nhận traffic không mã hóa (plain HTTP) từ **Traefik Ingress Controller** bên ngoài mesh thông qua chế độ **PERMISSIVE mTLS**.
2. **Internal Services** (Dịch vụ nội bộ) bắt buộc giao tiếp mã hóa qua **STRICT mTLS** và chịu sự kiểm soát của các **AuthorizationPolicy** cụ thể.

### Sơ đồ luồng dữ liệu (Traffic Flow)
```mermaid
graph TD
    %% Ingress & Edge
    Ingress[Traefik Ingress Controller] -->|Plain HTTP / Permissive| StorefrontUI[storefront-ui]
    Ingress -->|Plain HTTP / Permissive| BackofficeUI[backoffice-ui]
    Ingress -->|Plain HTTP / Permissive| SwaggerUI[swagger-ui]
    Ingress -->|Plain HTTP / Permissive| Keycloak[keycloak]
    Ingress -->|Plain HTTP / Permissive| StorefrontBFF[storefront-bff]
    Ingress -->|Plain HTTP / Permissive| BackofficeBFF[backoffice-bff]

    %% Internal mTLS STRICT
    subgraph Service Mesh (STRICT mTLS)
        StorefrontBFF -->|mTLS| Product[product]
        StorefrontBFF -->|mTLS| Cart[cart]
        StorefrontBFF -->|mTLS| Order[order]
        StorefrontBFF -->|mTLS| Customer[customer]
        StorefrontBFF -->|mTLS| Media[media]
        StorefrontBFF -->|mTLS| Search[search]

        BackofficeBFF -->|mTLS| Product
        BackofficeBFF -->|mTLS| Order
        BackofficeBFF -->|mTLS| Customer
        BackofficeBFF -->|mTLS| Inventory[inventory]
        BackofficeBFF -->|mTLS| Media
        BackofficeBFF -->|mTLS| Tax[tax]

        %% Inter-service calls
        Product -->|mTLS| Inventory
        Product -->|mTLS| Media
        Order -->|mTLS| Inventory
        Order -->|mTLS| Tax
        Search -->|mTLS| Product
        Sampledata[sampledata] -->|mTLS| Product

        %% Database & Middleware access
        AllServices[All Backend Pods] -->|mTLS| Postgres[(PostgreSQL)]
        AllServices -->|mTLS| Kafka[(Kafka)]
    end

    %% Styles
    classDef edgeClass fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef meshClass fill:#f1f8e9,stroke:#558b2f,stroke-width:2px;
    classDef dbClass fill:#fff3e0,stroke:#ef6c00,stroke-width:2px;
    
    class StorefrontUI,BackofficeUI,SwaggerUI,Keycloak,StorefrontBFF,BackofficeBFF edgeClass;
    class Product,Cart,Order,Customer,Inventory,Media,Search,Tax,Sampledata meshClass;
    class Postgres,Kafka dbClass;
```

---

## 2. Triển Khai GitOps (ArgoCD)

ArgoCD theo dõi thư mục `k8s/environments/dev` (nhánh `feat/advanced-gitops-servicemesh`) để đồng bộ toàn bộ ứng dụng và cấu hình mesh lên cluster K8s.

### Các bước cài đặt:
1. Đảm bảo cluster đã cài đặt **ArgoCD** và **Istio**.
2. Apply các tệp cấu hình Application để ArgoCD tự động tạo các tài nguyên:
   ```bash
   kubectl apply -f k8s/argocd/dev-application.yaml
   kubectl apply -f k8s/argocd/staging-application.yaml
   ```

---

## 3. Quy Trình Tự Động Hóa (Jenkins Pipelines)

1. **Jenkinsfile.dev-gitops**: Khi code push lên `main`, pipeline tự động build image, push lên Docker Hub với tag là commit SHA, sau đó dùng `yq` sửa tag trong `k8s/environments/dev/values.yaml` và commit ngược lại Git để kích hoạt ArgoCD tự đồng bộ.
2. **Jenkinsfile.staging-gitops**: Kích hoạt bằng Git tag (`v*`), tự động build và gán tag release tương ứng cho các service thay đổi, đồng bộ sang môi trường `staging`.
3. **Jenkinsfile.developer-build**: Cho phép deploy nhanh 1 nhánh tính năng riêng của dev sang namespace `yas-dev` thông qua tham số.

---

## 4. Hướng Dẫn Kịch Bản Kiểm Thử (Cách Test)

### Kịch Bản 1: Kiểm tra mTLS STRICT (Bảo mật đường truyền)
* **Mục tiêu**: Xác thực rằng các kết nối không thông qua Istio Sidecar (không mã hóa mTLS) sẽ bị từ chối truy cập vào các service nội bộ.
* **Cách thực hiện**:
  1. Chạy 1 pod thử nghiệm nằm ngoài mesh (ví dụ ở namespace `default` - không bật Istio injection):
     ```bash
     kubectl run curl-test-outside --image=curlimages/curl --restart=Never -n default -- sleep 3600
     ```
  2. Exec vào pod này và gửi request trực tiếp tới `product` service ở namespace `dev`:
     ```bash
     kubectl exec -n default curl-test-outside -- curl -s -o /dev/null -w "%{http_code}" http://product.dev.svc.cluster.local/actuator/health
     ```
* **Kết quả mong muốn**: Trả về mã lỗi `000` (Connection reset by peer) vì traffic không có chứng chỉ mTLS hợp lệ do Istio proxy cấp.

---

### Kịch Bản 2: Kiểm tra AuthorizationPolicy (Phân quyền kết nối RBAC)
* **Mục tiêu**: Đảm bảo dịch vụ chỉ nhận request từ các nguồn được định nghĩa rõ ràng.
* **Cách thực hiện**:
  1. **Kết nối hợp lệ (ALLOW)**: Gửi request từ `storefront-bff` sang `product`:
     ```bash
     kubectl exec -n dev deployment/storefront-bff -c storefront-bff -- curl -s -o /dev/null -w "%{http_code}" http://product/actuator/health
     ```
     *Kết quả mong đợi*: Trả về `200` OK.
  2. **Kết nối không hợp lệ (DENY)**: Gửi request từ `tax` sang `cart` (không nằm trong danh sách cho phép):
     ```bash
     kubectl exec -n dev deployment/tax -c tax -- curl -s -o /dev/null -w "%{http_code}" http://cart/actuator/health
     ```
     *Kết quả mong đợi*: Trả về `403` Forbidden (thông báo `RBAC: access denied`).

---

### Kịch Bản 3: Kiểm tra Retry Policy (Tự động thử lại)
* **Mục tiêu**: Xác thực Envoy sidecar tự động gửi lại request khi service đích bị lỗi mạng hoặc trả lỗi 5xx.
* **Cách thực hiện**:
  1. Giả lập lỗi `500` trên service `product` hoặc tạm thời stop container ứng dụng của `product` (giữ Envoy proxy chạy).
  2. Gửi request từ `storefront-bff` sang `product`:
     ```bash
     kubectl exec -n dev deployment/storefront-bff -c storefront-bff -- curl -v http://product/actuator/health
     ```
  3. Kiểm tra logs của Envoy sidecar trên `storefront-bff` để thấy các lượt retry:
     ```bash
     kubectl logs -n dev deployment/storefront-bff -c istio-proxy --tail=150
     ```
* **Kết quả mong muốn**: Logs hiển thị Envoy sidecar đã tự động thực hiện gửi lại request (retry) 3 lần trước khi quyết định trả về mã lỗi 500 cho client.
