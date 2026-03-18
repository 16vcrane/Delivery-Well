from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
import pyodbc 
import datetime

app = Flask(__name__)
app.secret_key = 'logistics_secure_key' 

# 数据库配置
DB_CONFIG = {
    'DRIVER': '{ODBC Driver 17 for SQL Server}',
    'SERVER': 'localhost',
    'DATABASE': 'LogisticsDB',
    'Trusted_Connection': 'yes' # 使用 Windows 身份验证
    #'UID': 'sa',          # 如果使用 SQL 账号密码
    #'PWD': 'your_password'
}

def get_db_connection():
    conn_str = f"DRIVER={DB_CONFIG['DRIVER']};SERVER={DB_CONFIG['SERVER']};DATABASE={DB_CONFIG['DATABASE']};Trusted_Connection={DB_CONFIG['Trusted_Connection']}"
    try:
        conn = pyodbc.connect(conn_str)
        return conn
    except Exception as e:
        print(f"Database connection error: {e}")
        return None

@app.route('/')
def index():
    conn = get_db_connection()
    if not conn:
        return render_template('index.html', pending_orders_count="--", intransit_vehicles_count="--", unhandled_exceptions_count="--", idle_vehicles_count="--")
    
    cursor = conn.cursor()
    
    # 统计数据
    cursor.execute("SELECT COUNT(*) FROM Orders WHERE order_status = 'Pending'")
    pending_orders_count = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM Vehicles WHERE current_status = 'InTransit'")
    intransit_vehicles_count = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(*) FROM ExceptionRecords WHERE handle_status = 'Unhandled'")
    unhandled_exceptions_count = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(*) FROM Vehicles WHERE current_status = 'Idle'")
    idle_vehicles_count = cursor.fetchone()[0]
    
    conn.close()
    
    return render_template('index.html', 
                           pending_orders_count=pending_orders_count, 
                           intransit_vehicles_count=intransit_vehicles_count, 
                           unhandled_exceptions_count=unhandled_exceptions_count, 
                           idle_vehicles_count=idle_vehicles_count)

# --- 1.1 车队管理 (新增) ---
@app.route('/fleets', methods=['GET', 'POST'])
def fleet_management():
    conn = get_db_connection()
    if not conn:
        flash("数据库连接失败", "danger")
        return render_template('fleets.html', fleets=[], centers=[])
    
    cursor = conn.cursor()
    
    if request.method == 'POST':
        fleet_name = request.form['fleet_name']
        center_id = request.form['center_id']
        try:
            cursor.execute("INSERT INTO Fleets (fleet_name, CenterID) VALUES (?, ?)", (fleet_name, center_id))
            conn.commit()
            flash("车队添加成功", "success")
        except Exception as e:
            conn.rollback()
            flash(f"添加失败: {e}", "danger")
            
    cursor.execute("SELECT f.*, dc.location_name FROM Fleets f JOIN DistributionCenters dc ON f.CenterID = dc.CenterID ORDER BY f.FleetID DESC")
    fleets = cursor.fetchall()
    
    cursor.execute("SELECT CenterID, location_name FROM DistributionCenters")
    centers = cursor.fetchall()
    
    conn.close()
    return render_template('fleets.html', fleets=fleets, centers=centers)

# --- 1. 基础信息管理 (司机 & 车辆) ---

@app.route('/staff', methods=['GET', 'POST'])
def staff_management():
    conn = get_db_connection()
    if not conn:
        flash("数据库连接失败", "danger")
        return render_template('staff.html', staff_list=[], fleets=[])

    cursor = conn.cursor()

    if request.method == 'POST':
        # 录入新司机/员工
        name = request.form['full_name']
        role = request.form['role_type']
        fleet_id = request.form['fleet_id']
        contact = request.form['contact_number']
        license_level = request.form.get('license_level') # 仅司机有

        try:
            cursor.execute("""
                INSERT INTO Staff (full_name, role_type, FleetID, contact_number, license_level)
                VALUES (?, ?, ?, ?, ?)
            """, (name, role, fleet_id, contact, license_level if role == 'Driver' else None))
            conn.commit()
            flash("员工添加成功", "success")
        except Exception as e:
            conn.rollback()
            flash(f"添加失败: {e}", "danger")

    # 获取列表
    cursor.execute("SELECT s.*, f.fleet_name FROM Staff s JOIN Fleets f ON s.FleetID = f.FleetID ORDER BY s.StaffID DESC")
    staff_list = cursor.fetchall()
    
    cursor.execute("SELECT FleetID, fleet_name FROM Fleets")
    fleets = cursor.fetchall()
    
    conn.close()
    return render_template('staff.html', staff_list=staff_list, fleets=fleets)

