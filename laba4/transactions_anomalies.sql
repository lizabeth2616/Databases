USE warehouse_lab3;

-- Создаем тестовый продукт для демонстрации аномалий
INSERT INTO product (sku, name, description, category_id, unit_id, default_price, min_stock_level, max_stock_level, is_active)
VALUES 
('TEST-001', 'Test Product for Transactions', 'Product for demonstrating transaction anomalies', 2, 1, 1000.00, 5, 50, TRUE);

SET @test_product_id = LAST_INSERT_ID();

-- Создаем тестовые движения товара
INSERT INTO inventory_movement (product_id, warehouse_id, movement_type, qty, related_type, note)
VALUES 
(@test_product_id, 1, 'IN', 30, 'test', 'Initial stock for transaction tests');

SELECT CONCAT('Тестовый продукт создан. ID: ', @test_product_id, ', SKU: TEST-001') AS 'Подготовка';

-- DIRTY READ (Грязное чтение)
-- Чтение неподтвержденных данных другой транзакции

SELECT '=== СЦЕНАРИЙ 1: DIRTY READ (Грязное чтение) ===' AS '';
SELECT 'Описание: T1 изменяет данные, T2 читает их до commit/rollback T1' AS '';
SELECT 'Уровень изоляции, где возникает: READ UNCOMMITTED' AS '';

-- Шаг 1: Устанавливаем уровень изоляции READ UNCOMMITTED (для демонстрации)
SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- Шаг 2: Транзакция 1 (T1) - начинает изменять цену
START TRANSACTION;
SELECT 'T1: Начинаем транзакцию, изменяем цену товара...' AS '';
UPDATE product SET default_price = 1500.00 WHERE id = @test_product_id;
SELECT CONCAT('T1: Изменили цену на 1500.00 (еще НЕ commit)') AS '';

-- Шаг 3: Транзакция 2 (T2) - читает неподтвержденные данные
START TRANSACTION;
SELECT 'T2: Начинаем транзакцию, читаем цену товара...' AS '';
SELECT id, sku, name, default_price FROM product WHERE id = @test_product_id;
SELECT 'T2: Прочитали цену 1500.00 (это DIRTY READ!)' AS '';
COMMIT;

-- Шаг 4: T1 откатывает изменения
ROLLBACK;
SELECT 'T1: Rollback! Цена возвращается к 1000.00' AS '';

-- Шаг 5: Проверяем окончательное состояние
SELECT 'Итоговое состояние:' AS '';
SELECT id, sku, name, default_price FROM product WHERE id = @test_product_id;
SELECT 'АНОМАЛИЯ: T2 прочитал цену 1500.00, которая никогда не была подтверждена!' AS '';

-- Как избежать Dirty Read: Использовать уровень изоляции READ COMMITTED или выше

SELECT '=== Как избежать DIRTY READ ===' AS '';
SELECT 'Устанавливаем уровень изоляции READ COMMITTED:' AS '';
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Повторяем сценарий с READ COMMITTED
START TRANSACTION;
SELECT 'T1 (READ COMMITTED): Изменяем цену на 1500.00...' AS '';
UPDATE product SET default_price = 1500.00 WHERE id = @test_product_id;

START TRANSACTION;
SELECT 'T2 (READ COMMITTED): Пытаемся прочитать цену...' AS '';
SELECT id, sku, name, default_price FROM product WHERE id = @test_product_id;
SELECT 'T2: Видим старую цену 1000.00 (ждем commit T1)' AS '';
COMMIT;

ROLLBACK;
SELECT 'Dirty Read предотвращен!' AS '';

-- NON-REPEATABLE READ (Неповторяющееся чтение)
-- Повторное чтение тех же данных дает разные результаты

SELECT '=== СЦЕНАРИЙ 2: NON-REPEATABLE READ ===' AS '';
SELECT 'Описание: T1 читает данные, T2 изменяет их, T1 читает снова и видит изменения' AS '';
SELECT 'Уровень изоляции, где возникает: READ COMMITTED' AS '';

