#!/usr/bin/env python3
"""Test fixtures for kit-net: a local HTTPS server and a small CONNECT proxy.

usage: net_fixtures.py DIR CERT KEY
Writes DIR/https.port and DIR/proxy.port once both listen (127.0.0.1, random ports) and appends
one line per proxied CONNECT to DIR/proxy.log. The proxy resolves every host name to 127.0.0.1,
so https://intranet.test.example:PORT/ only works through it. The HTTPS server answers 200 on
"/" and 404 elsewhere. Stops on SIGTERM.
"""
import http.server
import os
import select
import signal
import socket
import socketserver
import ssl
import sys
import threading


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"kit-net test server\n" if self.path == "/" else b"not found\n"
        self.send_response(200 if self.path == "/" else 404)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class Proxy(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def make_proxy_handler(logfile):
    class H(socketserver.StreamRequestHandler):
        def handle(self):
            try:
                self.tunnel()
            except OSError:
                pass   # a client that hangs up mid-request is normal

        def tunnel(self):
            line = self.rfile.readline().decode("latin-1").strip()
            while self.rfile.readline().strip():   # request headers
                pass
            parts = line.split()
            if len(parts) < 2 or parts[0] != "CONNECT":
                self.wfile.write(b"HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n")
                return
            host, _, port = parts[1].rpartition(":")
            with open(logfile, "a") as fh:
                fh.write("CONNECT %s\n" % parts[1])
            try:
                up = socket.create_connection(("127.0.0.1", int(port)), timeout=10)
            except OSError:
                self.wfile.write(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
                return
            self.wfile.write(b"HTTP/1.1 200 Connection established\r\n\r\n")
            self.wfile.flush()
            socks = [self.connection, up]
            while True:
                r, _, _ = select.select(socks, [], [], 30)
                if not r:
                    break
                done = False
                for s in r:
                    data = s.recv(65536)
                    if not data:
                        done = True
                        break
                    (up if s is self.connection else self.connection).sendall(data)
                if done:
                    break
            up.close()
    return H


def main():
    d, cert, key = sys.argv[1:4]
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(cert, key)
    https = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    https.socket = ctx.wrap_socket(https.socket, server_side=True)
    proxy = Proxy(("127.0.0.1", 0), make_proxy_handler(os.path.join(d, "proxy.log")))
    for srv in (https, proxy):
        threading.Thread(target=srv.serve_forever, daemon=True).start()
    with open(os.path.join(d, "https.port"), "w") as fh:
        fh.write(str(https.server_address[1]))
    with open(os.path.join(d, "proxy.port"), "w") as fh:
        fh.write(str(proxy.server_address[1]))
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    stop.wait()


if __name__ == "__main__":
    main()