@app.route('/vehicles', methods=['GET', 'POST'])
def vehicle_management():
    conn = get_db_connection()
    cursor = conn.cursor()

    if request.method == 'POST':
        plate = request.form['plate_number']
        fleet_id = request.form['fleet_id']
        max_weight = request.form['max_weight']
        max_vol = request.form['max_volume']
        
        try:
            cursor.execute("""
                INSERT INTO Vehicles (PlateNumber, FleetID, max_weight_kg, max_volume_m3, current_status)
                VALUES (?, ?, ?, ?, 'Idle')
            """, (plate, fleet_id, max_weight, max_vol))
            conn.commit()
            flash("车辆录入成功", "success")
        except Exception as e:
            flash(f"录入失败: {e}", "danger")

    cursor.execute("""
        SELECT v.*, f.fleet_name,
        (SELECT COUNT(*) FROM Orders o WHERE o.AssignedVehicleID = v.PlateNumber AND o.order_status = 'Assigned') as active_orders
        FROM Vehicles v 
        JOIN Fleets f ON v.FleetID = f.FleetID
    """)
    vehicles = cursor.fetchall()

    cursor.execute("SELECT FleetID, fleet_name FROM Fleets")
    fleets = cursor.fetchall()
    conn.close()
    return render_template('vehicles.html', vehicles=vehicles, fleets=fleets)


# --- 2. 运单分配 ---

@app.route('/orders', methods=['GET', 'POST'])
def order_management():
    conn = get_db_connection()
    cursor = conn.cursor()

    if request.method == 'POST':
        action = request.form.get('action')
        
        if action == 'create':
            weight = request.form['weight']
            volume = request.form['volume']
            dest = request.form['destination']
            try:
                cursor.execute("INSERT INTO Orders (weight_kg, volume_m3, destination) VALUES (?, ?, ?)", (weight, volume, dest))
                conn.commit()
                flash("新运单创建成功", "success")
            except Exception as e:
                flash(f"创建失败: {e}", "danger")
        
        elif action == 'assign':
            order_id = request.form['order_id']
            vehicle_plate = request.form['vehicle_plate']
            driver_id = request.form['driver_id']
            
            # --- 应用层校验：体积限制 ---
            # (由于数据库触发器只校验了重量，我们在应用层补充体积校验)
            cursor.execute("SELECT volume_m3 FROM Orders WHERE OrderID = ?", (order_id,))
            order_res = cursor.fetchone()
            if not order_res:
                 flash("订单不存在", "danger")
                 return redirect(url_for('order_management'))
            order_vol = order_res[0]
            
            cursor.execute("SELECT max_volume_m3 FROM Vehicles WHERE PlateNumber = ?", (vehicle_plate,))
            vehicle_res = cursor.fetchone()
            if not vehicle_res:
                flash("车辆不存在", "danger")
                return redirect(url_for('order_management'))
            vehicle_max_vol = vehicle_res[0]
            
            cursor.execute("SELECT ISNULL(SUM(volume_m3), 0) FROM Orders WHERE AssignedVehicleID = ? AND order_status = 'Assigned'", (vehicle_plate,))
            current_vol_load = cursor.fetchone()[0]
            
            if (current_vol_load + order_vol) > vehicle_max_vol:
                flash(f"分配失败：车辆容积不足！(当前已载: {current_vol_load}m³ + 本单: {order_vol}m³ > 上限: {vehicle_max_vol}m³)", "danger")
            else:
                try:
                    # 触发器 trg_CheckPayload 会在此处拦截超载 (重量)
                    cursor.execute("""
                        UPDATE Orders 
                        SET AssignedVehicleID = ?, DriverID = ?, order_status = 'Assigned' 
                        WHERE OrderID = ?
                    """, (vehicle_plate, driver_id, order_id))
                    conn.commit()
                    flash(f"运单 {order_id} 已成功分配给 {vehicle_plate} (司机ID: {driver_id})", "success")
                except pyodbc.Error as e:
                    # 捕获触发器抛出的异常
                    error_msg = str(e)
                    if "车辆超载" in error_msg:
                        flash(f"分配失败：车辆超载！(数据库触发器拦截)", "danger")
                    else:
                        flash(f"分配失败: {e}", "danger")

    # 获取未分配运单
    cursor.execute("SELECT * FROM Orders WHERE order_status = 'Pending'")
    pending_orders = cursor.fetchall()
    
    # 获取所有运单历史
    cursor.execute("""
        SELECT o.*, s.full_name as DriverName 
        FROM Orders o
        LEFT JOIN Staff s ON o.DriverID = s.StaffID
        ORDER BY o.created_at DESC
    """)
    all_orders = cursor.fetchall()
    
    # 获取可用车辆（空闲 或 运输中但未满载 - 简化为所有非异常车辆供选择，让触发器做校验）
    cursor.execute("SELECT PlateNumber, current_status, max_weight_kg, max_volume_m3 FROM Vehicles WHERE current_status != 'Exception' AND current_status != 'Maintenance'")
    available_vehicles = cursor.fetchall()

    # 获取所有司机
    cursor.execute("SELECT StaffID, full_name, role_type, FleetID, (SELECT fleet_name FROM Fleets WHERE Fleets.FleetID = Staff.FleetID) as fleet_name FROM Staff WHERE role_type = 'Driver'")
    drivers = cursor.fetchall()

    conn.close()
    return render_template('orders.html', pending_orders=pending_orders, all_orders=all_orders, vehicles=available_vehicles, drivers=drivers)

