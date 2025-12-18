USE warehouse_lab3;

-- Удаляем всё, чтобы можно было перезапускать
DROP FUNCTION IF EXISTS GetCurrentStock;
DROP FUNCTION IF EXISTS CheckProductAvailability;
DROP FUNCTION IF EXISTS GetWarehouseTotalValue;
DROP PROCEDURE IF EXISTS AddPurchaseLine;
DROP PROCEDURE IF EXISTS ProcessSale;
DROP PROCEDURE IF EXISTS AdjustInventory;
DROP PROCEDURE IF EXISTS GetProductStockReport;
DROP PROCEDURE IF EXISTS GetSupplierReport;
DROP PROCEDURE IF EXISTS ConfirmPurchaseInvoice;

DELIMITER $$

-- 1. Функция текущего остатка
CREATE FUNCTION GetCurrentStock(
    p_product_id BIGINT,
    p_warehouse_id BIGINT
) RETURNS DECIMAL(12, 2)
READS SQL DATA DETERMINISTIC
BEGIN
    DECLARE v_stock DECIMAL(12, 2) DEFAULT 0;
    DECLARE msg_text VARCHAR(500);

    IF NOT EXISTS (SELECT 1 FROM product WHERE id = p_product_id) THEN
        SET msg_text = 'Product not found';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM warehouse WHERE id = p_warehouse_id) THEN
        SET msg_text = 'Warehouse not found';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    SELECT COALESCE(SUM(
        CASE 
            WHEN movement_type = 'IN' THEN qty
            WHEN movement_type = 'OUT' THEN -qty
            WHEN movement_type = 'ADJUST' THEN qty
            ELSE 0
        END
    ), 0) INTO v_stock
    FROM inventory_movement
    WHERE product_id = p_product_id AND warehouse_id = p_warehouse_id;

    RETURN v_stock;
END$$

-- 2. Проверка доступности
CREATE FUNCTION CheckProductAvailability(
    p_product_id BIGINT,
    p_warehouse_id BIGINT,
    p_required_qty DECIMAL(12, 2)
) RETURNS BOOLEAN
READS SQL DATA DETERMINISTIC
BEGIN
    RETURN GetCurrentStock(p_product_id, p_warehouse_id) >= p_required_qty;
END$$

-- 3. Стоимость склада
CREATE FUNCTION GetWarehouseTotalValue(p_warehouse_id BIGINT)
RETURNS DECIMAL(12, 2)
READS SQL DATA DETERMINISTIC
BEGIN
    DECLARE v_total DECIMAL(12, 2) DEFAULT 0;
    DECLARE msg_text VARCHAR(500);

    IF NOT EXISTS (SELECT 1 FROM warehouse WHERE id = p_warehouse_id) THEN
        SET msg_text = 'Warehouse not found';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    SELECT COALESCE(SUM(GetCurrentStock(p.id, p_warehouse_id) * p.default_price), 0)
    INTO v_total
    FROM product p
    WHERE p.is_active = TRUE;

    RETURN v_total;
END$$

