-- Задание 1.
CREATE OR REPLACE PROCEDURE update_employees_rate (
    IN p_employee_rate_changes json
)
LANGUAGE plpgsql
AS $$
DECLARE
    _e record;
BEGIN
    FOR _e IN
        SELECT (e->>'employee_id')::uuid AS employee_id, (e->>'rate_change')::integer AS rate_change
        FROM json_array_elements(p_employee_rate_changes) AS e
    LOOP
        UPDATE employees
        SET rate = CASE
            WHEN (rate * ((100 + _e.rate_change) / 100.0)) < 500 THEN 500
            ELSE rate * ((100 + _e.rate_change) / 100.0) END
        WHERE id = _e.employee_id;
    END LOOP;
END;
$$;


-- Задание 2.
CREATE OR REPLACE PROCEDURE indexing_salary (
    IN p_salary_index integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    _avg_rate numeric;
BEGIN
    SELECT AVG(rate)
    INTO _avg_rate
    FROM employees;

    UPDATE employees
    SET rate = CASE
        WHEN rate < _avg_rate THEN rate * (100 + p_salary_index + 2) / 100.0
        ELSE rate * (100 + p_salary_index) / 100.0
    END;
END;
$$;


-- Задание 3.
CREATE OR REPLACE PROCEDURE close_project (
    IN p_project_id uuid
)
LANGUAGE plpgsql
AS $$
DECLARE
    _estimated_time integer;
    _is_active boolean;
    _work_hours_sum integer;
    _project_employees_count integer;
    _project_end_date date;
    _bonus_time integer;
BEGIN
    SELECT estimated_time, is_active
    INTO STRICT _estimated_time, _is_active
    FROM projects
    WHERE id = p_project_id;

    IF NOT _is_active THEN
        RAISE EXCEPTION 'Project: ''%'' is not active.', p_project_id;
    END IF;

    UPDATE projects
    SET is_active = false
    WHERE id = p_project_id;

    SELECT sum(work_hours), count(distinct employee_id), max(work_date)
    INTO _work_hours_sum, _project_employees_count, _project_end_date
    FROM logs
    WHERE project_id = p_project_id;

    IF _estimated_time IS NULL OR _estimated_time <= _work_hours_sum THEN
        RETURN;
    END IF;

    _bonus_time := FLOOR(((_estimated_time - _work_hours_sum) * 0.75) / _project_employees_count)::integer;

    IF _bonus_time = 0 THEN
        RETURN;
    END IF;

    IF _bonus_time > 16 THEN
        _bonus_time = 16;
    END IF;

    INSERT INTO logs (employee_id, project_id, work_date, work_hours, required_review, is_paid)
    SELECT
        l.employee_id AS employee_id,
        p_project_id AS project_id,
        _project_end_date::date AS work_date,
        _bonus_time AS work_hours,
        false AS required_review,
        false AS is_paid
    FROM logs AS l
    WHERE l.project_id = p_project_id
    GROUP BY l.employee_id;
END;
$$;


-- Задание 4.
CREATE OR REPLACE PROCEDURE log_work (
    IN p_employee_id uuid,
    IN p_project_id uuid,
    IN p_work_date date,
    IN p_work_hours integer
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT (
        SELECT is_active
        FROM projects
        WHERE id = p_project_id
        LIMIT 1
    ) THEN
        RAISE EXCEPTION 'Project closed.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM employees
        WHERE id = p_employee_id
    ) = 0 THEN
        RAISE EXCEPTION 'Employee ''%'' not found.', p_employee_id;
    END IF;

    IF p_work_hours < 1 OR p_work_hours > 24 THEN
        RAISE WARNING 'Время работы (%) находилось вне допустимого диапазона: от 1 до 24 часов.', p_work_hours;
        RETURN;
    END IF;

    INSERT INTO logs (employee_id, project_id, work_date, work_hours, required_review, is_paid)
    VALUES (
        p_employee_id,
        p_project_id,
        p_work_date,
        p_work_hours,
        p_work_hours > 16 OR p_work_date > current_date OR (p_work_date < (current_date - '7 days'::interval)),
        false
    );
END;
$$;


-- Задание 5.
CREATE TABLE IF NOT EXISTS employee_rate_history (
    id SERIAL PRIMARY KEY,
    employee_id uuid NOT NULL REFERENCES employees (id),
    rate integer NOT NULL,
    from_date date NOT NULL DEFAULT (current_date)
);

INSERT INTO employee_rate_history (employee_id, rate, from_date)
SELECT DISTINCT
    id AS employee_id,
    rate AS rate,
    '2020-12-26'::date AS from_date
FROM employees;

CREATE OR REPLACE FUNCTION save_employee_rate_history()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.rate IS DISTINCT FROM NEW.rate THEN
        INSERT INTO employee_rate_history (employee_id, rate)
        VALUES (NEW.id, NEW.rate);
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER change_employee_rate
AFTER INSERT OR UPDATE ON employees
FOR EACH ROW
EXECUTE FUNCTION save_employee_rate_history();


-- Задание 6*.
CREATE OR REPLACE FUNCTION best_project_workers (
    IN p_project_id uuid
)
RETURNS TABLE (
    employee text,
    work_hours integer
)
LANGUAGE sql
AS $$
    SELECT e.name AS employee, SUM(l.work_hours) AS work_hours
    FROM logs AS l
    JOIN employees AS e ON l.employee_id = e.id
    WHERE project_id = p_project_id
    GROUP BY e.name
    ORDER BY work_hours DESC, COUNT(DISTINCT work_date) DESC
    LIMIT 3
$$;


-- Задание 7*.
CREATE OR REPLACE FUNCTION calculate_month_salary (
    IN month_start date,
    IN month_end date
)
RETURNS TABLE (
    id uuid,
    employee text,
    worked_hours bigint,
    salary numeric
)
LANGUAGE plpgsql
AS $$
DECLARE
    _e record;
BEGIN
    FOR _e IN
        SELECT DISTINCT e.name, l.required_review
        FROM logs AS l
        JOIN employees AS e ON l.employee_id = e.id
        WHERE
            NOT l.is_paid
            AND l.work_date >= month_start AND l.work_date <= month_end
            AND l.required_review
    LOOP
        RAISE NOTICE 'Warning! Employee % hours must be reviewed!', _e.name;
    END LOOP;

    RETURN QUERY
    SELECT
        e.id,
        e.name,
        SUM(l.work_hours) AS worked_hours,
        CASE
            WHEN SUM(l.work_hours) > 160 THEN (160 * e.rate) + ((SUM(l.work_hours) - 160) * e.rate * 1.25)
            ELSE SUM(l.work_hours) * e.rate
        END AS salary
    FROM employees AS e
    JOIN logs AS l ON e.id = l.employee_id
    WHERE
        NOT l.is_paid
        AND l.work_date >= month_start AND l.work_date <= month_end
        AND NOT l.required_review
    GROUP BY e.id, e.name, e.rate;
END;
$$;
