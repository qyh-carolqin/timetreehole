#!/usr/bin/env python3
"""生成 iPhone 尺寸灵叶商店截图，用于 App Store Connect IAP 审核信息"""
import os
from PIL import Image, ImageDraw, ImageFont

# ---- 主题色（与 App 一致） ----
BG_PRIMARY      = (0x0E, 0x1A, 0x12)
BG_SURFACE      = (0x18, 0x27, 0x1E)
BG_SURFACE_ELEV = (0x1F, 0x33, 0x27)
ACCENT_PRIMARY  = (0x7B, 0xB6, 0x61)
ACCENT_SECONDARY= (0xE8, 0xA0, 0x4C)
TEXT_PRIMARY    = (0xF0, 0xEB, 0xE0)
TEXT_SECONDARY  = (0x9C, 0xB0, 0xA2)
TEXT_MUTED      = (0x5C, 0x6B, 0x62)
BORDER_SUBTLE   = (0x2A, 0x3A, 0x30)

FONT_PATH = r"C:\Windows\Fonts\msyh.ttc"

SIZES = {
    "iphone16promax": (1290, 2796),
    "iphone16pro": (1179, 2556),
}


def get_font(size, bold=False):
    try:
        return ImageFont.truetype(FONT_PATH, size, index=1 if bold else 0)
    except Exception:
        return ImageFont.truetype(FONT_PATH, size)


def text_size(draw, text, font):
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def draw_text(draw, text, pos, font, color, anchor="lt"):
    draw.text(pos, text, font=font, fill=color, anchor=anchor)


