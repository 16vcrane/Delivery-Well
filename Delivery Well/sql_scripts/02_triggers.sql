-- 02_triggers.sql
-- 触发器定义

USE LogisticsDB;
GO

-- 1. 自动载重校验触发器
-- 当向一辆车分配运单时，检查是否超载
IF OBJECT_ID('trg_CheckPayload', 'TR') IS NOT NULL DROP TRIGGER trg_CheckPayload;
GO

CREATE TRIGGER trg_CheckPayload
ON Orders
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- 仅当分配了车辆时检查 (AssignedVehicleID 不为空)
    IF EXISTS (SELECT 1 FROM inserted WHERE AssignedVehicleID IS NOT NULL)
    BEGIN
        DECLARE @VehicleID NVARCHAR(20);
        DECLARE @NewOrderWeight DECIMAL(10, 2);
        DECLARE @CurrentPayload DECIMAL(10, 2);
        DECLARE @MaxPayload DECIMAL(10, 2);

        -- 使用游标或集合操作处理批量插入/更新，这里为简化逻辑展示，处理单行或通过JOIN检查
        -- 检查所有涉及的车辆
        
        IF EXISTS (
            SELECT 1
            FROM inserted i
            JOIN Vehicles v ON i.AssignedVehicleID = v.PlateNumber
            CROSS APPLY (
                -- 计算该车辆当前已分配且未完成的运单总重 (包含本次插入/更新的运单，如果是INSERT)
                -- 注意：如果是UPDATE，需要排除旧值的影响，或是直接计算所有状态为Assigned的运单
                SELECT ISNULL(SUM(o.weight_kg), 0) as TotalWeight
                FROM Orders o 
                WHERE o.AssignedVehicleID = i.AssignedVehicleID 
                AND o.order_status = 'Assigned'
                AND o.OrderID != i.OrderID -- 排除自身，稍后加上
            ) calc
            WHERE (calc.TotalWeight + i.weight_kg) > v.max_weight_kg
        )
        BEGIN
            RAISERROR ('错误：车辆超载！新分配的货物重量加上已有货物重量超过了车辆最大载重。', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- 状态自动流转逻辑的一部分：如果车辆被分配了运单，且状态是 Idle，改为 InTransit
        UPDATE v
        SET current_status = 'InTransit'
        FROM Vehicles v
        JOIN inserted i ON v.PlateNumber = i.AssignedVehicleID
        WHERE v.current_status = 'Idle' AND i.order_status = 'Assigned';
    END
END
GO

-- 2. 车辆状态自动流转触发器
-- 当一辆车完成所有运单的签收，自动变为空闲
IF OBJECT_ID('trg_AutoVehicleStatus_Complete', 'TR') IS NOT NULL DROP TRIGGER trg_AutoVehicleStatus_Complete;
GO

CREATE TRIGGER trg_AutoVehicleStatus_Complete
ON Orders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- 检查是否有运单状态变为 Completed
    IF UPDATE(order_status)
    BEGIN
        -- 找出涉及的车辆
        DECLARE @AffectedVehicles TABLE (PlateNumber NVARCHAR(20));
        
        INSERT INTO @AffectedVehicles
        SELECT DISTINCT AssignedVehicleID 
        FROM inserted 
        WHERE order_status = 'Completed' AND AssignedVehicleID IS NOT NULL;

        -- 对每辆涉及的车，检查是否所有分配给它的运单都已完成
        UPDATE v
        SET current_status = 'Idle'
        FROM Vehicles v
        JOIN @AffectedVehicles av ON v.PlateNumber = av.PlateNumber
        WHERE NOT EXISTS (
            SELECT 1 
            FROM Orders o 
            WHERE o.AssignedVehicleID = v.PlateNumber 
            AND o.order_status = 'Assigned' -- 仍有未完成的运单
        ) AND v.current_status = 'InTransit'; -- 只有在运输中才改为空闲
    END
END
GO

-- 3. 异常处理状态流转触发器
-- 异常处理完成后，车辆状态变更
IF OBJECT_ID('trg_ExceptionHandled', 'TR') IS NOT NULL DROP TRIGGER trg_ExceptionHandled;
GO

CREATE TRIGGER trg_ExceptionHandled
ON ExceptionRecords
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF UPDATE(handle_status)
    BEGIN
        -- 如果异常变为 Handled
        UPDATE v
        SET current_status = CASE 
                                WHEN i.exception_type = 'IdleException' THEN 'Idle'
                                WHEN i.exception_type = 'TransitException' THEN 'InTransit' -- 或者由人工决定，这里按规则自动恢复
                                ELSE 'Idle'
                             END
        FROM Vehicles v
        JOIN inserted i ON v.PlateNumber = i.PlateNumber
        WHERE i.handle_status = 'Handled' 
		AND EXISTS (
		SELECT 1
		FROM deleted d
		WHERE d.PlateNumber = i.PlateNumber
		AND d.handle_status = 'Unhandled')
        --AND deleted.handle_status = 'Unhandled' -- 仅仅当状态翻转时
        AND v.current_status = 'Exception'; -- 仅当车辆当前是异常状态
    END
    
    -- 当插入新的未处理异常时，车辆变更为异常状态
    IF EXISTS (SELECT 1 FROM inserted WHERE handle_status = 'Unhandled')
    BEGIN
         UPDATE v
         SET current_status = 'Exception'
         FROM Vehicles v
         JOIN inserted i ON v.PlateNumber = i.PlateNumber
         WHERE i.handle_status = 'Unhandled';
    END
END
GO

-- 4. 审计日志触发器
-- 记录 Staff 表的关键信息修改
IF OBJECT_ID('trg_Audit_Staff', 'TR') IS NOT NULL DROP TRIGGER trg_Audit_Staff;
GO

CREATE TRIGGER trg_Audit_Staff
ON Staff
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF UPDATE(license_level)
    BEGIN
        INSERT INTO History_Log (table_name, record_id, column_name, old_value, new_value, operation_type)
        SELECT 
            'Staff',
            CAST(i.StaffID AS NVARCHAR(50)),
            'license_level',
            d.license_level,
            i.license_level,
            'UPDATE'
        FROM inserted i
        JOIN deleted d ON i.StaffID = d.StaffID
        WHERE ISNULL(d.license_level, '') != ISNULL(i.license_level, '');
    END
END
GO

-- 记录异常记录的处理
IF OBJECT_ID('trg_Audit_Exception', 'TR') IS NOT NULL DROP TRIGGER trg_Audit_Exception;
GO

CREATE TRIGGER trg_Audit_Exception
ON ExceptionRecords
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF UPDATE(handle_status)
    BEGIN
        INSERT INTO History_Log (table_name, record_id, column_name, old_value, new_value, operation_type)
        SELECT 
            'ExceptionRecords',
            CAST(i.RecordID AS NVARCHAR(50)),
            'handle_status',
            d.handle_status,
            i.handle_status,
            'UPDATE'
        FROM inserted i
        JOIN deleted d ON i.RecordID = d.RecordID
        WHERE d.handle_status != i.handle_status;
    END
END
GO
