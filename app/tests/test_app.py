def test_index_returns_200(client):
    response = client.get("/")
    assert response.status_code == 200


def test_index_returns_json_message(client):
    response = client.get("/")
    data = response.get_json()
    assert "message" in data


def test_health_returns_ok(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_ready_returns_ready(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ready"}


def test_metrics_returns_200(client):
    response = client.get("/metrics")
    assert response.status_code == 200


def test_metrics_contains_request_counter(client):
    client.get("/")
    response = client.get("/metrics")
    assert b"http_requests_total" in response.data


def test_metrics_contains_request_latency(client):
    client.get("/")
    response = client.get("/metrics")
    assert b"http_request_duration_seconds" in response.data


def test_metrics_content_type_is_text(client):
    response = client.get("/metrics")
    assert "text/plain" in response.content_type


def test_index_returns_exact_message(client):
    data = client.get("/").get_json()
    assert data["message"] == "GitOps Platform — Running"


def test_unknown_route_returns_404(client):
    assert client.get("/does-not-exist").status_code == 404


def test_post_to_health_returns_405(client):
    assert client.post("/health").status_code == 405


def test_post_to_index_returns_405(client):
    assert client.post("/").status_code == 405


def test_metrics_label_requests_by_route(client):
    client.get("/health")
    response = client.get("/metrics")
    assert b'route="/health"' in response.data


def test_unmatched_paths_share_one_route_label(client):
    client.get("/scanner-probe-a1b2c3")
    response = client.get("/metrics")
    assert b"scanner-probe-a1b2c3" not in response.data
    assert b'route="<unmatched>"' in response.data


def test_metrics_contains_app_info(client):
    response = client.get("/metrics")
    assert b"app_info" in response.data
