-- Ищем id нашей БД
SELECT oid, datname FROM pg_database;

-- Ищем 5 самых медленных запросов
SELECT
    query,
    calls,
    total_exec_time,
    min_exec_time,
    max_exec_time,
    mean_exec_time,
    rows
FROM pg_stat_statements
WHERE dbid = 28149
ORDER BY total_exec_time DESC
LIMIT 5;

-- Получаем следующие 5 самых медленных запросов
-- Номер запроса    mean_exec_time
-- 9                20393.9982718
-- 8                618.1909974
-- 7                295.428456
-- 2                111.1383726
-- 15               39.226496000000004



/* 9
План запроса до оптимизации:

Aggregate  (cost=61632712.74..61632712.75 rows=1 width=8) (actual time=20982.321..20982.323 rows=1 loops=1)
  ->  Nested Loop  (cost=0.30..61632712.51 rows=90 width=0) (actual time=212.530..20981.505 rows=1190 loops=1)
        ->  Seq Scan on order_statuses os  (cost=0.00..2059.34 rows=124334 width=8) (actual time=0.021..9.999 rows=124334 loops=1)
        ->  Memoize  (cost=0.30..2681.36 rows=1 width=8) (actual time=0.168..0.168 rows=0 loops=124334)
              Cache Key: os.order_id
              Cache Mode: logical
              Hits: 96650  Misses: 27684  Evictions: 0  Overflows: 0  Memory Usage: 1994kB
              ->  Index Scan using orders_order_id_idx on orders o  (cost=0.29..2681.35 rows=1 width=8) (actual time=0.748..0.748 rows=0 loops=27684)
                    Index Cond: (order_id = os.order_id)
                    Filter: ((city_id = 1) AND ((SubPlan 1) = 0))
                    Rows Removed by Filter: 1
                    SubPlan 1
                      ->  Aggregate  (cost=2681.01..2681.02 rows=1 width=8) (actual time=5.212..5.212 rows=1 loops=3958)
                            ->  Seq Scan on order_statuses os1  (cost=0.00..2681.01 rows=1 width=0) (actual time=3.316..5.205 rows=1 loops=3958)
                                  Filter: ((order_id = o.order_id) AND (status_id = 2))
                                  Rows Removed by Filter: 124333
Planning Time: 0.572 ms
JIT:
  Functions: 19
  Options: Inlining true, Optimization true, Expressions true, Deforming true
  Timing: Generation 1.021 ms, Inlining 81.422 ms, Optimization 61.031 ms, Emission 39.222 ms, Total 182.696 ms
Execution Time: 21008.813 ms

Общее время выполнения скрипта: 20982.323

Здесь нас интересует строчка (подзапрос в фильтре, на поиск неоплаченных заказов):
Seq Scan on order_statuses os1  (cost=0.00..2681.01 rows=1 width=0) (actual time=3.316..5.205 rows=1 loops=3958)
Полное время выполнения этого сегмента: 5.205 * 3958 = 20601.39 мс

Перепишем запрос так, чтобы вовсе не выполнялся подзапрос для каждой записи:
*/

WITH orders_city_id_1 AS (
    SELECT DISTINCT o.order_id
    FROM orders AS o
    JOIN order_statuses AS os ON o.order_id = os.order_id
    WHERE o.city_id = 1),
    paid_orders_city_id_1 AS (
    SELECT DISTINCT o.order_id
    FROM orders AS o
    JOIN order_statuses AS os ON o.order_id = os.order_id
    WHERE o.city_id = 1 AND os.status_id = 2)
SELECT
    (SELECT COUNT(*) FROM orders_city_id_1) - (SELECT COUNT(*) FROM paid_orders_city_id_1) AS unpaid_orders_count;

