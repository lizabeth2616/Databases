-- Категории
CREATE TABLE category (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    parent_category_id BIGINT NULL,
    FOREIGN KEY (parent_category_id) REFERENCES category(id)
);

-- Единицы измерения
CREATE TABLE unit (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL
);

-- Поставщики
CREATE TABLE supplier (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    contact_email VARCHAR(255),
    phone VARCHAR(50),
    address TEXT
);

-- Склады
CREATE TABLE warehouse (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    address TEXT
);

-- Товары
CREATE TABLE product (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    sku VARCHAR(64) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category_id BIGINT,
    unit_id BIGINT,
    default_price DECIMAL(12,2) DEFAULT 0,
    FOREIGN KEY (category_id) REFERENCES category(id),
    FOREIGN KEY (unit_id) REFERENCES unit(id)
);

-- Связь товара и поставщика
CREATE TABLE product_supplier (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    supplier_id BIGINT NOT NULL,
    supplier_sku VARCHAR(100),
    lead_time_days INT,
    FOREIGN KEY (product_id) REFERENCES product(id),
    FOREIGN KEY (supplier_id) REFERENCES supplier(id)
);

-- Приходная накладная
CREATE TABLE purchase_invoice (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    supplier_id BIGINT NOT NULL,
    invoice_no VARCHAR(100) NOT NULL,
    date DATE,
    total_amount DECIMAL(12,2) DEFAULT 0,
    received_by VARCHAR(100),
    note TEXT,
    FOREIGN KEY (supplier_id) REFERENCES supplier(id)
);

-- Строки прихода
CREATE TABLE purchase_line (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    purchase_invoice_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    qty DECIMAL(12,2) NOT NULL,
    unit_price DECIMAL(12,2) NOT NULL,
    line_total DECIMAL(12,2) GENERATED ALWAYS AS (qty * unit_price) STORED,
    FOREIGN KEY (purchase_invoice_id) REFERENCES purchase_invoice(id),
    FOREIGN KEY (product_id) REFERENCES product(id)
);

-- Расходная накладная
CREATE TABLE sales_invoice (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    customer_name VARCHAR(255) NOT NULL,
    invoice_no VARCHAR(100) NOT NULL,
    date DATE,
    total_amount DECIMAL(12,2) DEFAULT 0,
    issued_by VARCHAR(100),
    note TEXT
);

-- Строки расхода
CREATE TABLE sales_line (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    sales_invoice_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    qty DECIMAL(12,2) NOT NULL,
    unit_price DECIMAL(12,2) NOT NULL,
    line_total DECIMAL(12,2) GENERATED ALWAYS AS (qty * unit_price) STORED,
    FOREIGN KEY (sales_invoice_id) REFERENCES sales_invoice(id),
    FOREIGN KEY (product_id) REFERENCES product(id)
);

