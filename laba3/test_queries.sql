USE warehouse_lab3;

SET @test_start = NOW();

-- Начало тестов
SELECT CONCAT('=== STARTING TESTS AT: ', @test_start, ' ===') as test_header;
SELECT '' as empty_line;

SELECT '=== TEST 1: FUNCTIONS ===' as test_header;
SELECT '' as empty_line;

-- 1.1 Testing GetCurrentStock function
SELECT '1.1 Testing GetCurrentStock function:' as test_description;
SELECT '' as empty_line;

SELECT
    p.sku,
    p.name AS product_name,
    w.name AS warehouse_name,
    GetCurrentStock(p.id, w.id) AS current_stock
FROM
    product p
    CROSS JOIN warehouse w
WHERE
    p.id IN (1, 3, 5)
    AND w.id = 1
ORDER BY
    p.name;

-- 1.2 Testing GetCurrentStock with non-existent product (error handling)
SELECT '' as empty_line;
SELECT '1.2 Testing GetCurrentStock with non-existent product (should return error):' as test_description;
SELECT '' as empty_line;

-- Используем отдельный блок для обработки ошибок
DELIMITER $$
BEGIN NOT ATOMIC
    DECLARE error_message VARCHAR(500);
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION 
    BEGIN
        GET DIAGNOSTICS CONDITION 1 error_message = MESSAGE_TEXT;
        SELECT CONCAT('Error caught: ', error_message) as error_result;
    END;
    
    SELECT GetCurrentStock(9999, 1) AS test_result;
END$$
DELIMITER ;

-- 1.3 Testing CheckProductAvailability function
SELECT '' as empty_line;
SELECT '1.3 Testing CheckProductAvailability function:' as test_description;
SELECT '' as empty_line;

SELECT
    p.name AS product_name,
    w.name AS warehouse_name,
    GetCurrentStock(p.id, w.id) AS current_stock,
    CheckProductAvailability(p.id, w.id, 2) AS can_sell_2,
    CheckProductAvailability(p.id, w.id, 10) AS can_sell_10
FROM
    product p
    CROSS JOIN warehouse w
WHERE
    p.id IN (1, 3)
    AND w.id IN (1, 2)
ORDER BY
    p.name,
    w.name;

-- 1.4 Testing GetWarehouseTotalValue function
SELECT '' as empty_line;
SELECT '1.4 Testing GetWarehouseTotalValue function:' as test_description;
SELECT '' as empty_line;

SELECT
    w.name AS warehouse_name,
    GetWarehouseTotalValue(w.id) AS total_value
FROM
    warehouse w
ORDER BY
    w.name;

SELECT '' as empty_line;
SELECT '=== TEST 2: PROCEDURES ===' as test_header;
SELECT '' as empty_line;

-- 2.1 Testing ProcessSale (successful sale)
SELECT '2.1 Testing ProcessSale procedure (successful sale):' as test_description;
SELECT '' as empty_line;

SET @sale_id = NULL;
SET @sale_message = NULL;

CALL ProcessSale(
    'Test Company LLC',
    'SALE-TEST-001',
    3,
    2,
    15500.00,
    1,
    'Sales Manager',
    @sale_id,
    @sale_message
);

SELECT @sale_id AS sale_invoice_id, @sale_message AS result_message;

-- Check created records
SELECT '' as empty_line;
SELECT 'Checking created records:' as check_msg;
SELECT '' as empty_line;

SELECT 'Sales Invoice:' as record_type, 
       id, customer_name, invoice_no, total_amount, status
FROM sales_invoice
WHERE id = @sale_id;

SELECT '' as empty_line;
SELECT 'Sales Line:' as record_type,
       id, product_id, qty, unit_price, line_total
FROM sales_line
WHERE sales_invoice_id = @sale_id;

SELECT '' as empty_line;
SELECT 'Inventory Movement:' as record_type,
       id, movement_type, qty, note
FROM inventory_movement
WHERE related_id = @sale_id
    AND related_type = 'sale';

-- 2.2 Testing ProcessSale (insufficient stock - should fail)
SELECT '' as empty_line;
SELECT '2.2 Testing ProcessSale (insufficient stock - should fail):' as test_description;
SELECT '' as empty_line;

