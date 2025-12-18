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

    -- Проверяем статус накладной
    SELECT status INTO v_invoice_status
    FROM purchase_invoice
    WHERE id = NEW.purchase_invoice_id;

    IF v_invoice_status != 'DRAFT' THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot add line to confirmed or cancelled invoice';
    END IF;

    -- Проверяем активность товара
    SELECT is_active, name INTO v_product_active, v_product_name
    FROM product
    WHERE id = NEW.product_id;

    IF NOT v_product_active THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = CONCAT('Cannot add inactive product "', v_product_name, '" to purchase');
    END IF;

    -- Проверяем активность склада
    SELECT is_active, name INTO v_warehouse_active, v_warehouse_name
    FROM warehouse
    WHERE id = NEW.warehouse_id;

    IF NOT v_warehouse_active THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = CONCAT('Cannot add purchase to inactive warehouse "', v_warehouse_name, '"');
    END IF;

    -- Бизнес-правило: количество должно быть положительным
    IF NEW.qty <= 0 THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Quantity must be greater than 0';
    END IF;

    -- Бизнес-правило: цена должна быть положительной
    IF NEW.unit_price <= 0 THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Price must be greater than 0';
    END IF;

    -- Проверяем максимальный уровень запасов
    SELECT max_stock_level INTO v_max_stock_level
    FROM product
    WHERE id = NEW.product_id;

    IF v_max_stock_level IS NOT NULL THEN
        -- Получаем текущий остаток
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
        ) INTO v_current_stock
        FROM inventory_movement
        WHERE product_id = NEW.product_id
          AND warehouse_id = NEW.warehouse_id;
        
        IF (v_current_stock + NEW.qty) > v_max_stock_level THEN 
            SET v_stock_msg = CONCAT('Exceeds maximum stock level for product "',
                v_product_name, '". Current: ', v_current_stock,
                ', Adding: ', NEW.qty, ', Max: ', v_max_stock_level);
            
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_stock_msg;
        END IF;
    END IF;
END$$

DELIMITER ;

-- Триггер 2: Обновление суммы накладной после вставки строки прихода
DELIMITER $$

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

DELIMITER ;

-- Триггер 3: Проверка перед обновлением приходной накладной
DELIMITER $$

CREATE TRIGGER before_purchase_invoice_update 
BEFORE UPDATE ON purchase_invoice 
FOR EACH ROW 
BEGIN 
    -- Не позволяем изменять подтвержденные или отмененные накладные
    IF OLD.status != 'DRAFT' AND NEW.status != OLD.status THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot change status of confirmed or cancelled invoice';
    END IF;

    -- Проверяем, не пытаются ли изменить поставщика у подтвержденной накладной
    IF OLD.status != 'DRAFT' AND NEW.supplier_id != OLD.supplier_id THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot change supplier for confirmed or cancelled invoice';
    END IF;
END$$

DELIMITER ;

-- Триггер 4: Автоматическое создание движения товара при подтверждении накладной
DELIMITER $$

CREATE TRIGGER after_purchase_invoice_update 
AFTER UPDATE ON purchase_invoice 
FOR EACH ROW 
BEGIN 
    DECLARE v_supplier_name VARCHAR(255);
    DECLARE v_note VARCHAR(500);

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
            lsa.resolved_by = 'Purchase confirmation'
        WHERE pl.purchase_invoice_id = NEW.id
            AND lsa.is_resolved = FALSE;
    END IF;
END$$

DELIMITER ;


-- ТРИГГЕРЫ ДЛЯ РАСХОДНЫХ НАКЛАДНЫХ:

-- Триггер 5: Проверка данных перед вставкой строки продажи
DELIMITER $$

