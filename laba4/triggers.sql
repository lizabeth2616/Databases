USE warehouse_lab3;

-- Удаление существующих триггеров
DROP TRIGGER IF EXISTS before_purchase_line_insert;
DROP TRIGGER IF EXISTS after_purchase_line_insert;
DROP TRIGGER IF EXISTS before_purchase_invoice_update;
DROP TRIGGER IF EXISTS after_purchase_invoice_update;
DROP TRIGGER IF EXISTS before_sales_line_insert;
DROP TRIGGER IF EXISTS after_sales_line_insert;
DROP TRIGGER IF EXISTS before_sales_invoice_update;
DROP TRIGGER IF EXISTS after_sales_invoice_update;
DROP TRIGGER IF EXISTS before_product_update;
DROP TRIGGER IF EXISTS after_product_update;
DROP TRIGGER IF EXISTS before_inventory_movement_insert;
DROP TRIGGER IF EXISTS after_inventory_movement_insert;
DROP TRIGGER IF EXISTS before_purchase_line_delete;
DROP TRIGGER IF EXISTS before_sales_line_delete;
DROP TRIGGER IF EXISTS after_product_supplier_update;

-- ТРИГГЕРЫ ДЛЯ ПРИХОДНЫХ НАКЛАДНЫХ

-- Триггер 1: Проверка данных перед вставкой строки прихода
DELIMITER $$

CREATE TRIGGER before_purchase_line_insert
BEFORE INSERT ON purchase_line
FOR EACH ROW
BEGIN
    DECLARE v_invoice_status VARCHAR(20);
    DECLARE v_product_active BOOLEAN;
    DECLARE v_warehouse_active BOOLEAN;
    DECLARE v_current_stock DECIMAL(12, 2);
    DECLARE v_max_stock_level DECIMAL(12, 2);
    DECLARE v_product_name VARCHAR(255);
    DECLARE v_warehouse_name VARCHAR(200);
    DECLARE v_stock_msg VARCHAR(500);
    DECLARE msg VARCHAR(500);

    -- Проверяем статус накладной
    SELECT status INTO v_invoice_status
    FROM purchase_invoice
    WHERE id = NEW.purchase_invoice_id;

    IF v_invoice_status != 'DRAFT' THEN
        SET msg = 'Cannot add line to confirmed or cancelled invoice';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Проверяем активность товара
    SELECT is_active, name INTO v_product_active, v_product_name
    FROM product
    WHERE id = NEW.product_id;

    IF NOT v_product_active THEN
        SET msg = CONCAT('Cannot add inactive product "', v_product_name, '" to purchase');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Проверяем активность склада
    SELECT is_active, name INTO v_warehouse_active, v_warehouse_name
    FROM warehouse
    WHERE id = NEW.warehouse_id;

    IF NOT v_warehouse_active THEN
        SET msg = CONCAT('Cannot add purchase to inactive warehouse "', v_warehouse_name, '"');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Бизнес-правило: количество должно быть положительным
    IF NEW.qty <= 0 THEN
        SET msg = 'Quantity must be greater than 0';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Бизнес-правило: цена должна быть положительной
    IF NEW.unit_price <= 0 THEN
        SET msg = 'Price must be greater than 0';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Проверяем максимальный уровень запасов
    SELECT max_stock_level INTO v_max_stock_level
    FROM product
    WHERE id = NEW.product_id;

    IF v_max_stock_level IS NOT NULL THEN
        -- Получаем текущий остаток
        SET v_current_stock = GetCurrentStock(NEW.product_id, NEW.warehouse_id);
        
        IF (v_current_stock + NEW.qty) > v_max_stock_level THEN
            SET msg = CONCAT('Exceeds maximum stock level for product "',
                v_product_name, '". Current: ', v_current_stock,
                ', Adding: ', NEW.qty, ', Max: ', v_max_stock_level);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
        END IF;
    END IF;
END$$

-- Триггер 2: Обновление суммы накладной после вставки строки прихода
CREATE TRIGGER after_purchase_line_insert
AFTER INSERT ON purchase_line
FOR EACH ROW
BEGIN
    -- Обновляем сумму накладной
    UPDATE purchase_invoice
    SET total_amount = (
        SELECT COALESCE(SUM(line_total), 0)
        FROM purchase_line
        WHERE purchase_invoice_id = NEW.purchase_invoice_id
    )
    WHERE id = NEW.purchase_invoice_id;
