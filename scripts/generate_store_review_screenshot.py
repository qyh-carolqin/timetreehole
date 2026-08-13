#!/usr/bin/env python3
"""生成 1024x1024 灵叶商店 App Store Connect IAP 审核图"""
import os
from PIL import Image, ImageDraw, ImageFont

# ---- 主题色（与 TimeTreehole/Theme/Theme.swift 一致） ----
BG_PRIMARY      = (0x0E, 0x1A, 0x12)
BG_SURFACE      = (0x18, 0x27, 0x1E)
BG_SURFACE_ELEV = (0x1F, 0x33, 0x27)
ACCENT_PRIMARY  = (0x7B, 0xB6, 0x61)
ACCENT_SECONDARY= (0xE8, 0xA0, 0x4C)
TEXT_PRIMARY    = (0xF0, 0xEB, 0xE0)
TEXT_SECONDARY  = (0x9C, 0xB0, 0xA2)
TEXT_MUTED      = (0x5C, 0x6B, 0x62)
BORDER_SUBTLE   = (0x2A, 0x3A, 0x30)

W, H = 1024, 1024
FONT_PATH = r"C:\Windows\Fonts\msyh.ttc"

def hex_rgb(h):
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def get_font(size, bold=False):
    try:
        return ImageFont.truetype(FONT_PATH, size, index=1 if bold else 0)
    except Exception:
        return ImageFont.truetype(FONT_PATH, size)

def rounded_rect(draw, xy, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)

def gradient_rect(img, xy, radius, color_top, color_bottom, alpha_top=255, alpha_bottom=255):
    """在 xy 区域绘制纵向渐变圆角矩形"""
    x1, y1, x2, y2 = xy
    w, h = x2 - x1, y2 - y1
    base = Image.new("RGBA", (w, h))
    for y in range(h):
        ratio = y / max(h - 1, 1)
        r = int(color_top[0] * (1 - ratio) + color_bottom[0] * ratio)
        g = int(color_top[1] * (1 - ratio) + color_bottom[1] * ratio)
        b = int(color_top[2] * (1 - ratio) + color_bottom[2] * ratio)
        a = int(alpha_top * (1 - ratio) + alpha_bottom * ratio)
        for x in range(w):
            base.putpixel((x, y), (r, g, b, a))
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)
    img.paste(base, (x1, y1), mask)

def draw_text(draw, text, pos, font, fill, anchor="lt"):
    draw.text(pos, text, font=font, fill=fill, anchor=anchor)

def text_size(draw, text, font):
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]