@app.route('/complete_order/<int:order_id>')
def complete_order(order_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("UPDATE Orders SET order_status = 'Completed' WHERE OrderID = ?", (order_id,))
        conn.commit()
        flash(f"运单 {order_id} 已签收完成", "success")
    except Exception as e:
        flash(f"操作失败: {e}", "danger")
    conn.close()
    return redirect(url_for('order_management'))


# --- 3. 异常记录 ---

@app.route('/exceptions', methods=['GET', 'POST'])
def exception_management():
    conn = get_db_connection()
    cursor = conn.cursor()

    if request.method == 'POST':
        action = request.form.get('action')
        
        if action == 'register':
            plate = request.form['plate_number']
            e_type = request.form['type']
            desc = request.form['description']
            fine = request.form['fine']
            driver_id = request.form.get('driver_id') # 可选

            try:
                cursor.execute("""
                    INSERT INTO ExceptionRecords (PlateNumber, DriverID, exception_type, description, fine_amount, handle_status)
                    VALUES (?, ?, ?, ?, ?, 'Unhandled')
                """, (plate, driver_id if driver_id else None, e_type, desc, fine))
                conn.commit()
                flash("异常记录已登记", "warning")
            except Exception as e:
                flash(f"登记失败: {e}", "danger")

        elif action == 'resolve':
            record_id = request.form['record_id']
            try:
                cursor.execute("UPDATE ExceptionRecords SET handle_status = 'Handled' WHERE RecordID = ?", (record_id,))
                conn.commit()
                flash("异常已标记为处理完成", "success")
            except Exception as e:
                flash(f"处理失败: {e}", "danger")

    cursor.execute("""
        SELECT e.*, v.FleetID 
        FROM ExceptionRecords e
        LEFT JOIN Vehicles v ON e.PlateNumber = v.PlateNumber
        ORDER BY e.exception_time DESC
    """)
    exceptions = cursor.fetchall()
    
    cursor.execute("SELECT PlateNumber FROM Vehicles")
    vehicles = cursor.fetchall()
    
    cursor.execute("SELECT StaffID, full_name FROM Staff WHERE role_type='Driver'")
    drivers = cursor.fetchall()

    conn.close()
    return render_template('exceptions.html', exceptions=exceptions, vehicles=vehicles, drivers=drivers)


# --- 4 & 5. 统计与查询 ---

@app.route('/reports')
def reports():
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # 获取参数
    center_id = request.args.get('center_id')
    
    # 资源查询：各车队车辆状态概览
    # 支持按配送中心筛选
    sql_base = """
        SELECT f.fleet_name, v.PlateNumber, v.current_status, v.max_weight_kg, v.max_volume_m3,
        ISNULL((SELECT SUM(weight_kg) FROM Orders o WHERE o.AssignedVehicleID = v.PlateNumber AND o.order_status='Assigned'), 0) as current_load,
        ISNULL((SELECT SUM(volume_m3) FROM Orders o WHERE o.AssignedVehicleID = v.PlateNumber AND o.order_status='Assigned'), 0) as current_vol_load
        FROM Vehicles v
        JOIN Fleets f ON v.FleetID = f.FleetID
    """
    
    if center_id and center_id != 'all':
        sql_base += " WHERE f.CenterID = ?"
        params = (center_id,)
    else:
        params = ()
        
    sql_base += " ORDER BY f.fleet_name"
    
    cursor.execute(sql_base, params)
    fleet_status = cursor.fetchall()

    # 获取所有车队供选择
    cursor.execute("SELECT FleetID, fleet_name FROM Fleets")
    all_fleets = cursor.fetchall()
    
    # 获取配送中心供筛选
    cursor.execute("SELECT CenterID, location_name FROM DistributionCenters")
    centers = cursor.fetchall()
    
    # 获取司机列表供绩效查询
    cursor.execute("SELECT StaffID, full_name, f.fleet_name FROM Staff s JOIN Fleets f ON s.FleetID = f.FleetID WHERE role_type='Driver'")
    drivers = cursor.fetchall()

    conn.close()
    return render_template('reports.html', fleet_status=fleet_status, all_fleets=all_fleets, centers=centers, drivers=drivers, current_center=center_id)

@app.route('/api/monthly_performance/<int:fleet_id>/<string:month_str>')
def api_monthly_performance(fleet_id, month_str):
    # ... existing code ...
    # 调用存储过程
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # month_str format: 'YYYY-MM' -> needs 'YYYY-MM-01'
    date_param = f"{month_str}-01"
    
    try:
        # SQL Server EXEC syntax
        cursor.execute("EXEC sp_FleetMonthlyPerformance ?, ?", (fleet_id, date_param))
        row = cursor.fetchone()
        if row:
            data = {
                'fleet_name': row.fleet_name,
                'total_orders': row.total_orders,
                'total_exceptions': row.total_exceptions,
                'total_fines': float(row.total_fines)
            }
            return jsonify({'success': True, 'data': data})
        else:
            return jsonify({'success': False, 'message': 'No data'})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)})
    finally:
        conn.close()

