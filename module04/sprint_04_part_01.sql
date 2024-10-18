-- Задание 1.
DROP INDEX orders_city_id_idx, orders_device_type_city_id_idx, orders_device_type_idx, orders_discount_idx, orders_final_cost_idx, orders_order_dt_idx, orders_total_cost_idx, orders_total_final_cost_discount_idx;

CREATE SEQUENCE orders_order_id_seq OWNED BY orders.order_id;
ALTER TABLE orders
ALTER COLUMN order_id SET DEFAULT nextval('orders_order_id_seq');
UPDATE orders SET order_id = nextval('orders_order_id_seq');

-- Теперь можно убрать автоинкремент из команды вставки
INSERT INTO orders
    (order_dt, user_id, device_type, city_id, total_cost, discount,
    final_cost)
SELECT current_timestamp,
    '329551a1-215d-43e6-baee-322f2467272d',
    'Mobile', 1, 1000.00, null, 1000.00
FROM orders;


-- Задание 2.
CREATE TYPE gender AS ENUM ('male', 'female');

DROP MATERIALIZED VIEW IF EXISTS dish_type_orders_by_age_report;

ALTER TABLE users
ALTER COLUMN user_id TYPE uuid USING TRIM(user_id::text)::uuid,
ALTER COLUMN first_name TYPE varchar(100) USING TRIM(first_name::text)::varchar(100),
ALTER COLUMN last_name TYPE varchar(100) USING TRIM(last_name::text)::varchar(100),
ALTER COLUMN city_id TYPE int USING city_id::int,
ALTER COLUMN "gender" TYPE gender USING TRIM("gender"::text)::gender,
ALTER COLUMN birth_date TYPE timestamp USING TRIM(birth_date::text)::timestamp,
ALTER COLUMN registration_date TYPE timestamp USING TRIM(registration_date::text)::timestamp;

-- Теперь можно оптимизировать запрос, убрать кучу преобразований, уменьшить фильтр

SELECT user_id, first_name, last_name, city_id, gender
FROM users
WHERE city_id = 4
    AND to_char(birth_date, 'MMDD') = '1231';


-- Задание 3.
DROP PROCEDURE IF EXISTS add_payment(bigint, numeric);

CREATE OR REPLACE PROCEDURE public.add_payment(
    IN p_order_id bigint,
    IN p_sum_payment numeric)
LANGUAGE 'plpgsql'
AS $$
BEGIN
    INSERT INTO order_statuses (order_id, status_id, status_dt)
    VALUES (p_order_id, 2, statement_timestamp());

    INSERT INTO payments (payment_id, order_id, payment_sum)
    VALUES (nextval('payments_payment_id_sq'), p_order_id, p_sum_payment);
END;
$$;


-- Задание 4.
CREATE TABLE IF NOT EXISTS user_logs (
    visitor_id uuid,
    user_id uuid,
    event character varying(128),
    log_datetime timestamp without time zone,
    log_date date,
    log_id bigserial NOT NULL,
    CONSTRAINT user_logs_pkey PRIMARY KEY (log_id, log_date)
) PARTITION BY RANGE (log_date);

CREATE TABLE IF NOT EXISTS user_logs_y2024_q1 PARTITION OF user_logs
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

CREATE TABLE IF NOT EXISTS user_logs_y2024_q2 PARTITION OF user_logs
    FOR VALUES FROM ('2024-04-01') TO ('2024-07-01');

CREATE TABLE IF NOT EXISTS user_logs_y2024_q3 PARTITION OF user_logs
    FOR VALUES FROM ('2024-07-01') TO ('2024-10-01');

CREATE TABLE IF NOT EXISTS user_logs_y2024_q4 PARTITION OF user_logs
    FOR VALUES FROM ('2024-10-01') TO ('2025-01-01');


-- Задание 5.
CREATE MATERIALIZED VIEW IF NOT EXISTS dish_type_orders_by_age_report AS
    SELECT
        CASE
            WHEN EXTRACT(year from AGE(current_date, u.birth_date::date)) < 20 THEN 20
            WHEN EXTRACT(year from AGE(current_date, u.birth_date::date)) < 30 THEN 30
            WHEN EXTRACT(year from AGE(current_date, u.birth_date::date)) < 40 THEN 40
            ELSE 100
        END AS age,
        ROUND(SUM(d.spicy)::numeric / (SUM(d.spicy) + SUM(d.fish) + SUM(d.meat)) * 100, 2) AS spicy,
        ROUND(SUM(d.fish)::numeric / (SUM(d.spicy) + SUM(d.fish) + SUM(d.meat)) * 100, 2) AS fish,
        ROUND(SUM(d.meat)::numeric / (SUM(d.spicy) + SUM(d.fish) + SUM(d.meat)) * 100, 2) AS meat
    FROM orders AS o
    INNER JOIN order_items AS oi ON o.order_id = oi.order_id
    INNER JOIN dishes AS d ON oi.item = d.object_id
    INNER JOIN users AS u ON o.user_id = u.user_id
    -- INNER JOIN order_statuses AS os ON o.order_id = os.order_id
    -- INNER JOIN statuses AS s ON os.status_id = s.status_id
    --WHERE s.status_name = 'доставлен' ни одного заказа с таким статусом нет, поэтому не берем их в расчет в рамках задания
    WHERE o.order_dt::date < current_date
    GROUP BY age
    ORDER BY age;

SELECT *
FROM dish_type_orders_by_age_report;