from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel
from typing import List, Optional
import os
from sqlalchemy import create_engine, Column, Integer, String, MetaData, Table, select, JSON, Float, inspect
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv
from typing import Dict, Any

load_dotenv()  # read .env in dev

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "postgres")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")

DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

engine = create_engine(DATABASE_URL, future=True)
metadata = MetaData()

# Orders table (store userId, address, currency)
orders = Table(
    "orders",
    metadata,
    Column("id", String, primary_key=True),
    Column("userId", String, nullable=True),
    Column("address", JSON, nullable=True),
    Column("items", JSON, nullable=False),
    Column("total", Float, nullable=False),
    Column("currency", String, nullable=True),
    Column("status", String, nullable=False),
    Column("refund_attempt", JSON, nullable=True),
    Column("payment_refund_status", String, nullable=True)
)

# Inventory table (simple SKU -> quantity)
inventory = Table(
    "inventory",
    metadata,
    Column("sku", String, primary_key=True),
    Column("quantity", Integer, nullable=False),
)

# 🆕 Inventory Reservations table (track reserved stock for orders)
inventory_reservations = Table(
    "inventory_reservations",
    metadata,
    Column("id", String, primary_key=True),
    Column("orderId", String, nullable=False),
    Column("items", JSON, nullable=False),
    Column("status", String, nullable=False),
)

# Payments table
payments = Table(
    "payments",
    metadata,
    Column("id", String, primary_key=True),
    Column("order_id", String, nullable=False),
    Column("amount", Float, nullable=False),
    Column("status", String, nullable=False),
)

# Shipments table
shipments = Table(
    "shipments",
    metadata,
    Column("id", String, primary_key=True),
    Column("order_id", String, nullable=False),
    Column("address", JSON, nullable=False),
    Column("items", JSON, nullable=False),
    Column("status", String, nullable=False),
)

# Create tables
metadata.create_all(engine)

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

app = FastAPI(title="DATABASE_SERVICE - Aggregated DB APIs", version="0.3")

# ---------------------------------------------------------------------
# MODELS
# ---------------------------------------------------------------------
class OrderIn(BaseModel):
    id: str
    userId: Optional[str] = None
    address: Optional[dict] = None
    items: list
    total: float
    currency: Optional[str] = "INR"
    status: str
    refund_attempt: Optional[Dict[str, Any]] = None
    payment_refund_status: Optional[str] = None

class OrderOut(OrderIn):
    pass

class InventoryIn(BaseModel):
    id: str
    orderId: str
    items: list 
    status: str

class InventoryOut(InventoryIn):
    pass

# 🆕 Reservation models
class InventoryReservationIn(BaseModel):
    id: str
    orderId: str
    items: list
    status: str

class InventoryReservationOut(InventoryReservationIn):
    pass

class PaymentIn(BaseModel):
    id: str
    order_id: str
    amount: float
    status: str

class PaymentOut(PaymentIn):
    pass

class ShipmentIn(BaseModel):
    id: str
    order_id: str
    address: dict
    items: list
    status: str

class ShipmentOut(ShipmentIn):
    pass

# helper: lock row
def _lock_and_get_inventory_row(db, sku: str):
    stmt = select(inventory).where(inventory.c.sku == sku).with_for_update()
    row = db.execute(stmt).first()
    return row

# ---------------------------------------------------------------------
# DB SESSION
# ---------------------------------------------------------------------
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/health")
def health():
    return {"status": "ok", "service": "database-service"}

# ---------------------------------------------------------------------
# ORDERS CRUD
# ---------------------------------------------------------------------
@app.post("/orders", response_model=OrderOut, status_code=201)
def create_order(payload: OrderIn, db=Depends(get_db)):
    ins = orders.insert().values(**payload.dict())
    db.execute(ins)
    db.commit()
    return payload

