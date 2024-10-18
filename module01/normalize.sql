CREATE TABLE IF NOT EXISTS car_types (
    car_type SMALLINT PRIMARY KEY,
    car_type_name text
);

INSERT INTO car_types (car_type, car_type_name)
VALUES
    (1, 'вагон'),
    (2, 'локомотив'),
    (3, 'полувагон'),
    (4, 'рефрижератор'),
    (5, 'технический')
ON CONFLICT (car_type) DO UPDATE SET
    car_type_name = EXCLUDED.car_type_name;


CREATE TABLE IF NOT EXISTS cars (
    id SERIAL PRIMARY KEY,
    car_number INTEGER UNIQUE NOT NULL,
    car_type_id SMALLINT REFERENCES car_types (car_type) DEFAULT(1) NOT NULL
);

INSERT INTO cars (car_number, car_type_id)
VALUES
    (123456, DEFAULT),
    (234567, DEFAULT),
    (345678, DEFAULT),
    (456789, 2),
    (567890, 2)
ON CONFLICT (car_number) DO UPDATE SET
    car_type_id = EXCLUDED.car_type_id;

CREATE TABLE IF NOT EXISTS cars_passports (
    id SERIAL PRIMARY KEY,
    car_id INTEGER UNIQUE NOT NULL REFERENCES cars (id) ON DELETE CASCADE,
    date_entry DATE
);

INSERT INTO cars_passports (car_id, date_entry)
SELECT
    c.id as car_id,
    CASE WHEN c.car_number = 567890 THEN current_timestamp::DATE ELSE NULL END as date_entry
FROM cars as c
ON CONFLICT (car_id) DO UPDATE SET
    date_entry = EXCLUDED.date_entry;


CREATE TABLE IF NOT EXISTS trains (
    id SERIAL PRIMARY KEY,
    train_number text UNIQUE NOT NULL,
    departure_station INTEGER REFERENCES stations (id),
    departure_date timestamp,
    arrival_station INTEGER REFERENCES stations (id),
    arrival_date timestamp
);

INSERT INTO trains (train_number, departure_station, departure_date, arrival_station, arrival_date)
VALUES
    ('1234 567 8901', 2, '2023-06-20 10:00:00', 4, NULL),
    ('2345 678 9012', 2, '2023-06-22 10:00:00', 5, '2023-06-30 10:00:00')
ON CONFLICT (train_number) DO UPDATE SET
    departure_station = EXCLUDED.departure_station,
    departure_date = EXCLUDED.departure_date,
    arrival_station = EXCLUDED.arrival_station,
    arrival_date = EXCLUDED.arrival_date;


CREATE TABLE IF NOT EXISTS cars_in_trains (
    id SERIAL PRIMARY KEY,
    train_id INTEGER REFERENCES trains (id) NOT NULL,
    car_id INTEGER REFERENCES cars (id) NOT NULL,
    attach_date timestamp NOT NULL,
    detach_date timestamp CHECK (detach_date > attach_date),
    shipment_id INTEGER REFERENCES shipments (id),
    CONSTRAINT train_car_unique_pair UNIQUE (train_id, car_id)
);

INSERT INTO cars_in_trains (train_id, car_id, attach_date, detach_date, shipment_id)
VALUES
    (1, 4, '2023-06-20 10:00:00', NULL, NULL),
    (1, 1, '2023-06-20 10:00:00', '2023-06-25 10:00:00', 1),
    (2, 5, '2023-06-22 10:00:00', '2023-06-30 10:00:00', NULL),
    (2, 2, '2023-06-22 10:00:00', '2023-06-30 10:00:00', 2),
    (2, 3, '2023-06-25 10:00:00', '2023-06-30 10:00:00', 3)
ON CONSTRAINT (train_car_unique_pair) DO UPDATE SET
    attach_date = EXCLUDED.attach_date,
    detach_date = EXCLUDED.detach_date,
    shipment_id = EXCLUDED.shipment_id;


ALTER TABLE IF EXISTS shipments ADD cars_in_trains_id INTEGER REFERENCES cars_in_trains (id);

UPDATE shipments SET cars_in_trains_id = 2
WHERE id = 1;
UPDATE shipments UPDATE SET cars_in_trains_id = 4
WHERE id = 2;
UPDATE shipments UPDATE SET cars_in_trains_id = 5
WHERE id = 3;