-- КЛЮЧЕВАЯ ПРОЦЕДУРА: ProcessSale
CREATE PROCEDURE ProcessSale(
    IN p_customer_name VARCHAR(255),
    IN p_invoice_no VARCHAR(100),
    IN p_product_id BIGINT,
    IN p_qty DECIMAL(12, 2),
    IN p_price DECIMAL(12, 2),
    IN p_warehouse_id BIGINT,
    IN p_issued_by VARCHAR(100),
    OUT p_sale_id BIGINT,
    OUT p_message VARCHAR(500)
)
BEGIN
    DECLARE v_current_stock DECIMAL(12, 2);
    DECLARE msg_text VARCHAR(500);
    DECLARE temp_msg VARCHAR(500);
    DECLARE v_product_exists BOOLEAN;
    DECLARE v_warehouse_exists BOOLEAN;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_sale_id = NULL;
        SET p_message = 'Error: transaction rolled back';
    END;

    -- Проверка количества и цены
    IF p_qty <= 0 THEN
        SET msg_text = 'Quantity must be greater than 0';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    IF p_price <= 0 THEN
        SET msg_text = 'Price must be greater than 0';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    -- Проверка товара
    SET v_product_exists = EXISTS (
        SELECT 1 FROM product 
        WHERE id = p_product_id AND is_active = TRUE
    );
    
    IF NOT v_product_exists THEN
        SET msg_text = 'Product not found or inactive';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    -- Проверка склада
    SET v_warehouse_exists = EXISTS (
        SELECT 1 FROM warehouse 
        WHERE id = p_warehouse_id AND is_active = TRUE
    );
    
    IF NOT v_warehouse_exists THEN
        SET msg_text = 'Warehouse not found or inactive';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    -- Проверка остатка
    SET v_current_stock = GetCurrentStock(p_product_id, p_warehouse_id);
    IF v_current_stock < p_qty THEN
        SET temp_msg = CONCAT('Insufficient stock. Available: ', v_current_stock, ', required: ', p_qty);
        SET msg_text = temp_msg;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    START TRANSACTION;

    -- Создаём накладную
    INSERT INTO sales_invoice (
        customer_name, invoice_no, date, total_amount, status, issued_by
    ) VALUES (
        p_customer_name, p_invoice_no, CURDATE(), p_qty * p_price, 'CONFIRMED', p_issued_by
    );
    SET p_sale_id = LAST_INSERT_ID();

    -- Строка продажи
    INSERT INTO sales_line (
        sales_invoice_id, product_id, qty, unit_price, warehouse_id
    ) VALUES (
        p_sale_id, p_product_id, p_qty, p_price, p_warehouse_id
    );

    -- Движение товара
    INSERT INTO inventory_movement (
        product_id, warehouse_id, movement_type, qty, related_type, related_id, note
    ) VALUES (
        p_product_id, p_warehouse_id, 'OUT', p_qty, 'sale', p_sale_id,
        'Sale processed by ProcessSale procedure'
    );

    COMMIT;

    SET temp_msg = CONCAT('Sale successful. Invoice ID: ', p_sale_id);
    SET p_message = temp_msg;
END$$

-- 4. Добавление строки закупки
CREATE PROCEDURE AddPurchaseLine(
    IN p_invoice_id BIGINT,
    IN p_product_id BIGINT,
    IN p_qty DECIMAL(12,2),
    IN p_price DECIMAL(12,2),
    IN p_warehouse_id BIGINT,
    OUT p_result_message VARCHAR(500)
)
BEGIN
    DECLARE v_invoice_status VARCHAR(20);
    DECLARE v_product_exists BOOLEAN;
    DECLARE v_warehouse_exists BOOLEAN;
    DECLARE msg_text VARCHAR(500);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_result_message = 'Error: transaction failed';
        ROLLBACK;
    END;

    -- Проверка существования накладной
    SELECT status INTO v_invoice_status
    FROM purchase_invoice
    WHERE id = p_invoice_id;

    IF v_invoice_status IS NULL THEN
        SET msg_text = 'Invoice not found';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    IF v_invoice_status != 'DRAFT' THEN
        SET msg_text = 'Cannot add lines to non-draft invoice';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    -- Проверка товара
    SET v_product_exists = EXISTS (
        SELECT 1 FROM product WHERE id = p_product_id AND is_active = TRUE
    );
    
    IF NOT v_product_exists THEN
        SET msg_text = 'Product not found or inactive';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    -- Проверка склада
    SET v_warehouse_exists = EXISTS (
        SELECT 1 FROM warehouse WHERE id = p_warehouse_id AND is_active = TRUE
    );
    
    IF NOT v_warehouse_exists THEN
        SET msg_text = 'Warehouse not found or inactive';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    START TRANSACTION;

    -- Добавляем строку закупки
    INSERT INTO purchase_line (
        purchase_invoice_id, product_id, qty, unit_price, warehouse_id
    ) VALUES (
        p_invoice_id, p_product_id, p_qty, p_price, p_warehouse_id
    );

    COMMIT;

    SET p_result_message = 'Purchase line added successfully';
END$$