@app.get("/orders/{oid}", response_model=OrderOut)
def get_order(oid: str, db=Depends(get_db)):
    q = select(orders).where(orders.c.id == oid)
    r = db.execute(q).first()
    if not r:
        raise HTTPException(404, "order not found")
    return dict(r._mapping)

@app.get("/orders", response_model=List[OrderOut])
def list_orders(db=Depends(get_db)):
    r = db.execute(select(orders)).fetchall()
    return [dict(x._mapping) for x in r]

@app.put("/orders/{oid}", response_model=OrderOut)
def update_order(oid: str, payload: OrderIn, db=Depends(get_db)):
    """
    Merge update: preserve existing columns (including refund metadata)
    unless the incoming payload explicitly sets them.
    """
    try:
        with db.begin():
            q = select(orders).where(orders.c.id == oid)
            existing = db.execute(q).first()
            if not existing:
                raise HTTPException(status_code=404, detail="order not found")
            existing_obj = dict(existing._mapping)

            # payload may be a BaseModel; use exclude_unset to avoid overwriting with defaults
            # BUT FastAPI always builds the model - to support partial updates, you can accept
            # a Pydantic model with optional fields or use request.json directly. For simplicity
            # we treat incoming payload's values and overwrite only keys present and not None.
            incoming = payload.dict(exclude_unset=True)

            # Merge: incoming overrides existing, but keys not present in incoming stay intact
            merged = {**existing_obj, **incoming}

            db.execute(orders.update().where(orders.c.id == oid).values(**merged))
        return merged
    except SQLAlchemyError as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"DB error updating order: {e}")

@app.delete("/orders/{oid}", status_code=204)
def delete_order(oid: str, db=Depends(get_db)):
    db.execute(orders.delete().where(orders.c.id==oid))
    db.commit()
    return

# Safe refund-metadata endpoint
@app.post("/orders/{oid}/refund-metadata", status_code=200)
def add_refund_metadata(oid: str, payload: dict, db=Depends(get_db)):
    """
    payload: {"refund_attempt": {...}, "payment_refund_status": "refunded"}
    This updates only columns that actually exist in the orders table. Safe to call
    even if DB schema hasn't been altered.
    """
    try:
        # Inspect existing order columns
        inspector = inspect(engine)
        cols = [c["name"] for c in inspector.get_columns("orders")]
        # Filter payload to keys that are actual columns
        to_update = {k: v for k, v in payload.items() if k in cols}
        if not to_update:
            # Nothing to update, return OK (best-effort)
            return {"updated": False, "reason": "no matching columns"}
        db.execute(orders.update().where(orders.c.id == oid).values(**to_update))
        db.commit()
        return {"updated": True, "updated_keys": list(to_update.keys())}
    except Exception as e:
        db.rollback()
        # Best-effort: swallow and return failure note, caller will ignore if desired
        raise HTTPException(status_code=500, detail=f"Failed to apply refund metadata: {e}")

# ---------------------------------------------------------------------
# INVENTORY CRUD
# ---------------------------------------------------------------------
@app.post("/inventory", response_model=InventoryOut, status_code=201)
def create_inventory(payload: InventoryIn, db=Depends(get_db)):
    existing = db.execute(select(inventory).where(inventory.c.sku == payload.sku)).first()
    if existing:
        # Update quantity instead of throwing duplicate error
        db.execute(
            inventory.update()
            .where(inventory.c.sku == payload.sku)
            .values(quantity=payload.quantity)
        )
    else:
        db.execute(inventory.insert().values(**payload.dict()))
    db.commit()
    return payload

@app.get("/inventory/{sku}", response_model=InventoryOut)
def get_inventory(sku: str, db=Depends(get_db)):
    r = db.execute(select(inventory).where(inventory.c.sku==sku)).first()
    if not r:
        raise HTTPException(404, "sku not found")
    return dict(r._mapping)

