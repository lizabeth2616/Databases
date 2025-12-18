-- Удаляем базу данных, если существует
DROP DATABASE IF EXISTS warehouse_lab3;

-- Создаем базу данных
CREATE DATABASE warehouse_lab3 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE warehouse_lab3;

-- Таблица категорий товаров (иерархическая)
CREATE TABLE category (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    parent_category_id BIGINT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (parent_category_id) REFERENCES category(id) ON DELETE SET NULL,
    INDEX idx_parent_category (parent_category_id)
) ENGINE=InnoDB;

-- Единицы измерения
CREATE TABLE unit (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    INDEX idx_code (code)
) ENGINE=InnoDB;

-- Поставщики
CREATE TABLE supplier (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    contact_email VARCHAR(255),
    phone VARCHAR(50),
    address TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_supplier_active (is_active)
) ENGINE=InnoDB;

-- Склады
CREATE TABLE warehouse (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    address TEXT,
    capacity INT COMMENT 'Вместимость в паллетах',
    is_active BOOLEAN DEFAULT TRUE,
    INDEX idx_warehouse_active (is_active)
) ENGINE=InnoDB;

-- Товары
CREATE TABLE product (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    sku VARCHAR(64) UNIQUE NOT NULL COMMENT 'Артикул',
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category_id BIGINT,
    unit_id BIGINT,
    default_price DECIMAL(12, 2) DEFAULT 0.00,
    min_stock_level DECIMAL(12, 2) DEFAULT 0.00 COMMENT 'Минимальный остаток',
    max_stock_level DECIMAL(12, 2) COMMENT 'Максимальный остаток',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (category_id) REFERENCES category(id) ON DELETE SET NULL,
    FOREIGN KEY (unit_id) REFERENCES unit(id) ON DELETE SET NULL,
    INDEX idx_product_sku (sku),
    INDEX idx_product_category (category_id),
    INDEX idx_product_active (is_active)
) ENGINE=InnoDB;

-- Связь товаров с поставщиками
CREATE TABLE product_supplier (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    supplier_id BIGINT NOT NULL,
    supplier_sku VARCHAR(100) COMMENT 'Артикул у поставщика',
    lead_time_days INT COMMENT 'Срок поставки в днях',
    last_purchase_price DECIMAL(12, 2),
    is_preferred BOOLEAN DEFAULT FALSE,
    UNIQUE KEY unique_product_supplier (product_id, supplier_id),
    FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE,
    FOREIGN KEY (supplier_id) REFERENCES supplier(id) ON DELETE CASCADE,
    INDEX idx_product_supplier_product (product_id),
    INDEX idx_product_supplier_supplier (supplier_id)
) ENGINE=InnoDB;

-- Приходные накладные
CREATE TABLE purchase_invoice (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    supplier_id BIGINT NOT NULL,
    invoice_no VARCHAR(100) NOT NULL UNIQUE,
    date DATE NOT NULL,
    total_amount DECIMAL(12, 2) DEFAULT 0.00,
    received_by VARCHAR(100),
    note TEXT,
    status ENUM('DRAFT', 'CONFIRMED', 'CANCELLED') DEFAULT 'DRAFT',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (supplier_id) REFERENCES supplier(id) ON DELETE RESTRICT,
    INDEX idx_purchase_invoice_supplier (supplier_id),
    INDEX idx_purchase_invoice_date (date),
    INDEX idx_purchase_invoice_status (status)
) ENGINE=InnoDB;

