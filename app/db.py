
#imports fro PostreSQL
import time
import psycopg2
import os
#imports for MongoDB
from pymongo import MongoClient
#import for redis
import redis

#function to get a connection to PostgreSQL database
def get_postgres_connection():
    """
    Returns a connection to postgreSQL.
    Retries on failure because Postgres may not be up yet when the app starts.
    """
    max_retries = 10
    retry_delay = 3  # seconds

    for attempt in range(1, max_retries + 1):
        try:
            conn = psycopg2.connect(
                host=os.environ.get("POSTGRES_HOST", "postgres"),
                port=os.environ.get("POSTGRES_PORT", "5432"),
                user=os.environ.get("POSTGRES_USER"),
                password=os.environ.get("POSTGRES_PASSWORD"),
                dbname=os.environ.get("POSTGRES_DB"),
        )
            print("Successfully connected to PostgreSQL")
            return conn
        except psycopg2.OperationalError as e:
            print(f"Postgres not ready (attempt {attempt}/ {max_retries}) failed: {e}")
            time.sleep(retry_delay)
    raise Exception("Failed to connect to PostgreSQL after multiple attempts")

#function to get a connection to MongoDB database
def get_mongo_client():
    """
    Returns a MongoDB client. used to store audit log events
    (eg. 'item created', 'item updated') - unstructured, append only data.
    """

    mongo_host=os.environ.get("MONGO_HOST", "mongo")
    mongo_port=os.environ.get("MONGO_PORT", "27017")
    mongo_user=os.environ.get("MONGO_USER")
    mongo_password=os.environ.get("MONGO_PASSWORD")

    uri = f"mongodb://{mongo_user}:{mongo_password}@{mongo_host}:{mongo_port}/"
    client = MongoClient(uri, serverSelectionTimeoutMS=5000)  # 5 second timeout
    return client

#function to get a connection to Redis database
def get_redis_client():
    """
    Returns a Redis client. used to cache GET /items/<id> responses 
    reducing repeated load on postgreSQL for frequently requested items.
    """
    return redis.Redis(
        host=os.environ.get("REDIS_HOST", "redis"),
        port=int(os.environ.get("REDIS_PORT", "6379")),
        decode_responses=True,
    )