END$$

-- Триггер 3: Проверка перед обновлением приходной накладной
CREATE TRIGGER before_purchase_invoice_update
BEFORE UPDATE ON purchase_invoice
FOR EACH ROW
BEGIN
    DECLARE msg VARCHAR(500);

    -- Не позволяем изменять подтвержденные или отмененные накладные
    IF OLD.status != 'DRAFT' AND NEW.status != OLD.status THEN
        SET msg = 'Cannot change status of confirmed or cancelled invoice';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Проверяем, не пытаются ли изменить поставщика у подтвержденной накладной
    IF OLD.status != 'DRAFT' AND NEW.supplier_id != OLD.supplier_id THEN
        SET msg = 'Cannot change supplier for confirmed or cancelled invoice';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;
END$$

-- Триггер 4: Автоматическое создание движения товара при подтверждении накладной
CREATE TRIGGER after_purchase_invoice_update
AFTER UPDATE ON purchase_invoice
FOR EACH ROW
BEGIN
    DECLARE v_supplier_name VARCHAR(255);
    DECLARE v_note VARCHAR(500);
    DECLARE msg VARCHAR(500);

    -- Если статус изменился на CONFIRMED, создаем движения товаров
    IF OLD.status != 'CONFIRMED' AND NEW.status = 'CONFIRMED' THEN
        -- Получаем название поставщика
        SELECT name INTO v_supplier_name
        FROM supplier
        WHERE id = NEW.supplier_id;

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
            NEW.id,
            CONCAT('Purchase from ', v_supplier_name, ', invoice ', NEW.invoice_no)
        FROM purchase_line pl
        WHERE pl.purchase_invoice_id = NEW.id;

        -- Обновляем последние цены у поставщиков
        UPDATE product_supplier ps
        JOIN purchase_line pl ON ps.product_id = pl.product_id
        SET ps.last_purchase_price = pl.unit_price
        WHERE pl.purchase_invoice_id = NEW.id
            AND ps.supplier_id = NEW.supplier_id;

        -- Если остатки были низкими, помечаем алерты как решенные
        UPDATE low_stock_alerts lsa
        JOIN purchase_line pl ON lsa.product_id = pl.product_id
            AND lsa.warehouse_id = pl.warehouse_id
        SET lsa.is_resolved = TRUE,
            lsa.resolved_at = NOW(),
            lsa.resolved_by = 'Purchase confirmed'
        WHERE lsa.is_resolved = FALSE
            AND pl.purchase_invoice_id = NEW.id;
    END IF;
END$$

-- Триггер 5: Проверка перед вставкой строки продажи
CREATE TRIGGER before_sales_line_insert
BEFORE INSERT ON sales_line
FOR EACH ROW
BEGIN
    DECLARE v_invoice_status VARCHAR(20);
    DECLARE v_product_active BOOLEAN;
    DECLARE v_warehouse_active BOOLEAN;
    DECLARE v_current_stock DECIMAL(12, 2);
    DECLARE v_min_stock_level DECIMAL(12, 2);
    DECLARE v_product_name VARCHAR(255);
    DECLARE v_warehouse_name VARCHAR(200);
    DECLARE msg VARCHAR(500);

    -- Проверяем статус накладной
    SELECT status INTO v_invoice_status
    FROM sales_invoice
    WHERE id = NEW.sales_invoice_id;

    IF v_invoice_status != 'DRAFT' THEN
        SET msg = 'Cannot add line to confirmed or cancelled invoice';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Проверяем активность товара
    SELECT is_active, name INTO v_product_active, v_product_name
    FROM product
    WHERE id = NEW.product_id;

    IF NOT v_product_active THEN
        SET msg = CONCAT('Cannot sell inactive product "', v_product_name, '"');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Проверяем активность склада
    SELECT is_active, name INTO v_warehouse_active, v_warehouse_name
    FROM warehouse
    WHERE id = NEW.warehouse_id;

    IF NOT v_warehouse_active THEN
        SET msg = CONCAT('Cannot sell from inactive warehouse "', v_warehouse_name, '"');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Бизнес-правило: количество должно быть положительным
    IF NEW.qty <= 0 THEN
        SET msg = 'Quantity must be greater than 0';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Бизнес-правило: цена должна быть положительной
    IF NEW.unit_price <= 0 THEN
        SET msg = 'Price must be greater than 0';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Проверяем наличие достаточного количества
    SET v_current_stock = GetCurrentStock(NEW.product_id, NEW.warehouse_id);
    
    IF v_current_stock < NEW.qty THEN
        SET msg = CONCAT('Insufficient stock for product "', 
            v_product_name, '". Available: ', v_current_stock, 
            ', Requested: ', NEW.qty);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Проверяем минимальный уровень запасов
    SELECT min_stock_level INTO v_min_stock_level
    FROM product
    WHERE id = NEW.product_id;

    IF v_min_stock_level IS NOT NULL THEN
        IF (v_current_stock - NEW.qty) < v_min_stock_level THEN
            SET msg = CONCAT('Sale will bring stock below minimum level for product "',
                v_product_name, '". Will be: ', (v_current_stock - NEW.qty),
                ', Minimum: ', v_min_stock_level);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
        END IF;
    END IF;