/*
Result  (cost=6804.69..6804.71 rows=1 width=8) (actual time=39.649..39.653 rows=1 loops=1)
  InitPlan 1 (returns $0)
    ->  Aggregate  (cost=3552.37..3552.38 rows=1 width=8) (actual time=24.500..24.503 rows=1 loops=1)
          ->  HashAggregate  (cost=3463.32..3502.90 rows=3958 width=8) (actual time=23.868..24.355 rows=3958 loops=1)
                Group Key: o.order_id
                Batches: 1  Memory Usage: 465kB
                ->  Hash Join  (cost=715.52..3418.88 rows=17776 width=8) (actual time=2.900..21.207 rows=17798 loops=1)
                      Hash Cond: (os.order_id = o.order_id)
                      ->  Seq Scan on order_statuses os  (cost=0.00..2059.34 rows=124334 width=8) (actual time=0.006..6.817 rows=124334 loops=1)
                      ->  Hash  (cost=666.05..666.05 rows=3958 width=8) (actual time=2.883..2.883 rows=3958 loops=1)
                            Buckets: 4096  Batches: 1  Memory Usage: 187kB
                            ->  Seq Scan on orders o  (cost=0.00..666.05 rows=3958 width=8) (actual time=0.004..2.481 rows=3958 loops=1)
                                  Filter: (city_id = 1)
                                  Rows Removed by Filter: 23726
  InitPlan 2 (returns $1)
    ->  Aggregate  (cost=3252.30..3252.31 rows=1 width=8) (actual time=15.144..15.145 rows=1 loops=1)
          ->  HashAggregate  (cost=3191.08..3218.29 rows=2721 width=8) (actual time=14.779..15.048 rows=2768 loops=1)
                Group Key: o_1.order_id
                Batches: 1  Memory Usage: 241kB
                ->  Hash Join  (cost=715.52..3184.28 rows=2721 width=8) (actual time=3.086..14.097 rows=2768 loops=1)
                      Hash Cond: (os_1.order_id = o_1.order_id)
                      ->  Seq Scan on order_statuses os_1  (cost=0.00..2370.18 rows=19031 width=8) (actual time=0.008..8.958 rows=19330 loops=1)
                            Filter: (status_id = 2)
                            Rows Removed by Filter: 105004
                      ->  Hash  (cost=666.05..666.05 rows=3958 width=8) (actual time=3.065..3.065 rows=3958 loops=1)
                            Buckets: 4096  Batches: 1  Memory Usage: 187kB
                            ->  Seq Scan on orders o_1  (cost=0.00..666.05 rows=3958 width=8) (actual time=0.004..2.594 rows=3958 loops=1)
                                  Filter: (city_id = 1)
                                  Rows Removed by Filter: 23726
Planning Time: 0.374 ms
Execution Time: 39.738 ms

Общее время выполнения скрипта: 39.653

Теперь у нас по сути те же 2 запроса, но тот что на поиск неоплаченных заказов, стал на поиск оплаченных заказов и выполняется всего 1 раз.
*/



/* 8
План запроса до оптимизации:

Append  (cost=0.00..156004.95 rows=1550938 width=83) (actual time=649.797..649.798 rows=0 loops=1)
  ->  Seq Scan on user_logs user_logs_1  (cost=0.00..39193.25 rows=410081 width=83) (actual time=194.427..194.428 rows=0 loops=1)
        Filter: ((datetime)::date > CURRENT_DATE)
        Rows Removed by Filter: 1230243
  ->  Seq Scan on user_logs_y2021q2 user_logs_2  (cost=0.00..108217.92 rows=1132379 width=83) (actual time=450.296..450.296 rows=0 loops=1)
        Filter: ((datetime)::date > CURRENT_DATE)
        Rows Removed by Filter: 3397415
  ->  Seq Scan on user_logs_y2021q3 user_logs_3  (cost=0.00..826.82 rows=8435 width=83) (actual time=5.059..5.059 rows=0 loops=1)
        Filter: ((datetime)::date > CURRENT_DATE)
        Rows Removed by Filter: 25304
  ->  Seq Scan on user_logs_y2021q4 user_logs_4  (cost=0.00..12.28 rows=43 width=584) (actual time=0.011..0.011 rows=0 loops=1)
        Filter: ((datetime)::date > CURRENT_DATE)
Planning Time: 0.852 ms
JIT:
  Functions: 8
  Options: Inlining false, Optimization false, Expressions true, Deforming true
  Timing: Generation 0.481 ms, Inlining 0.000 ms, Optimization 0.258 ms, Emission 5.570 ms, Total 6.309 ms
Execution Time: 650.353 ms

Общее время выполнения скрипта: 649.798

Судя по заданию, запрос должен искать логи за Текущий день, а стоит знак ">"
Меняем фильтр:
*/