CREATE TRIGGER before_sales_line_insert 
BEFORE INSERT ON sales_line 
FOR EACH ROW 
BEGIN 
    DECLARE v_invoice_status VARCHAR(20);
    DECLARE v_product_active BOOLEAN;
    DECLARE v_warehouse_active BOOLEAN;
    DECLARE v_current_stock DECIMAL(12, 2);
    DECLARE v_product_name VARCHAR(255);
    DECLARE v_warehouse_name VARCHAR(200);
    DECLARE v_error_msg VARCHAR(500);

    -- Проверяем статус накладной
    SELECT status INTO v_invoice_status
    FROM sales_invoice
    WHERE id = NEW.sales_invoice_id;

    -- Если накладная не в черновике, проверяем остатки
    IF v_invoice_status != 'DRAFT' THEN 
        -- Получаем текущий остаток
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
        ) INTO v_current_stock
        FROM inventory_movement
        WHERE product_id = NEW.product_id
          AND warehouse_id = NEW.warehouse_id;

        -- Проверяем достаточность остатка
        IF v_current_stock < NEW.qty THEN 
            -- Получаем названия для сообщения об ошибке
            SELECT name INTO v_product_name
            FROM product
            WHERE id = NEW.product_id;

            SELECT name INTO v_warehouse_name
            FROM warehouse
            WHERE id = NEW.warehouse_id;

            SET v_error_msg = CONCAT('Insufficient stock for product "',
                v_product_name, '" in warehouse "', v_warehouse_name,
                '". Available: ', v_current_stock, ', Required: ', NEW.qty);
            
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_error_msg;
        END IF;

        -- Проверяем активность товара
        SELECT is_active INTO v_product_active
        FROM product
        WHERE id = NEW.product_id;

        IF NOT v_product_active THEN 
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot sell inactive product';
        END IF;

        -- Проверяем активность склада
        SELECT is_active INTO v_warehouse_active
        FROM warehouse
        WHERE id = NEW.warehouse_id;

        IF NOT v_warehouse_active THEN 
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot sell from inactive warehouse';
        END IF;
    END IF;

    -- Бизнес-правило: количество должно быть положительным
    IF NEW.qty <= 0 THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Quantity must be greater than 0';
    END IF;

    -- Бизнес-правило: цена должна быть положительной
    IF NEW.unit_price <= 0 THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Price must be greater than 0';
    END IF;
END$$

DELIMITER ;

-- Триггер 6: Обновление суммы накладной после вставки строки продажи
DELIMITER $$

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

DELIMITER ;

-- Триггер 7: Проверка перед обновлением расходной накладной
DELIMITER $$

CREATE TRIGGER before_sales_invoice_update 
BEFORE UPDATE ON sales_invoice 
FOR EACH ROW 
BEGIN 
    DECLARE v_stock_check INT;
    
    -- Не позволяем изменять подтвержденные или отмененные накладные
    IF OLD.status != 'DRAFT' AND NEW.status != OLD.status THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot change status of confirmed, shipped or cancelled invoice';
    END IF;

    -- Проверяем, достаточно ли товара при подтверждении накладной
    IF OLD.status = 'DRAFT' AND NEW.status = 'CONFIRMED' THEN 
        -- Проверяем остатки для всех строк накладной
        SELECT COUNT(*) INTO v_stock_check
        FROM sales_line sl
        WHERE sl.sales_invoice_id = NEW.id
          AND (
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
            )
            FROM inventory_movement
            WHERE product_id = sl.product_id
              AND warehouse_id = sl.warehouse_id
          ) < sl.qty;
        
        IF v_stock_check > 0 THEN 
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot confirm invoice: insufficient stock for some products';
        END IF;
    END IF;
END$$

DELIMITER ;

-- Триггер 8: Автоматическое создание движения товара при подтверждении накладной
DELIMITER $$

CREATE TRIGGER after_sales_invoice_update 
AFTER UPDATE ON sales_invoice 
FOR EACH ROW 
BEGIN 
    DECLARE v_current_stock DECIMAL(12, 2);
    DECLARE v_min_stock_level DECIMAL(12, 2);
    
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
            CONCAT('Sale to customer ', NEW.customer_name, ', invoice ', NEW.invoice_no)
        FROM sales_line sl
        WHERE sl.sales_invoice_id = NEW.id;

        -- Проверяем и создаем алерты по низкому остатку
        INSERT INTO low_stock_alerts (
            product_id,
            warehouse_id,
            current_stock,
            min_stock_level
        )
        SELECT 
            sl.product_id,
            sl.warehouse_id,
            (SELECT COALESCE(
                SUM(
                    CASE movement_type
                        WHEN 'IN' THEN qty
                        WHEN 'OUT' THEN -qty
                        WHEN 'ADJUST' THEN qty
                        ELSE 0
                    END
                ),
                0
            )
            FROM inventory_movement
            WHERE product_id = sl.product_id
              AND warehouse_id = sl.warehouse_id),
            p.min_stock_level
        FROM sales_line sl
        JOIN product p ON sl.product_id = p.id
        WHERE sl.sales_invoice_id = NEW.id
          AND (SELECT COALESCE(
                SUM(
                    CASE movement_type
                        WHEN 'IN' THEN qty
                        WHEN 'OUT' THEN -qty
                        WHEN 'ADJUST' THEN qty
                        ELSE 0
                    END
                ),
                0
            )
            FROM inventory_movement
            WHERE product_id = sl.product_id
              AND warehouse_id = sl.warehouse_id) <= p.min_stock_level
        ON DUPLICATE KEY UPDATE 
            current_stock = VALUES(current_stock),
            alert_date = NOW(),
            is_resolved = FALSE,
            resolved_at = NULL;

    END IF;

    -- Если накладная отменена, удаляем связанные движения товара
    IF NEW.status = 'CANCELLED' AND OLD.status != 'CANCELLED' THEN
        DELETE FROM inventory_movement
        WHERE related_type = 'sale'
            AND related_id = NEW.id;

        -- Удаляем алерты, созданные этой продажей
        DELETE FROM low_stock_alerts
        WHERE product_id IN (
            SELECT product_id
            FROM sales_line
            WHERE sales_invoice_id = NEW.id
        );
    END IF;
