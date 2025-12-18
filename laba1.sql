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