#!/usr/bin/env python3
"""生成无水印的 1024x1024 App Store 图标"""
import math
from PIL import Image, ImageDraw, ImageFilter, ImageChops

SIZE = 1024

def radial_gradient(size, color_inner, color_outer):
    """创建径向渐变背景"""
    img = Image.new('RGB', (size, size), color_outer)
    draw = ImageDraw.Draw(img)
    cx, cy = size // 2, size // 2
    max_r = int(math.hypot(cx, cy))
    for r in range(max_r, 0, -3):
        t = r / max_r
        r_i = color_inner[0]
        g_i = color_inner[1]
        b_i = color_inner[2]
        r_o = color_outer[0]
        g_o = color_outer[1]
        b_o = color_outer[2]
        col = (
            int(r_i + (r_o - r_i) * t),
            int(g_i + (g_o - g_i) * t),
            int(b_i + (b_o - b_i) * t),
        )
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
    return img

def create_leaf_shape(cx, cy, w, h):
    """创建叶片形状 (贝塞尔曲线近似)"""
    half_w = w // 2
    top = cy - h // 2
    bottom = cy + h // 2
    
    # 叶片轮廓点：右侧从上到下，再左侧从下到上，形成闭合多边形
    points = []
    steps = 80
    
    # 右半边：顶部 → 右侧 → 底部
    for i in range(steps + 1):
        t = i / steps
        # 宽度随高度变化
        width_factor = math.sin(math.pi * t) * 0.95
        if t > 0.88:
            width_factor *= (1 - (t - 0.88) / 0.12 * 0.5)
        x = cx + half_w * width_factor
        y = top + t * h
        points.append((x, y))
    
    # 左半边：底部 → 左侧 → 顶部
    for i in range(steps, -1, -1):
        t = i / steps
        width_factor = math.sin(math.pi * t) * 0.95
        if t > 0.88:
            width_factor *= (1 - (t - 0.88) / 0.12 * 0.5)
        x = cx - half_w * width_factor
        y = top + t * h
        points.append((x, y))
    
    return points

def draw_glowing_leaf(img, cx, cy, w, h):
    """绘制发光的叶片"""
    top = cy - h // 2
    bottom = cy + h // 2
    
    # 外发光
    glow = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    for i in range(15, 0, -1):
        alpha = int(25 * (1 - i / 15))
        offset = i * 5
        leaf = create_leaf_shape(cx, cy, w + offset * 2, h + offset * 2)
        gdraw.polygon(leaf, fill=(120, 220, 140, alpha))
    
    # 叶片主体
    leaf_points = create_leaf_shape(cx, cy, w, h)
    mask = Image.new('L', (SIZE, SIZE), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.polygon(leaf_points, fill=255)
    
    # 左半边浅绿，右半边深绿
    leaf_img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    ldraw = ImageDraw.Draw(leaf_img)
    ldraw.polygon(leaf_points, fill=(150, 235, 160, 255))
    
    # 右半边深绿覆盖
    right_mask = Image.new('L', (SIZE, SIZE), 0)
    rdraw = ImageDraw.Draw(right_mask)
    rdraw.polygon([(cx, top - 10), (cx, bottom + 10), (cx + w, bottom + 10), (cx + w, top - 10)], fill=255)
    right_mask = ImageChops.multiply(mask, right_mask)
    
    dark_half = Image.new('RGBA', (SIZE, SIZE), (60, 160, 90, 255))
    leaf_img = Image.composite(dark_half, leaf_img, right_mask)
    
    # 顶部高光
    highlight = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(highlight)
    hl_w, hl_h = w // 3, h // 8
    hdraw.ellipse([cx - hl_w // 2, top - 5, cx + hl_w // 2, top + hl_h], fill=(220, 255, 230, 180))
    leaf_img = Image.alpha_composite(leaf_img, highlight)
    
    return Image.alpha_composite(glow, leaf_img)

def draw_firefly(draw, x, y, radius):
    """绘制萤火虫光点"""
    for i in range(6, 0, -1):
        alpha = int(70 * (1 - i / 6))
        draw.ellipse(
            [x - radius - i * 2, y - radius - i * 2,
             x + radius + i * 2, y + radius + i * 2],
            fill=(220, 255, 160, alpha)
        )
    draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=(255, 255, 220, 255))

def main():
    # 深森林绿渐变背景
    bg = radial_gradient(SIZE, (28, 58, 38), (10, 26, 16))
    
    # 半透明叠加层增加质感
    overlay = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    
    # 萤火虫
    fireflies = [
        (180, 260, 5), (320, 180, 4), (780, 240, 5),
        (850, 420, 4), (740, 760, 5), (210, 680, 4),
        (480, 820, 3), (820, 640, 4), (150, 480, 3),
        (660, 150, 3), (280, 780, 3)
    ]
    for fx, fy, fr in fireflies:
        draw_firefly(od, fx, fy, fr)
    
    # 中心叶片
    leaf = draw_glowing_leaf(Image.new('RGBA', (SIZE, SIZE)), SIZE // 2, SIZE // 2 + 10, 280, 420)
    
    # 合成
    composite = Image.alpha_composite(bg.convert('RGBA'), overlay)
    composite = Image.alpha_composite(composite, leaf)
    
    # 轻微模糊让发光更自然
    composite = composite.filter(ImageFilter.GaussianBlur(radius=0.5))
    
    # 转 RGB 保存
    final = composite.convert('RGB')
    final.save('D:/时间树洞APP/design-exports/App图标-1024-clean.png', 'PNG')
    final.save('D:/时间树洞APP/TimeTreehole/TimeTreehole/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png', 'PNG')
    print('✅ 已生成无水印 App 图标:')
    print('   - design-exports/App图标-1024-clean.png')
    print('   - TimeTreehole/TimeTreehole/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png')

if __name__ == '__main__':
    main()