SELECT *
FROM user_logs
WHERE datetime >= current_date::timestamp AND datetime < (current_date + '1 day'::interval)::timestamp;

/*
"Append  (cost=0.44..33.43 rows=4 width=208) (actual time=0.020..0.021 rows=0 loops=1)"
"  ->  Index Scan using user_logs_datetime_idx on user_logs user_logs_1  (cost=0.44..8.46 rows=1 width=83) (actual time=0.008..0.008 rows=0 loops=1)"
"        Index Cond: ((datetime >= (CURRENT_DATE)::timestamp without time zone) AND (datetime < (CURRENT_DATE + '1 day'::interval)))"
"  ->  Index Scan using user_logs_y2021q2_datetime_idx on user_logs_y2021q2 user_logs_2  (cost=0.44..8.46 rows=1 width=83) (actual time=0.004..0.004 rows=0 loops=1)"
"        Index Cond: ((datetime >= (CURRENT_DATE)::timestamp without time zone) AND (datetime < (CURRENT_DATE + '1 day'::interval)))"
"  ->  Index Scan using user_logs_y2021q3_datetime_idx on user_logs_y2021q3 user_logs_3  (cost=0.30..8.32 rows=1 width=83) (actual time=0.003..0.004 rows=0 loops=1)"
"        Index Cond: ((datetime >= (CURRENT_DATE)::timestamp without time zone) AND (datetime < (CURRENT_DATE + '1 day'::interval)))"
"  ->  Index Scan using user_logs_y2021q4_datetime_idx on user_logs_y2021q4 user_logs_4  (cost=0.15..8.17 rows=1 width=584) (actual time=0.003..0.003 rows=0 loops=1)"
"        Index Cond: ((datetime >= (CURRENT_DATE)::timestamp without time zone) AND (datetime < (CURRENT_DATE + '1 day'::interval)))"
"Planning Time: 0.368 ms"
"Execution Time: 0.052 ms"

Общее время выполнения скрипта: 0.021

Теперь используется индекс
*/



/* 7
План запроса до оптимизации:

Gather Merge  (cost=92117.80..92141.14 rows=200 width=19) (actual time=272.298..277.184 rows=10 loops=1)
  Workers Planned: 2
  Workers Launched: 2
  ->  Sort  (cost=91117.78..91118.03 rows=100 width=19) (actual time=252.625..252.627 rows=3 loops=3)
        Sort Key: user_logs.datetime
        Sort Method: quicksort  Memory: 25kB
        Worker 0:  Sort Method: quicksort  Memory: 25kB
        Worker 1:  Sort Method: quicksort  Memory: 25kB
        ->  Parallel Append  (cost=0.00..91114.46 rows=100 width=19) (actual time=39.138..252.550 rows=3 loops=3)
              ->  Parallel Seq Scan on user_logs_y2021q2 user_logs_2  (cost=0.00..66461.43 rows=60 width=18) (actual time=104.545..169.927 rows=2 loops=3)
                    Filter: ((visitor_uuid)::text = 'fd3a4daa-494a-423a-a9d1-03fd4a7f94e0'::text)
                    Rows Removed by Filter: 1132470
              ->  Parallel Seq Scan on user_logs user_logs_1  (cost=0.00..24071.52 rows=32 width=18) (actual time=25.200..122.599 rows=2 loops=2)
                    Filter: ((visitor_uuid)::text = 'fd3a4daa-494a-423a-a9d1-03fd4a7f94e0'::text)
                    Rows Removed by Filter: 615119
              ->  Parallel Seq Scan on user_logs_y2021q3 user_logs_3  (cost=0.00..570.06 rows=10 width=18) (actual time=2.653..2.654 rows=0 loops=1)
                    Filter: ((visitor_uuid)::text = 'fd3a4daa-494a-423a-a9d1-03fd4a7f94e0'::text)
                    Rows Removed by Filter: 25304
              ->  Parallel Seq Scan on user_logs_y2021q4 user_logs_4  (cost=0.00..10.96 rows=1 width=282) (actual time=0.001..0.001 rows=0 loops=1)
                    Filter: ((visitor_uuid)::text = 'fd3a4daa-494a-423a-a9d1-03fd4a7f94e0'::text)
Planning Time: 0.251 ms
Execution Time: 277.224 ms

Общее время выполнения скрипта: 277.184

По каждой партиции происходит Parallel Seq Scan, можно проиндексировать visitor_uuid
и так как мы получаем всего 2 столбца для запроса, можно включить их в индекс:
*/

