def make_expense(client, category_id, title="Lunch", amount=250.0, spent_on="2026-07-10"):
    return client.post(
        "/expenses",
        json={
            "title": title,
            "amount": amount,
            "spent_on": spent_on,
            "category_id": category_id,
        },
    )


def test_create_expense(client, food_category):
    resp = make_expense(client, food_category["id"])
    assert resp.status_code == 201
    body = resp.json()
    assert body["title"] == "Lunch"
    assert body["amount"] == 250.0
    assert body["category"]["name"] == "Food"


def test_create_expense_unknown_category(client):
    resp = make_expense(client, category_id=42)
    assert resp.status_code == 404


def test_negative_amount_rejected(client, food_category):
    resp = make_expense(client, food_category["id"], amount=-5)
    assert resp.status_code == 422


def test_list_with_date_filter(client, food_category):
    make_expense(client, food_category["id"], title="Old", spent_on="2026-01-05")
    make_expense(client, food_category["id"], title="New", spent_on="2026-07-05")

    resp = client.get("/expenses", params={"start": "2026-06-01"})
    titles = [e["title"] for e in resp.json()]
    assert titles == ["New"]


def test_update_expense(client, food_category):
    expense_id = make_expense(client, food_category["id"]).json()["id"]
    resp = client.patch(f"/expenses/{expense_id}", json={"amount": 300.0})
    assert resp.status_code == 200
    assert resp.json()["amount"] == 300.0


def test_delete_expense(client, food_category):
    expense_id = make_expense(client, food_category["id"]).json()["id"]
    assert client.delete(f"/expenses/{expense_id}").status_code == 204
    assert client.get(f"/expenses/{expense_id}").status_code == 404


def test_monthly_report(client, food_category):
    travel = client.post("/categories", json={"name": "Travel"}).json()
    make_expense(client, food_category["id"], amount=100, spent_on="2026-07-01")
    make_expense(client, food_category["id"], amount=50, spent_on="2026-07-15")
    make_expense(client, travel["id"], amount=500, spent_on="2026-07-20")
    make_expense(client, travel["id"], amount=999, spent_on="2026-06-20")  # other month

    resp = client.get("/expenses/report/2026/7")
    assert resp.status_code == 200
    body = resp.json()
    assert body["total_spent"] == 650.0
    assert body["expense_count"] == 3
    totals = {c["category"]: c["total"] for c in body["by_category"]}
    assert totals == {"Food": 150.0, "Travel": 500.0}


def test_report_invalid_month(client):
    assert client.get("/expenses/report/2026/13").status_code == 422