-- Восстанавливаем исходную цену
UPDATE product SET default_price = 1000.00 WHERE id = @test_product_id;

-- Уровень изоляции READ COMMITTED
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Шаг 1: T1 начинает транзакцию и читает данные
START TRANSACTION;
SELECT 'T1: Читаем цену товара (первое чтение)...' AS '';
SELECT id, sku, name, default_price FROM product WHERE id = @test_product_id;

-- Шаг 2: T2 изменяет данные и подтверждает
START TRANSACTION;
SELECT 'T2: Изменяем цену на 1200.00 и commit...' AS '';
UPDATE product SET default_price = 1200.00 WHERE id = @test_product_id;
COMMIT;

-- Шаг 3: T1 читает снова
SELECT 'T1: Читаем цену товара снова (второе чтение)...' AS '';
SELECT id, sku, name, default_price FROM product WHERE id = @test_product_id;
SELECT 'T1: Цена изменилась с 1000.00 на 1200.00 в пределах одной транзакции!' AS '';
COMMIT;

SELECT 'АНОМАЛИЯ: Non-Repeatable Read - разные результаты при повторном чтении' AS '';

-- Использовать уровень изоляции REPEATABLE READ

SELECT '=== Как избежать NON-REPEATABLE READ ===' AS '';
SELECT 'Устанавливаем уровень изоляции REPEATABLE READ:' AS '';
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- Восстанавливаем исходную цену
UPDATE product SET default_price = 1000.00 WHERE id = @test_product_id;

-- Повторяем сценарий с REPEATABLE READ
START TRANSACTION;
SELECT 'T1 (REPEATABLE READ): Первое чтение...' AS '';
SELECT id, sku, name, default_price FROM product WHERE id = @test_product_id;

START TRANSACTION;
SELECT 'T2: Изменяем цену на 1200.00...' AS '';
UPDATE product SET default_price = 1200.00 WHERE id = @test_product_id;
COMMIT;

SELECT 'T1 (REPEATABLE READ): Второе чтение...' AS '';
SELECT id, sku, name, default_price FROM product WHERE id = @test_product_id;
SELECT 'T1: Цена осталась 1000.00 (консистентное чтение)!' AS '';
COMMIT;

SELECT 'Non-Repeatable Read предотвращен!' AS '';
SELECT 'Фактическая цена после всех транзакций:' AS '';
SELECT id, sku, name, default_price FROM product WHERE id = @test_product_id;

-- PHANTOM READ (Чтение фантомов)
-- Аномалия: Появление новых строк при повторном выполнении запроса

SELECT '=== СЦЕНАРИЙ 3: PHANTOM READ ===' AS '';
SELECT 'Описание: T1 выполняет запрос, T2 добавляет новые строки, T1 выполняет тот же запрос и видит новые строки' AS '';
SELECT 'Уровень изоляции, где возникает: REPEATABLE READ (для range-запросов)' AS '';

-- Уровень изоляции REPEATABLE READ
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- Шаг 1: T1 читает товары в определенном ценовом диапазоне
START TRANSACTION;
SELECT 'T1: Ищем товары с ценой от 500 до 2000...' AS '';
SELECT id, sku, name, default_price 
FROM product 
WHERE default_price BETWEEN 500 AND 2000 
AND is_active = TRUE
ORDER BY default_price;

-- Шаг 2: T2 добавляет новый товар в этот диапазон
START TRANSACTION;
SELECT 'T2: Добавляем новый товар с ценой 1500...' AS '';
INSERT INTO product (sku, name, description, category_id, unit_id, default_price, is_active)
VALUES 
('PHANTOM-001', 'Phantom Product', 'Product for phantom read demo', 2, 1, 1500.00, TRUE);
COMMIT;

-- Шаг 3: T1 повторяет запрос
SELECT 'T1: Повторяем тот же запрос...' AS '';
SELECT id, sku, name, default_price 
FROM product 
WHERE default_price BETWEEN 500 AND 2000 
AND is_active = TRUE
ORDER BY default_price;

SELECT 'T1: Появилась новая строка (Phantom Read)!' AS '';
COMMIT;

