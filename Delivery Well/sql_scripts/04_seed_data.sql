-- 04_seed_data.sql
-- 演示测试数据

USE LogisticsDB;
GO

-- 1. 配送中心
INSERT INTO DistributionCenters (location_name, address) VALUES 
('Beijing-Center', 'No.1 Logistics Road, Beijing'),
('Shanghai-Center', 'No.88 Port Road, Shanghai');

-- 2. 车队
INSERT INTO Fleets (CenterID, fleet_name) VALUES 
(1, 'North-Express-Team'),
(1, 'Beijing-City-Team'),
(2, 'East-Coast-Team');

-- 3. 员工
-- Team 1
INSERT INTO Staff (FleetID, full_name, role_type, contact_number, password_hash) VALUES 
(1, 'Alice Manager', 'Manager', '13800138001', '123456');

INSERT INTO Staff (FleetID, full_name, role_type, license_level, contact_number) VALUES 
(1, 'Bob Driver', 'Driver', 'A1', '13900139001'),
(1, 'Charlie Driver', 'Driver', 'B2', '13900139002');

-- Team 2
INSERT INTO Staff (FleetID, full_name, role_type, contact_number, password_hash) VALUES 
(2, 'David Manager', 'Manager', '13800138002', '123456');

-- 4. 车辆
INSERT INTO Vehicles (PlateNumber, FleetID, max_weight_kg, max_volume_m3, current_status) VALUES 
('京A-88888', 1, 5000.00, 20.00, 'Idle'), -- 5吨车
('京A-66666', 1, 2000.00, 10.00, 'Idle'), -- 2吨车
('京B-12345', 2, 1500.00, 8.00, 'Maintenance');

-- 5. 运单
-- 初始不分配
INSERT INTO Orders (weight_kg, volume_m3, destination, order_status) VALUES 
(500.00, 2.0, 'Chaoyang District, Beijing', 'Pending'),
(1200.00, 5.0, 'Haidian District, Beijing', 'Pending');

-- 6. 异常记录
INSERT INTO ExceptionRecords (PlateNumber, DriverID, exception_type, description, fine_amount, handle_status) VALUES 
('京B-12345', NULL, 'IdleException', 'Routine Maintenance Check failed', 0, 'Unhandled');

GO
