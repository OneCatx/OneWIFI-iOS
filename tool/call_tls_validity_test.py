"""Compare Apple TLS acceptance with only certificate lifetime changed."""
import hashlib
import http.server
import pathlib
import ssl
import subprocess
import sys
import tempfile
import threading


class Unauthorized(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(401)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *_):
        pass


def main():
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        key = root / "key.pem"
        subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key)], check=True)
        for days, expected in [(1825, False), (365, True)]:
            cert = root / f"cert-{days}.pem"
            subprocess.run([
                "openssl", "req", "-new", "-x509", "-key", str(key), "-sha256",
                "-days", str(days), "-subj", "/O=OneWIFI/CN=OneWIFI",
                "-addext", "subjectAltName=IP:127.0.0.1,DNS:localhost",
                "-addext", "basicConstraints=critical,CA:FALSE",
                "-addext", "keyUsage=critical,digitalSignature,keyEncipherment",
                "-addext", "extendedKeyUsage=serverAuth", "-out", str(cert)
            ], check=True)
            der = ssl.PEM_cert_to_DER_cert(cert.read_text())
            pin = hashlib.sha256(der).hexdigest()
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(cert, key)
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Unauthorized)
            server.socket = context.wrap_socket(server.socket, server_side=True)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                result = subprocess.run([
                    sys.argv[1], f"https://127.0.0.1:{server.server_port}", pin
                ], capture_output=True, text=True, timeout=30)
                print(f"certificate_days={days}\n{result.stdout}", flush=True)
                assert (result.returncode == 0) == expected, result.stderr
                if not expected:
                    assert "trustErrorCode=-67901" in result.stdout
                else:
                    assert "appleTrust=true" in result.stdout and "httpStatus=401" in result.stdout
            finally:
                server.shutdown()
                server.server_close()
        print("PASS: long-lived certificate rejected; 365-day certificate accepted")


if __name__ == "__main__":
    main()