SET @fail_sale_id = NULL;
SET @fail_sale_message = NULL;

CALL ProcessSale(
    'Fail Test Corp',
    'SALE-FAIL-001',
    1,
    100,
    56000.00,
    1,
    'Tester',
    @fail_sale_id,
    @fail_sale_message
);

SELECT @fail_sale_id AS sale_invoice_id, @fail_sale_message AS error_message;

-- 2.3 Testing AddPurchaseLine
SELECT '' as empty_line;
SELECT '2.3 Testing AddPurchaseLine procedure:' as test_description;
SELECT '' as empty_line;

-- Создаем черновик накладной
INSERT INTO purchase_invoice (
    supplier_id,
    invoice_no,
    date,
    status,
    received_by
)
VALUES (
    1,
    'PUR-TEST-001',
    CURDATE(),
    'DRAFT',
    'Test Receiver'
);

SET @draft_invoice_id = LAST_INSERT_ID();

SELECT CONCAT('Created draft invoice ID: ', @draft_invoice_id) as info_message;
SELECT '' as empty_line;

SET @purchase_message = NULL;

CALL AddPurchaseLine(
    @draft_invoice_id,
    2,
    3,
    63000.00,
    1,
    @purchase_message
);

SELECT @purchase_message AS result_message;

-- Check purchase records
SELECT '' as empty_line;
SELECT 'Checking purchase records:' as check_msg;
SELECT '' as empty_line;

SELECT 'Purchase Invoice:' as record_type, 
       id, invoice_no, total_amount, status
FROM purchase_invoice
WHERE id = @draft_invoice_id;

SELECT '' as empty_line;
SELECT 'Purchase Line:' as record_type,
       id, product_id, qty, unit_price, line_total
FROM purchase_line
WHERE purchase_invoice_id = @draft_invoice_id;

SELECT '' as empty_line;
SELECT 'Inventory Movement:' as record_type,
       id, movement_type, qty, note
FROM inventory_movement
WHERE related_id = @draft_invoice_id
    AND related_type = 'purchase'
ORDER BY id DESC
LIMIT 1;

-- 2.4 Testing AddPurchaseLine (negative quantity - should fail)
SELECT '' as empty_line;
SELECT '2.4 Testing AddPurchaseLine (negative quantity - should fail):' as test_description;
SELECT '' as empty_line;

SET @neg_purchase_message = NULL;

CALL AddPurchaseLine(
    @draft_invoice_id,
    2,
    -2,
    63000.00,
    1,
    @neg_purchase_message
);

SELECT @neg_purchase_message AS error_message;

-- 2.5 Testing AdjustInventory
SELECT '' as empty_line;
SELECT '2.5 Testing AdjustInventory procedure:' as test_description;
SELECT '' as empty_line;

SET @adjust_message = NULL;

CALL AdjustInventory(
    5,
    1,
    -3,
    'Damage during quality check',
    'Quality Inspector',
    @adjust_message
);

SELECT @adjust_message AS result_message;

-- Check inventory movement
SELECT '' as empty_line;
SELECT 'Checking inventory movement:' as check_msg;
SELECT '' as empty_line;

SELECT id, movement_type, qty, note, created_at
FROM inventory_movement
WHERE product_id = 5
    AND warehouse_id = 1
ORDER BY created_at DESC
LIMIT 3;

-- 2.6 Testing AdjustInventory (negative stock - should fail)
SELECT '' as empty_line;
SELECT '2.6 Testing AdjustInventory (negative stock - should fail):' as test_description;
SELECT '' as empty_line;

SET @neg_adjust_message = NULL;

CALL AdjustInventory(
    5,
    1,
    -100,
    'Test negative adjustment',
    'Tester',
    @neg_adjust_message
);

SELECT @neg_adjust_message AS error_message;

-- 2.7 Testing GetProductStockReport
SELECT '' as empty_line;
SELECT '2.7 Testing GetProductStockReport procedure:' as test_description;
SELECT '' as empty_line;

CALL GetProductStockReport(1, NULL, FALSE);

