-- 03_procedures_views.sql
-- 存储过程与视图

USE LogisticsDB;
GO

-- 1. 视图：车队异常警报视图
-- 只显示本周发生过异常的车辆和司机信息
IF OBJECT_ID('v_WeeklyExceptionAlert', 'V') IS NOT NULL DROP VIEW v_WeeklyExceptionAlert;
GO

CREATE VIEW v_WeeklyExceptionAlert AS
SELECT 
    f.fleet_name,
    e.PlateNumber,
    s.full_name AS DriverName,
    e.exception_type,
    e.description,
    e.exception_time,
    e.handle_status
FROM ExceptionRecords e
JOIN Vehicles v ON e.PlateNumber = v.PlateNumber
JOIN Fleets f ON v.FleetID = f.FleetID
LEFT JOIN Staff s ON e.DriverID = s.StaffID
WHERE e.exception_time >= DATEADD(day, -7, GETDATE());
GO

-- 2. 存储过程：车队月度绩效统计
-- 包含：总运单数、异常事件总数、累计罚款金额
IF OBJECT_ID('sp_FleetMonthlyPerformance', 'P') IS NOT NULL DROP PROCEDURE sp_FleetMonthlyPerformance;
GO

CREATE PROCEDURE sp_FleetMonthlyPerformance
    @FleetID INT,
    @ReportMonth DATE -- 传入如 '2023-01-01' 代表1月份
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartDate DATE = DATEFROMPARTS(YEAR(@ReportMonth), MONTH(@ReportMonth), 1);
    DECLARE @EndDate DATE = EOMONTH(@StartDate);

    SELECT 
        f.fleet_name,
        @StartDate AS report_month,
        -- 总运单数 (基于车辆归属计算)
        (
            SELECT COUNT(*)
            FROM Orders o
            JOIN Vehicles v ON o.AssignedVehicleID = v.PlateNumber
            WHERE v.FleetID = @FleetID
            AND o.created_at BETWEEN @StartDate AND @EndDate
        ) AS total_orders,
        -- 异常事件总数
        (
            SELECT COUNT(*)
            FROM ExceptionRecords e
            JOIN Vehicles v ON e.PlateNumber = v.PlateNumber
            WHERE v.FleetID = @FleetID
            AND e.exception_time BETWEEN @StartDate AND @EndDate
        ) AS total_exceptions,
        -- 累计罚款金额
        (
            SELECT ISNULL(SUM(e.fine_amount), 0)
            FROM ExceptionRecords e
            JOIN Vehicles v ON e.PlateNumber = v.PlateNumber
            WHERE v.FleetID = @FleetID
            AND e.exception_time BETWEEN @StartDate AND @EndDate
        ) AS total_fines
    FROM Fleets f
    WHERE f.FleetID = @FleetID;
END
GO

-- 3. 索引优化
-- 对高频查询字段建立索引
-- 检查索引是否存在，不存在则创建
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IDX_Vehicles_Status' AND object_id = OBJECT_ID('Vehicles'))
BEGIN
    CREATE INDEX IDX_Vehicles_Status ON Vehicles(current_status);
END

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IDX_Orders_Date' AND object_id = OBJECT_ID('Orders'))
BEGIN
    CREATE INDEX IDX_Orders_Date ON Orders(created_at);
END

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IDX_Staff_Fleet' AND object_id = OBJECT_ID('Staff'))
BEGIN
    CREATE INDEX IDX_Staff_Fleet ON Staff(FleetID);
END
GO