CREATE INDEX user_logs_visitor_uuid_idx ON user_logs (visitor_uuid) INCLUDE (event, datetime);
CREATE INDEX user_logs_y2021q2_visitor_uuid_idx ON user_logs_y2021q2 (visitor_uuid) INCLUDE (event, datetime);
CREATE INDEX user_logs_y2021q3_visitor_uuid_idx ON user_logs_y2021q3 (visitor_uuid) INCLUDE (event, datetime);
CREATE INDEX user_logs_y2021q4_visitor_uuid_idx ON user_logs_y2021q4 (visitor_uuid) INCLUDE (event, datetime);

/*
Sort  (cost=52.41..53.01 rows=238 width=19) (actual time=0.065..0.067 rows=10 loops=1)
  Sort Key: user_logs.datetime
  Sort Method: quicksort  Memory: 25kB
  ->  Append  (cost=0.55..43.02 rows=238 width=19) (actual time=0.023..0.058 rows=10 loops=1)
        ->  Index Only Scan using user_logs_visitor_uuid_idx on user_logs user_logs_1  (cost=0.55..9.88 rows=76 width=18) (actual time=0.023..0.025 rows=5 loops=1)
              Index Cond: (visitor_uuid = 'fd3a4daa-494a-423a-a9d1-03fd4a7f94e0'::text)
              Heap Fetches: 0
        ->  Index Only Scan using user_logs_y2021q2_visitor_uuid_idx on user_logs_y2021q2 user_logs_2  (cost=0.56..15.07 rows=144 width=18) (actual time=0.015..0.018 rows=5 loops=1)
              Index Cond: (visitor_uuid = 'fd3a4daa-494a-423a-a9d1-03fd4a7f94e0'::text)
              Heap Fetches: 0
        ->  Index Only Scan using user_logs_y2021q3_visitor_uuid_idx on user_logs_y2021q3 user_logs_3  (cost=0.41..8.71 rows=17 width=18) (actual time=0.009..0.009 rows=0 loops=1)
              Index Cond: (visitor_uuid = 'fd3a4daa-494a-423a-a9d1-03fd4a7f94e0'::text)
              Heap Fetches: 0
        ->  Index Only Scan using user_logs_y2021q4_visitor_uuid_idx on user_logs_y2021q4 user_logs_4  (cost=0.14..8.16 rows=1 width=282) (actual time=0.003..0.003 rows=0 loops=1)
              Index Cond: (visitor_uuid = 'fd3a4daa-494a-423a-a9d1-03fd4a7f94e0'::text)
              Heap Fetches: 0
Planning Time: 0.287 ms
Execution Time: 0.098 ms

Общее время выполнения скрипта: 0.067

Теперь происходит Index Only Scan.
*/