SELECT 'АНОМАЛИЯ: Phantom Read - новые строки появились при повторном выполнении' AS '';

-- Удаляем фантомный продукт
DELETE FROM product WHERE sku = 'PHANTOM-001';

-- Использовать уровень изоляции SERIALIZABLE

SELECT '=== Как избежать PHANTOM READ ===' AS '';
SELECT 'Устанавливаем уровень изоляции SERIALIZABLE:' AS '';
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- Повторяем сценарий с SERIALIZABLE
START TRANSACTION;
SELECT 'T1 (SERIALIZABLE): Первое чтение...' AS '';
SELECT id, sku, name, default_price 
FROM product 
WHERE default_price BETWEEN 500 AND 2000 
AND is_active = TRUE
ORDER BY default_price;

START TRANSACTION;
SELECT 'T2: Пытаемся добавить новый товар...' AS '';
-- В SERIALIZABLE эта вставка будет заблокирована или завершится ошибкой
INSERT INTO product (sku, name, description, category_id, unit_id, default_price, is_active)
VALUES 
('PHANTOM-002', 'Phantom Product 2', 'Product for serializable demo', 2, 1, 1500.00, TRUE);
SELECT 'T2: Вставка заблокирована (ждет завершения T1)...' AS '';

SELECT 'T1 (SERIALIZABLE): Второе чтение...' AS '';
SELECT id, sku, name, default_price 
FROM product 
WHERE default_price BETWEEN 500 AND 2000 
AND is_active = TRUE
ORDER BY default_price;

COMMIT; -- T1 завершается

-- Теперь T2 может завершиться
COMMIT;

SELECT 'Phantom Read предотвращен! T2 ждал завершения T1.' AS '';

-- Удаляем тестовый продукт
DELETE FROM product WHERE sku = 'PHANTOM-002';

-- LOST UPDATE (Потерянное обновление)
-- Аномалия: Две транзакции читают, изменяют и сохраняют данные, одно изменение теряется

SELECT '=== СЦЕНАРИЙ 4: LOST UPDATE ===' AS '';
SELECT 'Описание: Две транзакции читают одни данные, обе изменяют и commit, последнее изменение перезаписывает первое' AS '';

-- Восстанавливаем исходный остаток
DELETE FROM inventory_movement WHERE product_id = @test_product_id;
INSERT INTO inventory_movement (product_id, warehouse_id, movement_type, qty, related_type, note)
VALUES (@test_product_id, 1, 'IN', 30, 'test', 'Reset stock for lost update test');

SELECT 'Начальный остаток:' AS '';
SELECT GetCurrentStock(@test_product_id, 1) as initial_stock;

-- Уровень изоляции READ COMMITTED (по умолчанию)
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Шаг 1: T1 и T2 читают текущий остаток
START TRANSACTION; -- T1
START TRANSACTION; -- T2

SELECT 'T1: Читаем остаток...' AS '';
SELECT GetCurrentStock(@test_product_id, 1) INTO @stock_t1;
SELECT @stock_t1 as stock_t1;

SELECT 'T2: Читаем остаток...' AS '';
SELECT GetCurrentStock(@test_product_id, 1) INTO @stock_t2;
SELECT @stock_t2 as stock_t2;

-- Шаг 2: Обе транзакции изменяют остаток
SELECT 'T1: Продаем 10 единиц...' AS '';
INSERT INTO inventory_movement (product_id, warehouse_id, movement_type, qty, related_type, note)
VALUES (@test_product_id, 1, 'OUT', 10, 'test', 'Sale from T1');

SELECT 'T2: Продаем 5 единиц...' AS '';
INSERT INTO inventory_movement (product_id, warehouse_id, movement_type, qty, related_type, note)
VALUES (@test_product_id, 1, 'OUT', 5, 'test', 'Sale from T2');

-- Шаг 3: Обе транзакции подтверждаются
COMMIT; -- T1
COMMIT; -- T2

