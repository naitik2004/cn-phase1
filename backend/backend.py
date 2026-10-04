#!/usr/bin/env python3

import hashlib
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


BACKEND = os.environ.get("BACKEND", "A")
PORT = int(os.environ.get("PORT", "3001"))


STATIC_BODY = json.dumps({
    "message": "cacheable resource",
    "version": 1
}).encode()

STATIC_ETAG = '"' + hashlib.md5(STATIC_BODY).hexdigest() + '"'


class Handler(BaseHTTPRequestHandler):

    protocol_version = "HTTP/1.1"

    def reply(
        self,
        code,
        body=b"",
        content_type="application/json",
        headers=None
    ):

        self.send_response(code)

        self.send_header("X-Backend", BACKEND)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))

        for key, value in (headers or {}).items():
            self.send_header(key, value)

        self.end_headers()

        if self.command != "HEAD" and code != 304:
            self.wfile.write(body)

    def do_GET(self):

        path = self.path.split("?")[0]

        # Homepage
        if path == "/":

            body = (
                f"<h1>Backend {BACKEND} is running</h1>"
            ).encode()

            self.reply(
                200,
                body,
                "text/html",
                {
                    "Cache-Control": "no-cache"
                }
            )

        # Dynamic status endpoint
        elif path == "/api/status":

            body = json.dumps({
                "backend": BACKEND,
                "status": "ok"
            }).encode()

            self.reply(
                200,
                body,
                headers={
                    "Cache-Control": "no-store"
                }
            )

        # Cache demonstration
        elif path == "/api/static":

            headers = {
                "ETag": STATIC_ETAG,
                "Cache-Control": "max-age=60"
            }

            if self.headers.get("If-None-Match") == STATIC_ETAG:

                self.reply(
                    304,
                    headers=headers
                )

            else:

                self.reply(
                    200,
                    STATIC_BODY,
                    headers=headers
                )

        else:

            body = json.dumps({
                "error": "not found"
            }).encode()

            self.reply(404, body)

    do_HEAD = do_GET


if __name__ == "__main__":

    server = ThreadingHTTPServer(
        ("0.0.0.0", PORT),
        Handler
    )

    print(
        f"Backend {BACKEND} listening on 0.0.0.0:{PORT}",
        flush=True
    )

    server.serve_forever()