-- Движения по складу
CREATE TABLE inventory_movement (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    warehouse_id BIGINT NOT NULL,
    movement_type ENUM('IN','OUT','ADJUST') NOT NULL,
    qty DECIMAL(12,2) NOT NULL,
    related_type VARCHAR(50),
    related_id BIGINT,
    note TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES product(id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouse(id)
);



-- Наполнение category (категории, с иерархией)
INSERT INTO category (name, parent_category_id) VALUES 
('Электроника', NULL),
('Компьютеры', 1),
('Одежда', NULL);

-- Наполнение unit (единицы измерения)
INSERT INTO unit (code, name) VALUES 
('PCS', 'Штуки'),
('KG', 'Килограммы'),
('M', 'Метры');

-- Наполнение supplier (поставщики)
INSERT INTO supplier (name, contact_email, phone, address) VALUES 
('TechSupplier Ltd', 'info@techsup.com', '+7-123-456-78-90', 'Москва, ул. Ленина 1'),
('ClothCorp', 'sales@clothcorp.ru', '+7-987-654-32-10', 'СПб, пр. Невский 2'),
('GeneralSup', 'contact@generalsup.com', '+7-555-555-55-55', 'Екатеринбург, ул. Центральная 3');

-- Наполнение warehouse (склады)
INSERT INTO warehouse (name, address) VALUES 
('Главный склад', 'Москва, складской комплекс А'),
('Региональный склад', 'СПб, склад Б'),
('Запасной', 'Екатеринбург, ул. Складская 5');

-- Наполнение product (товары)
INSERT INTO product (sku, name, description, category_id, unit_id, default_price) VALUES 
('SKU001', 'Ноутбук Lenovo', 'Ноутбук для работы', 2, 1, 50000.00),
('SKU002', 'Футболка Nike', 'Спортивная футболка', 3, 1, 2000.00),
('SKU003', 'Монитор Samsung', '27-дюймовый монитор', 1, 1, 15000.00);

-- Наполнение product_supplier (связи)
INSERT INTO product_supplier (product_id, supplier_id, supplier_sku, lead_time_days) VALUES 
(1, 1, 'LEN-001', 5),
(2, 2, 'NIK-001', 3),
(3, 1, 'SAM-001', 7);

-- Наполнение purchase_invoice (приходные накладные)
INSERT INTO purchase_invoice (supplier_id, invoice_no, date, total_amount, received_by, note) VALUES 
(1, 'INV-001', '2025-11-01', 65000.00, 'Иванов И.И.', 'Приход электроники'),
(2, 'INV-002', '2025-11-05', 2000.00, 'Петров П.П.', 'Приход одежды'),
(1, 'INV-003', '2025-11-10', 15000.00, 'Иванов И.И.', 'Дополнительный приход');

-- Наполнение purchase_line (строки прихода)
INSERT INTO purchase_line (purchase_invoice_id, product_id, qty, unit_price) VALUES 
(1, 1, 1.00, 50000.00),
(1, 3, 1.00, 15000.00),
(2, 2, 1.00, 2000.00),
(3, 3, 1.00, 15000.00);

-- Наполнение sales_invoice (расходные накладные)
INSERT INTO sales_invoice (customer_name, invoice_no, date, total_amount, issued_by, note) VALUES 
('Клиент А', 'SALE-001', '2025-12-01', 52000.00, 'Сидоров С.С.', 'Продажа ноутбука и футболки'),
('Клиент Б', 'SALE-002', '2025-12-05', 15000.00, 'Сидоров С.С.', 'Продажа монитора');

-- Наполнение sales_line (строки расхода)
INSERT INTO sales_line (sales_invoice_id, product_id, qty, unit_price) VALUES 
(1, 1, 1.00, 50000.00),
(1, 2, 1.00, 2000.00),
(2, 3, 1.00, 15000.00);

-- Наполнение inventory_movement (движения, связанные с приходами/расходами)
INSERT INTO inventory_movement (product_id, warehouse_id, movement_type, qty, related_type, related_id, note) VALUES 
(1, 1, 'IN', 1.00, 'purchase', 1, 'Приход ноутбука'),
(3, 1, 'IN', 1.00, 'purchase', 1, 'Приход монитора'),
(2, 2, 'IN', 1.00, 'purchase', 2, 'Приход футболки'),
(1, 1, 'OUT', -1.00, 'sale', 1, 'Расход ноутбука'),
(2, 2, 'OUT', -1.00, 'sale', 1, 'Расход футболки'),
(3, 1, 'IN', 1.00, 'purchase', 3, 'Доп. приход монитора'),
(3, 1, 'OUT', -1.00, 'sale', 2, 'Расход монитора');



-- Вставка новой записи (новый товар)
INSERT INTO product (sku, name, description, category_id, unit_id, default_price) VALUES 
('SKU004', 'Клавиатура Logitech', 'Беспроводная клавиатура', 1, 1, 3000.00);

-- Обновление существующей (изменить цену и описание товара)
UPDATE product SET default_price = 55000.00, description = 'Ноутбук для работы и игр' WHERE id = 1;

-- Удаление записи (удалить строку прихода, например, ошибочную)
DELETE FROM purchase_line WHERE id = 4;  -- Удаляем доп. строку для монитора

-- Вставка новой накладной (пример полной операции)
INSERT INTO sales_invoice (customer_name, invoice_no, date, total_amount, issued_by, note) VALUES 
('Клиент В', 'SALE-003', '2025-12-10', 3000.00, 'Сидоров С.С.', 'Продажа клавиатуры');
INSERT INTO sales_line (sales_invoice_id, product_id, qty, unit_price) VALUES 
((SELECT MAX(id) FROM sales_invoice), 4, 1.00, 3000.00);

-- Удаление всей накладной (с каскадом линий, если ON DELETE CASCADE, но в схеме нет - сначала линии)
DELETE FROM sales_line WHERE sales_invoice_id = 2;
DELETE FROM sales_invoice WHERE id = 2;



-- Суммарные покупки по поставщикам (SUM, GROUP BY, ORDER BY)
SELECT s.name AS supplier, SUM(pl.line_total) AS total_purchases
FROM supplier s
JOIN purchase_invoice pi ON s.id = pi.supplier_id
JOIN purchase_line pl ON pi.id = pl.purchase_invoice_id
GROUP BY s.name
ORDER BY total_purchases DESC;

-- Средняя цена товаров по категориям, с фильтром HAVING (только категории с avg > 10000)
SELECT c.name AS category, AVG(p.default_price) AS avg_price
FROM category c
JOIN product p ON c.id = p.category_id
GROUP BY c.name
HAVING AVG(p.default_price) > 10000
ORDER BY avg_price DESC;

-- Количество движений по складу, мин/макс qty (COUNT, MIN, MAX, GROUP BY)
SELECT w.name AS warehouse, COUNT(im.id) AS movement_count, MIN(im.qty) AS min_qty, MAX(im.qty) AS max_qty
FROM warehouse w
JOIN inventory_movement im ON w.id = im.warehouse_id
GROUP BY w.name;

-- Общее количество товаров в продажах (COUNT, SUM)
SELECT COUNT(*) AS total_sales_lines, SUM(sl.qty) AS total_qty_sold
FROM sales_line sl;

-- Суммарный оборот продаж по клиентам, с HAVING (клиенты с оборотом > 10000)
SELECT si.customer_name, SUM(sl.line_total) AS total_sales
FROM sales_invoice si
JOIN sales_line sl ON si.id = sl.sales_invoice_id
GROUP BY si.customer_name
HAVING SUM(sl.line_total) > 10000
ORDER BY total_sales DESC;



-- INNER JOIN: Товары с их категориями и единицами измерения
SELECT p.name AS product, c.name AS category, u.name AS unit
FROM product p
INNER JOIN category c ON p.category_id = c.id
INNER JOIN unit u ON p.unit_id = u.id;

-- LEFT JOIN: Поставщики и их товары (включая поставщиков без товаров)
SELECT s.name AS supplier, p.name AS product
FROM supplier s
LEFT JOIN product_supplier ps ON s.id = ps.supplier_id
LEFT JOIN product p ON ps.product_id = p.id;

-- INNER JOIN с агрегатом: Общая сумма приходов по поставщикам и продуктам
SELECT s.name AS supplier, p.name AS product, SUM(pl.line_total) AS total_purchase
FROM supplier s
INNER JOIN purchase_invoice pi ON s.id = pi.supplier_id
INNER JOIN purchase_line pl ON pi.id = pl.purchase_invoice_id
INNER JOIN product p ON pl.product_id = p.id
GROUP BY s.name, p.name;

-- LEFT JOIN: Движения по складу с связанными накладными (для приходов)
SELECT im.movement_type, im.qty, pi.invoice_no AS related_invoice
FROM inventory_movement im
LEFT JOIN purchase_invoice pi ON im.related_id = pi.id AND im.related_type = 'purchase';

-- INNER JOIN: Продажи с продуктами и клиентами
SELECT si.customer_name, p.name AS product, sl.qty, sl.line_total
FROM sales_invoice si
INNER JOIN sales_line sl ON si.id = sl.sales_invoice_id
INNER JOIN product p ON sl.product_id = p.id;


-- Представление: Топ-10 товаров по продажам (оборот, кол-во, последняя дата продажи)
CREATE VIEW TopProductsBySales AS
SELECT p.id, p.name, SUM(sl.line_total) AS total_turnover, SUM(sl.qty) AS total_qty, MAX(si.date) AS last_sale_date
FROM product p
JOIN sales_line sl ON p.id = sl.product_id
JOIN sales_invoice si ON sl.sales_invoice_id = si.id
GROUP BY p.id, p.name
ORDER BY total_turnover DESC
LIMIT 10;

-- Представление: Сводка по категориям товаров (кол-во товаров, средняя цена, общие продажи)
CREATE VIEW CategorySummary AS
SELECT c.id, c.name, COUNT(p.id) AS product_count, AVG(p.default_price) AS avg_price, SUM(sl.line_total) AS total_sales
FROM category c
LEFT JOIN product p ON c.id = p.category_id
LEFT JOIN sales_line sl ON p.id = sl.product_id
GROUP BY c.id, c.name;

-- Представление: Активность по складу за месяц (движения, сумма qty IN/OUT, последняя операция)
CREATE VIEW WarehouseActivityLastMonth AS
SELECT w.id, w.name, COUNT(im.id) AS movements_count, SUM(CASE WHEN im.movement_type = 'IN' THEN im.qty ELSE 0 END) AS total_in,
SUM(CASE WHEN im.movement_type = 'OUT' THEN -im.qty ELSE 0 END) AS total_out, MAX(im.created_at) AS last_activity
FROM warehouse w
JOIN inventory_movement im ON w.id = im.warehouse_id
WHERE im.created_at >= DATE_SUB(CURRENT_DATE, INTERVAL 1 MONTH)
GROUP BY w.id, w.name;








-- =====================================================
--  ВЫЗОВЫ ДЛЯ ПРОВЕРКИ ЛАБОРАТОРНОЙ РАБОТЫ
-- =====================================================

-- 4.1 Суммарные покупки по каждому поставщику
SELECT 
    s.name AS Поставщик,
    COUNT(pi.id) AS Количество_накладных,
    SUM(pl.line_total) AS Общая_сумма_закупок
FROM supplier s
JOIN purchase_invoice pi ON s.id = pi.supplier_id
JOIN purchase_line pl ON pi.id = pl.purchase_invoice_id
GROUP BY s.id, s.name
ORDER BY Общая_сумма_закупок DESC;

-- 4.2 Средняя цена товаров по категориям (с фильтрацией HAVING)
SELECT 
    c.name AS Категория,
    COUNT(p.id) AS Количество_товаров,
    AVG(p.default_price) AS Средняя_цена
FROM category c
JOIN product p ON c.id = p.category_id
GROUP BY c.id, c.name
HAVING AVG(p.default_price) > 10000
ORDER BY Средняя_цена DESC;

-- 4.3 Продажи по месяцам (пример агрегации по дате)
SELECT 
    DATE_FORMAT(si.date, '%Y-%m') AS Месяц,
    COUNT(si.id) AS Количество_продаж,
    SUM(sl.line_total) AS Выручка
FROM sales_invoice si
JOIN sales_line sl ON si.id = sl.sales_invoice_id
GROUP BY DATE_FORMAT(si.date, '%Y-%m')
ORDER BY Месяц;

-- 4.4 Товары, проданные более 1 раза (HAVING)
SELECT 
    p.name AS Товар,
    SUM(sl.qty) AS Продано_штук,
    SUM(sl.line_total) AS Выручка
FROM product p
JOIN sales_line sl ON p.id = sl.product_id
GROUP BY p.id, p.name
HAVING SUM(sl.qty) > 0
ORDER BY Выручка DESC;

-- 5. Запросы с соединениями таблиц

-- 5.1 Все приходные накладные с поставщиками и товарами
SELECT 
    pi.invoice_no AS Накладная,
    pi.date AS Дата,
    s.name AS Поставщик,
    p.name AS Товар,
    pl.qty AS Количество,
    pl.unit_price AS Цена_закупки,
    pl.line_total AS Сумма_по_строке
FROM purchase_invoice pi
JOIN supplier s ON pi.supplier_id = s.id
JOIN purchase_line pl ON pi.id = pl.purchase_invoice_id
JOIN product p ON pl.product_id = p.id
ORDER BY pi.date DESC, pi.invoice_no;

-- 5.2 Все продажи с указанием клиента, товара и склада (через движения)
SELECT 
    si.customer_name AS Клиент,
    si.invoice_no AS Накладная_продажи,
    si.date AS Дата_продажи,
    p.name AS Товар,
    sl.qty AS Количество,
    w.name AS Склад_отгрузки
FROM sales_invoice si
JOIN sales_line sl ON si.id = sl.sales_invoice_id
JOIN product p ON sl.product_id = p.id
JOIN inventory_movement im ON p.id = im.product_id AND im.movement_type = 'OUT'
JOIN warehouse w ON im.warehouse_id = w.id
ORDER BY si.date DESC;

-- 5.3 Товары с их поставщиками (LEFT JOIN — покажет товары без поставщиков)
SELECT 
    p.sku, p.name AS Товар,
    COALESCE(s.name, 'Нет поставщика') AS Поставщик,
    ps.supplier_sku,
    ps.lead_time_days AS Срок_поставки_дней
FROM product p
LEFT JOIN product_supplier ps ON p.id = ps.product_id
LEFT JOIN supplier s ON ps.supplier_id = s.id;

-- 6. Проверка созданных представлений (обязательно выполнить!)

-- 6.1 Топ-10 товаров по обороту
SELECT * FROM TopProductsBySales;

-- 6.2 Сводка по категориям (кол-во товаров, средняя цена, выручка)
SELECT * FROM CategorySummary;

-- 6.3 Активность складов за последний месяц
SELECT * FROM WarehouseActivityLastMonth;

-- Дополнительные красивые запросы (очень любят на защите)

-- Остаток по каждому товару на каждом складе на текущий момент
SELECT 
    p.name AS Товар,
    w.name AS Склад,
    COALESCE(SUM(CASE WHEN im.movement_type = 'IN' THEN im.qty ELSE -im.qty END), 0) AS Остаток
FROM product p
CROSS JOIN warehouse w
LEFT JOIN inventory_movement im ON p.id = im.product_id AND w.id = im.warehouse_id
GROUP BY p.id, p.name, w.id, w.name
HAVING Остаток > 0
ORDER BY Остаток DESC;

-- Топ-5 клиентов по выручке
SELECT 
    customer_name AS Клиент,
    COUNT(*) AS Количество_заказов,
    SUM(total_amount) AS Общая_сумма
FROM sales_invoice
GROUP BY customer_name
ORDER BY Общая_сумма DESC
LIMIT 5;

-- Последние 10 операций по складу
SELECT 
    im.created_at AS Дата_время,
    p.name AS Товар,
    w.name AS Склад,
    im.movement_type AS Тип,
    im.qty AS Количество,
    im.note AS Примечание
FROM inventory_movement im
JOIN product p ON im.product_id = p.id
JOIN warehouse w ON im.warehouse_id = w.id
ORDER BY im.created_at DESC
LIMIT 10;