END$$

DELIMITER ;

-- ТРИГГЕРЫ ДЛЯ ТОВАРОВ

-- Триггер 9: Проверка изменения цены (ограничение на снижение более чем на 20%)
DELIMITER $$

CREATE TRIGGER before_product_update 
BEFORE UPDATE ON product 
FOR EACH ROW 
BEGIN 
    DECLARE v_reduction DECIMAL(5, 2);
    DECLARE v_error_msg VARCHAR(500);
    
    -- Проверяем, не снижается ли цена более чем на 20%
    IF NEW.default_price < OLD.default_price * 0.8 THEN 
        SET v_reduction = ROUND((1 - NEW.default_price / OLD.default_price) * 100, 2);
        SET v_error_msg = CONCAT('Cannot reduce price by more than 20%. ',
            'Current price: ', OLD.default_price,
            ', New price: ', NEW.default_price,
            ', Reduction: ', v_reduction, '%');
        
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = v_error_msg;
    END IF;

    -- Проверяем, что минимальный уровень запасов не отрицательный
    IF NEW.min_stock_level < 0 THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Minimum stock level cannot be negative';
    END IF;

    -- Проверяем, что максимальный уровень запасов больше минимального (если указан)
    IF NEW.max_stock_level IS NOT NULL AND NEW.max_stock_level <= NEW.min_stock_level THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Maximum stock level must be greater than minimum stock level';
    END IF;

    -- Если товар деактивируется, проверяем нет ли его в активных заказах
    IF OLD.is_active = TRUE AND NEW.is_active = FALSE THEN 
        -- Проверяем активные приходные накладные
        IF EXISTS (
            SELECT 1
            FROM purchase_line pl
            JOIN purchase_invoice pi ON pl.purchase_invoice_id = pi.id
            WHERE pl.product_id = NEW.id
                AND pi.status = 'DRAFT'
        ) THEN 
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot deactivate product: it exists in draft purchase invoices';
        END IF;

        -- Проверяем активные продажи
        IF EXISTS (
            SELECT 1
            FROM sales_line sl
            JOIN sales_invoice si ON sl.sales_invoice_id = si.id
            WHERE sl.product_id = NEW.id
                AND si.status = 'DRAFT'
        ) THEN 
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot deactivate product: it exists in draft sales invoices';
        END IF;
    END IF;
END$$

DELIMITER ;

-- Триггер 10: Аудит изменений цен
DELIMITER $$

CREATE TRIGGER after_product_update 
AFTER UPDATE ON product 
FOR EACH ROW 
BEGIN 
    DECLARE v_change_percent DECIMAL(5, 2);

    -- Логируем только если цена изменилась
    IF OLD.default_price != NEW.default_price THEN 
        -- Вычисляем процент изменения
        SET v_change_percent = ROUND(((NEW.default_price - OLD.default_price) / OLD.default_price) * 100, 2);

        -- Записываем в таблицу аудита
        INSERT INTO price_audit_log (
            product_id,
            old_price,
            new_price,
            change_percent,
            changed_by,
            reason
        )
        VALUES (
            NEW.id,
            OLD.default_price,
            NEW.default_price,
            v_change_percent,
            USER(),
            'Price update'
        );
    END IF;

    -- Если товар деактивируется, помечаем алерты как решенные
    IF OLD.is_active = TRUE AND NEW.is_active = FALSE THEN
        UPDATE low_stock_alerts
        SET is_resolved = TRUE,
            resolved_at = NOW(),
            resolved_by = 'Product deactivation'
        WHERE product_id = NEW.id
            AND is_resolved = FALSE;
    END IF;