def rounded_rect(draw, xy, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def draw_status_bar(draw, w, top_h=59):
    """iPhone 灵动岛占位 + 状态栏时间"""
    # 灵动岛胶囊
    island_w, island_h = 126, 37
    island_x, island_y = (w - island_w) // 2, 12
    rounded_rect(draw, (island_x, island_y, island_x + island_w, island_y + island_h), 18, fill=BG_SURFACE)
    # 时间
    font = get_font(17, bold=True)
    draw_text(draw, "9:41", (w - 34, 21), font, TEXT_PRIMARY, anchor="rm")
    # 信号/电池图标简化
    draw.rectangle((34, 21, 52, 26), fill=TEXT_PRIMARY, outline=None)
    draw.rectangle((56, 21, 74, 26), fill=TEXT_PRIMARY, outline=None)
    draw.rectangle((78, 19, 96, 28), outline=TEXT_PRIMARY, width=2)
    draw.rectangle((80, 21, 91, 26), fill=ACCENT_PRIMARY, outline=None)


def draw_bottom_bar(draw, w, h, bar_h=92):
    y = h - bar_h
    draw.rectangle((0, y, w, h), fill=BG_SURFACE)
    # home indicator
    draw.rounded_rectangle(((w - 134) // 2, y + 62, (w + 134) // 2, y + 68), 3, fill=TEXT_MUTED)
    icons = [("leaf.fill", "灵叶"), ("tree.fill", "树洞"), ("person.fill", "我的")]
    font = get_font(13)
    for idx, (icon_name, label) in enumerate(icons):
        x = (w // 4) * (idx + 1) - w // 8
        icon_color = ACCENT_PRIMARY if idx == 0 else TEXT_MUTED
        text_color = TEXT_PRIMARY if idx == 0 else TEXT_MUTED
        # 简化图标用圆点/方块代替，避免 emoji 问题
        r = 12
        draw.ellipse((x - r, y + 16, x + r, y + 40), fill=icon_color)
        lw, lh = text_size(draw, label, font)
        draw_text(draw, label, (x, y + 52), font, text_color, anchor="mm")


def generate(size_name, w, h):
    img = Image.new("RGB", (w, h), BG_PRIMARY)
    draw = ImageDraw.Draw(img)

    fonts = {
        "large": get_font(42, bold=True),
        "title": get_font(32, bold=True),
        "body": get_font(26),
        "body_b": get_font(26, bold=True),
        "small": get_font(22),
        "tiny": get_font(18),
        "price": get_font(34, bold=True),
    }

    margin = 58
    top_y = 95

    draw_status_bar(draw, w)

    # 标题
    draw_text(draw, "灵叶商店", (w // 2, top_y), fonts["large"], TEXT_PRIMARY, anchor="mm")
    top_y += 80

    # 余额卡片
    card_h = 140
    rounded_rect(draw, (margin, top_y, w - margin, top_y + card_h), 24, fill=BG_SURFACE)
    rounded_rect(draw, (margin, top_y, w - margin, top_y + card_h), 24, outline=BORDER_SUBTLE, width=2)
    draw_text(draw, "当前灵叶", (margin + 26, top_y + 24), fonts["small"], TEXT_SECONDARY)
    draw_text(draw, "0", (margin + 26, top_y + 64), fonts["title"], TEXT_PRIMARY)
    draw_text(draw, "可用于上传/获取种子", (margin + 26, top_y + 110), fonts["tiny"], TEXT_MUTED)
    top_y += card_h + 28

    # 今日配额
    q_card_h = 90
    rounded_rect(draw, (margin, top_y, w - margin, top_y + q_card_h), 20, fill=BG_SURFACE_ELEV)
    draw_text(draw, "今日免费", (margin + 24, top_y + 20), fonts["small"], TEXT_SECONDARY)
    draw_text(draw, "上传 0/1 次 · 获取 0/1 次", (margin + 24, top_y + 52), fonts["tiny"], TEXT_SECONDARY)
    top_y += q_card_h + 36

    # 套餐标题
    draw_text(draw, "充值灵叶", (margin, top_y), fonts["body_b"], TEXT_PRIMARY)
    top_y += 56

    packages = [
        ("一袋灵叶", "50 灵叶", "¥6", False),
        ("一捧灵叶", "120 灵叶", "¥12", True),
        ("一篮灵叶", "300 灵叶", "¥25", False),
    ]
    pkg_h = 152
    gap = 22

    for name, amount, price, hot in packages:
        rounded_rect(draw, (margin, top_y, w - margin, top_y + pkg_h), 24, fill=BG_SURFACE)
        rounded_rect(draw, (margin, top_y, w - margin, top_y + pkg_h), 24, outline=BORDER_SUBTLE, width=2)

        # 叶子图标
        leaf_r = 22
        draw.ellipse((margin + 24, top_y + 22, margin + 24 + leaf_r * 2, top_y + 22 + leaf_r * 2), fill=ACCENT_PRIMARY)
        draw_text(draw, amount, (margin + 84, top_y + 34), fonts["body_b"], TEXT_PRIMARY)

        # 价格和按钮
        draw_text(draw, price, (w - margin - 24, top_y + 40), fonts["price"], ACCENT_PRIMARY, anchor="rm")
        btn_w, btn_h = 120, 46
        btn_x = w - margin - 24 - btn_w
        btn_y = top_y + 84
        rounded_rect(draw, (btn_x, btn_y, btn_x + btn_w, btn_y + btn_h), 12, fill=ACCENT_PRIMARY)
        draw_text(draw, "购买", (btn_x + btn_w // 2, btn_y + btn_h // 2), fonts["small"], BG_PRIMARY, anchor="mm")

        draw_text(draw, name, (margin + 24, top_y + 84), fonts["small"], TEXT_SECONDARY)
        draw_text(draw, "每日额度用尽后使用", (margin + 24, top_y + 114), fonts["tiny"], TEXT_MUTED)

        if hot:
            badge_w, badge_h = 76, 28
            badge_x = w - margin - 24 - btn_w - badge_w - 16
            badge_y = top_y + 88
            rounded_rect(draw, (badge_x, badge_y, badge_x + badge_w, badge_y + badge_h), 8, fill=ACCENT_SECONDARY)
            draw_text(draw, "热门", (badge_x + badge_w // 2, badge_y + badge_h // 2), fonts["tiny"], BG_PRIMARY, anchor="mm")

        top_y += pkg_h + gap

    # 使用规则
    top_y += 18
    rules_h = 130
    rounded_rect(draw, (margin, top_y, w - margin, top_y + rules_h), 20, fill=BG_SURFACE)
    draw_text(draw, "使用规则", (margin + 24, top_y + 18), fonts["body_b"], TEXT_SECONDARY)
    rules = [
        "· 上传种子到公共域：10 灵叶 / 次",
        "· 从公共域获取种子：5 灵叶 / 次",
        "· 每天免费上传 1 次 + 获取 1 次，0:00 重置",
    ]
    ry = top_y + 56
    for line in rules:
        draw_text(draw, line, (margin + 24, ry), fonts["tiny"], TEXT_SECONDARY)
        ry += 30

    # 底部导航
    draw_bottom_bar(draw, w, h)

    out_path = os.path.join(r"D:\时间树洞APP\design-exports", f"credits-store-{size_name}.jpg")
    img.save(out_path, "JPEG", quality=95, dpi=(72, 72))
    print(f"Saved: {out_path}  ({w}x{h})")
    return out_path


if __name__ == "__main__":
    for name, (w, h) in SIZES.items():
        generate(name, w, h)