-- 5. Корректировка инвентаря
CREATE PROCEDURE AdjustInventory(
    IN p_product_id BIGINT, 
    IN p_warehouse_id BIGINT, 
    IN p_qty DECIMAL(12,2),
    IN p_note TEXT, 
    IN p_by VARCHAR(100), 
    OUT p_msg VARCHAR(500)
)
BEGIN
    DECLARE v_current_stock DECIMAL(12,2);
    DECLARE v_product_name VARCHAR(255);
    DECLARE v_warehouse_name VARCHAR(200);
    DECLARE msg_text VARCHAR(500);
    DECLARE temp_msg VARCHAR(500);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_msg = 'Error during inventory adjustment';
    END;

    -- Проверяем существование товара
    SELECT name INTO v_product_name
    FROM product
    WHERE id = p_product_id AND is_active = TRUE;

    IF v_product_name IS NULL THEN
        SET msg_text = 'Product not found or inactive';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    -- Проверяем существование склада
    SELECT name INTO v_warehouse_name
    FROM warehouse
    WHERE id = p_warehouse_id AND is_active = TRUE;

    IF v_warehouse_name IS NULL THEN
        SET msg_text = 'Warehouse not found or inactive';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    START TRANSACTION;

    -- Добавляем движение товара
    INSERT INTO inventory_movement (
        product_id, warehouse_id, movement_type, qty, 
        related_type, note, created_by
    ) VALUES (
        p_product_id, p_warehouse_id, 'ADJUST', p_qty,
        'adjustment', p_note, p_by
    );

    -- Получаем новый остаток
    SET v_current_stock = GetCurrentStock(p_product_id, p_warehouse_id);

    -- Проверяем и создаем алерт при низком остатке
    INSERT INTO low_stock_alerts (
        product_id, warehouse_id, current_stock, min_stock_level, alert_date
    )
    SELECT 
        p.id, p_warehouse_id, v_current_stock, p.min_stock_level, NOW()
    FROM product p
    WHERE p.id = p_product_id
        AND p.min_stock_level IS NOT NULL
        AND v_current_stock <= p.min_stock_level
        AND NOT EXISTS (
            SELECT 1 FROM low_stock_alerts lsa
            WHERE lsa.product_id = p_product_id
                AND lsa.warehouse_id = p_warehouse_id
                AND lsa.is_resolved = FALSE
        );

    COMMIT;

    SET temp_msg = CONCAT('Inventory adjusted successfully. New stock: ', v_current_stock);
    SET p_msg = temp_msg;
END$$

-- 6. Отчет по остаткам товаров
CREATE PROCEDURE GetProductStockReport(
    IN p_warehouse_id BIGINT, 
    IN p_category_id BIGINT, 
    IN p_low_only BOOLEAN
)
BEGIN
    DECLARE v_warehouse_name VARCHAR(200);
    DECLARE v_category_name VARCHAR(200);
    
    -- Получаем названия для отчета
    SELECT name INTO v_warehouse_name
    FROM warehouse
    WHERE id = p_warehouse_id;
    
    SELECT name INTO v_category_name
    FROM category
    WHERE id = p_category_id;
    
    -- Основной запрос отчета
    SELECT 
        p.sku,
        p.name AS product_name,
        c.name AS category_name,
        GetCurrentStock(p.id, p_warehouse_id) AS current_stock,
        p.default_price,
        ROUND(GetCurrentStock(p.id, p_warehouse_id) * p.default_price, 2) AS stock_value,
        p.min_stock_level,
        p.max_stock_level,
        CASE 
            WHEN GetCurrentStock(p.id, p_warehouse_id) <= p.min_stock_level THEN 'LOW'
            WHEN p.max_stock_level IS NOT NULL AND 
                 GetCurrentStock(p.id, p_warehouse_id) >= p.max_stock_level * 0.9 THEN 'HIGH'
            ELSE 'NORMAL'
        END AS stock_status
    FROM product p
    LEFT JOIN category c ON p.category_id = c.id
    WHERE p.is_active = TRUE
        AND (p_category_id IS NULL OR p.category_id = p_category_id)
        AND (NOT p_low_only OR GetCurrentStock(p.id, p_warehouse_id) <= p.min_stock_level)
    ORDER BY stock_status, product_name;
END$$

