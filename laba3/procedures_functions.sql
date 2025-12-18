USE warehouse_lab3;

DROP FUNCTION IF EXISTS GetCurrentStock;
DROP FUNCTION IF EXISTS CheckProductAvailability;
DROP FUNCTION IF EXISTS GetWarehouseTotalValue;
DROP PROCEDURE IF EXISTS AddPurchaseLine;
DROP PROCEDURE IF EXISTS ProcessSale;
DROP PROCEDURE IF EXISTS AdjustInventory;
DROP PROCEDURE IF EXISTS GetProductStockReport;
DROP PROCEDURE IF EXISTS GetSupplierReport;
DROP PROCEDURE IF EXISTS ConfirmPurchaseInvoice;

-- Функция 1: Получение текущего остатка товара на складе
DELIMITER $$

CREATE FUNCTION GetCurrentStock(
    p_product_id BIGINT,
    p_warehouse_id BIGINT
) RETURNS DECIMAL(12, 2) 
READS SQL DATA 
DETERMINISTIC
BEGIN
    DECLARE v_stock DECIMAL(12, 2);
    DECLARE v_product_exists INT;
    DECLARE v_warehouse_exists INT;

    -- Проверяем существование товара
    SELECT COUNT(*) INTO v_product_exists
    FROM product
    WHERE id = p_product_id;

    IF v_product_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Product not found';
    END IF;

    -- Проверяем существование склада
    SELECT COUNT(*) INTO v_warehouse_exists
    FROM warehouse
    WHERE id = p_warehouse_id;

    IF v_warehouse_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Warehouse not found';
    END IF;

    -- Вычисляем остаток
    SELECT COALESCE(
        SUM(
            CASE movement_type
                WHEN 'IN' THEN qty
                WHEN 'OUT' THEN -qty
                WHEN 'ADJUST' THEN qty
                ELSE 0
            END
        ),
        0
    ) INTO v_stock
    FROM inventory_movement
    WHERE product_id = p_product_id
      AND warehouse_id = p_warehouse_id;

    RETURN v_stock;
END$$

DELIMITER ;

-- Функция 2: Проверка доступности товара для продажи
DELIMITER $$

CREATE FUNCTION CheckProductAvailability(
    p_product_id BIGINT,
    p_warehouse_id BIGINT,
    p_required_qty DECIMAL(12, 2)
) RETURNS BOOLEAN 
READS SQL DATA 
DETERMINISTIC
BEGIN
    DECLARE v_current_stock DECIMAL(12, 2);
    DECLARE v_is_available BOOLEAN;

    -- Получаем текущий остаток
    SET v_current_stock = GetCurrentStock(p_product_id, p_warehouse_id);

    -- Проверяем доступность
    IF v_current_stock >= p_required_qty THEN
        SET v_is_available = TRUE;
    ELSE
        SET v_is_available = FALSE;
    END IF;

    RETURN v_is_available;
END$$

DELIMITER ;

-- Функция 3: Получение общей стоимости товаров на складе
DELIMITER $$

