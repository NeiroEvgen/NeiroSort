function DeltaFactory
    clear; clc; close all;
    
    %% 1. ИНИЦИАЛИЗАЦИЯ ИНТЕРФЕЙСА
    fig = figure('Name', 'Delta Robot: Full Simulation V3 (UI)', 'Color', 'w', ...
        'Units', 'normalized', 'OuterPosition', [0.1 0.1 0.8 0.9]);
    movegui(fig, 'center');
    
    % --- ПАНЕЛЬ УПРАВЛЕНИЯ ---
    pnl = uipanel(fig, 'Title', 'Центр управления', 'FontSize', 12, ...
        'BackgroundColor', 'w', 'Position', [0 0 0.25 1]);
    
    % СЧЕТЧИКИ
    uicontrol(pnl, 'Style', 'text', 'String', 'ОТСОРТИРОВАНО:', 'Position', [20 750 200 20], ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
    txt_sorted = uicontrol(pnl, 'Style', 'text', 'String', '0', 'Position', [20 710 200 40], ...
        'FontSize', 24, 'ForegroundColor', 'g', 'BackgroundColor', [0.2 0.2 0.2]);
        
    uicontrol(pnl, 'Style', 'text', 'String', 'ПРОПУЩЕНО:', 'Position', [20 670 200 20], ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
    txt_missed = uicontrol(pnl, 'Style', 'text', 'String', '0', 'Position', [20 630 200 40], ...
        'FontSize', 24, 'ForegroundColor', 'r', 'BackgroundColor', [0.2 0.2 0.2]);

    % --- ПОЛЗУНКИ С ПОДПИСЯМИ ---
    
    % 1. Скорость времени (Time Scale)
    uicontrol(pnl, 'Style', 'text', 'String', 'Скорость времени (Slo-Mo)', 'Position', [20 500 200 20], ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w', 'FontWeight', 'bold');
    
    % Сам ползунок
    sld_timescale = uicontrol(pnl, 'Style', 'slider', 'Min', 0.02, 'Max', 1.5, 'Value', 1.0, ...
        'Position', [20 470 200 20]);
    
    % >> ПОДПИСИ ДИАПАЗОНА <<
    uicontrol(pnl, 'Style', 'text', 'String', '0.02x', 'Position', [20 455 50 15], ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w', 'FontSize', 8, 'ForegroundColor', [0.4 0.4 0.4]);
    uicontrol(pnl, 'Style', 'text', 'String', '1.5x', 'Position', [170 455 50 15], ...
        'HorizontalAlignment', 'right', 'BackgroundColor', 'w', 'FontSize', 8, 'ForegroundColor', [0.4 0.4 0.4]);

    
    % 2. Плотность потока (Спавн рейт)
    uicontrol(pnl, 'Style', 'text', 'String', 'Плотность (Кол-во мусора)', 'Position', [20 430 200 20], ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w', 'FontWeight', 'bold');
    
    % Сам ползунок
    sld_density = uicontrol(pnl, 'Style', 'slider', 'Min', 0, 'Max', 100, 'Value', 30, ...
        'Position', [20 400 200 20]);
        
    % >> ПОДПИСИ ДИАПАЗОНА <<
    uicontrol(pnl, 'Style', 'text', 'String', '0%', 'Position', [20 385 50 15], ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w', 'FontSize', 8, 'ForegroundColor', [0.4 0.4 0.4]);
    uicontrol(pnl, 'Style', 'text', 'String', '100%', 'Position', [170 385 50 15], ...
        'HorizontalAlignment', 'right', 'BackgroundColor', 'w', 'FontSize', 8, 'ForegroundColor', [0.4 0.4 0.4]);
        
    % 3. Ширина разброса
    uicontrol(pnl, 'Style', 'text', 'String', 'Ширина разброса ленты', 'Position', [20 360 200 20], ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w', 'FontWeight', 'bold');
    
    % Сам ползунок
    sld_width = uicontrol(pnl, 'Style', 'slider', 'Min', 0.1, 'Max', 0.8, 'Value', 0.4, ...
        'Position', [20 330 200 20]);
        
    % >> ПОДПИСИ ДИАПАЗОНА <<
    uicontrol(pnl, 'Style', 'text', 'String', '0.1м', 'Position', [20 315 50 15], ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w', 'FontSize', 8, 'ForegroundColor', [0.4 0.4 0.4]);
    uicontrol(pnl, 'Style', 'text', 'String', '0.8м', 'Position', [170 315 50 15], ...
        'HorizontalAlignment', 'right', 'BackgroundColor', 'w', 'FontSize', 8, 'ForegroundColor', [0.4 0.4 0.4]);

    % Кнопка сброса
    uicontrol(pnl, 'Style', 'pushbutton', 'String', 'СБРОС СИМУЛЯЦИИ', ...
        'Position', [20 200 200 50], 'Callback', @resetSim);

    % --- ГРАФИКА ---
    ax = axes('Parent', fig, 'Position', [0.3 0.1 0.65 0.8]);
    view(ax, 45, 30); axis(ax, 'equal'); grid(ax, 'on'); hold(ax, 'on');
    xlim(ax, [-0.8 1.0]); ylim(ax, [-1.0 1.0]); zlim(ax, [-0.8 0.4]);
    xlabel('X'); ylabel('Y'); zlabel('Z');
    
    %% 2. ПАРАМЕТРЫ
    rob_par.R_base = 0.175; rob_par.R_plat = 0.045;
    rob_par.L1 = 0.350;     rob_par.L2 = 0.800;
    g = 9.81;
    
    Conv.Start = [-0.8; 0; -0.65]; Conv.End = [1.0; 0; -0.65];
    Conv.Speed = 0.4; % м/с (реальная скорость ленты)
    
    Bin_Red = [0.0; 0.7; -0.65]; Bin_Blue = [0.0; -0.7; -0.65]; Bin_Green = [0.7; 0.0; -0.65];
    
    % Статика
    DrawFloor();
    plot3([Conv.Start(1) Conv.End(1)], [0 0], [Conv.Start(3) Conv.End(3)], 'k-', 'LineWidth', 1); % Центр
    h_belt_L = plot3([-0.8 1.0], [0.2 0.2], [-0.65 -0.65], 'k--', 'LineWidth', 1);
    h_belt_R = plot3([-0.8 1.0], [-0.2 -0.2], [-0.65 -0.65], 'k--', 'LineWidth', 1);
    
    DrawBin(Bin_Red, 'r', 'RED'); DrawBin(Bin_Blue, 'b', 'BLUE'); DrawBin(Bin_Green, 'g', 'GREEN');
    
    h_robot = CreateRobotGroup();
    
    %% 3. ПЕРЕМЕННЫЕ СОСТОЯНИЯ (STATE MACHINE)
    % Мусор: Struct Array. Поля: x, y, z, type(color), state, target, vx, vy, vz
    % State мусора: 0=OnBelt, 1=Gripped, 2=Flying, 3=Done
    TrashList = []; 
    TrashHandles = []; % Хранит графические объекты scatter/plot для каждого мусора
    
    % Робот
    Rob.State = 0; % 0=Idle, 1=Intercepting, 2=MovingToThrow, 3=Returning
    Rob.Pos = [0; 0; -0.4];
    Rob.TargetTrashID = -1; % ID мусора, за которым охотимся
    Rob.TargetPos = [0;0;0];
    Rob.ThrowStartPos = [0;0;0];
    Rob.Timer = 0; % Для интерполяции движений
    
    Counts.Sorted = 0;
    Counts.Missed = 0;
    
    SpawnTimer = 0;
    SimTime = 0;
    
    % Callback сброса
    function resetSim(~,~)
        TrashList = [];
        delete(TrashHandles); TrashHandles = [];
        Counts.Sorted = 0; Counts.Missed = 0;
        set(txt_sorted, 'String', '0'); set(txt_missed, 'String', '0');
        Rob.State = 0; Rob.Pos = [0; 0; -0.4]; Rob.TargetTrashID = -1;
    end

    %% 4. ГЛАВНЫЙ ЦИКЛ (GAME LOOP)
    last_tic = tic;
    
    while ishandle(fig)
        % 1. Читаем время и слайдеры
        dt_real = toc(last_tic);
        last_tic = tic;
        
        time_scale = get(sld_timescale, 'Value');
        density_val = get(sld_density, 'Value'); % 0 to 100
        width_val = get(sld_width, 'Value');
        
        % Обновляем границы ленты визуально
        set(h_belt_L, 'YData', [width_val/2 width_val/2]);
        set(h_belt_R, 'YData', [-width_val/2 -width_val/2]);
        
        % dt_sim - это "сколько времени прошло в мире симуляции"
        dt_sim = dt_real * time_scale; 
        
        % Если пауза (слайдер в 0), ставим минимальный шаг, чтоб не висело
        if dt_sim < 0.0001, dt_sim = 0; end
        
        %% А. ЛОГИКА СПАВНА (ГЕНЕРАТОР МУСОРА)
        % density_val управляет частотой. Чем больше, тем меньше интервал.
        % Интервал от 2.0 сек (при 0) до 0.2 сек (при 100)
        spawn_interval = 2.0 - (density_val / 100) * 1.8; 
        
        SpawnTimer = SpawnTimer + dt_sim;
        if density_val > 0 && SpawnTimer > spawn_interval
            SpawnTimer = 0;
            
            % Создаем новый мусор
            newTrash.x = Conv.Start(1);
            newTrash.y = (rand - 0.5) * width_val; % Разброс по ширине
            newTrash.z = Conv.Start(3) + 0.05;
            newTrash.type = randi(3); % 1=r, 2=b, 3=g
            newTrash.state = 0; % На ленте
            newTrash.vx = 0; newTrash.vy = 0; newTrash.vz = 0;
            newTrash.id = rand; % Уникальный ID
            
            TrashList = [TrashList, newTrash];
            
            % Создаем графический объект для него
            cols = {'r', 'b', 'g'};
            h_t = plot3(ax, newTrash.x, newTrash.y, newTrash.z, ...
                'o', 'MarkerSize', 8, 'MarkerFaceColor', cols{newTrash.type}, 'MarkerEdgeColor', 'k');
            TrashHandles = [TrashHandles, h_t];
        end
        
        %% Б. ЛОГИКА РОБОТА (STATE MACHINE)
        switch Rob.State
            case 0 % IDLE (Поиск цели)
                % Ищем ближайший мусор, который в зоне досягаемости (-0.2 < x < 0.2)
                % и который еще на ленте (state=0)
                best_idx = -1;
                max_x = -999;
                
                for i = 1:length(TrashList)
                    t = TrashList(i);
                    if t.state == 0 && t.x > -0.4 && t.x < 0.1 && abs(t.y) < 0.5
                        % Берем тот, который проехал дальше всех (ближе к выходу)
                        if t.x > max_x
                            max_x = t.x;
                            best_idx = i;
                        end
                    end
                end
                
                if best_idx ~= -1
                    Rob.TargetTrashID = TrashList(best_idx).id;
                    Rob.State = 1; % Перехват
                    Rob.Timer = 0;
                else
                    % Плавно возвращаемся домой, если нечего делать
                    Rob.Pos = Rob.Pos * 0.95 + [0;0;-0.4] * 0.05;
                end
                
            case 1 % INTERCEPT (Движение к мусору)
                % Находим индекс цели
                idx = find([TrashList.id] == Rob.TargetTrashID, 1);
                
                if isempty(idx)
                    Rob.State = 0; % Цель исчезла
                else
                    target_pos = [TrashList(idx).x; TrashList(idx).y; TrashList(idx).z];
                    
                    % Двигаемся к цели быстро (скорость робота ~ 2 м/с)
                    dir = target_pos - Rob.Pos;
                    dist = norm(dir);
                    speed_rob = 2.0 * dt_sim; 
                    
                    if dist < speed_rob
                        Rob.Pos = target_pos;
                        Rob.State = 2; % Схватил
                        TrashList(idx).state = 1; % Gripped
                        
                        % Определяем куда кидать
                        switch TrashList(idx).type
                            case 1, target_bin = Bin_Red;
                            case 2, target_bin = Bin_Blue;
                            case 3, target_bin = Bin_Green;
                        end
                        
                        % Расчет точки сброса (Ballistic Release Point)
                        vec_to_bin = target_bin(1:3) - Rob.Pos;
                        dir_throw = vec_to_bin / norm(vec_to_bin);
                        Rob.ThrowStartPos = Rob.Pos;
                        Rob.TargetPos = Rob.Pos + dir_throw * 0.25 + [0;0;0.15]; % Разгон 25см + вверх
                        Rob.Timer = 0;
                        
                    else
                        Rob.Pos = Rob.Pos + (dir/dist) * speed_rob;
                    end
                end
                
            case 2 % THROW MOVE (Разгон для броска)
                Rob.Timer = Rob.Timer + dt_sim;
                throw_duration = 0.15; % За сколько секунд совершаем рывок
                p = Rob.Timer / throw_duration;
                
                if p >= 1
                    p = 1;
                    % МОМЕНТ БРОСКА
                    idx = find([TrashList.id] == Rob.TargetTrashID, 1);
                    if ~isempty(idx)
                        TrashList(idx).state = 2; % Летит
                        
                        % Расчет физики (твоя функция)
                        switch TrashList(idx).type
                            case 1, tb = Bin_Red;
                            case 2, tb = Bin_Blue;
                            case 3, tb = Bin_Green;
                        end
                        [v_vec, ~] = calculate_ballistic_vel(Rob.Pos, tb, g);
                        TrashList(idx).vx = v_vec(1);
                        TrashList(idx).vy = v_vec(2);
                        TrashList(idx).vz = v_vec(3);
                    end
                    Rob.State = 3; % Возврат
                end
                
                % Квадратичная интерполяция для рывка
                Rob.Pos = Rob.ThrowStartPos * (1-p^2) + Rob.TargetPos * p^2;
                
                % Если держим мусор, он двигается с роботом
                idx = find([TrashList.id] == Rob.TargetTrashID, 1);
                if ~isempty(idx)
                    TrashList(idx).x = Rob.Pos(1);
                    TrashList(idx).y = Rob.Pos(2);
                    TrashList(idx).z = Rob.Pos(3);
                end
                
            case 3 % RETURN (Возврат домой)
                dir = [0;0;-0.4] - Rob.Pos;
                dist = norm(dir);
                speed_ret = 1.5 * dt_sim;
                if dist < speed_ret
                    Rob.State = 0;
                else
                    Rob.Pos = Rob.Pos + (dir/dist) * speed_ret;
                end
        end
        
        %% В. ФИЗИКА ВСЕГО МУСОРА
        to_delete = [];
        for i = 1:length(TrashList)
            if TrashList(i).state == 0 % На ленте
                TrashList(i).x = TrashList(i).x + Conv.Speed * dt_sim;
                
                % Если уехал за край - Промах
                if TrashList(i).x > 0.8
                    Counts.Missed = Counts.Missed + 1;
                    set(txt_missed, 'String', num2str(Counts.Missed));
                    to_delete = [to_delete, i]; %#ok<AGROW>
                end
                
            elseif TrashList(i).state == 2 % В полете (Баллистика)
                TrashList(i).x = TrashList(i).x + TrashList(i).vx * dt_sim;
                TrashList(i).y = TrashList(i).y + TrashList(i).vy * dt_sim;
                TrashList(i).z = TrashList(i).z + TrashList(i).vz * dt_sim - 0.5 * g * dt_sim^2;
                TrashList(i).vz = TrashList(i).vz - g * dt_sim;
                
                % Если упал ниже пола
                if TrashList(i).z < -0.7
                    % Проверяем попадание (упрощенно по дистанции до урн)
                    % Тут считаем что попал, если был брошен
                    Counts.Sorted = Counts.Sorted + 1;
                    set(txt_sorted, 'String', num2str(Counts.Sorted));
                    to_delete = [to_delete, i]; %#ok<AGROW>
                end
            end
        end
        
        % Удаление старого мусора и очистка графики
        if ~isempty(to_delete)
            % С конца, чтобы не сбить индексы
            to_delete = sort(to_delete, 'descend');
            for k = to_delete
                delete(TrashHandles(k));
                TrashHandles(k) = [];
                TrashList(k) = [];
            end
        end
        
        %% Г. ОТРИСОВКА
        UpdateRobot(h_robot, Rob.Pos, rob_par);
        
        % Обновляем позиции всех шариков
        for i = 1:length(TrashList)
            set(TrashHandles(i), 'XData', TrashList(i).x, ...
                                 'YData', TrashList(i).y, ...
                                 'ZData', TrashList(i).z);
        end
        
        drawnow limitrate;
        
        % Задержка для управления частотой кадров (чтобы слайдер работал корректно)
        if time_scale < 0.1
             pause(0.01);
        end
    end
end

%% ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
function [V_release, t_flight] = calculate_ballistic_vel(P_release, P_target, g)
    delta_z = P_release(3) - P_target(3);
    if delta_z <= 0
        t_flight = 0.6;
        vz = (P_target(3) - P_release(3) + 0.5*g*t_flight^2) / t_flight;
    else
        t_flight = sqrt(2 * delta_z / g);
        vz = 0; 
    end
    vx = (P_target(1) - P_release(1)) / t_flight;
    vy = (P_target(2) - P_release(2)) / t_flight;
    V_release = [vx, vy, vz];
end

function h_group = CreateRobotGroup()
    h_group.legs = gobjects(3,1);
    h_group.plat = plot3(0,0,0, 'k-', 'LineWidth', 2);
    colors = {'b', 'r', '#D95319'};
    for i=1:3
        h_group.legs(i) = plot3([0 0 0], [0 0 0], [0 0 0], 'Color', colors{i}, 'LineWidth', 2);
    end
end

function UpdateRobot(h_group, pos, p)
    q = InverseKinematics(pos, p);
    phi = [0; 2*pi/3; 4*pi/3];
    Base = zeros(3,3); Knee = zeros(3,3); Plat = zeros(3,3);
    for i=1:3
        Base(:,i) = [p.R_base*cos(phi(i)); p.R_base*sin(phi(i)); 0];
        r_h = p.R_base + p.L1 * cos(q(i));
        z_h = -p.L1 * sin(q(i));
        Knee(:,i) = [r_h*cos(phi(i)); r_h*sin(phi(i)); z_h];
        Plat(:,i) = pos + [p.R_plat*cos(phi(i)); p.R_plat*sin(phi(i)); 0];
        set(h_group.legs(i), 'XData', [Base(1,i) Knee(1,i) Plat(1,i)], ...
                             'YData', [Base(2,i) Knee(2,i) Plat(2,i)], ...
                             'ZData', [Base(3,i) Knee(3,i) Plat(3,i)]);
    end
    set(h_group.plat, 'XData', [Plat(1,:) Plat(1,1)], 'YData', [Plat(2,:) Plat(2,1)], 'ZData', [Plat(3,:) Plat(3,1)]);
end

function q = InverseKinematics(pos, p)
    x = pos(1); y = pos(2); z = pos(3);
    q = zeros(3,1);
    phi = [0; 2*pi/3; 4*pi/3];
    for i=1:3
        x_rot = x*cos(phi(i)) + y*sin(phi(i));
        y_rot = -x*sin(phi(i)) + y*cos(phi(i));
        val1 = x_rot + p.R_plat - p.R_base;
        val2 = z;
        D = sqrt(val1^2 + val2^2);
        L2_proj = sqrt(p.L2^2 - y_rot^2);
        alpha = atan2(val2, val1);
        beta  = acos((p.L1^2 + D^2 - L2_proj^2) / (2 * p.L1 * D));
        q(i) = -(alpha + beta);
        if ~isreal(q(i)), q(i) = 0; end
    end
end

function DrawBin(pos, col, name)
    [x,y,z] = cylinder(0.2, 20); 
    z(1,:) = -1.0; z(2,:) = pos(3);
    x = x + pos(1); y = y + pos(2);
    surf(x,y,z, 'FaceColor', col, 'FaceAlpha', 0.4, 'EdgeColor', 'none');
    text(pos(1), pos(2), pos(3)+0.3, name, 'HorizontalAlignment', 'center', 'Color', col, 'FontWeight','bold');
end

function DrawFloor()
    patch([-1 -1 1 1], [-1 1 1 -1], [-0.8 -0.8 -0.8 -0.8], [0.9 0.9 0.9], 'EdgeColor', 'none');
end