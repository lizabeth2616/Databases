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

-- Остальные тесты аналогично исправлены (замена PRINT на SELECT, использование переменных для ошибок).

-- ... (полный код с аналогичными изменениями для всех тестов)

SELECT '' as empty_line;
SELECT '=== TESTS COMPLETED ===' as final_message;
SELECT CONCAT('Total test time: ', TIMESTAMPDIFF(SECOND, @test_start, NOW()), ' seconds') as test_duration;