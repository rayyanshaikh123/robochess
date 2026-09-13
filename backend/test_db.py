import asyncio
from motor.motor_asyncio import AsyncIOMotorClient
import certifi

async def test_conn():
    uri = "mongodb+srv://rayyanshaikhh_db_user:BRbJAekuUQRRSyFp@robochess.q6tntiw.mongodb.net/"
    print("Connecting...")
    client = AsyncIOMotorClient(
        uri, 
        serverSelectionTimeoutMS=5000,
        tls=True,
        tlsCAFile=certifi.where()
    )
    try:
        db = client["robochess"]
        await db.command("ping")
        print("Success!")
    except Exception as e:
        print(f"Failed: {e}")
    finally:
        client.close()

if __name__ == "__main__":
    asyncio.run(test_conn())
