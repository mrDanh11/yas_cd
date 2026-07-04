import socket
import threading
import sys
import time

# IP Tailscale của máy K3s Node chứa các service
TARGET_IP = '100.92.3.126'

# Danh sách các cổng NodePort cần chuyển tiếp
PORTS = [
    31210, # ingress (new traefik http port)
    31763, # ingress (old storefront port)
    31245, # cart
    31272, # customer
    30735, # inventory
    32087, # location
    31271, # media
    32540, # order
    30214, # payment
    32177, # payment-paypal
    30834, # product
    30186, # promotion
    31831, # rating
    31253, # recommendation
    30626, # search
    31509, # tax
    31236, # webhook
    31516, # backoffice-bff
    31864, # storefront-bff
]

def pipe(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        src.close()
        dst.close()

def forward_port(port):
    local_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    local_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        local_socket.bind(('0.0.0.0', port))
        local_socket.listen(100)
        print(f"  [Active] http://localhost:{port} (and http://{TARGET_IP}:{port})")
    except Exception as e:
        print(f"  [Error] Không thể mở cổng :{port}: {e}")
        return

    while True:
        try:
            client_conn, client_addr = local_socket.accept()
            remote_conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            remote_conn.connect((TARGET_IP, port))
            threading.Thread(target=pipe, args=(client_conn, remote_conn), daemon=True).start()
            threading.Thread(target=pipe, args=(remote_conn, client_conn), daemon=True).start()
        except Exception as e:
            # Bỏ qua các lỗi kết nối nhỏ để tránh rác log
            pass

def main():
    print("==========================================================")
    print(f"Khởi chạy hệ thống chuyển tiếp đa cổng tới K3s ({TARGET_IP})...")
    print("==========================================================")
    
    threads = []
    for port in PORTS:
        t = threading.Thread(target=forward_port, args=(port,), daemon=True)
        t.start()
        threads.append(t)
    
    print("==========================================================")
    print("Đang hoạt động. Hãy giữ terminal này mở để duy trì kết nối.")
    print("Nhấn Ctrl+C để dừng.")
    print("==========================================================")
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nĐang dừng các cổng chuyển tiếp...")

if __name__ == '__main__':
    main()