def main():
    img = Image.new("RGB", (W, H), BG_PRIMARY)
    draw = ImageDraw.Draw(img)

    fonts = {
        "title": get_font(56, bold=True),
        "subtitle": get_font(22),
        "section": get_font(28, bold=True),
        "body": get_font(24),
        "body_b": get_font(24, bold=True),
        "small": get_font(18),
        "tiny": get_font(16),
        "price": get_font(44, bold=True),
        "balance": get_font(64, bold=True),
        "badge": get_font(18, bold=True),
    }

    cx = W // 2
    card_w = 900
    left = (W - card_w) // 2
    y = 40

    # ---- 标题 ----
    draw_text(draw, "灵叶商店", (cx, y), fonts["title"], TEXT_PRIMARY, anchor="mt")
    y += 62
    draw_text(draw, "灵叶是树洞的能量，用来播种和发现更多故事", (cx, y), fonts["subtitle"], TEXT_SECONDARY, anchor="mt")
    y += 58

    # ---- 余额卡片 ----
    balance_h = 160
    gradient_rect(img, (left, y, left + card_w, y + balance_h), 28,
                  ACCENT_PRIMARY, BG_SURFACE, alpha_top=30, alpha_bottom=255)
    rounded_rect(draw, (left, y, left + card_w, y + balance_h), 28,
                 outline=tuple(c + round((255 - c) * 0.2) for c in ACCENT_PRIMARY), width=2)
    draw_text(draw, "我的灵叶", (left + 32, y + 28), fonts["body"], TEXT_SECONDARY)
    draw_text(draw, "0", (left + 32, y + 64), fonts["balance"], ACCENT_PRIMARY)
    tw, th = text_size(draw, "0", fonts["balance"])
    draw_text(draw, "灵叶", (left + 36 + tw, y + 90), fonts["body"], TEXT_SECONDARY)
    # 装饰叶子
    lx, ly = left + card_w - 84, y + balance_h // 2
    leaf = Image.new("RGBA", (88, 88), (0, 0, 0, 0))
    ld = ImageDraw.Draw(leaf)
    ld.ellipse((0, 0, 87, 87), fill=(*ACCENT_PRIMARY, 60))
    ld.polygon([(44, 18), (66, 44), (44, 70), (22, 44)], fill=(*ACCENT_PRIMARY, 180))
    img.paste(leaf, (lx - 44, ly - 44), leaf)
    y += balance_h + 36

    # ---- 今日配额 ----
    quota_h = 200
    rounded_rect(draw, (left, y, left + card_w, y + quota_h), 20, fill=BG_SURFACE)
    qy = y + 18
    draw_text(draw, "今日配额", (left + 24, qy), fonts["section"], TEXT_PRIMARY)
    qy += 48

    def quota_row(qy_local, icon_points, label, used, max_count, cost):
        # 图标圆圈
        ix = left + 28
        draw.ellipse((ix, qy_local, ix + 38, qy_local + 38), fill=BORDER_SUBTLE)
        # 小三角箭头
        draw.polygon(icon_points, fill=ACCENT_PRIMARY)
        tx = left + 80
        draw_text(draw, label, (tx, qy_local + 2), fonts["body"], TEXT_PRIMARY)
        # 进度条
        bar_y = qy_local + 32
        bar_w = card_w - 110
        rounded_rect(draw, (tx, bar_y, tx + bar_w, bar_y + 8), 4, fill=BORDER_SUBTLE)
        fill_w = int(bar_w * min(used, max_count) / max_count)
        if fill_w > 0:
            rounded_rect(draw, (tx, bar_y, tx + fill_w, bar_y + 8), 4, fill=ACCENT_PRIMARY)
        # 文字
        draw_text(draw, f"{used}/{max_count} 次免费", (tx, bar_y + 16), fonts["tiny"], TEXT_MUTED)
        cost_text = f"超出需 {cost} 灵叶"
        cw, _ = text_size(draw, cost_text, fonts["tiny"])
        draw_text(draw, cost_text, (left + card_w - 24 - cw, bar_y + 16), fonts["tiny"], ACCENT_SECONDARY)

    up_points = [(left + 47, qy + 10), (left + 37, qy + 26), (left + 57, qy + 26)]
    quota_row(qy, up_points, "上传到公共域", 0, 1, 10)
    qy += 66
    down_points = [(left + 37, qy + 10), (left + 57, qy + 10), (left + 47, qy + 26)]
    quota_row(qy, down_points, "从公共域获取", 0, 1, 5)
    y += quota_h + 36

    # ---- 充值套餐标题 ----
    draw_text(draw, "充值灵叶", (left, y), fonts["section"], TEXT_PRIMARY)
    rr_text = "恢复购买"
    rr_w, _ = text_size(draw, rr_text, fonts["body"])
    draw_text(draw, rr_text, (left + card_w, y + 4), fonts["body"], ACCENT_PRIMARY, anchor="rt")
    y += 48

    # ---- 三个产品卡片（横向） ----
    products = [
        {"name": "一袋灵叶", "credits": "50 灵叶", "price": "¥6", "per": "¥0.12/灵叶", "popular": False},
        {"name": "一捧灵叶", "credits": "120 灵叶", "price": "¥12", "per": "¥0.10/灵叶", "popular": True},
        {"name": "一篮灵叶", "credits": "300 灵叶 · 超值装", "price": "¥25", "per": "¥0.08/灵叶", "popular": False},
    ]
    p_card_w = 280
    p_card_h = 260
    p_gap = 30
    start_x = (W - (p_card_w * 3 + p_gap * 2)) // 2
    for i, p in enumerate(products):
        px = start_x + i * (p_card_w + p_gap)
        bg = tuple(round(ACCENT_PRIMARY[j] * 0.08 + BG_SURFACE[j] * 0.92) for j in range(3)) if p["popular"] else BG_SURFACE
        outline = tuple(round(ACCENT_PRIMARY[j] * 0.3 + BG_SURFACE[j] * 0.7) for j in range(3)) if p["popular"] else BORDER_SUBTLE
        rounded_rect(draw, (px, y, px + p_card_w, y + p_card_h), 20, fill=bg, outline=outline, width=2)

        # 名称 + 热门 badge
        name_x = px + 20
        name_y = y + 22
        draw_text(draw, p["name"], (name_x, name_y), fonts["body_b"], TEXT_PRIMARY)
        if p["popular"]:
            nw, nh = text_size(draw, p["name"], fonts["body_b"])
            badge_text = "热门"
            bw, bh = text_size(draw, badge_text, fonts["badge"])
            bx = name_x + nw + 10
            by = name_y
            rounded_rect(draw, (bx, by, bx + bw + 16, by + 26), 13, fill=ACCENT_SECONDARY)
            draw_text(draw, badge_text, (bx + 8, by + 4), fonts["badge"], BG_PRIMARY)

        # 灵叶数
        draw_text(draw, p["credits"], (px + 20, y + 58), fonts["small"], TEXT_SECONDARY)
        # 价格
        draw_text(draw, p["price"], (px + p_card_w - 20, y + 180), fonts["price"], ACCENT_PRIMARY, anchor="rs")
        # 单价
        draw_text(draw, p["per"], (px + p_card_w - 20, y + 222), fonts["tiny"], TEXT_MUTED, anchor="rs")

    y += p_card_h + 36

    # ---- 使用规则 ----
    rules_h = 100
    rounded_rect(draw, (left, y, left + card_w, y + rules_h), 20, fill=BG_SURFACE)
    draw_text(draw, "灵叶使用规则", (left + 24, y + 16), fonts["body_b"], TEXT_SECONDARY)
    rules = [
        (ACCENT_PRIMARY, "上传种子到公共域：10 灵叶 / 次"),
        (ACCENT_PRIMARY, "从公共域获取种子：5 灵叶 / 次"),
        (ACCENT_SECONDARY, "每天免费上传 1 次 + 获取 1 次"),
        (ACCENT_SECONDARY, "每日免费额度每天 0:00 重置"),
    ]
    col_w = (card_w - 48) // 2
    for idx, (dot_color, text) in enumerate(rules):
        col = idx % 2
        row = idx // 2
        rx = left + 24 + col * col_w
        ry = y + 50 + row * 30
        draw.ellipse((rx, ry + 4, rx + 10, ry + 14), fill=dot_color)
        draw_text(draw, text, (rx + 18, ry), fonts["tiny"], TEXT_SECONDARY)

    # 保存严格合规版本：RGB、72 dpi、无 alpha、英文文件名避免上传异常
    out_dir = r"D:\时间树洞APP\design-exports"
    out_path_en = os.path.join(out_dir, "credits-store-1024.png")
    out_path_cn = os.path.join(out_dir, "灵叶商店-1024.png")
    save_kwargs = {"format": "PNG", "dpi": (72, 72)}
    img.save(out_path_en, **save_kwargs)
    img.save(out_path_cn, **save_kwargs)
    print(f"Saved: {out_path_en}")
    print(f"Saved: {out_path_cn}")

if __name__ == "__main__":
    main()
