#!/system/bin/sh
# 指纹双击触发手电筒 - 自动识别event节点版
# 解决重启后event0变event3的问题

# 等待系统完全启动
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

# 核心：自动查找指纹传感器的event节点（根据KEY_SELECT事件特征）
find_fingerprint_event() {
    for event in /dev/input/event*; do
        # 检查该event节点是否支持KEY_SELECT事件，是则为指纹传感器
        if getevent -il "$event" 2>/dev/null | grep -q "KEY_SELECT"; then
            echo "$event"
            return 0
        fi
    done
    # 兜底：如果自动识别失败，按你设备实际情况添加常用节点（如event0/event3）
    echo "/dev/input/event3"
    return 1
}

# 初始化变量
FINGER_EVENT=$(find_fingerprint_event)
press_count=0
last_press_time=0
double_press_timeout=1  # 双击最大间隔（秒），可调整
log_file="/data/local/tmp/finger_torch.log"

# 写入启动日志，方便排查
echo "$(date +%Y-%m-%d\ %H:%M:%S) - 模块启动，识别到指纹节点：$FINGER_EVENT" >> "$log_file"

# 主监听逻辑
while true; do
    # 若节点失效，重新识别
    if [ ! -e "$FINGER_EVENT" ]; then
        FINGER_EVENT=$(find_fingerprint_event)
        echo "$(date +%Y-%m-%d\ %H:%M:%S) - 重新识别指纹节点：$FINGER_EVENT" >> "$log_file"
        sleep 1
        continue
    fi

    # 监听指纹按压事件
    getevent -l "$FINGER_EVENT" | while read line; do
        if echo "$line" | grep -q "KEY_SELECT.*DOWN"; then
            current_time=$(date +%s)
            time_diff=$((current_time - last_press_time))
            echo "$(date +%Y-%m-%d\ %H:%M:%S) - 检测到指纹按压，计数：$press_count，间隔：$time_diff秒" >> "$log_file"

            if [ $press_count -eq 0 ]; then
                # 第一次按压
                press_count=1
                last_press_time=$current_time
            elif [ $press_count -eq 1 ] && [ $time_diff -le $double_press_timeout ]; then
                # 第二次按压（在超时内），执行手电筒命令
                press_count=0
                last_press_time=0
                echo 8000 >> /sys/class/leds/led:torch_0/brightness
                echo 8000 >> /sys/class/leds/led:torch_3/brightness
                echo "$(date +%Y-%m-%d\ %H:%M:%S) - 双击生效，手电筒已开启" >> "$log_file"
                sleep 0.5  # 防抖，避免重复触发
            else
                # 超时，重置为第一次按压
                press_count=1
                last_press_time=$current_time
            fi
        fi
    done
    # 若getevent意外退出，1秒后重启监听
    sleep 1
done
