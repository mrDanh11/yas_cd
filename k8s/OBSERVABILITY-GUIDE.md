# Hướng Dẫn & Giải Thích Về Observability (Giám Sát Hệ Thống) Trong YAS

Hệ thống **YAS (Yet Another Shop)** tích hợp giải pháp giám sát toàn diện (**Observability**) dựa trên tiêu chuẩn mã nguồn mở **OpenTelemetry (OTel)** kết hợp với bộ công cụ của Grafana (**Prometheus, Loki, Tempo, Grafana**).

Dưới đây là phân tích chi tiết về 2 ảnh chụp màn hình giám sát để bạn đưa vào báo cáo và giải thích với giảng viên.

---

## 1. Giải Thích Ảnh 1: Distributed Tracing (Truy vết phân tán với Grafana Tempo)

### Ảnh này là gì?
Đây là giao diện truy vết cuộc gọi (**Trace View**) sử dụng công cụ **Grafana Tempo**. Nó thể hiện luồng đi chi tiết của một request từ khi người dùng tương tác cho đến khi truy vấn dữ liệu dưới Database.

### Phân tích luồng request cụ thể trong ảnh:
* **Trace ID**: `a3c97d283b3390b81734e610adb88499` (Mỗi request đi vào hệ thống sẽ được cấp một ID duy nhất này để định danh xuyên suốt qua tất cả các microservices).
* **Luồng đi của Request**:
  1. **Khởi đầu**: Request đi vào dịch vụ cổng **`backoffice-bff-service`** thực hiện hàm `GET api` với tổng thời gian xử lý là **`438.38ms`**.
  2. **Gọi dịch vụ**: `backoffice-bff-service` sau đó gửi một request HTTP GET sang dịch vụ quản lý sản phẩm **`product-service`** (`GET /product/backoffice/...`) mất **`406.64ms`**.
  3. **Truy vấn Database**: Tại `product-service`, ứng dụng Spring Boot thực hiện truy vấn SQL (`SELECT product ...`) xuống cơ sở dữ liệu PostgreSQL (`server.address: postgres` trên cổng `5432`) mất **`35.88ms`**.
* **Attributes (Thuộc tính chi tiết của DB query)**:
  * Bên phải hiển thị chi tiết câu lệnh SQL được tự động bắt bởi OpenTelemetry: `select p1_0.id, p1_0.brand_id ... from product p1_0 ...`
  * Hệ cơ sở dữ liệu: `postgresql`.
  * Tài khoản thực thi: `admin`.
  * Thư viện tự động trace: `io.opentelemetry.jdbc` (tự động trace các câu lệnh SQL đi qua JDBC Driver).

### Ý nghĩa & Lợi ích:
* **Tìm điểm nghẽn hiệu năng (Bottleneck)**: Nhìn vào đây ta thấy tổng thời gian là `438.38ms`, trong đó thời gian gọi sang `product-service` chiếm tới `406.64ms` (92%), nhưng bản thân truy vấn SQL chỉ mất `35.88ms`. Điều này chỉ ra lỗi nghẽn không nằm ở Database mà nằm ở phần xử lý logic Java hoặc độ trễ mạng (network latency) của `product-service`.
* **Khắc phục lỗi nhanh (Troubleshooting)**: Nếu request bị lỗi (ví dụ trả về 500), mã lỗi sẽ hiển thị màu đỏ trực quan tại span bị lỗi giúp khoanh vùng lỗi ngay lập tức.

---

## 2. Giải Thích Ảnh 2: JVM & Application Metrics Dashboard (Giám sát tài nguyên Java)

### Ảnh này là gì?
Đây là **Grafana Dashboard** trực quan hóa các chỉ số đo lường (Metrics) thời gian thực của máy ảo Java (JVM) đang chạy các Spring Boot microservices. Các chỉ số này được Prometheus crawl từ endpoint `/actuator/prometheus` của ứng dụng.

### Ý nghĩa của các chỉ số chính hiển thị trên Dashboard:
1. **JVM Memory (Heap & Non-Heap Memory)**:
   * Biểu đồ hiển thị lượng RAM thực tế đang sử dụng và giới hạn tối đa của vùng nhớ Heap (nơi chứa đối tượng ứng dụng tạo ra) và Non-Heap (chứa Metaspace, Class metadata).
   * *Ứng dụng thực tế*: Giúp phát hiện lỗi rò rỉ bộ nhớ (Memory Leak) nếu biểu đồ sử dụng RAM liên tục đi lên theo hình bậc thang mà không đi xuống sau khi chạy Garbage Collection.
2. **Thread States (Trạng thái luồng)**:
   * Giám sát số lượng thread đang ở các trạng thái: `RUNNABLE`, `TIMED_WAITING`, `BLOCKED`, `WAITING`.
   * *Ứng dụng thực tế*: Nếu số lượng thread `BLOCKED` tăng cao đột biến, hệ thống đang bị nghẽn (deadlock) hoặc quá tải do chờ tài nguyên dùng chung.
3. **Garbage Collection (GC - Thu gom rác)**:
   * Thống kê tần suất chạy GC và thời gian dừng ứng dụng để dọn rác (GC Pause Time).
   * *Ứng dụng thực tế*: GC chạy quá nhiều hoặc tốn thời gian (GC pause lâu) sẽ gây giật, lag ứng dụng (Stop-the-world).
4. **Hikari Connection Pool (Giám sát kết nối DB)**:
   * Thống kê số lượng kết nối DB đang hoạt động (`Active`), đang rảnh (`Idle`), hoặc đang phải chờ đợi kết nối.
   * *Ứng dụng thực tế*: Giúp cấu hình kích thước Connection Pool phù hợp, tránh lỗi thiếu kết nối DB làm nghẽn ứng dụng.

---

## 3. Cách Thức Hoạt Động (How it works)

Bạn có thể giải thích với thầy giáo cơ chế hoạt động đằng sau như sau:

1. **Thu thập Metrics (Ảnh 2)**:
   * Mỗi microservice Spring Boot được cài đặt **Spring Boot Actuator** và **Micrometer**.
   * Micrometer tự động đo lường các chỉ số của JVM và expose ra qua HTTP endpoint `/actuator/prometheus`.
   * Cụm **Prometheus** định kỳ truy cập vào endpoint này của từng service để thu thập dữ liệu và lưu vào cơ sở dữ liệu Time-series.
   * **Grafana** kết nối với Prometheus để vẽ lên Dashboard trực quan.

2. **Thu thập Traces (Ảnh 1)**:
   * Các microservice được chạy kèm với **OpenTelemetry Java Agent** (dưới dạng `-javaagent:opentelemetry-javaagent.jar`).
   * Agent này tự động can thiệp (instrumentation) vào các thư viện HTTP client, Spring Web, và JDBC để ghi nhận Span khi có request đi qua.
   * Khi `backoffice-bff` gọi sang `product-service`, Agent tự động truyền thông tin Trace ID qua HTTP Header (W3C Trace Context).
   * Các Agent gửi dữ liệu Trace về **OpenTelemetry Collector**.
   * OTel Collector đẩy dữ liệu vào **Tempo** để lưu trữ và truy vấn trên Grafana.