SELECT '' as empty_line;
SELECT '2.8 Testing GetProductStockReport (only low stock):' as test_description;
SELECT '' as empty_line;

CALL GetProductStockReport(1, NULL, TRUE);

-- 2.8 Testing GetSupplierReport
SELECT '' as empty_line;
SELECT '2.9 Testing GetSupplierReport procedure:' as test_description;
SELECT '' as empty_line;

CALL GetSupplierReport(NULL);

SELECT '' as empty_line;
SELECT '2.10 Testing GetSupplierReport (specific supplier):' as test_description;
SELECT '' as empty_line;

CALL GetSupplierReport(1);

-- 2.9 Testing ConfirmPurchaseInvoice
SELECT '' as empty_line;
SELECT '2.11 Testing ConfirmPurchaseInvoice procedure:' as test_description;
SELECT '' as empty_line;

SET @confirm_message = NULL;

CALL ConfirmPurchaseInvoice(@draft_invoice_id, 'Manager', @confirm_message);

SELECT @confirm_message AS result_message;

-- Check after confirmation
SELECT '' as empty_line;
SELECT 'Checking after confirmation:' as check_msg;
SELECT '' as empty_line;

SELECT 'Purchase Invoice:' as record_type, 
       id, invoice_no, status, total_amount
FROM purchase_invoice
WHERE id = @draft_invoice_id;

SELECT '' as empty_line;
SELECT 'Inventory Movements:' as record_type,
       id, product_id, movement_type, qty, note
FROM inventory_movement
WHERE related_id = @draft_invoice_id
    AND related_type = 'purchase';

SELECT '' as empty_line;
SELECT '=== TEST 3: TRIGGERS ===' as test_header;
SELECT '' as empty_line;

-- 3.1 Testing before_product_update trigger (price reduction >20% - should fail)
SELECT '3.1 Testing price reduction >20% trigger (should fail):' as test_description;
SELECT '' as empty_line;

-- Используем отдельный блок для обработки ошибок
DELIMITER $$
BEGIN NOT ATOMIC
    DECLARE error_msg VARCHAR(500);
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION 
    BEGIN
        GET DIAGNOSTICS CONDITION 1 error_msg = MESSAGE_TEXT;
        SELECT CONCAT('Trigger error: ', error_msg) as error_message;
    END;
    
    UPDATE product
    SET default_price = 40000.00
    WHERE id = 1;
    
    SELECT 'ERROR: Update should have failed!' as warning;
END$$
DELIMITER ;

-- 3.2 Testing before_product_update trigger (price reduction <20% - should succeed)
SELECT '' as empty_line;
SELECT '3.2 Testing price reduction <20% (should succeed):' as test_description;
SELECT '' as empty_line;

DELIMITER $$
BEGIN NOT ATOMIC
    DECLARE error_msg VARCHAR(500);
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION 
    BEGIN
        GET DIAGNOSTICS CONDITION 1 error_msg = MESSAGE_TEXT;
        SELECT CONCAT('Error: ', error_msg) as error_message;
    END;
    
    UPDATE product
    SET default_price = 53000.00
    WHERE id = 1;
    
    SELECT 'Price updated successfully to 53000.00' as success_message;
END$$
DELIMITER ;

-- Check price audit log
SELECT '' as empty_line;
SELECT 'Checking price audit log:' as check_msg;
SELECT '' as empty_line;

SELECT
    p.sku,
    p.name AS product_name,
    pal.old_price,
    pal.new_price,
    pal.change_percent,
    pal.changed_by,
    pal.changed_at
FROM
    price_audit_log pal
    JOIN product p ON pal.product_id = p.id
WHERE
    p.id = 1
ORDER BY
    pal.changed_at DESC;

-- 3.3 Testing before_purchase_line_insert trigger (insert into confirmed invoice - should fail)
SELECT '' as empty_line;
SELECT '3.3 Testing insert into confirmed invoice (should fail):' as test_description;
SELECT '' as empty_line;

-- Создаем подтвержденную накладную
INSERT INTO purchase_invoice (
    supplier_id,
    invoice_no,
    date,
    status,
    received_by
)
VALUES (
    1,
    'PUR-CONFIRMED-001',
    CURDATE(),
    'CONFIRMED',
    'Receiver'
);

