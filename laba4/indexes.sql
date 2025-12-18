USE warehouse_lab3;

-- 1. ИНДЕКСЫ ДЛЯ ПОИСКА ПО ДИАПАЗОНУ ЗНАЧЕНИЙ (числовые поля)

-- Запрос 1.1: Поиск приходных накладных за период дат
SELECT '=== Запрос 1.1: Поиск по диапазону дат (purchase_invoice.date) ===' AS '';
-- В MariaDB используем EXPLAIN вместо EXPLAIN ANALYZE
EXPLAIN
SELECT * FROM purchase_invoice 
WHERE date BETWEEN '2025-01-10' AND '2025-01-15'
ORDER BY date DESC;

-- Выполняем запрос для сравнения времени
SELECT 'Фактическое выполнение запроса:' AS '';
SELECT COUNT(*) as total_rows FROM purchase_invoice 
WHERE date BETWEEN '2025-01-10' AND '2025-01-15';

-- Создаем индекс для поля date
SELECT 'Создаем индекс idx_purchase_invoice_date_range...' AS '';
CREATE INDEX idx_purchase_invoice_date_range ON purchase_invoice(date);

-- Выполняем тот же запрос после создания индекса
SELECT 'После создания индекса:' AS '';
EXPLAIN
SELECT * FROM purchase_invoice 
WHERE date BETWEEN '2025-01-10' AND '2025-01-15'
ORDER BY date DESC;

-- 2. ИНДЕКСЫ ДЛЯ ФИЛЬТРАЦИИ И СОРТИРОВКИ ПО ТЕКСТОВЫМ ПОЛЯМ

-- Запрос 2.1: Фильтрация и сортировка по названию товара
SELECT '=== Запрос 2.1: Фильтрация и сортировка по product.name ===' AS '';
EXPLAIN
SELECT * FROM product 
WHERE name LIKE '%Laptop%' 
ORDER BY name;

SELECT 'Фактическое выполнение запроса:' AS '';
SELECT COUNT(*) as total_rows FROM product WHERE name LIKE '%Laptop%';

-- Создаем индекс для поля name
SELECT 'Создаем индекс idx_product_name...' AS '';
CREATE INDEX idx_product_name ON product(name);

-- Выполняем тот же запрос после создания индекса
SELECT 'После создания индекса:' AS '';
EXPLAIN
SELECT * FROM product 
WHERE name LIKE '%Laptop%' 
ORDER BY name;

-- 3. ИНДЕКСЫ ДЛЯ ПОИСКА ПО ПОДСТРОКЕ С LIKE (текстовые поля)

-- Запрос 3.1: Поиск клиентов по части имени
SELECT '=== Запрос 3.1: Поиск по подстроке customer_name в sales_invoice ===' AS '';
EXPLAIN
SELECT * FROM sales_invoice 
WHERE customer_name LIKE '%Company%';

SELECT 'Фактическое выполнение запроса:' AS '';
SELECT COUNT(*) as total_rows FROM sales_invoice WHERE customer_name LIKE '%Company%';

-- Создаем индекс для поля customer_name (для префиксного поиска)
SELECT 'Создаем индекс idx_sales_invoice_customer_name...' AS '';
CREATE INDEX idx_sales_invoice_customer_name ON sales_invoice(customer_name);

-- Выполняем тот же запрос после создания индекса
SELECT 'После создания индекса:' AS '';
EXPLAIN
SELECT * FROM sales_invoice 
WHERE customer_name LIKE '%Company%';

-- 4. ИНДЕКСЫ ДЛЯ ГРУППИРОВКИ И АГРЕГАЦИИ

-- Запрос 4.1: Группировка по категории товаров с подсчетом количества
SELECT '=== Запрос 4.1: Группировка по category_id в product ===' AS '';
EXPLAIN
SELECT category_id, COUNT(*) as product_count, AVG(default_price) as avg_price
FROM product 
GROUP BY category_id 
ORDER BY product_count DESC;

SELECT 'Фактическое выполнение запроса:' AS '';
SELECT category_id, COUNT(*) as product_count, AVG(default_price) as avg_price
FROM product 
GROUP BY category_id 
ORDER BY product_count DESC;

-- Создаем составной индекс для группировки и агрегации
SELECT 'Создаем индекс idx_product_category_grouping...' AS '';
CREATE INDEX idx_product_category_grouping ON product(category_id, default_price);

-- Выполняем тот же запрос после создания индекса
SELECT 'После создания индекса:' AS '';
EXPLAIN
SELECT category_id, COUNT(*) as product_count, AVG(default_price) as avg_price
FROM product 
GROUP BY category_id 
ORDER BY product_count DESC;

-- 5. ИНДЕКСЫ ДЛЯ СЛОЖНЫХ УСЛОВИЙ (комбинированные индексы)

-- Запрос 5.1: Поиск активных товаров с ценой в диапазоне
SELECT '=== Запрос 5.1: Фильтрация по is_active и default_price ===' AS '';
EXPLAIN
SELECT * FROM product 
WHERE is_active = TRUE 
  AND default_price BETWEEN 1000 AND 50000
ORDER BY default_price DESC;

SELECT 'Фактическое выполнение запроса:' AS '';
SELECT COUNT(*) as total_rows FROM product 
WHERE is_active = TRUE 
  AND default_price BETWEEN 1000 AND 50000;

-- Создаем составной индекс
SELECT 'Создаем индекс idx_product_active_price...' AS '';
CREATE INDEX idx_product_active_price ON product(is_active, default_price);

