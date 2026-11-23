from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Event, Thread


def serve():
    site = Path(__file__).resolve().parent / "site"
    if not (site / "index.html").is_file():
        raise SystemExit("Missing lab/site/index.html. Follow the README setup first.")
    handler = partial(SimpleHTTPRequestHandler, directory=str(site))
    servers = [ThreadingHTTPServer(("0.0.0.0", port), handler) for port in range(9000, 9004)]
    for server in servers:
        Thread(target=server.serve_forever, daemon=True).start()
    Event().wait()


if __name__ == "__main__":
    serve()