SET @confirmed_invoice_id = LAST_INSERT_ID();

DELIMITER $$
BEGIN NOT ATOMIC
    DECLARE error_msg VARCHAR(500);
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION 
    BEGIN
        GET DIAGNOSTICS CONDITION 1 error_msg = MESSAGE_TEXT;
        SELECT CONCAT('Trigger error: ', error_msg) as error_message;
    END;
    
    INSERT INTO purchase_line (
        purchase_invoice_id,
        product_id,
        qty,
        unit_price,
        warehouse_id
    )
    VALUES (@confirmed_invoice_id, 1, 2, 52000.00, 1);
    
    SELECT 'ERROR: Insert should have failed!' as warning;
END$$
DELIMITER ;

-- 3.4 Testing before_sales_line_insert trigger (sale with insufficient stock - should fail)
SELECT '' as empty_line;
SELECT '3.4 Testing sale with insufficient stock in confirmed invoice (should fail):' as test_description;
SELECT '' as empty_line;

INSERT INTO sales_invoice (
    customer_name,
    invoice_no,
    date,
    issued_by,
    status
)
VALUES (
    'Stock Test',
    'SALE-STOCK-001',
    CURDATE(),
    'Tester',
    'CONFIRMED'
);

SET @stock_test_invoice_id = LAST_INSERT_ID();

DELIMITER $$
BEGIN NOT ATOMIC
    DECLARE error_msg VARCHAR(500);
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION 
    BEGIN
        GET DIAGNOSTICS CONDITION 1 error_msg = MESSAGE_TEXT;
        SELECT CONCAT('Trigger error: ', error_msg) as error_message;
    END;
    
    INSERT INTO sales_line (
        sales_invoice_id,
        product_id,
        qty,
        unit_price,
        warehouse_id
    )
    VALUES (@stock_test_invoice_id, 1, 1000, 56000.00, 1);
    
    SELECT 'ERROR: Insert should have failed!' as warning;
END$$
DELIMITER ;

-- 3.5 Testing before_sales_line_insert trigger (draft - no stock check required)
SELECT '' as empty_line;
SELECT '3.5 Testing sale in draft invoice (should succeed without stock check):' as test_description;
SELECT '' as empty_line;

INSERT INTO sales_invoice (
    customer_name,
    invoice_no,
    date,
    issued_by,
    status
)
VALUES (
    'Draft Test',
    'SALE-DRAFT-001',
    CURDATE(),
    'Tester',
    'DRAFT'
);

SET @draft_sale_invoice_id = LAST_INSERT_ID();

DELIMITER $$
BEGIN NOT ATOMIC
    DECLARE error_msg VARCHAR(500);
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION 
    BEGIN
        GET DIAGNOSTICS CONDITION 1 error_msg = MESSAGE_TEXT;
        SELECT CONCAT('Error: ', error_msg) as error_message;
    END;
    
    INSERT INTO sales_line (
        sales_invoice_id,
        product_id,
        qty,
        unit_price,
        warehouse_id
    )
    VALUES (@draft_sale_invoice_id, 1, 1000, 56000.00, 1);
    
    SELECT 'Draft line added successfully (no stock check for drafts)' as success_message;
END$$
DELIMITER ;

-- 3.6 Testing after_sales_invoice_update trigger (draft confirmation - should fail)
SELECT '' as empty_line;
SELECT '3.6 Testing draft confirmation (should fail due to insufficient stock):' as test_description;
SELECT '' as empty_line;

DELIMITER $$
BEGIN NOT ATOMIC
    DECLARE error_msg VARCHAR(500);
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION 
    BEGIN
        GET DIAGNOSTICS CONDITION 1 error_msg = MESSAGE_TEXT;
        SELECT CONCAT('Trigger error: ', error_msg) as error_message;
    END;
    
    UPDATE sales_invoice
    SET status = 'CONFIRMED'
    WHERE id = @draft_sale_invoice_id;
    
    SELECT 'ERROR: Update should have failed!' as warning;