@app.route('/api/driver_performance/<int:driver_id>')
def api_driver_performance(driver_id):
    start_date = request.args.get('start')
    end_date = request.args.get('end')
    
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        # 1. 统计运单数
        # 假设统计 create_at 在此期间且已分配/完成的单子
        cursor.execute("""
            SELECT COUNT(*) 
            FROM Orders 
            WHERE DriverID = ? 
            AND created_at BETWEEN ? AND ?
        """, (driver_id, start_date, end_date))
        order_count = cursor.fetchone()[0]
        
        # 2. 获取异常记录详情
        cursor.execute("""
            SELECT exception_type, description, exception_time, fine_amount, handle_status
            FROM ExceptionRecords
            WHERE DriverID = ?
            AND exception_time BETWEEN ? AND ?
            ORDER BY exception_time DESC
        """, (driver_id, start_date, end_date))
        
        exceptions = []
        rows = cursor.fetchall()
        for row in rows:
            exceptions.append({
                'type': row.exception_type,
                'desc': row.description,
                'time': row.exception_time.strftime('%Y-%m-%d %H:%M'),
                'fine': float(row.fine_amount),
                'status': row.handle_status
            })
            
        return jsonify({
            'success': True, 
            'order_count': order_count, 
            'exceptions': exceptions
        })
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)})
    finally:
        conn.close()

if __name__ == '__main__':
    print("启动 Logistics Management System...")
    app.run(debug=True, port=5000)
