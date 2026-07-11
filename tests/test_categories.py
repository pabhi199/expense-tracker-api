def test_create_and_list_categories(client):
    resp = client.post("/categories", json={"name": "Travel"})
    assert resp.status_code == 201
    assert resp.json()["name"] == "Travel"

    resp = client.get("/categories")
    assert resp.status_code == 200
    names = [c["name"] for c in resp.json()]
    assert "Travel" in names


def test_duplicate_category_rejected(client):
    client.post("/categories", json={"name": "Rent"})
    resp = client.post("/categories", json={"name": "Rent"})
    assert resp.status_code == 409


def test_empty_name_rejected(client):
    resp = client.post("/categories", json={"name": ""})
    assert resp.status_code == 422


def test_delete_category(client, food_category):
    resp = client.delete(f"/categories/{food_category['id']}")
    assert resp.status_code == 204
    assert client.get("/categories").json() == []


def test_delete_missing_category(client):
    resp = client.delete("/categories/999")
    assert resp.status_code == 404
