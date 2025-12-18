@echo off
echo Запуск лабораторной работы №3 и №4...
cd /d "C:\Users\84835\Desktop\Laba3VSCode"

echo ========================================
echo 1. Проверяю наличие необходимых файлов...
dir *.sql

echo.
echo ========================================
echo 2. ПОДГОТОВКА БАЗЫ ДАННЫХ
echo ========================================

echo 2.1. Создаю базу warehouse_lab3...
C:\xampp\mysql\bin\mysql.exe -u root -e "DROP DATABASE IF EXISTS warehouse_lab3; CREATE DATABASE warehouse_lab3 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; SELECT 'База создана' as status;"

echo.
echo ========================================
echo 3. ВЫПОЛНЕНИЕ ЛАБОРАТОРНОЙ РАБОТЫ №3
echo ========================================

echo.
echo 3.1. Создание структуры базы данных...
if exist "create_database.sql" (
    echo Выполняю create_database.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < create_database.sql > lab3_structure_result.txt 2>&1
    if errorlevel 1 (
        echo Ошибка при создании структуры БД
        type lab3_structure_result.txt
    ) else (
        echo Структура БД создана успешно
    )
) else (
    echo Файл create_database.sql не найден!
    pause
    exit /b 1
)

echo.
echo 3.2. Создание функций и процедур...
if exist "procedures_functions.sql" (
    echo Выполняю procedures_functions.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < procedures_functions.sql > lab3_procedures_result.txt 2>&1
    if errorlevel 1 (
        echo Ошибка при создании процедур
        type lab3_procedures_result.txt
    ) else (
        echo Функции и процедуры созданы успешно
    )
) else (
    echo Файл procedures_functions.sql не найден!
)

echo.
echo 3.3. Создание триггеров...
if exist "triggers.sql" (
    echo Выполняю triggers.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < triggers.sql > lab3_triggers_result.txt 2>&1
    if errorlevel 1 (
        echo Ошибка при создании триггеров
        type lab3_triggers_result.txt
    ) else (
        echo Триггеры созданы успешно
    )
) else (
    echo Файл triggers.sql не найден!
)

echo.
echo 3.4. Тестирование функционала...
if exist "test_queries.sql" (
    echo Выполняю test_queries.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < test_queries.sql > lab3_test_result.txt 2>&1
    if errorlevel 1 (
        echo Ошибка при тестировании
        type lab3_test_result.txt
    ) else (
        echo Тестирование выполнено успешно
    )
) else (
    echo Файл test_queries.sql не найден!
)

echo.
echo ========================================
echo 4. ПРОВЕРКА РЕЗУЛЬТАТОВ ЛАБЫ №3
echo ========================================

echo 4.1 Список всех таблиц:
C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 -e "SHOW TABLES;"

echo.
echo 4.2 Количество таблиц:
C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 -e "SELECT COUNT(*) as total_tables FROM information_schema.tables WHERE table_schema = 'warehouse_lab3';"

echo.
echo 4.3 Проверка данных (первые 3 товара):
C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 -e "SELECT id, sku, name FROM product LIMIT 3;"

echo.
echo 4.4 Проверка функций и процедур:
C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 -e "SELECT routine_name, routine_type FROM information_schema.routines WHERE routine_schema = 'warehouse_lab3' ORDER BY routine_type, routine_name;"

echo.
echo 4.5 Проверка триггеров:
C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 -e "SELECT trigger_name, event_object_table, action_timing, event_manipulation FROM information_schema.triggers WHERE trigger_schema = 'warehouse_lab3' ORDER BY trigger_name;"

echo.
echo ========================================
echo 5. ВЫПОЛНЕНИЕ ЛАБОРАТОРНОЙ РАБОТЫ №4
echo ========================================