END$$
DELIMITER ;

-- 3.7 Testing after_inventory_movement_insert trigger (low stock alert creation)
SELECT '' as empty_line;
SELECT '3.7 Testing low stock alert creation:' as test_description;
SELECT '' as empty_line;

INSERT INTO inventory_movement (
    product_id,
    warehouse_id,
    movement_type,
    qty,
    related_type,
    note
)
VALUES (
    5,
    1,
    'OUT',
    45,
    'test',
    'Test for low stock alert'
);

SELECT 'Checking low stock alerts:' as check_msg;
SELECT '' as empty_line;

SELECT
    p.name AS product_name,
    w.name AS warehouse_name,
    lsa.current_stock,
    lsa.min_stock_level,
    lsa.alert_date,
    lsa.is_resolved
FROM
    low_stock_alerts lsa
    JOIN product p ON lsa.product_id = p.id
    JOIN warehouse w ON lsa.warehouse_id = w.id
WHERE
    lsa.product_id = 5
    AND lsa.warehouse_id = 1;

-- 3.8 Testing before_purchase_line_delete trigger (delete from confirmed invoice - should fail)
SELECT '' as empty_line;
SELECT '3.8 Testing delete from confirmed invoice (should fail):' as test_description;
SELECT '' as empty_line;

DELIMITER $$
BEGIN NOT ATOMIC
    DECLARE error_msg VARCHAR(500);
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION 
    BEGIN
        GET DIAGNOSTICS CONDITION 1 error_msg = MESSAGE_TEXT;
        SELECT CONCAT('Trigger error: ', error_msg) as error_message;
    END;
    
    DELETE FROM purchase_line
    WHERE purchase_invoice_id = @confirmed_invoice_id;
    
    SELECT 'ERROR: Delete should have failed!' as warning;
END$$
DELIMITER ;

SELECT '' as empty_line;
SELECT '=== TEST 4: ERROR HANDLING ===' as test_header;
SELECT '' as empty_line;

-- 4.1 Testing foreign key violation handling
SELECT '4.1 Testing foreign key violation (should be handled gracefully):' as test_description;
SELECT '' as empty_line;

SET @fk_sale_id = NULL;
SET @fk_sale_message = NULL;

CALL ProcessSale(
    'FK Test',
    'SALE-FK-001',
    9999,
    2,
    100.00,
    1,
    'Tester',
    @fk_sale_id,
    @fk_sale_message
);

SELECT @fk_sale_message AS error_message;

-- 4.2 Testing unique constraint violation handling
SELECT '' as empty_line;
SELECT '4.2 Testing unique constraint violation:' as test_description;
SELECT '' as empty_line;

DELIMITER $$
BEGIN NOT ATOMIC
    DECLARE error_msg VARCHAR(500);
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION 
    BEGIN
        GET DIAGNOSTICS CONDITION 1 error_msg = MESSAGE_TEXT;
        SELECT CONCAT('Constraint violation: ', error_msg) as error_message;
    END;
    
    INSERT INTO purchase_invoice (
        supplier_id,
        invoice_no,
        date,
        status,
        received_by
    )
    VALUES (1, 'PUR-001', CURDATE(), 'DRAFT', 'Test');
    
    SELECT 'ERROR: Insert should have failed!' as warning;
END$$
DELIMITER ;

-- 4.3 Testing inactive product sale (should fail)
SELECT '' as empty_line;
SELECT '4.3 Testing inactive product sale (should fail):' as test_description;
SELECT '' as empty_line;

UPDATE product
SET is_active = FALSE
WHERE id = 7;

SET @inactive_sale_id = NULL;
SET @inactive_sale_message = NULL;

CALL ProcessSale(
    'Inactive Test',
    'SALE-INACTIVE-001',
    7,
    2,
    4500.00,
    2,
    'Tester',
    @inactive_sale_id,
    @inactive_sale_message
);

SELECT @inactive_sale_message AS error_message;

-- Restore activity
UPDATE product
SET is_active = TRUE
WHERE id = 7;

-- 4.4 Testing inactive warehouse (should fail)
SELECT '' as empty_line;
SELECT '4.4 Testing inactive warehouse (should fail):' as test_description;
SELECT '' as empty_line;