@app.get("/inventory", response_model=List[InventoryOut])
def list_inventory(db=Depends(get_db)):
    r = db.execute(select(inventory)).fetchall()
    return [dict(x._mapping) for x in r]

@app.put("/inventory/{sku}", response_model=InventoryOut)
def update_inventory(sku: str, payload: InventoryIn, db=Depends(get_db)):
    db.execute(inventory.update().where(inventory.c.sku==sku).values(**payload.dict()))
    db.commit()
    return payload

@app.delete("/inventory/{sku}", status_code=204)
def delete_inventory(sku: str, db=Depends(get_db)):
    db.execute(inventory.delete().where(inventory.c.sku==sku))
    db.commit()
    return

# ---------------------------------------------------------------------
# 🆕 INVENTORY RESERVATIONS CRUD
# ---------------------------------------------------------------------
@app.post("/inventory/reserve", response_model=InventoryReservationOut, status_code=201)
def create_reservation(payload: InventoryReservationIn, db=Depends(get_db)):
    try:
        with db.begin():
            # 1) check availability with row locks
            for it in payload.items:
                sku = it.get("sku")
                qty = int(it.get("qty"))
                row = _lock_and_get_inventory_row(db, sku)
                if not row:
                    raise HTTPException(409, f"SKU {sku} not found")
                current_qty = row._mapping["quantity"]
                if current_qty < qty:
                    raise HTTPException(409, f"Insufficient stock for {sku}")

            # 2) decrement inventory for all items
            for it in payload.items:
                sku = it.get("sku")
                qty = int(it.get("qty"))
                db.execute(
                    inventory.update()
                    .where(inventory.c.sku == sku)
                    .values(quantity=inventory.c.quantity - qty)
                )

            # 3) insert reservation row
            db.execute(inventory_reservations.insert().values(**payload.dict()))
        return payload

    except HTTPException:
        raise
    except SQLAlchemyError as e:
        db.rollback()
        raise HTTPException(500, detail=f"DB error reserving inventory: {e}")

@app.get("/inventory/reserve/{rid}", response_model=InventoryReservationOut)
def get_reservation(rid: str, db=Depends(get_db)):
    q = select(inventory_reservations).where(inventory_reservations.c.id == rid)
    r = db.execute(q).first()
    if not r:
        raise HTTPException(404, "reservation not found")
    return dict(r._mapping)

@app.put("/inventory/reserve/{rid}", response_model=InventoryReservationOut)
def update_reservation(rid: str, payload: InventoryReservationIn, db=Depends(get_db)):
    try:
        with db.begin():
            q = select(inventory_reservations).where(inventory_reservations.c.id == rid).with_for_update()
            existing = db.execute(q).first()
            if not existing:
                raise HTTPException(404, "reservation not found")

            existing_obj = dict(existing._mapping)
            prev_status = existing_obj.get("status")
            new_status = payload.status

            # release: restore inventory only if previous status was reserved
            if prev_status == "reserved" and new_status == "released":
                for it in existing_obj["items"]:
                    sku = it.get("sku")
                    qty = int(it.get("qty"))
                    row = _lock_and_get_inventory_row(db, sku)
                    if not row:
                        # create the row if deleted
                        db.execute(inventory.insert().values(sku=sku, quantity=qty))
                    else:
                        db.execute(
                            inventory.update()
                            .where(inventory.c.sku == sku)
                            .values(quantity=inventory.c.quantity + qty)
                        )

            # if committing from reserved -> committed, nothing to change (inventory already decremented)
            db.execute(inventory_reservations.update().where(inventory_reservations.c.id == rid).values(**payload.dict()))
        return payload

    except HTTPException:
        raise
    except SQLAlchemyError as e:
        db.rollback()
        raise HTTPException(500, detail=f"DB error updating reservation: {e}")

@app.get("/inventory/reserve", response_model=List[InventoryReservationOut])
def list_reservations(db=Depends(get_db)):
    r = db.execute(select(inventory_reservations)).fetchall()
    return [dict(x._mapping) for x in r]