echo.
echo 5.1. Часть 1: Индексы
echo ========================================
if exist "indexes.sql" (
    echo Выполняю indexes.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < indexes.sql > lab4_indexes_result.txt 2>&1
    if errorlevel 1 (
        echo Ошибка при выполнении indexes.sql
        type lab4_indexes_result.txt
    ) else (
        echo Часть 1 (индексы) выполнена успешно!
        echo Результаты сохранены в lab4_indexes_result.txt
    )
) else (
    echo Файл indexes.sql не найден!
)

echo.
echo 5.2. Часть 2: Анализ производительности
echo ========================================
if exist "explain_analysis.sql" (
    echo Выполняю explain_analysis.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < explain_analysis.sql > lab4_explain_result.txt 2>&1
    if errorlevel 1 (
        echo Ошибка при выполнении explain_analysis.sql
        type lab4_explain_result.txt
    ) else (
        echo Часть 2 (анализ производительности) выполнена успешно!
        echo Результаты сохранены в lab4_explain_result.txt
    )
) else (
    echo Файл explain_analysis.sql не найден!
)

echo.
echo 5.3. Часть 3: Транзакции и аномалии
echo ========================================
if exist "transactions_anomalies.sql" (
    echo Выполняю transactions_anomalies.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < transactions_anomalies.sql > lab4_transactions_result.txt 2>&1
    if errorlevel 1 (
        echo Ошибка при выполнении transactions_anomalies.sql
        type lab4_transactions_result.txt
    ) else (
        echo Часть 3 (транзакции) выполнена успешно!
        echo Результаты сохранены в lab4_transactions_result.txt
    )
) else (
    echo Файл transactions_anomalies.sql не найден!
)

echo.
echo ========================================
echo 6. ПРОВЕРКА РЕЗУЛЬТАТОВ ЛАБЫ №4
echo ========================================

echo.
echo 6.1 Список созданных индексов:
C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 -e "
SELECT 
    CONCAT(table_name, '.', index_name) as 'Индекс',
    GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR ', ') as 'Колонки',
    CASE non_unique 
        WHEN 0 THEN 'UNIQUE' 
        ELSE 'NON-UNIQUE' 
    END as 'Тип',
    index_type as 'Вид индекса'
FROM information_schema.statistics 
WHERE table_schema = 'warehouse_lab3' 
    AND index_name NOT LIKE 'PRIMARY'
GROUP BY table_name, index_name, non_unique, index_type
ORDER BY table_name, index_name;
"

echo.
echo 6.2 Статистика по индексам:
C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 -e "
SELECT 
    COUNT(*) as 'Всего индексов',
    COUNT(DISTINCT table_name) as 'Таблиц с индексами',
    SUM(CASE WHEN non_unique = 0 THEN 1 ELSE 0 END) as 'Уникальных индексов',
    SUM(CASE WHEN index_type = 'BTREE' THEN 1 ELSE 0 END) as 'B-tree индексов'
FROM information_schema.statistics 
WHERE table_schema = 'warehouse_lab3';
"

echo.
echo 6.3 Уровни изоляции транзакций:
C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 -e "
SELECT @@global.transaction_isolation as 'Глобальный уровень изоляции',
       @@session.transaction_isolation as 'Сессионный уровень изоляции';
"

echo.
echo 6.4 Общие итоги по базе данных:
C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 -e "
SELECT 
    (SELECT COUNT(*) FROM product) as 'Всего товаров',
    (SELECT COUNT(*) FROM product WHERE is_active = TRUE) as 'Активных товаров',
    (SELECT COUNT(*) FROM inventory_movement) as 'Движений товаров',
    (SELECT COUNT(*) FROM sales_invoice WHERE status = 'CONFIRMED') as 'Подтвержденных продаж',
    (SELECT COUNT(*) FROM purchase_invoice WHERE status = 'CONFIRMED') as 'Подтвержденных закупок',
    (SELECT COUNT(*) FROM low_stock_alerts WHERE is_resolved = FALSE) as 'Активных алертов'
FROM DUAL;
"