-- Строки приходных накладных
CREATE TABLE purchase_line (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    purchase_invoice_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    qty DECIMAL(12, 2) NOT NULL,
    unit_price DECIMAL(12, 2) NOT NULL,
    line_total DECIMAL(12, 2) AS (qty * unit_price) STORED,
    warehouse_id BIGINT NOT NULL,
    note TEXT,
    FOREIGN KEY (purchase_invoice_id) REFERENCES purchase_invoice(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE RESTRICT,
    FOREIGN KEY (warehouse_id) REFERENCES warehouse(id) ON DELETE RESTRICT,
    INDEX idx_purchase_line_invoice (purchase_invoice_id),
    INDEX idx_purchase_line_product (product_id),
    INDEX idx_purchase_line_warehouse (warehouse_id)
) ENGINE=InnoDB;

-- Расходные накладные
CREATE TABLE sales_invoice (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    customer_name VARCHAR(255) NOT NULL,
    invoice_no VARCHAR(100) NOT NULL UNIQUE,
    date DATE NOT NULL,
    total_amount DECIMAL(12, 2) DEFAULT 0.00,
    issued_by VARCHAR(100),
    note TEXT,
    status ENUM('DRAFT', 'CONFIRMED', 'SHIPPED', 'CANCELLED') DEFAULT 'DRAFT',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_sales_invoice_customer (customer_name),
    INDEX idx_sales_invoice_date (date),
    INDEX idx_sales_invoice_status (status)
) ENGINE=InnoDB;

-- Строки расходных накладных
CREATE TABLE sales_line (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    sales_invoice_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    qty DECIMAL(12, 2) NOT NULL,
    unit_price DECIMAL(12, 2) NOT NULL,
    line_total DECIMAL(12, 2) AS (qty * unit_price) STORED,
    warehouse_id BIGINT NOT NULL,
    note TEXT,
    FOREIGN KEY (sales_invoice_id) REFERENCES sales_invoice(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE RESTRICT,
    FOREIGN KEY (warehouse_id) REFERENCES warehouse(id) ON DELETE RESTRICT,
    INDEX idx_sales_line_invoice (sales_invoice_id),
    INDEX idx_sales_line_product (product_id),
    INDEX idx_sales_line_warehouse (warehouse_id)
) ENGINE=InnoDB;

-- Движение товаров (инвентаризация)
CREATE TABLE inventory_movement (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    warehouse_id BIGINT NOT NULL,
    movement_type ENUM('IN', 'OUT', 'ADJUST') NOT NULL,
    qty DECIMAL(12, 2) NOT NULL,
    related_type VARCHAR(50) COMMENT 'purchase, sale, adjustment',
    related_id BIGINT,
    note TEXT,
    created_by VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE,
    FOREIGN KEY (warehouse_id) REFERENCES warehouse(id) ON DELETE CASCADE,
    INDEX idx_inventory_product_warehouse (product_id, warehouse_id),
    INDEX idx_inventory_created_at (created_at),
    INDEX idx_inventory_movement_type (movement_type),
    INDEX idx_inventory_related (related_type, related_id)
) ENGINE=InnoDB;

-- Таблица для аудита изменений цен
CREATE TABLE price_audit_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    old_price DECIMAL(12, 2),
    new_price DECIMAL(12, 2),
    change_percent DECIMAL(5, 2),
    changed_by VARCHAR(100),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reason TEXT,
    FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE,
    INDEX idx_price_audit_product (product_id),
    INDEX idx_price_audit_changed_at (changed_at)
) ENGINE=InnoDB;

-- Таблица для отслеживания низких остатков
CREATE TABLE low_stock_alerts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    warehouse_id BIGINT NOT NULL,
    current_stock DECIMAL(12, 2),
    min_stock_level DECIMAL(12, 2),
    alert_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP NULL,
    resolved_by VARCHAR(100),
    FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE,
    FOREIGN KEY (warehouse_id) REFERENCES warehouse(id) ON DELETE CASCADE,
    INDEX idx_low_stock_product_warehouse (product_id, warehouse_id),
    INDEX idx_low_stock_alert_date (alert_date),
    INDEX idx_low_stock_resolved (is_resolved)
) ENGINE=InnoDB;