-- 7. Отчет по поставщикам
CREATE PROCEDURE GetSupplierReport(IN p_supplier_id BIGINT)
BEGIN
    DECLARE v_supplier_name VARCHAR(255);
    
    -- Получаем имя поставщика
    SELECT name INTO v_supplier_name
    FROM supplier
    WHERE id = p_supplier_id;
    
    IF v_supplier_name IS NULL THEN
        SELECT 'Supplier not found' AS error;
    ELSE
        -- Основной запрос отчета
        SELECT 
            p.sku,
            p.name AS product_name,
            ps.supplier_sku,
            ps.last_purchase_price,
            ps.lead_time_days,
            ps.is_preferred,
            (SELECT COUNT(*) FROM purchase_line pl 
             JOIN purchase_invoice pi ON pl.purchase_invoice_id = pi.id
             WHERE pl.product_id = p.id AND pi.supplier_id = p_supplier_id) AS purchase_count,
            (SELECT SUM(pl.qty) FROM purchase_line pl 
             JOIN purchase_invoice pi ON pl.purchase_invoice_id = pi.id
             WHERE pl.product_id = p.id AND pi.supplier_id = p_supplier_id) AS total_purchased_qty
        FROM product_supplier ps
        JOIN product p ON ps.product_id = p.id
        WHERE ps.supplier_id = p_supplier_id
            AND p.is_active = TRUE
        ORDER BY p.name;
    END IF;
END$$

-- 8. Подтверждение накладной закупки
CREATE PROCEDURE ConfirmPurchaseInvoice(
    IN p_invoice_id BIGINT, 
    IN p_by VARCHAR(100), 
    OUT p_msg VARCHAR(500)
)
BEGIN
    DECLARE v_current_status VARCHAR(20);
    DECLARE v_supplier_name VARCHAR(255);
    DECLARE v_invoice_no VARCHAR(100);
    DECLARE temp_msg VARCHAR(500);
    DECLARE msg_text VARCHAR(500);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_msg = 'Error confirming invoice';
    END;

    -- Проверяем текущий статус накладной
    SELECT status, supplier_id, invoice_no 
    INTO v_current_status, @v_supplier_id, v_invoice_no
    FROM purchase_invoice
    WHERE id = p_invoice_id;

    IF v_current_status IS NULL THEN
        SET msg_text = 'Invoice not found';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    IF v_current_status != 'DRAFT' THEN
        SET temp_msg = CONCAT('Invoice already has status: ', v_current_status);
        SET msg_text = temp_msg;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg_text;
    END IF;

    -- Получаем имя поставщика
    SELECT name INTO v_supplier_name
    FROM supplier
    WHERE id = @v_supplier_id;

    START TRANSACTION;

    -- Обновляем статус накладной
    UPDATE purchase_invoice
    SET status = 'CONFIRMED',
        received_by = p_by
    WHERE id = p_invoice_id;

    -- Автоматически создаем движения товара (это также сделает триггер, но делаем явно)
    INSERT INTO inventory_movement (
        product_id, warehouse_id, movement_type, qty, 
        related_type, related_id, note
    )
    SELECT 
        pl.product_id,
        pl.warehouse_id,
        'IN',
        pl.qty,
        'purchase',
        p_invoice_id,
        CONCAT('Purchase confirmed from ', v_supplier_name, ', invoice ', v_invoice_no)
    FROM purchase_line pl
    WHERE pl.purchase_invoice_id = p_invoice_id;

    -- Обновляем последние цены у поставщиков
    UPDATE product_supplier ps
    JOIN purchase_line pl ON ps.product_id = pl.product_id
    SET ps.last_purchase_price = pl.unit_price
    WHERE pl.purchase_invoice_id = p_invoice_id
        AND ps.supplier_id = @v_supplier_id;

    COMMIT;

    SET temp_msg = CONCAT('Invoice ', v_invoice_no, ' confirmed successfully');
    SET p_msg = temp_msg;
END$$

DELIMITER ;

-- Успешное завершение
SELECT 'All functions and procedures created successfully!' AS status;

-- Показать созданные функции и процедуры
SELECT 
    routine_name,
    routine_type,
    created
FROM information_schema.routines
WHERE routine_schema = 'warehouse_lab3'
ORDER BY routine_type, routine_name;