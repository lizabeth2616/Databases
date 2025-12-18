@echo off
echo Запуск лабораторной работы...
cd /d "C:\Users\84835\Desktop\Laba3VSCode"

echo ========================================
echo 1. Проверяю какие файлы есть...
dir *.sql

echo.
echo ========================================
echo 2. Создаю базу warehouse_lab3...
C:\xampp\mysql\bin\mysql.exe -u root -e "DROP DATABASE IF EXISTS warehouse_lab3; CREATE DATABASE warehouse_lab3 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; SELECT 'База создана' as status;"

echo.
echo ========================================
echo 3. Ищу и выполняю SQL файлы...

:: Проверяем какие версии файлов существуют
if exist "create_database_fixed.sql" (
    echo Выполняю create_database_fixed.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < create_database_fixed.sql
) else if exist "create_database.sql" (
    echo Выполняю create_database.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < create_database.sql
) else (
    echo Файл создания базы не найден!
)

if exist "procedures_functions_mysql_fixed.sql" (
    echo Выполняю procedures_functions_mysql_fixed.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < procedures_functions_mysql_fixed.sql
) else if exist "procedures_functions.sql" (
    echo Выполняю procedures_functions.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < procedures_functions.sql
) else (
    echo Файл процедур не найден!
)

if exist "triggers_mysql_fixed.sql" (
    echo Выполняю triggers_mysql_fixed.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < triggers_mysql_fixed.sql
) else if exist "triggers.sql" (
    echo Выполняю triggers.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < triggers.sql
) else (
    echo Файл триггеров не найден!
)

if exist "test_reports_mysql.sql" (
    echo Выполняю test_reports_mysql.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < test_reports_mysql.sql
) else if exist "test_queries.sql" (
    echo Выполняю test_queries.sql...
    C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 < test_queries.sql
) else (
    echo Тестовые запросы не найдены!
)

echo.
echo ========================================
echo 4. ПРОВЕРКА РЕЗУЛЬТАТОВ
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
C:\xampp\mysql\bin\mysql.exe -u root warehouse_lab3 -e "SELECT routine_name, routine_type FROM information_schema.routines WHERE routine_schema = 'warehouse_lab3';"

echo.
echo ========================================
echo ЛАБОРАТОРНАЯ РАБОТА ВЫПОЛНЕНА!
echo ========================================
pause