-- Вставка тестовых данных
-- Категории
INSERT INTO category (name, parent_category_id) VALUES
('Electronics', NULL),
('Computers and Components', 1),
('Peripherals', 1),
('Clothing', NULL),
('Mens Clothing', 4),
('Womens Clothing', 4);

-- Единицы измерения
INSERT INTO unit (code, name) VALUES
('PCS', 'Pieces'),
('KG', 'Kilograms'),
('M', 'Meters'),
('SET', 'Sets'),
('PAIR', 'Pairs');

-- Поставщики
INSERT INTO supplier (name, contact_email, phone, address) VALUES
('TechSupply Ltd', 'info@techsupply.com', '+1-111-222-3333', '123 Tech Street, City'),
('Clothing Corp', 'sales@clothing.com', '+1-444-555-6666', '456 Fashion Ave, City'),
('Office Supplies Inc', 'contact@office.com', '+1-777-888-9999', '789 Office Blvd, City');

-- Склады
INSERT INTO warehouse (name, address, capacity) VALUES
('Main Warehouse', '123 Warehouse Road, City', 1000),
('Secondary Warehouse', '456 Storage Street, City', 500),
('Regional Warehouse', '789 Distribution Ave, City', 800);

-- Товары
INSERT INTO product (sku, name, description, category_id, unit_id, default_price, min_stock_level, max_stock_level) VALUES
('NB-LEN-001', 'Laptop Lenovo IdeaPad', '15.6 inch, Intel Core i5, 8GB RAM, 512GB SSD', 2, 1, 55000.00, 3, 20),
('NB-ASUS-002', 'Laptop Asus VivoBook', '14 inch, AMD Ryzen 5, 16GB RAM, 1TB SSD', 2, 1, 65000.00, 2, 15),
('MON-SAMS-001', 'Monitor Samsung 24"', 'Full HD, IPS, 75Hz, HDMI/DP', 3, 1, 15000.00, 5, 30),
('MON-LG-001', 'Monitor LG 27"', '2K, IPS, 144Hz, FreeSync', 3, 1, 25000.00, 3, 20),
('TSHIRT-M-001', 'T-Shirt Mens', '100% cotton, black, size M', 5, 1, 1200.00, 10, 100),
('TSHIRT-F-001', 'T-Shirt Womens', '100% cotton, white, size S', 6, 1, 1100.00, 10, 100),
('KB-LOGI-001', 'Keyboard Logitech', 'Mechanical keyboard, RGB backlight', 3, 1, 5000.00, 8, 50),
('MOUSE-RAZER-001', 'Mouse Razer DeathAdder', 'Gaming mouse, 16000 DPI, optical sensor', 3, 1, 4500.00, 10, 60);

-- Связи товаров с поставщиками
INSERT INTO product_supplier (product_id, supplier_id, supplier_sku, lead_time_days, last_purchase_price, is_preferred) VALUES
(1, 1, 'LEN-IPAD-15', 5, 52000.00, TRUE),
(2, 1, 'ASUS-VIVO-14', 7, 62000.00, TRUE),
(3, 1, 'SAMS-24FHD', 3, 14000.00, TRUE),
(4, 1, 'LG-27-2K', 4, 23000.00, TRUE),
(5, 2, 'TS-M-BLACK-M', 2, 1000.00, TRUE),
(6, 2, 'TS-F-WHITE-S', 2, 950.00, TRUE),
(7, 1, 'LOG-KB-MECH', 4, 4500.00, TRUE),
(8, 1, 'RAZER-DA', 5, 4000.00, TRUE);

-- Приходные накладные
INSERT INTO purchase_invoice (supplier_id, invoice_no, date, status, received_by) VALUES
(1, 'PUR-2025-001', '2025-01-10', 'CONFIRMED', 'John Smith'),
(1, 'PUR-2025-002', '2025-01-12', 'CONFIRMED', 'Jane Doe'),
(2, 'PUR-2025-003', '2025-01-15', 'CONFIRMED', 'Bob Johnson');

