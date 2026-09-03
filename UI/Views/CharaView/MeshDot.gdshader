shader_type canvas_item;

// 网点的颜色，设置为白色
uniform vec4 dot_color : source_color = vec4(1.0);
// 背景颜色，设置为黑色或透明
uniform vec4 bg_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);

// 控制网点的大小和间距
uniform float dot_size = 0.3;
uniform float spacing = 40.0;

// 控制整体移动的速度和方向 (x: 水平, y: 垂直)
uniform vec2 move_speed = vec2(-0.5, -0.5);

// 控制中心区域网点放大的程度和范围
uniform float center_scale = 3.0;
uniform float center_radius = 0.4;

// 用于抗锯齿的平滑度
uniform float smoothness = 0.02;

// Godot 4.7 的 canvas_item shader 不再自动对 fragment 输出应用 modulate 链。
// vertex() 中 COLOR 内置变量包含完整 modulate * self_modulate * 父节点链，
// 经 varying 传到 fragment 显式乘回，让父节点淡出时网点跟着淡出。
varying vec4 modulate_chain;

void vertex() {
    modulate_chain = COLOR;
}

void fragment() {
    // 1. 获取当前像素的坐标
    vec2 uv = UV * 1.0;
    vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
    vec2 pixel_coord = uv * screen_size;

    // 2. 计算随时间移动的网格偏移
    //    乘以 -1.0 让网点向左上方 (negative direction) 移动[reference:1]
    vec2 offset = -1.0 * move_speed * TIME; 

    // 3. 计算每个网点所在的网格位置
    //    floor 和 spacing 将屏幕划分为网格
    vec2 grid_pos = floor((pixel_coord + offset) / spacing);
    // 计算网格的中心点坐标
    vec2 grid_center = grid_pos * spacing + spacing * 0.5 - offset;

    // 4. 计算当前像素到其所在网格中心的距离
    float dist = length(pixel_coord - grid_center);

    // 5. 核心：计算每个网点的动态半径
    //    5.1 获取网格中心对应的UV坐标 (0-1范围)
    vec2 grid_center_uv = grid_center / screen_size;
    //    5.2 计算网格中心到屏幕中心的距离 (0-1范围)
    float dist_to_center = length(grid_center_uv - 0.5);
    //    5.3 根据距离计算一个缩放因子。距离中心越近，缩放越大
    //        使用 1.0 - dist_to_center / center_radius 让中心区域缩放最大
    float scale_factor = 1.0 + (center_scale - 1.0) * (1.0 - smoothstep(0.0, center_radius, dist_to_center));
    //    5.4 计算最终的半径，并限制最大值，防止无限放大
    float radius = dot_size * spacing * 0.5 * min(scale_factor, center_scale);

    // 6. 绘制圆点
    //    smoothstep 用于抗锯齿，让圆点边缘更平滑[reference:2]
    float alpha = 1.0 - smoothstep(radius - smoothness, radius + smoothness, dist);
    // 如果当前像素到中心距离远大于半径，则 alpha 为 0，直接跳过
    if (alpha < 0.001) discard;

    // 7. 混合颜色，并乘回完整的 modulate 链（让父节点淡出时网点跟着淡出）
    COLOR = mix(bg_color, dot_color, alpha);
    COLOR *= modulate_chain;
}