CREATE FUNCTION GetWarehouseTotalValue(p_warehouse_id BIGINT) 
RETURNS DECIMAL(12, 2) 
READS SQL DATA 
DETERMINISTIC
BEGIN
    DECLARE v_total_value DECIMAL(12, 2);

    -- Проверяем существование склада
    IF NOT EXISTS (
        SELECT 1 FROM warehouse WHERE id = p_warehouse_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Warehouse not found';
    END IF;

    -- Вычисляем общую стоимость
    SELECT COALESCE(
        SUM(GetCurrentStock(p.id, p_warehouse_id) * p.default_price),
        0
    ) INTO v_total_value
    FROM product p
    WHERE p.is_active = TRUE;

    RETURN v_total_value;
END$$

DELIMITER ;

-- Процедура 1: Добавление строки прихода с проверками
DELIMITER $$

CREATE PROCEDURE AddPurchaseLine(
    IN p_invoice_id BIGINT,
    IN p_product_id BIGINT,
    IN p_qty DECIMAL(12, 2),
    IN p_price DECIMAL(12, 2),
    IN p_warehouse_id BIGINT,
    OUT p_result_message VARCHAR(500)
)
BEGIN
    DECLARE v_invoice_exists INT;
    DECLARE v_product_exists INT;
    DECLARE v_warehouse_exists INT;
    DECLARE v_current_stock DECIMAL(12, 2);
    DECLARE v_max_stock_level DECIMAL(12, 2);
    DECLARE v_supplier_id BIGINT;
    DECLARE v_invoice_status VARCHAR(20);
    DECLARE v_product_name VARCHAR(255);
    DECLARE v_warehouse_name VARCHAR(200);
    DECLARE v_line_id BIGINT;
    DECLARE v_error_msg VARCHAR(500);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 
            v_error_msg = MESSAGE_TEXT;
        SET p_result_message = CONCAT('Error: ', v_error_msg);
    END;

    -- Проверка входных параметров
    IF p_qty <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Quantity must be greater than 0';
    END IF;

    IF p_price <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Price must be greater than 0';
    END IF;

    -- Проверка существования записей
    SELECT COUNT(*), status 
    INTO v_invoice_exists, v_invoice_status
    FROM purchase_invoice
    WHERE id = p_invoice_id;

    IF v_invoice_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Purchase invoice not found';
    END IF;

    SELECT COUNT(*), name 
    INTO v_product_exists, v_product_name
    FROM product
    WHERE id = p_product_id AND is_active = TRUE;

    IF v_product_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Product not found or not active';
    END IF;

    SELECT COUNT(*), name 
    INTO v_warehouse_exists, v_warehouse_name
    FROM warehouse
    WHERE id = p_warehouse_id AND is_active = TRUE;

    IF v_warehouse_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Warehouse not found or not active';
    END IF;

    -- Проверка статуса накладной
    IF v_invoice_status != 'DRAFT' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot add line to confirmed or cancelled invoice';
    END IF;

    -- Проверка максимального уровня запасов
    SELECT max_stock_level INTO v_max_stock_level
    FROM product
    WHERE id = p_product_id;

    SET v_current_stock = GetCurrentStock(p_product_id, p_warehouse_id);

    IF v_max_stock_level IS NOT NULL AND (v_current_stock + p_qty) > v_max_stock_level THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = CONCAT(
            'Exceeds maximum stock level for product "',
            v_product_name,
            '". Current: ',
            v_current_stock,
            ', Adding: ',
            p_qty,
            ', Max: ',
            v_max_stock_level
        );
    END IF;

    -- Начинаем транзакцию
    START TRANSACTION;

    -- Получаем supplier_id из накладной
    SELECT supplier_id INTO v_supplier_id
    FROM purchase_invoice
    WHERE id = p_invoice_id;

    -- Вставляем строку прихода
    INSERT INTO purchase_line (
        purchase_invoice_id,
        product_id,
        qty,
        unit_price,
        warehouse_id
    ) VALUES (
        p_invoice_id,
        p_product_id,
        p_qty,
        p_price,
        p_warehouse_id
    );

    SET v_line_id = LAST_INSERT_ID();

    -- Обновляем сумму накладной
    UPDATE purchase_invoice
    SET total_amount = (
        SELECT COALESCE(SUM(line_total), 0)
        FROM purchase_line
        WHERE purchase_invoice_id = p_invoice_id
    )
    WHERE id = p_invoice_id;

    -- Обновляем последнюю цену покупки у поставщика
    UPDATE product_supplier
    SET last_purchase_price = p_price
    WHERE product_id = p_product_id
      AND supplier_id = v_supplier_id;

    -- Если связь не существует, создаем ее
    IF ROW_COUNT() = 0 THEN
        INSERT INTO product_supplier (
            product_id, 
            supplier_id, 
            last_purchase_price
        ) VALUES (
            p_product_id, 
            v_supplier_id, 
            p_price
        );
    END IF;

    -- Создаем движение товара
    INSERT INTO inventory_movement (
        product_id,
        warehouse_id,
        movement_type,
        qty,
        related_type,
        related_id,
        note
    ) VALUES (
        p_product_id,
        p_warehouse_id,
        'IN',
        p_qty,
        'purchase',
        p_invoice_id,
        CONCAT(
            'Purchase line #',
            v_line_id,
            ' for product "',
            v_product_name,
            '" to warehouse "',
            v_warehouse_name,
            '"'
        )
    );

    -- Если были алерты по низкому остатку, помечаем их как решенные
    UPDATE low_stock_alerts
    SET is_resolved = TRUE,
        resolved_at = NOW(),
        resolved_by = 'Purchase'
    WHERE product_id = p_product_id
      AND warehouse_id = p_warehouse_id
      AND is_resolved = FALSE;

    COMMIT;

    SET p_result_message = CONCAT(
        'Purchase line added successfully. Line ID: ',
        v_line_id,
        '. New stock: ',
        (v_current_stock + p_qty),
        ' in warehouse "',
        v_warehouse_name,
        '"'
    );
END$$

DELIMITER ;

-- Процедура 2: Оформление продажи с проверкой остатков
DELIMITER $$

CREATE PROCEDURE ProcessSale(
    IN p_customer_name VARCHAR(255),
    IN p_invoice_no VARCHAR(100),
    IN p_product_id BIGINT,
    IN p_qty DECIMAL(12, 2),
    IN p_unit_price DECIMAL(12, 2),
    IN p_warehouse_id BIGINT,
    IN p_issued_by VARCHAR(100),
    OUT p_sale_id BIGINT,
    OUT p_result_message VARCHAR(500)
)
BEGIN
    DECLARE v_current_stock DECIMAL(12, 2);
    DECLARE v_product_name VARCHAR(255);
    DECLARE v_warehouse_name VARCHAR(200);
    DECLARE v_sales_invoice_id BIGINT;
    DECLARE v_line_id BIGINT;
    DECLARE v_min_stock_level DECIMAL(12, 2);
    DECLARE v_error_msg VARCHAR(500);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 
            v_error_msg = MESSAGE_TEXT;
        SET p_result_message = CONCAT('Error: ', v_error_msg);
        SET p_sale_id = NULL;
    END;

    -- Проверка входных данных
    IF p_qty <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Quantity must be greater than 0';
    END IF;

    IF p_unit_price <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Price must be greater than 0';
    END IF;

    -- Получаем названия для сообщений
    SELECT name INTO v_product_name
    FROM product
    WHERE id = p_product_id;

    SELECT name INTO v_warehouse_name
    FROM warehouse
    WHERE id = p_warehouse_id;

    -- Проверяем активность товара и склада
    IF NOT EXISTS (
        SELECT 1 FROM product
        WHERE id = p_product_id AND is_active = TRUE
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Product is not active';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM warehouse
        WHERE id = p_warehouse_id AND is_active = TRUE
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Warehouse is not active';
    END IF;

    -- Проверяем остаток
    SET v_current_stock = GetCurrentStock(p_product_id, p_warehouse_id);

    IF v_current_stock < p_qty THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = CONCAT(
            'Insufficient stock for product "',
            v_product_name,
            '" in warehouse "',
            v_warehouse_name,
            '". Available: ',
            v_current_stock,
            ', Required: ',
            p_qty
        );
    END IF;

    -- Получаем минимальный уровень запасов
    SELECT min_stock_level INTO v_min_stock_level
    FROM product
    WHERE id = p_product_id;

    -- Начинаем транзакцию
    START TRANSACTION;

    -- Создаем накладную
    INSERT INTO sales_invoice (
        customer_name,
        invoice_no,
        date,
        issued_by,
        status
    ) VALUES (
        p_customer_name,
        p_invoice_no,
        CURDATE(),
        p_issued_by,
        'CONFIRMED'
    );

    SET v_sales_invoice_id = LAST_INSERT_ID();
    SET p_sale_id = v_sales_invoice_id;

    -- Добавляем строку продажи
    INSERT INTO sales_line (
        sales_invoice_id,
        product_id,
        qty,
        unit_price,
        warehouse_id
    ) VALUES (
        v_sales_invoice_id,
        p_product_id,
        p_qty,
        p_unit_price,
        p_warehouse_id
    );

    SET v_line_id = LAST_INSERT_ID();

    -- Обновляем сумму накладной
    UPDATE sales_invoice
    SET total_amount = (
        SELECT COALESCE(SUM(line_total), 0)
        FROM sales_line
        WHERE sales_invoice_id = v_sales_invoice_id
    )
    WHERE id = v_sales_invoice_id;

    -- Создаем движение товара
    INSERT INTO inventory_movement (
        product_id,
        warehouse_id,
        movement_type,
        qty,
        related_type,
        related_id,
        note
    ) VALUES (
        p_product_id,
        p_warehouse_id,
        'OUT',
        p_qty,
        'sale',
        v_sales_invoice_id,
        CONCAT(
            'Sale line #',
            v_line_id,
            ' to customer "',
            p_customer_name,
            '", invoice ',
            p_invoice_no
        )
    );

    -- Проверяем остаток после продажи
    SET v_current_stock = GetCurrentStock(p_product_id, p_warehouse_id);

    -- Если остаток ниже минимального уровня, создаем алерт
    IF v_current_stock < v_min_stock_level THEN
        INSERT INTO low_stock_alerts (
            product_id,
            warehouse_id,
            current_stock,
            min_stock_level
        ) VALUES (
            p_product_id,
            p_warehouse_id,
            v_current_stock,
            v_min_stock_level
        );
    END IF;

    COMMIT;

    SET p_result_message = CONCAT(
        'Sale processed successfully. Invoice ID: ',
        v_sales_invoice_id,
        ', Line ID: ',
        v_line_id,
        '. Stock after sale: ',
        v_current_stock,
        ' in warehouse "',
        v_warehouse_name,
        '"'
    );
END$$

DELIMITER ;

-- Процедура 3: Корректировка остатков (инвентаризация)
DELIMITER $$

CREATE PROCEDURE AdjustInventory(
    IN p_product_id BIGINT,
    IN p_warehouse_id BIGINT,
    IN p_adjustment_qty DECIMAL(12, 2),
    IN p_reason TEXT,
    IN p_adjusted_by VARCHAR(100),
    OUT p_result_message VARCHAR(500)
)
BEGIN
    DECLARE v_current_stock DECIMAL(12, 2);
    DECLARE v_product_name VARCHAR(255);
    DECLARE v_warehouse_name VARCHAR(200);
    DECLARE v_new_stock DECIMAL(12, 2);
    DECLARE v_min_stock_level DECIMAL(12, 2);
    DECLARE v_movement_id BIGINT;
    DECLARE v_error_msg VARCHAR(500);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 
            v_error_msg = MESSAGE_TEXT;
        SET p_result_message = CONCAT('Error: ', v_error_msg);
    END;

    -- Получаем названия
    SELECT name INTO v_product_name
    FROM product
    WHERE id = p_product_id;

    SELECT name INTO v_warehouse_name
    FROM warehouse
    WHERE id = p_warehouse_id;

    -- Проверяем существование товара и склада
    IF v_product_name IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Product not found';
    END IF;

    IF v_warehouse_name IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Warehouse not found';
    END IF;

    -- Текущий остаток
    SET v_current_stock = GetCurrentStock(p_product_id, p_warehouse_id);
    SET v_new_stock = v_current_stock + p_adjustment_qty;

    -- Проверяем, не уйдет ли остаток в отрицательное значение
    IF v_new_stock < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = CONCAT(
            'Cannot adjust. Would result in negative stock: ',
            v_new_stock
        );
    END IF;

    -- Получаем минимальный уровень запасов
    SELECT min_stock_level INTO v_min_stock_level
    FROM product
    WHERE id = p_product_id;

    -- Начинаем транзакцию
    START TRANSACTION;

    -- Добавляем движение
    INSERT INTO inventory_movement (
        product_id,
        warehouse_id,
        movement_type,
        qty,
        related_type,
        note,
        created_by
    ) VALUES (
        p_product_id,
        p_warehouse_id,
        'ADJUST',
        p_adjustment_qty,
        'adjustment',
        CONCAT(
            'Adjustment. Reason: ',
            p_reason,
            '. Previous: ',
            v_current_stock,
            ', Adjustment: ',
            p_adjustment_qty,
            ', New: ',
            v_new_stock
        ),
        p_adjusted_by
    );

    SET v_movement_id = LAST_INSERT_ID();

    -- Если остаток ниже минимального уровня, создаем алерт
    IF v_new_stock < v_min_stock_level THEN
        INSERT INTO low_stock_alerts (
            product_id,
            warehouse_id,
            current_stock,
            min_stock_level
        ) VALUES (
            p_product_id,
            p_warehouse_id,
            v_new_stock,
            v_min_stock_level
        );
    END IF;

    -- Если были алерты и теперь остаток выше минимального, помечаем как решенные
    IF v_new_stock >= v_min_stock_level THEN
        UPDATE low_stock_alerts
        SET is_resolved = TRUE,
            resolved_at = NOW(),
            resolved_by = p_adjusted_by
        WHERE product_id = p_product_id
          AND warehouse_id = p_warehouse_id
          AND is_resolved = FALSE;
    END IF;

    COMMIT;

    SET p_result_message = CONCAT(
        'Inventory adjusted successfully. Movement ID: ',
        v_movement_id,
        '. Product: ',
        v_product_name,
        ', Warehouse: ',
        v_warehouse_name,
        ', Previous: ',
        v_current_stock,
        ', Adjustment: ',
        p_adjustment_qty,
        ', New: ',
        v_new_stock
    );
END$$

DELIMITER ;

-- Процедура 4: Отчет по остаткам товаров
DELIMITER $$

CREATE PROCEDURE GetProductStockReport(
    IN p_warehouse_id BIGINT,
    IN p_category_id BIGINT,
    IN p_show_only_low_stock BOOLEAN
)
BEGIN
    DECLARE v_warehouse_name VARCHAR(200);

    -- Получаем название склада
    SELECT name INTO v_warehouse_name
    FROM warehouse
    WHERE id = p_warehouse_id;

    IF v_warehouse_name IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Warehouse not found';
    END IF;

    -- Формируем отчет
    SELECT
        p.sku,
        p.name AS product_name,
        c.name AS category_name,
        u.name AS unit_name,
        GetCurrentStock(p.id, p_warehouse_id) AS current_stock,
        p.min_stock_level,
        p.max_stock_level,
        p.default_price,
        ROUND(GetCurrentStock(p.id, p_warehouse_id) * p.default_price, 2) AS total_value,
        CASE
            WHEN GetCurrentStock(p.id, p_warehouse_id) <= p.min_stock_level THEN 'LOW'
            WHEN p.max_stock_level IS NOT NULL
                 AND GetCurrentStock(p.id, p_warehouse_id) >= p.max_stock_level * 0.9 THEN 'HIGH'
            ELSE 'NORMAL'
        END AS stock_status,
        CASE
            WHEN CheckProductAvailability(p.id, p_warehouse_id, 1) = TRUE THEN 'AVAILABLE'
            ELSE 'OUT OF STOCK'
        END AS availability
    FROM product p
    LEFT JOIN category c ON p.category_id = c.id
    LEFT JOIN unit u ON p.unit_id = u.id
    WHERE p.is_active = TRUE
      AND (p_category_id IS NULL OR p.category_id = p_category_id)
      AND (
          NOT p_show_only_low_stock
          OR GetCurrentStock(p.id, p_warehouse_id) <= p.min_stock_level
      )
    ORDER BY
        CASE WHEN GetCurrentStock(p.id, p_warehouse_id) <= p.min_stock_level THEN 1 ELSE 2 END,
        p.name;
END$$

DELIMITER ;

-- Процедура 5: Отчет по поставщикам
DELIMITER $$

CREATE PROCEDURE GetSupplierReport(IN p_supplier_id BIGINT)
BEGIN
    DECLARE v_supplier_name VARCHAR(255);

    -- Получаем название поставщика
    SELECT name INTO v_supplier_name
    FROM supplier
    WHERE id = p_supplier_id;

    IF p_supplier_id IS NOT NULL AND v_supplier_name IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Supplier not found';
    END IF;

    -- Формируем отчет
    SELECT
        s.id AS supplier_id,
        s.name AS supplier_name,
        s.contact_email,
        s.phone,
        s.is_active,
        COUNT(DISTINCT ps.product_id) AS total_products,
        COUNT(DISTINCT pi.id) AS total_invoices,
        COALESCE(SUM(pi.total_amount), 0) AS total_purchase_amount,
        COALESCE(AVG(ps.last_purchase_price), 0) AS avg_purchase_price,
        MIN(ps.lead_time_days) AS min_lead_time,
        MAX(ps.lead_time_days) AS max_lead_time
    FROM supplier s
    LEFT JOIN product_supplier ps ON s.id = ps.supplier_id
    LEFT JOIN purchase_invoice pi ON s.id = pi.supplier_id
    WHERE (p_supplier_id IS NULL OR s.id = p_supplier_id)
    GROUP BY s.id, s.name, s.contact_email, s.phone, s.is_active
    ORDER BY total_purchase_amount DESC;
END$$

DELIMITER ;

-- Процедура 6: Подтверждение приходной накладной
DELIMITER $$

CREATE PROCEDURE ConfirmPurchaseInvoice(
    IN p_invoice_id BIGINT,
    IN p_confirmed_by VARCHAR(100),
    OUT p_result_message VARCHAR(500)
)
BEGIN
    DECLARE v_invoice_exists INT;
    DECLARE v_current_status VARCHAR(20);
    DECLARE v_supplier_name VARCHAR(255);
    DECLARE v_invoice_no VARCHAR(100);
    DECLARE v_error_msg VARCHAR(500);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 
            v_error_msg = MESSAGE_TEXT;
        SET p_result_message = CONCAT('Error: ', v_error_msg);
    END;

    -- Проверяем существование накладной
    SELECT COUNT(*), status, invoice_no 
    INTO v_invoice_exists, v_current_status, v_invoice_no
    FROM purchase_invoice
    WHERE id = p_invoice_id;

    IF v_invoice_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Purchase invoice not found';
    END IF;

    -- Проверяем текущий статус
    IF v_current_status = 'CONFIRMED' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invoice is already confirmed';
    END IF;

    IF v_current_status = 'CANCELLED' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot confirm cancelled invoice';
    END IF;

    -- Получаем название поставщика
    SELECT name INTO v_supplier_name
    FROM supplier s
    JOIN purchase_invoice pi ON s.id = pi.supplier_id
    WHERE pi.id = p_invoice_id;

    -- Начинаем транзакцию
    START TRANSACTION;

    -- Обновляем статус накладной
    UPDATE purchase_invoice
    SET status = 'CONFIRMED'
    WHERE id = p_invoice_id;

    -- Для каждой строки накладной создаем движение товара
    INSERT INTO inventory_movement (
        product_id,
        warehouse_id,
        movement_type,
        qty,
        related_type,
        related_id,
        note
    )
    SELECT
        pl.product_id,
        pl.warehouse_id,
        'IN',
        pl.qty,
        'purchase',
        p_invoice_id,
        CONCAT(
            'Confirmed purchase from ',
            v_supplier_name,
            ', invoice ',
            v_invoice_no
        )
    FROM purchase_line pl
    WHERE pl.purchase_invoice_id = p_invoice_id;

    COMMIT;

    SET p_result_message = CONCAT(
        'Purchase invoice confirmed successfully. Invoice: ',
        v_invoice_no,
        ', Supplier: ',
        v_supplier_name
    );
END$$

DELIMITER ;

-- Проверка создания
SELECT 'Functions and procedures created successfully!' as message;

SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'warehouse_lab3'
ORDER BY routine_type, routine_name;