-- ==========================================
-- СЫРЫЕ ДАННЫЕ
-- ==========================================

-- Создаём схему raw_data и таблицу sales для выгрузки сырых данных в этой схеме.
CREATE SCHEMA IF NOT EXISTS raw_data;

-- Создаём таблицу для сырых данных
CREATE TABLE IF NOT EXISTS raw_data.sales (
    id INTEGER PRIMARY KEY,
    auto text,
    gasoline_consumption NUMERIC(3, 1),
    price NUMERIC(19, 12),
    date DATE,
    person_name text,
    phone text,
    discount SMALLINT,
    brand_origin text
);


-- ==========================================
-- COPY
-- ==========================================

-- Копируем данные в таблицу
-- Скорее всего нужно прописать свой путь до файла
-- =========================
-- COPY raw_data.sales (id, auto, gasoline_consumption, price, date, person_name, phone, discount, brand_origin)
-- FROM '/home/cars.csv'
-- WITH CSV HEADER DELIMITER ',' NULL AS 'null';


-- ==========================================
-- СОЗДАЕМ ТАБЛИЦЫ
-- ==========================================

-- Создаём схему car_shop
CREATE SCHEMA IF NOT EXISTS car_shop;

-- Для тестовых целей, когда необходимо было перезапустить скрипт, чтобы не было ошибки
DROP TABLE IF EXISTS car_shop.orders;
DROP TABLE IF EXISTS car_shop.customer_discounts;
DROP TABLE IF EXISTS car_shop.customers;
DROP TABLE IF EXISTS car_shop.cars;
DROP TABLE IF EXISTS car_shop.car_brands;
DROP TABLE IF EXISTS car_shop.countries;

-- Создаем таблицу с локациями
CREATE TABLE IF NOT EXISTS car_shop.countries (
    id SERIAL PRIMARY KEY,
    -- Текстовое поле для названия государства, предполагаем, что название государства не больше 100 символов
    -- NOT NULL - в таблице со странами должны быть записи со странами
    -- UNIQUE - чтобы названия стран не повторялись
    country varchar(100) NOT NULL UNIQUE
);

-- Создаем таблицу с брэндами машин
CREATE TABLE IF NOT EXISTS car_shop.car_brands (
    id SERIAL PRIMARY KEY,
    -- Текстовое поле для название бренда, предполагаем, что название бренда не больше 100 символов
    -- NOT NULL - в таблице брэнды должны быть записи с брэндами
    -- UNIQUE - чтобы названия брэндов не повторялись
    brand varchar(100) NOT NULL UNIQUE,
    -- FK - Ссылка на таблицу со списком стран, для указания страны происхождения брэнда
    -- NULLABLE - в сырых данных не все государства были заполнены
    country_id INTEGER REFERENCES car_shop.countries (id)
);

-- Создаем таблицу с машинами
CREATE TABLE IF NOT EXISTS car_shop.cars (
    id SERIAL PRIMARY KEY,
    -- FK - Ссылка на брэнд машины
    -- NOT NULL - скорей всего не бывает машин без брэнда
    brand_id INTEGER NOT NULL REFERENCES car_shop.car_brands (id),
    -- Текстовое поле для названия модели, предполагаем, что название модели не больше 100 символов
    -- NOT NULL - у машины обязательно должна быть модель
    model VARCHAR(100) NOT NULL,
    -- Потребление бензина не может быть трехзначным и больше, выделяем 2 знака на целую часть, и судя по сырым данным 1 знак после запятой
    -- NULLABLE - для электромобилей
    gasoline_consumption NUMERIC(3, 1)
    -- Можно было бы добавить UNIQUE для брэнда, модели и цвета, но бывает разная комплектация и правило становится слишком сложным
);

-- Создаем таблицу клиентов
-- Обязательно заполняем все поля для клиента, чтобы можно было обращаться к нему по имени и знать телефон для связи
CREATE TABLE IF NOT EXISTS car_shop.customers (
    id SERIAL PRIMARY KEY,
    person_name VARCHAR(200) NOT NULL,
    phone VARCHAR(30) NOT NULL
);

