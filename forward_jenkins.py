import socket
import threading
import sys

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

def forward(local_port, remote_host, remote_port):
    local_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    local_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        local_socket.bind(('127.0.0.1', local_port))
    except Exception as e:
        print(f"Error: Could not bind to port {local_port} on localhost: {e}")
        print("Maybe another process is already using this port? Try choosing a different port.")
        sys.exit(1)
        
    local_socket.listen(100)
    print(f"WSL Port Forwarding active: http://localhost:{local_port} -> http://{remote_host}:{remote_port}")
    print("Keep this terminal open to maintain the connection. Press Ctrl+C to stop.")
    
    try:
        while True:
            client_conn, client_addr = local_socket.accept()
            remote_conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            try:
                remote_conn.connect((remote_host, remote_port))
                threading.Thread(target=pipe, args=(client_conn, remote_conn), daemon=True).start()
                threading.Thread(target=pipe, args=(remote_conn, client_conn), daemon=True).start()
            except Exception as e:
                print(f"Error connecting to Jenkins ({remote_host}:{remote_port}): {e}")
                client_conn.close()
    except KeyboardInterrupt:
        print("\nStopping port forwarder...")
    finally:
        local_socket.close()

if __name__ == '__main__':
    # Forward local port 8081 to Jenkins IP 100.92.3.126 on port 8081
    forward(8081, '100.92.3.126', 8081)
