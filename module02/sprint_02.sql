-- ==========================================
-- Этап 1. Создание дополнительных таблиц.
-- ==========================================

-- Шаг 1.
--CREATE TYPE cafe.restaurant_type AS ENUM ('coffee_shop', 'restaurant', 'bar', 'pizzeria');

DROP TABLE IF EXISTS cafe.sales CASCADE;
DROP TABLE IF EXISTS cafe.restaurant_manager_work_dates CASCADE;
DROP TABLE IF EXISTS cafe.managers CASCADE;
DROP TABLE IF EXISTS cafe.restaurants CASCADE;

-- Шаг 2.
CREATE TABLE IF NOT EXISTS cafe.restaurants (
    restaurant_uuid uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
    "name" varchar(50) NOT NULL,
    "location" geometry(POINT, 4326) NOT NULL,
    "type" cafe.restaurant_type NOT NULL,
    menu jsonb NOT NULL
);

-- Шаг 3.
CREATE TABLE IF NOT EXISTS cafe.managers (
    manager_uuid uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
    "name" varchar(200) NOT NULL,
    phone varchar(50) NOT NULL
);

-- Шаг 3.
CREATE TABLE IF NOT EXISTS cafe.restaurant_manager_work_dates (
    restaurant_uuid uuid NOT NULL REFERENCES cafe.restaurants (restaurant_uuid),
    manager_uuid uuid NOT NULL REFERENCES cafe.managers (manager_uuid),
    shift_start_at date,
    shift_end_at date CHECK(shift_end_at > shift_start_at),
    PRIMARY KEY (restaurant_uuid, manager_uuid)
);

-- Шаг 5.
CREATE TABLE IF NOT EXISTS cafe.sales (
    "date" date NOT NULL,
    restaurant_uuid uuid NOT NULL REFERENCES cafe.restaurants (restaurant_uuid),
    avg_check numeric(6, 2) CHECK (avg_check >= 0),
    PRIMARY KEY ("date", restaurant_uuid)
);


-- Наполнение таблиц.

-- Рестораны
INSERT INTO cafe.restaurants ("name", "location", "type", menu)
SELECT DISTINCT
    s.cafe_name AS "name",
    ST_GeomFromText(CONCAT('POINT(', s.longitude, ' ', s.latitude, ')'), 4326),
    s.type::cafe.restaurant_type AS "type",
    m.menu AS menu
FROM raw_data.sales AS s
JOIN raw_data.menu AS m on s.cafe_name = m.cafe_name;

-- Менеджеры
INSERT INTO cafe.managers ("name", phone)
SELECT DISTINCT s.manager AS "name", s.manager_phone AS phone
FROM raw_data.sales AS s;

-- Смены менеджеров в ресторанах
INSERT INTO cafe.restaurant_manager_work_dates (restaurant_uuid, manager_uuid)
SELECT DISTINCT r.restaurant_uuid AS restaurant_uuid, m.manager_uuid AS manager_uuid
FROM raw_data.sales AS s
INNER JOIN cafe.restaurants AS r on s.cafe_name = r.name
INNER JOIN cafe.managers AS m on s.manager = m.name;

-- Продажи
INSERT INTO cafe.sales ("date", restaurant_uuid, avg_check)
SELECT s.report_date AS "date", r.restaurant_uuid AS restaurant_uuid, s.avg_check AS avg_check
FROM raw_data.sales AS s
INNER JOIN cafe.restaurants AS r on s.cafe_name = r.name;


-- ==========================================
-- Этап 2. Создание представлений и написание аналитических запросов.
-- ==========================================

-- Задание 1.
CREATE VIEW cafe.v_top_rests_by_avg_check AS
    WITH top_rests AS (
        SELECT r.name, r.type, AVG(s.avg_check) AS max_avg_check
        FROM cafe.restaurants AS r
        INNER JOIN cafe.sales AS s USING (restaurant_uuid)
        GROUP BY r.name, r.type)
    SELECT t1.name AS "Название заведения", t1.type AS "Тип заведения", ROUND(t1.max_avg_check, 2) AS "Средний чек"
    FROM (
        SELECT
            t.name,
            t.type,
            t.max_avg_check,
            ROW_NUMBER() OVER (PARTITION BY t.type ORDER BY t.type, t.max_avg_check DESC)
        FROM top_rests AS t
        ORDER BY t.type, t.max_avg_check DESC
    ) AS t1
    WHERE t1.row_number < 4;

