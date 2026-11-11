import os
from prometheus_client import Counter, Histogram, Gauge

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP request count",
    ["method", "route", "status"],
)

REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "route"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 1.0, 2.5, 5.0],
)

APP_INFO = Gauge(
    "app_info",
    "Application metadata",
    ["version", "environment"],
)

APP_INFO.labels(
    version=os.getenv("APP_VERSION", "dev"),
    environment=os.getenv("APP_ENV", "development"),
).set(1)
