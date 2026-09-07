import os
import time
from flask import Flask, jsonify, Response, g, request
from prometheus_client import (
    generate_latest,
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    multiprocess as prom_multiprocess,
)
from metrics import REQUEST_COUNT, REQUEST_LATENCY


def create_app():
    app = Flask(__name__)

    @app.before_request
    def start_timer():
        g.start = time.time()

    @app.after_request
    def record_metrics(response):
        latency = time.time() - g.get("start", time.time())
        endpoint = request.url_rule.rule if request.url_rule else request.path
        REQUEST_COUNT.labels(
            method=request.method,
            endpoint=endpoint,
            status=response.status_code,
        ).inc()
        REQUEST_LATENCY.labels(
            method=request.method,
            endpoint=endpoint,
        ).observe(latency)
        return response

    @app.route("/")
    def index():
        return jsonify({"message": "GitOps Platform — Running"})

    @app.route("/health")
    def health():
        return jsonify({"status": "ok"})

    @app.route("/ready")
    def ready():
        return jsonify({"status": "ready"})

    @app.route("/metrics")
    def metrics():
        if os.getenv("PROMETHEUS_MULTIPROC_DIR"):
            registry = CollectorRegistry()
            prom_multiprocess.MultiProcessCollector(registry)
            return Response(generate_latest(registry), mimetype=CONTENT_TYPE_LATEST)
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

    return app


if __name__ == "__main__":
    app = create_app()
    app.run(host="0.0.0.0", port=8080)