/* 2
План запроса до оптимизации:

Nested Loop  (cost=15.51..33509.86 rows=44 width=54) (actual time=105.927..105.931 rows=2 loops=1)
  Join Filter: (os.status_id = s.status_id)
  Rows Removed by Join Filter: 10
  ->  Seq Scan on statuses s  (cost=0.00..22.70 rows=1270 width=36) (actual time=0.004..0.006 rows=6 loops=1)
  ->  Materialize  (cost=15.51..33353.82 rows=7 width=26) (actual time=8.706..17.653 rows=2 loops=6)
        ->  Hash Join  (cost=15.51..33353.79 rows=7 width=26) (actual time=52.234..105.910 rows=2 loops=1)
              Hash Cond: (os.order_id = o.order_id)
              Join Filter: (SubPlan 1)
              Rows Removed by Join Filter: 10
              ->  Seq Scan on order_statuses os  (cost=0.00..2059.34 rows=124334 width=20) (actual time=0.002..6.722 rows=124334 loops=1)
              ->  Hash  (cost=15.48..15.48 rows=3 width=22) (actual time=0.013..0.014 rows=2 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 9kB
                    ->  Bitmap Heap Scan on orders o  (cost=4.31..15.48 rows=3 width=22) (actual time=0.010..0.010 rows=2 loops=1)
                          Recheck Cond: (user_id = 'c2885b45-dddd-4df3-b9b3-2cc012df727c'::uuid)
                          Heap Blocks: exact=1
                          ->  Bitmap Index Scan on orders_user_id_idx  (cost=0.00..4.31 rows=3 width=0) (actual time=0.005..0.006 rows=2 loops=1)
                                Index Cond: (user_id = 'c2885b45-dddd-4df3-b9b3-2cc012df727c'::uuid)
              SubPlan 1
                ->  Aggregate  (cost=2370.19..2370.20 rows=1 width=8) (actual time=7.536..7.537 rows=1 loops=12)
                      ->  Seq Scan on order_statuses  (cost=0.00..2370.18 rows=5 width=8) (actual time=7.488..7.526 rows=6 loops=12)
                            Filter: (order_id = o.order_id)
                            Rows Removed by Filter: 124328
Planning Time: 0.261 ms
Execution Time: 105.973 ms

Общее время выполнения скрипта: 105.931

Здесь нас интересует строчка (подзапрос в фильтре, на поиск последних установленных статусов):
Seq Scan on order_statuses  (cost=0.00..2370.18 rows=5 width=8) (actual time=7.488..7.526 rows=6 loops=12)
Полное время выполнения этого сегмента: 7.526 * 12 = 90.312 мс

Перепишем запрос с помощью оконных функций, так, чтобы вовсе не выполнялся подзапрос для каждой записи:
*/

WITH user_last_order_statuses AS (
    SELECT
        o.order_id, o.order_dt, o.final_cost, s.status_name,
        ROW_NUMBER() OVER (PARTITION BY o.order_id ORDER BY os.status_dt DESC)
    FROM order_statuses os
    JOIN orders o ON o.order_id = os.order_id
    JOIN statuses s ON s.status_id = os.status_id
    WHERE o.user_id = 'c2885b45-dddd-4df3-b9b3-2cc012df727c'::uuid)
SELECT order_id, order_dt, final_cost, status_name
FROM user_last_order_statuses
WHERE row_number = 1

