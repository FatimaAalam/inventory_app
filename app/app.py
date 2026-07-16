from flask import Flask, request, jsonify
from datetime import datetime
from db import get_postgres_connection, get_mongo_client, get_redis_client
from prometheus_flask_exporter import PrometheusMetrics
import json

app = Flask(__name__)
metrics = PrometheusMetrics(app)

@app.route('/items', methods=['POST'])
def create_item():
    """
    Create a new item in the inventory in PostgreSQL
    and log the event in MongoDB.
    """
    data = request.get_json()

    name = data.get("name")
    quantity = data.get("quantity")
    price = data.get("price")

    if not name or quantity is None or price is None:
        return jsonify({"error": "Missing required fields"}), 400
    
    # Insert into PostgreSQL
    conn = get_postgres_connection()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO items (name, quantity, price) VALUES (%s, %s, %s) RETURNING id",
        (name, quantity, price),
    )
    new_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()

    # Log the event in MongoDB
    mongo_client = get_mongo_client()
    audit_db = mongo_client["inventory_audit"] #create or target existing DB
    audit_db["events"].insert_one({
        "event": "item created",
        "item_id": new_id,
        "name": name,
        "timestamp": datetime.utcnow().isoformat(),
    })
    mongo_client.close()

    return jsonify({"id": new_id, "name": name, "quantity": quantity, "price": price}), 201

@app.route("/item/<int:item_id>", methods=["GET"])
def get_item(item_id):
    """"
    Fetches a single item by id.
    checks redis first (cache-aside pattern); falls back to postersql
    on a cache miss, then populates the cache for next time.
    """
    redis_client = get_redis_client()
    chache_key = f"item:{item_id}"

    # Check Redis cache first
    cached = redis_client.get(chache_key)
    if cached:
        return jsonify({"source": "cache", "data": json.loads(cached)}), 200 #turn it back into a usable dictionary.
    
    # Cache miss; fetch from PostgreSQL
    conn = get_postgres_connection()
    cur = conn.cursor()
    cur.execute("SELECT id, name, quantity, price FROM items WHERE id = %s", (item_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()

    if row is None:
        return jsonify({"error": "Item not found"}), 404
    
    item = {"id": row[0], "name": row[1], "quantity": row[2], "price": float(row[3])}

    # Store in Redis cache for future requests
    redis_client.setex(chache_key, 60, json.dumps(item))  # Cache for 9 minutes
    return jsonify({"source": "database", "data": item}), 200

@app.route("/health", methods=["GET"])
def health_check():
    """
    Reports whether the app and its dependent services are reachablr.
    used by healthcheck.sh and docker compose's built-in healthcheck.

    """
    status = {"app": "ok"}

    try:
        # Check PostgreSQL
        conn = get_postgres_connection()
        conn.close()
        status["postgres"] = "ok"
    except Exception as e:
        status["postgres"] = f"error: {e}"

    try:
        # Check MongoDB
        mongo_client = get_mongo_client()
        mongo_client.admin.command('ping')  # Ping the server to check connection
        mongo_client.close()
        status["mongo"] = "ok"
    except Exception as e:
        status["mongo"] = f"error: {e}"

    try:
        # Check Redis
        redis_client = get_redis_client()
        redis_client.ping()  # Ping the server to check connection
        status["redis"] = "ok"
    except Exception as e:
        status["redis"] = f"error: {e}"
    
    overall_ok = all(value == "ok" for value in status.values())

    return jsonify(status), 200 if overall_ok else 503 

# Entry point 
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