END$$

-- Триггер 6: Обновление суммы накладной после вставки строки продажи
CREATE TRIGGER after_sales_line_insert
AFTER INSERT ON sales_line
FOR EACH ROW
BEGIN
    -- Обновляем сумму накладной
    UPDATE sales_invoice
    SET total_amount = (
        SELECT COALESCE(SUM(line_total), 0)
        FROM sales_line
        WHERE sales_invoice_id = NEW.sales_invoice_id
    )
    WHERE id = NEW.sales_invoice_id;
END$$

-- Триггер 7: Проверка перед обновлением накладной продажи
CREATE TRIGGER before_sales_invoice_update
BEFORE UPDATE ON sales_invoice
FOR EACH ROW
BEGIN
    DECLARE msg VARCHAR(500);

    -- Не позволяем изменять подтвержденные или отмененные накладные
    IF OLD.status != 'DRAFT' AND NEW.status != OLD.status THEN
        SET msg = 'Cannot change status of confirmed or cancelled invoice';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;
END$$

-- Триггер 8: Автоматическое создание движения товара при подтверждении продажи
CREATE TRIGGER after_sales_invoice_update
AFTER UPDATE ON sales_invoice
FOR EACH ROW
BEGIN
    -- Если статус изменился на CONFIRMED, создаем движения товаров
    IF OLD.status != 'CONFIRMED' AND NEW.status = 'CONFIRMED' THEN
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
            sl.product_id,
            sl.warehouse_id,
            'OUT',
            sl.qty,
            'sale',
            NEW.id,
            CONCAT('Sale to ', NEW.customer_name, ', invoice ', NEW.invoice_no)
        FROM sales_line sl
        WHERE sl.sales_invoice_id = NEW.id;

        -- Проверяем и создаем алерты для низких остатков
        INSERT INTO low_stock_alerts (
            product_id,
            warehouse_id,
            current_stock,
            min_stock_level,
            alert_date
        )
        SELECT
            sl.product_id,
            sl.warehouse_id,
            GetCurrentStock(sl.product_id, sl.warehouse_id) as current_stock,
            p.min_stock_level,
            NOW()
        FROM sales_line sl
        JOIN product p ON sl.product_id = p.id
        WHERE sl.sales_invoice_id = NEW.id
            AND p.min_stock_level IS NOT NULL
            AND GetCurrentStock(sl.product_id, sl.warehouse_id) <= p.min_stock_level
            AND NOT EXISTS (
                SELECT 1 FROM low_stock_alerts lsa
                WHERE lsa.product_id = sl.product_id
                    AND lsa.warehouse_id = sl.warehouse_id
                    AND lsa.is_resolved = FALSE
            );
    END IF;
END$$

