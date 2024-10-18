create table if not exists clients (
    id integer primary key,
    name text,
    phone text
);

create table if not exists speeds (
    id integer primary key,
    type text,
    coeff numeric(2, 1)
);

create table if not exists stations (
    id integer primary key,
    station_code integer,
    station_name text,
    station_rw text
);

create table if not exists shipments (
    id integer primary key,
    datetime timestamp,
    freight text,
    sender_id integer references clients,
    receiver_id integer references clients,
    speed_id integer references speeds
);

create table if not exists routes (
    id integer primary key,
    shipment_id integer references shipments,
    station_id integer references stations,
    date_arrival date
); 

create table if not exists clients_discounts (
    id integer primary key,
    client_id integer references clients unique,
    discount numeric
);


INSERT INTO clients (id, name, phone)
VALUES
    (1, 'Кузнецов Игорь Николаевич',79112223344),
    (2, 'ООО “Ручки-попрыгучки”', 79225556677),
    (3, 'Кузнецов Николай Петрович', 79441112233),
    (4, 'ООО “Всем по принтеру”', 79338889900),
    (5, 'ООО “Волнующий тюльпан”', 79554445566);

INSERT INTO speeds (id, type, coeff)
VALUES
    (1, 'Грузовая',1),
    (2, 'Пассажирская', 1.6),
    (3, 'Большая', 2.1);

INSERT INTO shipments (id, datetime, freight, sender_id, receiver_id, speed_id)
VALUES
    (1, to_timestamp('10.05.2023 17:10:00', 'dd.mm.yyyy hh24:mi:ss'), 'Личные вещи', 1, 3, 1),
    (2, to_timestamp('12.05.2023 11:30:00', 'dd.mm.yyyy hh24:mi:ss'), 'Канцтовары', 2, 4, 1),
    (3, to_timestamp('24.05.2023 09:00:00', 'dd.mm.yyyy hh24:mi:ss'), 'Упаковочные материалы', 4, 5, 3);

INSERT INTO clients_discounts (id, client_id, discount)
VALUES
    (1, 4, 5.0);

INSERT INTO stations (id, station_code, station_name, station_rw)
VALUES
    (1, 11111, 'Лапочкинск', 'Октябрьская ЖД'),
    (2, 22222, 'Радужный город', 'Октябрьская ЖД'),
    (3, 33333, 'Морковный хутор', 'Московская ЖД'),
    (4, 44444, 'Городищево', 'Московская ЖД'),
    (5, 55555, 'Береговское', 'Московская ЖД');

INSERT INTO routes (id, shipment_id, station_id, date_arrival)
VALUES
    (1, 1, 2, to_date('10.05.2023', 'dd.mm.yyyy')),
    (2, 1, 3, to_date('13.05.2023', 'dd.mm.yyyy')),
    (3, 3, 3, to_date('24.05.2023', 'dd.mm.yyyy')),
    (4, 3, 5, to_date('26.05.2023', 'dd.mm.yyyy')),
    (5, 2, 5, to_date('12.05.2023', 'dd.mm.yyyy'));


-- TEST
-- INSERT INTO clients_discounts (id, client_id, discount)
-- VALUES (2, 100, 10.0);
-- DELETE FROM stations WHERE id = 3;

-- удаляем внешний ключ
ALTER TABLE routes DROP CONSTRAINT routes_station_id_fkey;
-- добавляем новый внешний ключ с действием ON DELETE CASCADE
ALTER TABLE routes ADD FOREIGN KEY (station_id) REFERENCES stations ON DELETE CASCADE;
-- пробуем удалить строку из stations
DELETE FROM stations WHERE id = 3;
-- проверяем, что строки из routes также удалились
SELECT * FROM routes 


--удаляем внешний ключ
ALTER TABLE routes DROP CONSTRAINT routes_station_id_fkey;
--добавляем новый внешний ключ с действием ON DELETE RESTRICT
ALTER TABLE routes ADD FOREIGN KEY (station_id) REFERENCES stations ON DELETE RESTRICT;
--пробуем удалить строку из stations
DELETE FROM stations WHERE id = 2;


DELETE FROM stations WHERE id = 1;
SELECT * FROM stations WHERE id = 1;