-- Шаг 4: Проверяем результат
SELECT 'Итоговый остаток:' AS '';
SELECT GetCurrentStock(@test_product_id, 1) as final_stock;
SELECT 'ОЖИДАЛИ: 30 - 10 - 5 = 15' AS '';
SELECT 'ПОЛУЧИЛИ: Потерянное обновление!' AS '';

-- Как избежать Lost Update: Использовать пессимистическую блокировку или оптимистичную версионность

SELECT '=== Как избежать LOST UPDATE (метод 1: SELECT FOR UPDATE) ===' AS '';

-- Восстанавливаем остаток
DELETE FROM inventory_movement WHERE product_id = @test_product_id 
AND note LIKE '%Sale from%';
INSERT INTO inventory_movement (product_id, warehouse_id, movement_type, qty, related_type, note)
VALUES (@test_product_id, 1, 'IN', 15, 'test', 'Reset for FOR UPDATE test');

SELECT 'Начальный остаток:' AS '';
SELECT GetCurrentStock(@test_product_id, 1) as initial_stock;

START TRANSACTION; -- T1

-- T1 использует SELECT FOR UPDATE для пессимистической блокировки
SELECT 'T1: SELECT FOR UPDATE (блокируем запись)...' AS '';
SELECT GetCurrentStock(@test_product_id, 1) INTO @stock1 FOR UPDATE;

SELECT 'T1: Продаем 10 единиц...' AS '';
INSERT INTO inventory_movement (product_id, warehouse_id, movement_type, qty, related_type, note)
VALUES (@test_product_id, 1, 'OUT', 10, 'test', 'Sale with FOR UPDATE T1');

COMMIT; -- T1

-- T2 начинается после завершения T1
START TRANSACTION; -- T2
SELECT 'T2: Начинаем после T1...' AS '';

SELECT 'T2: Блокируем запись...' AS '';
SELECT GetCurrentStock(@test_product_id, 1) INTO @stock2 FOR UPDATE;

SELECT 'T2: Продаем 5 единиц...' AS '';
INSERT INTO inventory_movement (product_id, warehouse_id, movement_type, qty, related_type, note)
VALUES (@test_product_id, 1, 'OUT', 5, 'test', 'Sale with FOR UPDATE T2');

COMMIT; -- T2

SELECT 'Итоговый остаток:' AS '';
SELECT GetCurrentStock(@test_product_id, 1) as final_stock;
SELECT 'ПРАВИЛЬНО: 30 - 10 - 5 = 15' AS '';
SELECT 'Lost Update предотвращен!' AS '';

-- ДЕМОНСТРАЦИЯ РАЗНЫХ УРОВНЕЙ ИЗОЛЯЦИИ

SELECT '=== СРАВНЕНИЕ УРОВНЕЙ ИЗОЛЯЦИИ ===' AS '';

SELECT 'Уровень изоляции        | Dirty Read | Non-Repeatable Read | Phantom Read | Производительность' AS '';
SELECT '------------------------|------------|---------------------|--------------|-------------------' AS '';
SELECT 'READ UNCOMMITTED        |     ДА     |         ДА          |      ДА      |     Высокая       ' AS '';
SELECT 'READ COMMITTED          |     НЕТ    |         ДА          |      ДА      |     Выше среднего ' AS '';
SELECT 'REPEATABLE READ         |     НЕТ    |         НЕТ         |      ДА*     |     Средняя       ' AS '';
SELECT 'SERIALIZABLE            |     НЕТ    |         НЕТ         |      НЕТ     |     Низкая        ' AS '';
SELECT '' AS '';
SELECT '* - В MySQL REPEATABLE READ предотвращает Phantom Read за счет next-key locks' AS '';

-- ПРАКТИЧЕСКИЙ ПРИМЕР: Безопасное обновление остатков

SELECT '=== ПРАКТИЧЕСКИЙ ПРИМЕР: Безопасное обновление остатков ===' AS '';

-- Создаем процедуру для безопасного уменьшения остатков
DELIMITER $$