/*
Subquery Scan on user_last_order_statuses  (cost=2585.38..2588.08 rows=1 width=54) (actual time=14.823..14.973 rows=2 loops=1)
  Filter: (user_last_order_statuses.row_number = 1)
  ->  WindowAgg  (cost=2585.38..2587.04 rows=83 width=70) (actual time=14.822..14.831 rows=2 loops=1)
        Run Condition: (row_number() OVER (?) <= 1)
        ->  Sort  (cost=2585.38..2585.59 rows=83 width=62) (actual time=14.817..14.820 rows=12 loops=1)
              Sort Key: o.order_id, os.status_dt DESC
              Sort Method: quicksort  Memory: 25kB
              ->  Hash Join  (cost=54.09..2582.74 rows=83 width=62) (actual time=14.739..14.809 rows=12 loops=1)
                    Hash Cond: (os.status_id = s.status_id)
                    ->  Hash Join  (cost=15.51..2541.24 rows=13 width=34) (actual time=14.708..14.775 rows=12 loops=1)
                          Hash Cond: (os.order_id = o.order_id)
                          ->  Seq Scan on order_statuses os  (cost=0.00..2059.34 rows=124334 width=20) (actual time=0.004..6.237 rows=124334 loops=1)
                          ->  Hash  (cost=15.48..15.48 rows=3 width=22) (actual time=0.013..0.014 rows=2 loops=1)
                                Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                ->  Bitmap Heap Scan on orders o  (cost=4.31..15.48 rows=3 width=22) (actual time=0.009..0.010 rows=2 loops=1)
                                      Recheck Cond: (user_id = 'c2885b45-dddd-4df3-b9b3-2cc012df727c'::uuid)
                                      Heap Blocks: exact=1
                                      ->  Bitmap Index Scan on orders_user_id_idx  (cost=0.00..4.31 rows=3 width=0) (actual time=0.005..0.005 rows=2 loops=1)
                                            Index Cond: (user_id = 'c2885b45-dddd-4df3-b9b3-2cc012df727c'::uuid)
                    ->  Hash  (cost=22.70..22.70 rows=1270 width=36) (actual time=0.016..0.016 rows=6 loops=1)
                          Buckets: 2048  Batches: 1  Memory Usage: 17kB
                          ->  Seq Scan on statuses s  (cost=0.00..22.70 rows=1270 width=36) (actual time=0.011..0.012 rows=6 loops=1)
Planning Time: 0.213 ms
Execution Time: 15.018 ms

Общее время выполнения скрипта: 14.973

Теперь мы не проверяем для каждой записи не является ли статус этого заказа последним по дате,
мы пронумеровываем записи для каждого заказа от самого последнего до начального и выбераем только первый.
*/



/* 15
План запроса до оптимизации:

Sort  (cost=4808.91..4810.74 rows=735 width=66) (actual time=52.709..52.727 rows=362 loops=1)
  Sort Key: (sum(oi.count)) DESC
  Sort Method: quicksort  Memory: 48kB
  InitPlan 1 (returns $0)
    ->  Aggregate  (cost=1501.65..1501.66 rows=1 width=32) (actual time=15.678..15.680 rows=1 loops=1)
          ->  HashAggregate  (cost=1480.72..1490.23 rows=761 width=40) (actual time=15.500..15.627 rows=761 loops=1)
                Group Key: oi_2.item
                Batches: 1  Memory Usage: 169kB
                ->  Seq Scan on order_items oi_2  (cost=0.00..1134.48 rows=69248 width=16) (actual time=0.006..3.693 rows=69248 loops=1)
  ->  HashAggregate  (cost=3263.06..3272.25 rows=735 width=66) (actual time=52.462..52.567 rows=362 loops=1)
        Group Key: d.name
        Batches: 1  Memory Usage: 105kB
        ->  Hash Join  (cost=1522.66..3147.65 rows=23083 width=42) (actual time=31.416..45.467 rows=35854 loops=1)
              Hash Cond: (oi.item = d.object_id)
              ->  Seq Scan on order_items oi  (cost=0.00..1134.48 rows=69248 width=16) (actual time=0.009..3.912 rows=69248 loops=1)
              ->  Hash  (cost=1519.48..1519.48 rows=254 width=50) (actual time=31.402..31.405 rows=366 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 39kB
                    ->  Hash Join  (cost=1497.85..1519.48 rows=254 width=50) (actual time=31.203..31.352 rows=366 loops=1)
                          Hash Cond: (d.object_id = dishes_sales.item)
                          ->  Seq Scan on dishes d  (cost=0.00..19.62 rows=762 width=42) (actual time=0.005..0.056 rows=762 loops=1)
                          ->  Hash  (cost=1494.67..1494.67 rows=254 width=8) (actual time=31.193..31.194 rows=366 loops=1)
                                Buckets: 1024  Batches: 1  Memory Usage: 23kB
                                ->  Subquery Scan on dishes_sales  (cost=1480.72..1494.67 rows=254 width=8) (actual time=30.931..31.147 rows=366 loops=1)
                                      ->  HashAggregate  (cost=1480.72..1492.13 rows=254 width=40) (actual time=30.931..31.120 rows=366 loops=1)
                                            Group Key: oi_1.item
                                            Filter: (sum(oi_1.count) > $0)
                                            Batches: 1  Memory Usage: 169kB
                                            Rows Removed by Filter: 395
                                            ->  Seq Scan on order_items oi_1  (cost=0.00..1134.48 rows=69248 width=16) (actual time=0.002..3.510 rows=69248 loops=1)
Planning Time: 0.204 ms
Execution Time: 52.816 ms

Общее время выполнения скрипта: 52.727

В данном запросе происходит 2 повторяющихся запроса (к одной таблице с одной и той же сигнатурой и т.д.):

SELECT item, SUM(count) AS total_sales
FROM order_items
GROUP BY item

Который мы можем переместить в CTE:
*/