@app.delete("/inventory/reserve/{rid}", status_code=204)
def delete_reservation(rid: str, db=Depends(get_db)):
    try:
        with db.begin():
            q = select(inventory_reservations).where(inventory_reservations.c.id == rid).with_for_update()
            existing = db.execute(q).first()
            if existing:
                existing_obj = dict(existing._mapping)
                if existing_obj.get("status") == "reserved":
                    # restore stock
                    for it in existing_obj["items"]:
                        sku = it.get("sku")
                        qty = int(it.get("qty"))
                        row = _lock_and_get_inventory_row(db, sku)
                        if not row:
                            db.execute(inventory.insert().values(sku=sku, quantity=qty))
                        else:
                            db.execute(
                                inventory.update()
                                .where(inventory.c.sku == sku)
                                .values(quantity=inventory.c.quantity + qty)
                            )
                db.execute(inventory_reservations.delete().where(inventory_reservations.c.id == rid))
            else:
                # idempotent delete
                return
        return
    except SQLAlchemyError as e:
        db.rollback()
        raise HTTPException(500, detail=f"DB error deleting reservation: {e}")

# ---------------------------------------------------------------------
# PAYMENTS CRUD
# ---------------------------------------------------------------------
@app.post("/payments", response_model=PaymentOut, status_code=201)
def create_payment(payload: PaymentIn, db=Depends(get_db)):
    db.execute(payments.insert().values(**payload.dict()))
    db.commit()
    return payload

@app.get("/payments/{pid}", response_model=PaymentOut)
def get_payment(pid: str, db=Depends(get_db)):
    r = db.execute(select(payments).where(payments.c.id==pid)).first()
    if not r:
        raise HTTPException(404, "payment not found")
    return dict(r._mapping)

@app.get("/payments", response_model=List[PaymentOut])
def list_payments(db=Depends(get_db)):
    r = db.execute(select(payments)).fetchall()
    return [dict(x._mapping) for x in r]

@app.put("/payments/{pid}", response_model=PaymentOut)
def update_payment(pid: str, payload: PaymentIn, db=Depends(get_db)):
    db.execute(payments.update().where(payments.c.id==pid).values(**payload.dict()))
    db.commit()
    return payload

@app.delete("/payments/{pid}", status_code=204)
def delete_payment(pid: str, db=Depends(get_db)):
    db.execute(payments.delete().where(payments.c.id==pid))
    db.commit()
    return

# ---------------------------------------------------------------------
# SHIPMENTS CRUD
# ---------------------------------------------------------------------
@app.post("/shipments", response_model=ShipmentOut, status_code=201)
def create_shipment(payload: ShipmentIn, db=Depends(get_db)):
    db.execute(shipments.insert().values(**payload.dict()))
    db.commit()
    return payload

@app.get("/shipments/{sid}", response_model=ShipmentOut)
def get_shipment(sid: str, db=Depends(get_db)):
    r = db.execute(select(shipments).where(shipments.c.id==sid)).first()
    if not r:
        raise HTTPException(404, "shipment not found")
    return dict(r._mapping)

@app.get("/shipments", response_model=List[ShipmentOut])
def list_shipments(db=Depends(get_db)):
    r = db.execute(select(shipments)).fetchall()
    return [dict(x._mapping) for x in r]

@app.put("/shipments/{sid}", response_model=ShipmentOut)
def update_shipment(sid: str, payload: ShipmentIn, db=Depends(get_db)):
    db.execute(shipments.update().where(shipments.c.id==sid).values(**payload.dict()))
    db.commit()
    return payload

@app.delete("/shipments/{sid}", status_code=204)
def delete_shipment(sid: str, db=Depends(get_db)):
    db.execute(shipments.delete().where(shipments.c.id==sid))
    db.commit()
    return