-- Триггер 9: Аудит изменения цен товаров
CREATE TRIGGER before_product_update
BEFORE UPDATE ON product
FOR EACH ROW
BEGIN
    -- Если цена изменилась, записываем в аудит
    IF OLD.default_price != NEW.default_price THEN
        INSERT INTO price_audit_log (
            product_id,
            old_price,
            new_price,
            change_percent,
            changed_by,
            reason
        ) VALUES (
            NEW.id,
            OLD.default_price,
            NEW.default_price,
            ROUND(((NEW.default_price - OLD.default_price) / OLD.default_price * 100), 2),
            USER(),
            'Price updated by trigger'
        );
    END IF;
END$$

-- Триггер 10: Проверка перед вставкой движения товара
CREATE TRIGGER before_inventory_movement_insert
BEFORE INSERT ON inventory_movement
FOR EACH ROW
BEGIN
    DECLARE v_product_active BOOLEAN;
    DECLARE v_warehouse_active BOOLEAN;
    DECLARE v_product_name VARCHAR(255);
    DECLARE v_warehouse_name VARCHAR(200);
    DECLARE msg VARCHAR(500);

    -- Проверяем активность товара
    SELECT is_active, name INTO v_product_active, v_product_name
    FROM product
    WHERE id = NEW.product_id;

    IF NOT v_product_active THEN
        SET msg = CONCAT('Cannot move inactive product "', v_product_name, '"');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Проверяем активность склада
    SELECT is_active, name INTO v_warehouse_active, v_warehouse_name
    FROM warehouse
    WHERE id = NEW.warehouse_id;

    IF NOT v_warehouse_active THEN
        SET msg = CONCAT('Cannot move to/from inactive warehouse "', v_warehouse_name, '"');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Проверяем допустимые типы движения
    IF NOT (NEW.movement_type IN ('IN', 'OUT', 'ADJUST')) THEN
        SET msg = CONCAT('Invalid movement type: "', NEW.movement_type, '"');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Проверяем количество
    IF NEW.qty <= 0 THEN
        SET msg = 'Quantity must be greater than 0';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;

    -- Для OUT движений проверяем наличие товара
    IF NEW.movement_type = 'OUT' THEN
        IF GetCurrentStock(NEW.product_id, NEW.warehouse_id) < NEW.qty THEN
            SET msg = CONCAT('Insufficient stock for OUT movement. Product: "',
                v_product_name, '", Available: ',
                GetCurrentStock(NEW.product_id, NEW.warehouse_id));
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
        END IF;
    END IF;
END$$

-- Триггер 11: Проверка при удалении строки прихода
CREATE TRIGGER before_purchase_line_delete
BEFORE DELETE ON purchase_line
FOR EACH ROW
BEGIN
    DECLARE v_invoice_status VARCHAR(20);
    DECLARE msg VARCHAR(500);

    -- Проверяем статус накладной
    SELECT status INTO v_invoice_status
    FROM purchase_invoice
    WHERE id = OLD.purchase_invoice_id;

    IF v_invoice_status != 'DRAFT' THEN
        SET msg = 'Cannot delete line from confirmed or cancelled invoice';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;
END$$

-- Триггер 12: Проверка при удалении строки продажи
CREATE TRIGGER before_sales_line_delete
BEFORE DELETE ON sales_line
FOR EACH ROW
BEGIN
    DECLARE v_invoice_status VARCHAR(20);
    DECLARE msg VARCHAR(500);

    -- Проверяем статус накладной
    SELECT status INTO v_invoice_status
    FROM sales_invoice
    WHERE id = OLD.sales_invoice_id;

    IF v_invoice_status != 'DRAFT' THEN
        SET msg = 'Cannot delete line from confirmed or cancelled invoice';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
    END IF;
END$$

-- Триггер 13: Обновление времени при изменении связи товар-поставщик
CREATE TRIGGER after_product_supplier_update
AFTER UPDATE ON product_supplier
FOR EACH ROW
BEGIN
    -- Обновляем последнюю цену, если она изменилась
    IF OLD.last_purchase_price != NEW.last_purchase_price THEN
        UPDATE product_supplier
        SET last_purchase_price = NEW.last_purchase_price
        WHERE id = NEW.id;
    END IF;
END$$

DELIMITER ;

-- Проверка создания
SELECT 'Triggers created successfully!' as message;

SELECT trigger_name, event_object_table, action_timing, event_manipulation
FROM information_schema.triggers
WHERE trigger_schema = 'warehouse_lab3'
ORDER BY trigger_name;