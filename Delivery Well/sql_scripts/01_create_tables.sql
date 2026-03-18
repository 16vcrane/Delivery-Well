-- 01_create_tables.sql
-- 数据库初始化脚本
-- 遵循3NF设计规范

-- 创建数据库 (如果不存在)
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'LogisticsDB')
BEGIN
    CREATE DATABASE LogisticsDB;
END
GO

USE LogisticsDB;
GO

-- 1. 配送中心表 (DistributionCenters)
IF OBJECT_ID('DistributionCenters', 'U') IS NOT NULL DROP TABLE DistributionCenters;
CREATE TABLE DistributionCenters (
    CenterID INT IDENTITY(1,1) PRIMARY KEY,
    location_name NVARCHAR(100) NOT NULL UNIQUE,
    address NVARCHAR(200)
);

-- 2. 车队表 (Fleets)
IF OBJECT_ID('Fleets', 'U') IS NOT NULL DROP TABLE Fleets;
CREATE TABLE Fleets (
    FleetID INT IDENTITY(1,1) PRIMARY KEY,
    CenterID INT NOT NULL,
    fleet_name NVARCHAR(50) NOT NULL,
    CONSTRAINT FK_Fleets_Centers FOREIGN KEY (CenterID) REFERENCES DistributionCenters(CenterID)
);

-- 3. 人员表 (Staff)
-- 包含调度主管和司机
IF OBJECT_ID('Staff', 'U') IS NOT NULL DROP TABLE Staff;
CREATE TABLE Staff (
    StaffID INT IDENTITY(1001,1) PRIMARY KEY,
    FleetID INT NOT NULL,
    full_name NVARCHAR(50) NOT NULL,
    role_type NVARCHAR(20) NOT NULL CHECK (role_type IN ('Manager', 'Driver')), -- 调度主管 or 司机
    license_level NVARCHAR(10) NULL, -- 驾照等级，仅司机需要
    contact_number NVARCHAR(20),
    password_hash NVARCHAR(100) DEFAULT '123456', -- 简化演示用
    CONSTRAINT FK_Staff_Fleets FOREIGN KEY (FleetID) REFERENCES Fleets(FleetID)
);

-- 4. 车辆表 (Vehicles)
IF OBJECT_ID('Vehicles', 'U') IS NOT NULL DROP TABLE Vehicles;
CREATE TABLE Vehicles (
    PlateNumber NVARCHAR(20) PRIMARY KEY, -- 车牌作为主键
    FleetID INT NOT NULL,
    max_weight_kg DECIMAL(10, 2) NOT NULL,
    max_volume_m3 DECIMAL(10, 2) NOT NULL,
    current_status NVARCHAR(20) NOT NULL DEFAULT 'Idle' CHECK (current_status IN ('Idle', 'InTransit', 'Maintenance', 'Exception')), -- 空闲, 运输中, 维修中, 异常
    CONSTRAINT FK_Vehicles_Fleets FOREIGN KEY (FleetID) REFERENCES Fleets(FleetID)
);

-- 5. 运单表 (Orders)
IF OBJECT_ID('Orders', 'U') IS NOT NULL DROP TABLE Orders;
CREATE TABLE Orders (
    OrderID INT IDENTITY(5001,1) PRIMARY KEY,
    weight_kg DECIMAL(10, 2) NOT NULL,
    volume_m3 DECIMAL(10, 2) NOT NULL,
    destination NVARCHAR(100) NOT NULL,
    order_status NVARCHAR(20) NOT NULL DEFAULT 'Pending' CHECK (order_status IN ('Pending', 'Assigned', 'Completed')), -- 待分配, 已分配, 已完成
    AssignedVehicleID NVARCHAR(20) NULL, -- 分配的车辆
    DriverID INT NULL, -- 关联司机 (通常是车辆的当前驾驶员，这里简化为分配时的司机)
    created_at DATETIME DEFAULT GETDATE(),
    CONSTRAINT FK_Orders_Vehicles FOREIGN KEY (AssignedVehicleID) REFERENCES Vehicles(PlateNumber),
    CONSTRAINT FK_Orders_Staff FOREIGN KEY (DriverID) REFERENCES Staff(StaffID)
);

-- 6. 异常记录表 (ExceptionRecords)
IF OBJECT_ID('ExceptionRecords', 'U') IS NOT NULL DROP TABLE ExceptionRecords;
CREATE TABLE ExceptionRecords (
    RecordID INT IDENTITY(1,1) PRIMARY KEY,
    PlateNumber NVARCHAR(20) NULL,
    DriverID INT NULL,
    exception_time DATETIME DEFAULT GETDATE(),
    exception_type NVARCHAR(20) NOT NULL CHECK (exception_type IN ('TransitException', 'IdleException')), -- 运输中异常, 空闲时异常
    description NVARCHAR(500),
    fine_amount DECIMAL(10, 2) DEFAULT 0,
    handle_status NVARCHAR(20) DEFAULT 'Unhandled' CHECK (handle_status IN ('Unhandled', 'Handled')),
    CONSTRAINT FK_Exceptions_Vehicles FOREIGN KEY (PlateNumber) REFERENCES Vehicles(PlateNumber),
    CONSTRAINT FK_Exceptions_Staff FOREIGN KEY (DriverID) REFERENCES Staff(StaffID)
);

-- 7. 审计日志表 (History_Log)
IF OBJECT_ID('History_Log', 'U') IS NOT NULL DROP TABLE History_Log;
CREATE TABLE History_Log (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    table_name NVARCHAR(50),
    record_id NVARCHAR(50),
    column_name NVARCHAR(50),
    old_value NVARCHAR(MAX),
    new_value NVARCHAR(MAX),
    operation_type NVARCHAR(20),
    change_time DATETIME DEFAULT GETDATE(),
    operator NVARCHAR(50) DEFAULT SYSTEM_USER
);
GO