-- Создаем таблицу скидок для клиентов
CREATE TABLE IF NOT EXISTS car_shop.customer_discounts (
    id SERIAL PRIMARY KEY,
    -- Ссылка на customers
    -- UNIQUE - у одного клиента может быть только одна скидка (1 к 1)
    customer_id INTEGER NOT NULL UNIQUE REFERENCES car_shop.customers (id),
    -- NUMERIC - На целую часть 3 знака (т.к. максимальное значение 100), 2 знака после запятой для удобства, чтобы не выходить на тысячные доли
    -- NOT NULL, DEFAULT (0) - исходя из сырых данных, если дисконт не задан, то он устанавливается в 0
    -- CHECK - чтобы не получилось отрицательной скидки или выше максимально возможной
    discount NUMERIC(5, 2) NOT NULL DEFAULT (0) CHECK (discount >= 0.0 AND discount <= 100.0)
);

-- Создаем таблицу заказов
CREATE TABLE IF NOT EXISTS car_shop.orders (
    id SERIAL PRIMARY KEY,
    -- ссылка на клиента
    -- NOT NULL - всегда заполнено, так как, если есть заказ, значит должен быть и клиент
    customer_id INTEGER NOT NULL REFERENCES car_shop.customers (id),
    -- Ссылка на машину
    -- NOT NULL - при добавлении позиции в корзину обязательно должен быть id продукта
    car_id INTEGER REFERENCES car_shop.cars (id) NOT NULL,
    -- DATE - для хранения даты
    -- NOT NULL - всегда заполнено так как, если есть заказ, значит есть и время его оформления
    -- DEFAULT - для того чтобы можно было установить текущую дату при оформлении заказа, если значение не было передано
    order_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    -- NUMERIC - Цена не может быть больше 7-ми значной суммы, выделяем 7 знаков на целую часть, и судя по сырым данным 12 знаков после запятой
    -- NOT NULL - обязательно должна быть цена для продукта
    -- CHECK - проверяем, чтобы не установили отрицательную цену
    price NUMERIC(19, 12) NOT NULL CHECK (price >= 0),
    -- Текстовое поле для цвета, предполагаем, что название цвета не больше 50 символов
    -- NOT NULL - скорей всего все машины окрашиваются
    color VARCHAR(50) NOT NULL
);


-- ==========================================
-- НАПОЛНЕНИЕ ТАБЛИЦ
-- ==========================================

-- Записываем данные в таблицу со странами
INSERT INTO car_shop.countries (country)
SELECT DISTINCT
    s.brand_origin
FROM raw_data.sales s
WHERE s.brand_origin IS NOT NULL;

-- Записываем данные в таблицу брэндов
INSERT INTO car_shop.car_brands (brand, country_id)
SELECT DISTINCT
    -- Выделяем брэнд из поля auto (так как брэнд 1 слово, до первого пробела)
    SUBSTR(s.auto, 0, STRPOS(s.auto, ' ')) brand,
    (
        SELECT c.id
        FROM car_shop.countries c
        WHERE c.country = s.brand_origin
    ) country_id
FROM raw_data.sales s;

-- Записываем данные в таблицу машин
INSERT INTO car_shop.cars (brand_id, model, gasoline_consumption)
SELECT DISTINCT
    (
        SELECT b.id
        FROM car_shop.car_brands b
        WHERE b.brand = SUBSTR(s.auto, 0, STRPOS(s.auto, ' '))
    ) brand_id,
    SUBSTR(s.auto, STRPOS(s.auto, ' ') + 1, STRPOS(s.auto, ',') - STRPOS(s.auto, ' ') - 1) model,
    s.gasoline_consumption
FROM raw_data.sales s;

-- Записываем данные в таблицу клиентов
INSERT INTO car_shop.customers (person_name, phone)
SELECT DISTINCT
    s.person_name,
    s.phone
FROM raw_data.sales s;