END$$

DELIMITER ;

-- ТРИГГЕРЫ ДЛЯ ДВИЖЕНИЯ ТОВАРОВ

-- Триггер 11: Проверка перед вставкой движения товара
DELIMITER $$

CREATE TRIGGER before_inventory_movement_insert 
BEFORE INSERT ON inventory_movement 
FOR EACH ROW 
BEGIN 
    DECLARE v_product_active BOOLEAN;
    DECLARE v_warehouse_active BOOLEAN;
    DECLARE v_current_stock DECIMAL(12, 2);
    DECLARE v_error_msg VARCHAR(500);

    -- Проверяем активность товара
    SELECT is_active INTO v_product_active
    FROM product
    WHERE id = NEW.product_id;

    IF NOT v_product_active AND NEW.movement_type != 'ADJUST' THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot add movement for inactive product';
    END IF;

    -- Проверяем активность склада
    SELECT is_active INTO v_warehouse_active
    FROM warehouse
    WHERE id = NEW.warehouse_id;

    IF NOT v_warehouse_active THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot add movement to inactive warehouse';
    END IF;

    -- Получаем текущий остаток
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
    ) INTO v_current_stock
    FROM inventory_movement
    WHERE product_id = NEW.product_id
      AND warehouse_id = NEW.warehouse_id;

    -- Для движения OUT проверяем достаточность остатка
    IF NEW.movement_type = 'OUT' THEN 
        IF v_current_stock < NEW.qty THEN 
            SET v_error_msg = CONCAT('Insufficient stock for movement. Available: ',
                v_current_stock, ', Required: ', NEW.qty);
            
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_error_msg;
        END IF;
    END IF;

    -- Для движения ADJUST проверяем, не уйдет ли остаток в отрицательное
    IF NEW.movement_type = 'ADJUST' THEN 
        IF (v_current_stock + NEW.qty) < 0 THEN 
            SET v_error_msg = CONCAT('Cannot adjust. Would result in negative stock: ',
                (v_current_stock + NEW.qty));
            
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_error_msg;
        END IF;
    END IF;
END$$

DELIMITER ;

-- Триггер 12: Проверка остатка после движения товара и создание алертов
DELIMITER $$

CREATE TRIGGER after_inventory_movement_insert 
AFTER INSERT ON inventory_movement 
FOR EACH ROW 
BEGIN 
    DECLARE v_current_stock DECIMAL(12, 2);
    DECLARE v_min_stock_level DECIMAL(12, 2);
    DECLARE v_product_active BOOLEAN;

    -- Проверяем активность товара
    SELECT is_active INTO v_product_active
    FROM product
    WHERE id = NEW.product_id;

    IF v_product_active THEN 
        -- Получаем текущий остаток
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
        ) INTO v_current_stock
        FROM inventory_movement
        WHERE product_id = NEW.product_id
          AND warehouse_id = NEW.warehouse_id;

        -- Получаем минимальный уровень запасов
        SELECT min_stock_level INTO v_min_stock_level
        FROM product
        WHERE id = NEW.product_id;

        -- Если остаток ниже минимального уровня, создаем алерт
        IF v_current_stock <= v_min_stock_level THEN
            INSERT INTO low_stock_alerts (
                product_id,
                warehouse_id,
                current_stock,
                min_stock_level
            )
            VALUES (
                NEW.product_id,
                NEW.warehouse_id,
                v_current_stock,
                v_min_stock_level
            )
            ON DUPLICATE KEY UPDATE 
                current_stock = v_current_stock,
                alert_date = NOW(),
                is_resolved = FALSE,
                resolved_at = NULL;
        ELSE 
            -- Если остаток выше минимального уровня, помечаем алерты как решенные
            UPDATE low_stock_alerts
            SET is_resolved = TRUE,
                resolved_at = NOW(),
                resolved_by = 'Stock replenished'
            WHERE product_id = NEW.product_id
                AND warehouse_id = NEW.warehouse_id
                AND is_resolved = FALSE;
        END IF;
    END IF;
END$$

DELIMITER ;

-- ТРИГГЕР ДЛЯ УДАЛЕНИЯ СТРОК НАКЛАДНЫХ

-- Триггер 13: Проверка перед удалением строки прихода
DELIMITER $$