WITH dishes_sales AS (
    SELECT item, SUM(count) AS total_sales
    FROM order_items
    GROUP BY item)
SELECT d.name, SUM(count) AS orders_quantity
FROM order_items AS oi
JOIN dishes AS d ON oi.item = d.object_id
WHERE oi.item IN (
    SELECT item
    FROM dishes_sales
    WHERE dishes_sales.total_sales > (
        SELECT SUM(total_sales) / COUNT(*)
        FROM dishes_sales))
GROUP BY d.name
ORDER BY orders_quantity DESC;

/*
Sort  (cost=3340.61..3342.45 rows=735 width=66) (actual time=36.803..36.820 rows=362 loops=1)
  Sort Key: (sum(oi.count)) DESC
  Sort Method: quicksort  Memory: 48kB
  CTE dishes_sales
    ->  HashAggregate  (cost=1480.72..1490.23 rows=761 width=40) (actual time=15.276..15.452 rows=761 loops=1)
          Group Key: order_items.item
          Batches: 1  Memory Usage: 169kB
          ->  Seq Scan on order_items  (cost=0.00..1134.48 rows=69248 width=16) (actual time=0.002..3.504 rows=69248 loops=1)
  InitPlan 2 (returns $1)
    ->  Aggregate  (cost=17.13..17.14 rows=1 width=32) (actual time=0.409..0.410 rows=1 loops=1)
          ->  CTE Scan on dishes_sales dishes_sales_1  (cost=0.00..15.22 rows=761 width=32) (actual time=0.001..0.322 rows=761 loops=1)
  ->  HashAggregate  (cost=1789.07..1798.25 rows=735 width=66) (actual time=36.632..36.702 rows=362 loops=1)
        Group Key: d.name
        Batches: 1  Memory Usage: 105kB
        ->  Hash Join  (cost=48.51..1673.50 rows=23113 width=42) (actual time=16.170..29.873 rows=35854 loops=1)
              Hash Cond: (oi.item = d.object_id)
              ->  Seq Scan on order_items oi  (cost=0.00..1134.48 rows=69248 width=16) (actual time=0.009..3.888 rows=69248 loops=1)
              ->  Hash  (cost=45.34..45.34 rows=254 width=50) (actual time=16.155..16.157 rows=366 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 39kB
                    ->  Hash Join  (cost=21.29..45.34 rows=254 width=50) (actual time=15.951..16.104 rows=366 loops=1)
                          Hash Cond: (d.object_id = dishes_sales.item)
                          ->  Seq Scan on dishes d  (cost=0.00..19.62 rows=762 width=42) (actual time=0.004..0.057 rows=762 loops=1)
                          ->  Hash  (cost=19.33..19.33 rows=157 width=8) (actual time=15.940..15.941 rows=366 loops=1)
                                Buckets: 1024  Batches: 1  Memory Usage: 23kB
                                ->  HashAggregate  (cost=17.76..19.33 rows=157 width=8) (actual time=15.871..15.901 rows=366 loops=1)
                                      Group Key: dishes_sales.item
                                      Batches: 1  Memory Usage: 61kB
                                      ->  CTE Scan on dishes_sales  (cost=0.00..17.12 rows=254 width=8) (actual time=15.691..15.804 rows=366 loops=1)
                                            Filter: (total_sales > $1)
                                            Rows Removed by Filter: 395
Planning Time: 0.228 ms
Execution Time: 36.899 ms

Общее время выполнения скрипта: 36.820

В данном плане добавилась скан происходит по CTE а не в Subquery.
*/