-- Записываем данные в таблицу с дисконтами для клиентов
INSERT INTO car_shop.customer_discounts (customer_id, discount)
SELECT DISTINCT
    c.id customer_id,
    (
        SELECT s.discount
        FROM raw_data.sales s
        WHERE c.person_name = s.person_name AND c.phone = s.phone
        LIMIT 1 -- Так как у некоторых клиентов несколько заказов, их скидки дублируются
    ) discount
FROM car_shop.customers c;

-- Записываем данные в таблицу заказов
INSERT INTO car_shop.orders (customer_id, car_id, order_date, price, color)
SELECT DISTINCT
    (
        SELECT c.id
        FROM car_shop.customers c
        WHERE c.person_name = s.person_name AND c.phone = s.phone
    ) customer_id,
    (
        SELECT c.id
        FROM car_shop.cars c
        JOIN car_shop.car_brands b on c.brand_id = b.id
        WHERE
            CONCAT(b.brand, ' ', c.model) =
            CONCAT(SUBSTR(s.auto, 0, STRPOS(s.auto, ' ')), ' ', SUBSTR(s.auto, STRPOS(s.auto, ' ') + 1, STRPOS(s.auto, ',') - STRPOS(s.auto, ' ') - 1))
    ) car_id,
    s.date,
    s.price,
    SUBSTR(s.auto, STRPOS(s.auto, ',') + 2) color
FROM raw_data.sales s;


-- ==========================================
-- УПРАЖНЕНИЯ
-- ==========================================

-- Задание 1
SELECT
    ROUND(
        (
            SELECT count(c.*)
            FROM car_shop.cars c
            WHERE c.gasoline_consumption IS NULL
        )::numeric / (
            SELECT count(*)
            FROM car_shop.cars)::numeric * 100, 2) nulls_percentage_gasoline_consumption;

-- Задание 2
SELECT
    b.brand AS brand_name,
    EXTRACT(YEAR FROM o.order_date) AS year,
    ROUND(AVG(o.price), 2) AS price_avg
FROM car_shop.orders AS o
JOIN car_shop.cars AS c on o.car_id = c.id
JOIN car_shop.car_brands AS b ON c.brand_id = b.id
GROUP BY b.brand, year
ORDER BY b.brand, year;

-- Задание 3
SELECT
    EXTRACT(MONTH FROM o.order_date) AS month,
    EXTRACT(YEAR FROM o.order_date) AS year,
    ROUND(AVG(o.price), 2) AS price_avg
FROM car_shop.orders AS o
GROUP BY month, year
ORDER BY year, month;

-- Задание 4
SELECT
    c.person_name AS person,
    STRING_AGG(cb.brand || ' ' || car.model, ', ') AS cars
FROM car_shop.customers AS c
JOIN car_shop.orders AS o ON c.id = o.customer_id
JOIN car_shop.cars AS car ON o.car_id = car.id
JOIN car_shop.car_brands AS cb ON car.brand_id = cb.id
GROUP BY c.person_name
ORDER BY c.person_name;

-- Задание 5
SELECT
    origin.country,
    ROUND(MAX(o.price * 100 / (100 - cd.discount)), 2) AS price_max,
    ROUND(MIN(o.price * 100 / (100 - cd.discount)), 2) AS price_min
FROM car_shop.orders AS o
JOIN car_shop.customers AS c ON o.customer_id = c.id
JOIN car_shop.customer_discounts AS cd ON c.id = cd.customer_id
JOIN car_shop.cars AS car ON o.car_id = car.id
JOIN car_shop.car_brands AS cb ON car.brand_id = cb.id
JOIN car_shop.countries AS origin ON cb.country_id = origin.id
-- Можно использовать left join, чтобы включить брэнды, для которых не указана страна
-- но данные будут не очень валидны, так как такие брэнды могут быть из разных стран
-- LEFT JOIN car_shop.countries AS origin ON cb.country_id = origin.id
GROUP BY origin.country;

-- Задание 6
SELECT COUNT(DISTINCT c.person_name)
FROM car_shop.customers AS c
WHERE SUBSTR(c.phone, 1, 2) = '+1';