-- Задание 2.
CREATE MATERIALIZED VIEW cafe.v_avg_check_year_by_year_fluct AS
    SELECT
        EXTRACT(YEAR FROM s.date) AS "Год",
        r.name AS "Название заведения",
        r.type AS "Тип заведения",
        ROUND(AVG(s.avg_check), 2) AS "Средний чек в этом году",
        ROUND(LAG(AVG(s.avg_check)) OVER (PARTITION BY r.name ORDER BY EXTRACT(YEAR FROM s.date)), 2) AS "Средний чек в предыдущем году",
        ROUND(
            AVG(s.avg_check) / LAG(AVG(s.avg_check)) OVER (PARTITION BY r.name ORDER BY EXTRACT(YEAR FROM s.date)) * 100 - 100,
            2) AS "Изменение среднего чека в %"
    FROM cafe.restaurants AS r
    INNER JOIN cafe.sales AS s USING (restaurant_uuid)
    WHERE EXTRACT(YEAR FROM s.date) != 2023
    GROUP BY EXTRACT(YEAR FROM s.date), r.name, r.type
    ORDER BY "Название заведения", "Год";

-- Задание 3.
SELECT r.name AS "Название заведения", COUNT(DISTINCT m.manager_uuid) AS "Сколько раз менялся менеджер"
FROM cafe.restaurants AS r
INNER JOIN cafe.restaurant_manager_work_dates AS m USING (restaurant_uuid)
GROUP BY r.name
ORDER BY "Сколько раз менялся менеджер" DESC
LIMIT 3;

-- Задание 4.
WITH rest_pizza_junction AS
    (
        SELECT r.name, jsonb_object_keys(r.menu -> 'Пицца') AS pizza
        FROM cafe.restaurants AS r
    ), ranked_rests_by_pizzas_count AS
    (
        SELECT
            t0.name AS rest_name,
            COUNT(t0.pizza) AS pizzas_count,
            DENSE_RANK() OVER (ORDER BY COUNT(t0.pizza) DESC)
        FROM rest_pizza_junction AS t0
        GROUP BY t0.name
    )
SELECT t1.rest_name AS "Название заведения", t1.pizzas_count AS "Количество пицц в меню"
FROM ranked_rests_by_pizzas_count AS t1
WHERE t1.dense_rank = 1;

-- Задание 5.
SELECT
    r.name AS "Название заведения",
    'Пицца' as "Тип блюда",
    (
        SELECT p.key AS pizza
        FROM jsonb_each(r.menu -> 'Пицца') AS p
        ORDER BY p.value DESC
        LIMIT 1
    ) AS "Название пиццы",
    (
        SELECT p.value AS price
        FROM jsonb_each(r.menu -> 'Пицца') AS p
        ORDER BY p.value DESC
        LIMIT 1
    ) AS "Цена"
FROM cafe.restaurants AS r
WHERE
    (
        SELECT p.key AS pizza
        FROM jsonb_each(r.menu -> 'Пицца') AS p
        ORDER BY p.value DESC
        LIMIT 1
    ) IS NOT NULL;

-- Задание 6.
SELECT
    r0.name AS "Название Заведения 1",
    r1.name AS "Название Заведения 2",
    r0.type AS "Тип заведения",
    ST_Distance(r0.location::geography, r1.location::geography) AS "Расстояние"
FROM cafe.restaurants AS r0
CROSS JOIN cafe.restaurants AS r1
WHERE r0.restaurant_uuid != r1.restaurant_uuid AND r0.type = r1.type
ORDER BY "Расстояние"
LIMIT 1;

-- Задание 7.
WITH district_restaurants_count_desc AS
    (
        SELECT d.district_name AS district_name, COUNT(r.*) AS restaurants_count
        FROM cafe.districts AS d
        INNER JOIN cafe.restaurants AS r ON ST_Within(r.location, d.district_geom)
        GROUP BY d.district_name
        ORDER BY restaurants_count DESC
        LIMIT 1
    ), district_restaurants_count_asc AS
    (
        SELECT d.district_name AS district_name, COUNT(r.*) AS restaurants_count
        FROM cafe.districts AS d
        INNER JOIN cafe.restaurants AS r ON ST_Within(r.location, d.district_geom)
        GROUP BY d.district_name
        ORDER BY restaurants_count ASC
        LIMIT 1
    )
SELECT t.district_name AS "Название района", t.restaurants_count AS "Количество заведений"
FROM district_restaurants_count_desc AS t
UNION
SELECT t.district_name AS "Название района", t.restaurants_count AS "Количество заведений"
FROM district_restaurants_count_asc AS t
ORDER BY "Количество заведений" DESC;