UPDATE warehouse
SET is_active = FALSE
WHERE id = 2;

SET @inactive_warehouse_sale_id = NULL;
SET @inactive_warehouse_sale_message = NULL;

CALL ProcessSale(
    'Inactive Warehouse Test',
    'SALE-WAREHOUSE-001',
    7,
    2,
    4500.00,
    2,
    'Tester',
    @inactive_warehouse_sale_id,
    @inactive_warehouse_sale_message
);

SELECT @inactive_warehouse_sale_message AS error_message;

-- Restore activity
UPDATE warehouse
SET is_active = TRUE
WHERE id = 2;

SELECT '' as empty_line;
SELECT '=== TEST 5: COMPLEX SCENARIOS ===' as test_header;
SELECT '' as empty_line;

-- 5.1 Complete cycle: purchase → sale → stock check
SELECT '5.1 Complete cycle: purchase → sale → stock check' as test_description;
SELECT '' as empty_line;

INSERT INTO purchase_invoice (
    supplier_id,
    invoice_no,
    date,
    status,
    received_by
)
VALUES (
    1,
    'PUR-CYCLE-001',
    CURDATE(),
    'DRAFT',
    'Cycle Test'
);

SET @cycle_invoice_id = LAST_INSERT_ID();

SET @cycle_purchase_msg = NULL;

CALL AddPurchaseLine(
    @cycle_invoice_id,
    8,
    10,
    4200.00,
    2,
    @cycle_purchase_msg
);

SELECT @cycle_purchase_msg AS purchase_result;

SET @cycle_confirm_msg = NULL;

CALL ConfirmPurchaseInvoice(@cycle_invoice_id, 'Manager', @cycle_confirm_msg);

SELECT @cycle_confirm_msg AS confirmation_result;

SET @cycle_sale_id = NULL;
SET @cycle_sale_msg = NULL;

CALL ProcessSale(
    'Cycle Customer',
    'SALE-CYCLE-001',
    8,
    5,
    4800.00,
    2,
    'Sales',
    @cycle_sale_id,
    @cycle_sale_msg
);

SELECT @cycle_sale_msg AS sale_result;

SELECT '' as empty_line;
SELECT 'Final stock check:' as check_msg;
SELECT '' as empty_line;

SELECT
    p.name AS product_name,
    w.name AS warehouse_name,
    GetCurrentStock(p.id, w.id) AS final_stock,
    p.min_stock_level,
    p.max_stock_level
FROM
    product p
    CROSS JOIN warehouse w
WHERE
    p.id = 8
    AND w.id = 2;

-- 5.2 Adjustment with alert creation and resolution
SELECT '' as empty_line;
SELECT '5.2 Adjustment with alert creation and resolution:' as test_description;
SELECT '' as empty_line;

INSERT INTO inventory_movement (
    product_id,
    warehouse_id,
    movement_type,
    qty,
    related_type,
    note
)
VALUES (
    6,
    1,
    'OUT',
    35,
    'test',
    'Create low stock situation'
);

SELECT 'Low stock alert created:' as check_msg;
SELECT '' as empty_line;

SELECT *
FROM low_stock_alerts
WHERE product_id = 6
    AND warehouse_id = 1
ORDER BY alert_date DESC
LIMIT 1;

-- Restore stock (should resolve alert)
INSERT INTO inventory_movement (
    product_id,
    warehouse_id,
    movement_type,
    qty,
    related_type,
    note
)
VALUES (6, 1, 'IN', 40, 'test', 'Resolve low stock');

SELECT '' as empty_line;
SELECT 'Alert should be resolved:' as check_msg;
SELECT '' as empty_line;

SELECT *
FROM low_stock_alerts
WHERE product_id = 6
    AND warehouse_id = 1
ORDER BY alert_date DESC
LIMIT 1;

SELECT '' as empty_line;
SELECT '=== TESTS COMPLETED ===' as final_message;
SELECT CONCAT('Total test time: ', TIMESTAMPDIFF(SECOND, @test_start, NOW()), ' seconds') as test_duration;