CREATE TRIGGER before_purchase_line_delete 
BEFORE DELETE ON purchase_line 
FOR EACH ROW 
BEGIN 
    DECLARE v_invoice_status VARCHAR(20);

    -- Проверяем статус накладной
    SELECT status INTO v_invoice_status
    FROM purchase_invoice
    WHERE id = OLD.purchase_invoice_id;

    IF v_invoice_status != 'DRAFT' THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot delete line from confirmed or cancelled invoice';
    END IF;
END$$

DELIMITER ;

-- Триггер 14: Проверка перед удалением строки продажи
DELIMITER $$

CREATE TRIGGER before_sales_line_delete 
BEFORE DELETE ON sales_line 
FOR EACH ROW 
BEGIN 
    DECLARE v_invoice_status VARCHAR(20);

    -- Проверяем статус накладной
    SELECT status INTO v_invoice_status
    FROM sales_invoice
    WHERE id = OLD.sales_invoice_id;

    IF v_invoice_status != 'DRAFT' THEN 
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot delete line from confirmed, shipped or cancelled invoice';
    END IF;
END$$

DELIMITER ;

-- ТРИГГЕР ДЛЯ ОБНОВЛЕНИЯ СВЯЗИ ТОВАР-ПОСТАВЩИК

-- Триггер 15: Обновление последней цены при изменении связи товар-поставщик
DELIMITER $$

CREATE TRIGGER after_product_supplier_update 
AFTER UPDATE ON product_supplier 
FOR EACH ROW 
BEGIN 
    DECLARE v_change_percent DECIMAL(5, 2);
    
    -- Логируем изменение цены у поставщика
    IF OLD.last_purchase_price != NEW.last_purchase_price THEN
        -- Вычисляем процент изменения
        IF OLD.last_purchase_price = 0 THEN
            SET v_change_percent = 100.00;
        ELSE
            SET v_change_percent = ROUND(((NEW.last_purchase_price - OLD.last_purchase_price) / OLD.last_purchase_price) * 100, 2);
        END IF;
        
        INSERT INTO price_audit_log (
            product_id,
            old_price,
            new_price,
            change_percent,
            changed_by,
            reason
        )
        VALUES (
            NEW.product_id,
            OLD.last_purchase_price,
            NEW.last_purchase_price,
            v_change_percent,
            USER(),
            'Supplier price update'
        );
    END IF;
END$$

DELIMITER ;


-- ПРОВЕРКА СОЗДАНИЯ ТРИГГЕРОВ

SELECT 'Triggers created successfully:' as message;
SELECT '' as empty_line;
SELECT 'FOR PURCHASE INVOICES (4):' as header;
SELECT '  1. before_purchase_line_insert' as trigger_name;
SELECT '  2. after_purchase_line_insert' as trigger_name;
SELECT '  3. before_purchase_invoice_update' as trigger_name;
SELECT '  4. after_purchase_invoice_update' as trigger_name;
SELECT '' as empty_line;
SELECT 'FOR SALES INVOICES (4):' as header;
SELECT '  1. before_sales_line_insert' as trigger_name;
SELECT '  2. after_sales_line_insert' as trigger_name;
SELECT '  3. before_sales_invoice_update' as trigger_name;
SELECT '  4. after_sales_invoice_update' as trigger_name;
SELECT '' as empty_line;
SELECT 'FOR PRODUCTS (2):' as header;
SELECT '  1. before_product_update' as trigger_name;
SELECT '  2. after_product_update' as trigger_name;
SELECT '' as empty_line;
SELECT 'FOR INVENTORY MOVEMENTS (2):' as header;
SELECT '  1. before_inventory_movement_insert' as trigger_name;
SELECT '  2. after_inventory_movement_insert' as trigger_name;
SELECT '' as empty_line;
SELECT 'FOR DELETE OPERATIONS (2):' as header;
SELECT '  1. before_purchase_line_delete' as trigger_name;
SELECT '  2. before_sales_line_delete' as trigger_name;
SELECT '' as empty_line;
SELECT 'FOR PRODUCT-SUPPLIER (1):' as header;
SELECT '  1. after_product_supplier_update' as trigger_name;
SELECT '======================================================================' as separator;
SELECT 'Total triggers: 15' as total;
SELECT '======================================================================' as separator;
SELECT '' as empty_line;
SELECT 'Checking created triggers...' as check_msg;
SELECT trigger_name, event_object_table, action_timing, event_manipulation 
FROM information_schema.triggers 
WHERE trigger_schema = 'warehouse_lab3'
ORDER BY trigger_name;