-- Строки приходных накладных
INSERT INTO purchase_line (purchase_invoice_id, product_id, qty, unit_price, warehouse_id) VALUES
(1, 1, 5, 52000.00, 1),
(1, 3, 10, 14000.00, 1),
(2, 2, 3, 62000.00, 1),
(2, 4, 5, 23000.00, 1),
(2, 7, 15, 4500.00, 2),
(2, 8, 20, 4000.00, 2),
(3, 5, 50, 1000.00, 1),
(3, 6, 40, 950.00, 1);

-- Движение товаров
INSERT INTO inventory_movement (product_id, warehouse_id, movement_type, qty, related_type, related_id, note) VALUES
(1, 1, 'IN', 5, 'purchase', 1, 'Purchase from invoice PUR-2025-001'),
(3, 1, 'IN', 10, 'purchase', 1, 'Purchase from invoice PUR-2025-001'),
(2, 1, 'IN', 3, 'purchase', 2, 'Purchase from invoice PUR-2025-002'),
(4, 1, 'IN', 5, 'purchase', 2, 'Purchase from invoice PUR-2025-002'),
(7, 2, 'IN', 15, 'purchase', 2, 'Purchase from invoice PUR-2025-002'),
(8, 2, 'IN', 20, 'purchase', 2, 'Purchase from invoice PUR-2025-002'),
(5, 1, 'IN', 50, 'purchase', 3, 'Purchase from invoice PUR-2025-003'),
(6, 1, 'IN', 40, 'purchase', 3, 'Purchase from invoice PUR-2025-003');

-- Расходные накладные
INSERT INTO sales_invoice (customer_name, invoice_no, date, status, issued_by) VALUES
('ABC Company', 'SALE-2025-001', '2025-01-20', 'CONFIRMED', 'Sales Manager'),
('XYZ Corp', 'SALE-2025-002', '2025-01-21', 'CONFIRMED', 'Sales Manager'),
('Retail Store', 'SALE-2025-003', '2025-01-22', 'CONFIRMED', 'Sales Person');

-- Теперь добавляем проверки и вывод информации (MariaDB-совместимый)
SELECT 'Database warehouse_lab3 created successfully with test data!' as message;

-- Проверка созданных таблиц
SELECT 
    COUNT(*) as tables_created, 
    'Tables created: category, unit, supplier, warehouse, product, product_supplier, purchase_invoice, purchase_line, sales_invoice, sales_line, inventory_movement, price_audit_log, low_stock_alerts' as table_list
FROM information_schema.tables 
WHERE table_schema = 'warehouse_lab3';

-- Проверка вставленных данных
SELECT 
    (SELECT COUNT(*) FROM category) as categories,
    (SELECT COUNT(*) FROM unit) as units,
    (SELECT COUNT(*) FROM supplier) as suppliers,
    (SELECT COUNT(*) FROM warehouse) as warehouses,
    (SELECT COUNT(*) FROM product) as products,
    (SELECT COUNT(*) FROM product_supplier) as product_suppliers,
    (SELECT COUNT(*) FROM purchase_invoice) as purchase_invoices,
    (SELECT COUNT(*) FROM purchase_line) as purchase_lines,
    (SELECT COUNT(*) FROM inventory_movement) as inventory_movements,
    (SELECT COUNT(*) FROM sales_invoice) as sales_invoices;

-- Общая статистика

SELECT 'Total test records inserted: ~49+' as summary;

SELECT 'Laboratory work completed successfully!' as status;


-- Дополнительная проверка: покажем некоторые данные
SELECT 
    'Sample data check - First 3 products:' as check_title,
    p.sku,
    p.name,
    c.name as category,
    u.name as unit,
    p.default_price
FROM product p
LEFT JOIN category c ON p.category_id = c.id
LEFT JOIN unit u ON p.unit_id = u.id
LIMIT 3;