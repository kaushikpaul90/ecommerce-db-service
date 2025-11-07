CREATE TABLE IF NOT EXISTS inventory (
	sku varchar NOT NULL,
	quantity int4 NOT NULL,
	CONSTRAINT inventory_pkey PRIMARY KEY (sku)
);

CREATE TABLE IF NOT EXISTS inventory_reservations (
	id varchar NOT NULL,
	"orderId" varchar NOT NULL,
	items json NOT NULL,
	status varchar NOT NULL,
	CONSTRAINT inventory_reservations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS orders (
	id varchar NOT NULL,
	items json NOT NULL,
	total float8 NOT NULL,
	status varchar NOT NULL,
	"userId" varchar NULL,
	address jsonb NULL,
	currency varchar NULL,
	refund_attempt jsonb NULL,
	payment_refund_status varchar NULL,
	CONSTRAINT orders_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS payments (
	id varchar NOT NULL,
	order_id varchar NOT NULL,
	amount float8 NOT NULL,
	status varchar NOT NULL,
	CONSTRAINT payments_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS reservations (
	id varchar NOT NULL,
	"orderId" varchar NOT NULL,
	items json NOT NULL,
	status varchar NOT NULL,
	CONSTRAINT reservations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS shipments (
	id varchar NOT NULL,
	order_id varchar NOT NULL,
	address jsonb NOT NULL,
	items json NOT NULL,
	status varchar NOT NULL,
	CONSTRAINT shipments_pkey PRIMARY KEY (id)
);