-- Выполняем тот же запрос после создания индекса
SELECT 'После создания индекса:' AS '';
EXPLAIN
SELECT * FROM product 
WHERE is_active = TRUE 
  AND default_price BETWEEN 1000 AND 50000
ORDER BY default_price DESC;

-- 6. ИНДЕКСЫ ДЛЯ СВЯЗЕЙ МЕЖДУ ТАБЛИЦАМИ (JOIN)

-- Запрос 6.1: JOIN между product и purchase_line
SELECT '=== Запрос 6.1: JOIN product и purchase_line ===' AS '';
EXPLAIN
SELECT p.name, p.sku, SUM(pl.qty) as total_purchased, AVG(pl.unit_price) as avg_purchase_price
FROM product p
JOIN purchase_line pl ON p.id = pl.product_id
GROUP BY p.id, p.name, p.sku
HAVING total_purchased > 0
ORDER BY total_purchased DESC;

SELECT 'Фактическое выполнение запроса (первые 5 строк):' AS '';
SELECT p.name, p.sku, SUM(pl.qty) as total_purchased, AVG(pl.unit_price) as avg_purchase_price
FROM product p
JOIN purchase_line pl ON p.id = pl.product_id
GROUP BY p.id, p.name, p.sku
HAVING total_purchased > 0
ORDER BY total_purchased DESC
LIMIT 5;

-- Индексы уже существуют (product.id - PRIMARY, purchase_line.product_id - idx_purchase_line_product)
-- Но можно создать покрывающий индекс для ускорения агрегации
SELECT 'Создаем индекс idx_purchase_line_product_qty_price...' AS '';
CREATE INDEX idx_purchase_line_product_qty_price ON purchase_line(product_id, qty, unit_price);

-- Выполняем тот же запрос после создания индекса
SELECT 'После создания индекса:' AS '';
EXPLAIN
SELECT p.name, p.sku, SUM(pl.qty) as total_purchased, AVG(pl.unit_price) as avg_purchase_price
FROM product p
JOIN purchase_line pl ON p.id = pl.product_id
GROUP BY p.id, p.name, p.sku
HAVING total_purchased > 0
ORDER BY total_purchased DESC;

-- 7. ДОПОЛНИТЕЛЬНЫЙ ПРИМЕР: Индекс для часто используемого WHERE + ORDER BY

-- Запрос 7.1: Поиск и сортировка по дате создания
SELECT '=== Запрос 7.1: Поиск по статусу и сортировка по дате ===' AS '';
EXPLAIN
SELECT * FROM sales_invoice 
WHERE status = 'CONFIRMED'
ORDER BY created_at DESC
LIMIT 10;

SELECT 'Создаем индекс для статуса и даты...' AS '';
CREATE INDEX idx_sales_invoice_status_created ON sales_invoice(status, created_at);

SELECT 'После создания индекса:' AS '';
EXPLAIN
SELECT * FROM sales_invoice 
WHERE status = 'CONFIRMED'
ORDER BY created_at DESC
LIMIT 10;

-- 8. АНАЛИЗ ИСПОЛЬЗОВАНИЯ ИНДЕКСОВ

SELECT '=== Анализ использования индексов ===' AS '';
SELECT 
    table_name,
    index_name,
    GROUP_CONCAT(column_name ORDER BY seq_in_index) as columns,
    index_type,
    CASE non_unique 
        WHEN 0 THEN 'UNIQUE'
        ELSE 'NON-UNIQUE' 
    END as uniqueness
FROM information_schema.statistics
WHERE table_schema = 'warehouse_lab3'
GROUP BY table_name, index_name, index_type, non_unique
ORDER BY table_name, index_name;

-- 9. СТАТИСТИКА ПО ИНДЕКСАМ

SELECT '=== Статистика по индексам ===' AS '';
SELECT 
    COUNT(*) as total_indexes,
    COUNT(DISTINCT table_name) as tables_with_indexes,
    SUM(CASE WHEN index_name = 'PRIMARY' THEN 1 ELSE 0 END) as primary_keys,
    SUM(CASE WHEN non_unique = 0 AND index_name != 'PRIMARY' THEN 1 ELSE 0 END) as unique_indexes,
    SUM(CASE WHEN index_type = 'BTREE' THEN 1 ELSE 0 END) as btree_indexes,
    'Индексы успешно созданы и протестированы!' as status
FROM information_schema.statistics 
WHERE table_schema = 'warehouse_lab3';

-- 10. СОВЕТЫ ПО ОПТИМИЗАЦИИ

SELECT '=== Советы по оптимизации индексов ===' AS '';
SELECT '1. Составные индексы должны учитывать порядок столбцов:' AS '';
SELECT '   - WHERE column1 = ? AND column2 = ? → индекс (column1, column2)' AS '';
SELECT '   - WHERE column1 = ? ORDER BY column2 → индекс (column1, column2)' AS '';
SELECT '' AS '';
SELECT '2. Индексы для LIKE:' AS '';
SELECT '   - LIKE "prefix%" → может использовать индекс' AS '';
SELECT '   - LIKE "%suffix" → НЕ использует индекс' AS '';
SELECT '   - LIKE "%infix%" → НЕ использует индекс' AS '';
SELECT '' AS '';
SELECT '3. Избыточные индексы:' AS '';
SELECT '   - (a,b,c) делает избыточными (a,b) и (a)' AS '';
SELECT '   - (a) НЕ делает избыточным (a,b,c)' AS '';