DROP PROCEDURE IF EXISTS SafeDecreaseStock $$
CREATE PROCEDURE SafeDecreaseStock(
    IN p_product_id BIGINT,
    IN p_warehouse_id BIGINT,
    IN p_decrease_qty DECIMAL(12,2),
    IN p_reason VARCHAR(255),
    OUT p_success BOOLEAN,
    OUT p_message VARCHAR(500)
)
BEGIN
    DECLARE v_current_stock DECIMAL(12,2);
    DECLARE v_error_message VARCHAR(500);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_success = FALSE;
        GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
        SET p_message = CONCAT('Ошибка: ', COALESCE(v_error_message, 'Unknown error'));
    END;
    
    -- Начинаем транзакцию с уровнем изоляции SERIALIZABLE
    SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    START TRANSACTION;
    
    -- Блокируем запись для обновления
    SELECT GetCurrentStock(p_product_id, p_warehouse_id) INTO v_current_stock FOR UPDATE;
    
    IF v_current_stock >= p_decrease_qty THEN
        -- Выполняем обновление
        INSERT INTO inventory_movement 
            (product_id, warehouse_id, movement_type, qty, related_type, note)
        VALUES 
            (p_product_id, p_warehouse_id, 'OUT', p_decrease_qty, 'safe_decrease', p_reason);
        
        SET p_success = TRUE;
        SET p_message = CONCAT('Остаток уменьшен на ', p_decrease_qty, 
                              '. Новый остаток: ', v_current_stock - p_decrease_qty);
        COMMIT;
    ELSE
        SET p_success = FALSE;
        SET p_message = CONCAT('Недостаточно остатка. Текущий: ', 
                              v_current_stock, ', Требуется: ', p_decrease_qty);
        ROLLBACK;
    END IF;
    
    -- Возвращаем стандартный уровень изоляции
    SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
END $$

DELIMITER ;

-- Тестируем безопасное уменьшение остатков
SELECT 'Тестируем безопасное уменьшение остатков...' AS '';
CALL SafeDecreaseStock(@test_product_id, 1, 3, 'Безопасная продажа', @success, @message);
SELECT @message as 'Результат 1';

CALL SafeDecreaseStock(@test_product_id, 1, 25, 'Продажа большого количества', @success, @message);
SELECT @message as 'Результат 2';

-- ОЧИСТКА: Удаляем тестовые данные
SELECT '=== ОЧИСТКА ТЕСТОВЫХ ДАННЫХ ===' AS '';

-- Удаляем тестовый продукт и все связанные данные
DELETE FROM inventory_movement WHERE product_id = @test_product_id;
DELETE FROM low_stock_alerts WHERE product_id = @test_product_id;
DELETE FROM price_audit_log WHERE product_id = @test_product_id;
DELETE FROM product_supplier WHERE product_id = @test_product_id;
DELETE FROM product WHERE id = @test_product_id;

SELECT 'Тестовые данные удалены.' AS '';

-- ИТОГИ И РЕКОМЕНДАЦИИ
SELECT '=== ИТОГИ И РЕКОМЕНДАЦИИ ===' AS '';
SELECT '1. Уровни изоляции:' AS '';
SELECT '   - READ COMMITTED: Баланс производительности и согласованности' AS '';
SELECT '   - REPEATABLE READ: Для финансовых операций, где важна согласованность' AS '';
SELECT '   - SERIALIZABLE: Для критически важных операций (редко)' AS '';

SELECT '2. Методы предотвращения аномалий:' AS '';
SELECT '   - SELECT FOR UPDATE: Для предотвращения Lost Update' AS '';
SELECT '   - Оптимистичные блокировки (версии): Для high-concurrency систем' AS '';
SELECT '   - Короткие транзакции: Уменьшают время блокировок' AS '';

SELECT '3. Для вашей системы учета:' AS '';
SELECT '   - Использовать REPEATABLE READ для операций с остатками' AS '';
SELECT '   - Использовать SELECT FOR UPDATE при изменении критических данных' AS '';
SELECT '   - Логировать все изменения для аудита' AS '';

SELECT 'Лабораторная работа по транзакциям завершена успешно!' AS '';