echo.
echo ========================================
echo 7. ФОРМИРОВАНИЕ ИТОГОВОГО ОТЧЕТА
echo ========================================

echo Создаю итоговый отчет...
(
echo ========================================
echo ИТОГОВЫЙ ОТЧЕТ ПО ЛАБОРАТОРНЫМ РАБОТАМ №3 и №4
echo ========================================
echo Дата выполнения: %date% %time%
echo Папка: %cd%
echo.
echo ЛАБОРАТОРНАЯ РАБОТА №3
echo ------------------
echo 1. Структура БД: 
if exist lab3_structure_result.txt (
    find /c "Database created successfully" lab3_structure_result.txt
) else (
    echo Файл результатов не найден
)
echo.
echo 2. Функции и процедуры: 
if exist lab3_procedures_result.txt (
    find /c "Functions and procedures created" lab3_procedures_result.txt
) else (
    echo Файл результатов не найден
)
echo.
echo 3. Триггеры: 
if exist lab3_triggers_result.txt (
    find /c "Triggers created successfully" lab3_triggers_result.txt
) else (
    echo Файл результатов не найден
)
echo.
echo 4. Тестирование: 
if exist lab3_test_result.txt (
    find /c "TESTS COMPLETED" lab3_test_result.txt
) else (
    echo Файл результатов не найден
)
echo.
echo ЛАБОРАТОРНАЯ РАБОТА №4
echo ------------------
echo 1. Индексы: 
if exist lab4_indexes_result.txt (
    find /c "Индексы созданы" lab4_indexes_result.txt
) else (
    echo Файл результатов не найден
)
echo.
echo 2. Анализ производительности: 
if exist lab4_explain_result.txt (
    find /c "ВЫВОДЫ" lab4_explain_result.txt
) else (
    echo Файл результатов не найден
)
echo.
echo 3. Транзакции: 
if exist lab4_transactions_result.txt (
    find /c "Лабораторная работа по транзакциям" lab4_transactions_result.txt
) else (
    echo Файл результатов не найден
)
echo.
echo ========================================
echo СВОДНАЯ СТАТИСТИКА БАЗЫ ДАННЫХ
echo ========================================
) > final_report.txt

echo Добавляю статистику в отчет...
C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 -e "
SELECT 
    'ТАБЛИЦЫ' as 'Категория',
    COUNT(*) as 'Количество'
FROM information_schema.tables 
WHERE table_schema = 'warehouse_lab3'
UNION ALL
SELECT 
    'ИНДЕКСЫ',
    COUNT(*) 
FROM information_schema.statistics 
WHERE table_schema = 'warehouse_lab3'
UNION ALL
SELECT 
    'ФУНКЦИИ/ПРОЦЕДУРЫ',
    COUNT(*) 
FROM information_schema.routines 
WHERE routine_schema = 'warehouse_lab3'
UNION ALL
SELECT 
    'ТРИГГЕРЫ',
    COUNT(*) 
FROM information_schema.triggers 
WHERE trigger_schema = 'warehouse_lab3'
UNION ALL
SELECT 
    'ТОВАРЫ',
    COUNT(*) 
FROM product
UNION ALL
SELECT 
    'ДВИЖЕНИЯ ТОВАРОВ',
    COUNT(*) 
FROM inventory_movement;
" >> final_report.txt

echo.
echo 7.1 Краткий отчет:
type final_report.txt

echo.
echo 7.2 Файлы с результатами:
echo   Лаба 3: lab3_*_result.txt (4 файла)
echo   Лаба 4: lab4_*_result.txt (3 файла)
echo   Отчет: final_report.txt


echo.
echo Для детального просмотра результатов:
echo 1. lab3_test_result.txt - тестирование функций и процедур
echo 2. lab4_indexes_result.txt - создание и тестирование индексов
echo 3. lab4_explain_result.txt - анализ производительности
echo 4. lab4_transactions_result.txt - транзакции и аномалии
echo.
pause