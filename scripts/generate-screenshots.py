#!/usr/bin/env python3
"""把 iPhone 6.7" (1290x2796) 素材生成 App Store Connect 需要的
6.5" (1242x2688) 与 13" iPad (2048x2732) 截屏。

- 6.5"：直接缩放，比例接近（1290/2796≈0.461，1242/2688≈0.462）。
- 13" iPad：采用 fit-height 居中放置，两侧留深色边。iPhone-only App
  在 iPad 上以兼容模式（2x）运行正是居中显示，画面诚实且可通过审核。
"""

from pathlib import Path
from PIL import Image

SRC_DIR = Path("D:/时间树洞APP/design-exports")
IPHONE66_DIR = SRC_DIR / "AppStore-6.5inch"
IPAD_DIR = SRC_DIR / "AppStore-ipad-13inch"

IPHONE66_SIZE = (1242, 2688)
IPAD_SIZE = (2048, 2732)
BG_COLOR = (18, 18, 24)  # 接近时间树洞深色背景


def fit_center(canvas: Image.Image, src: Image.Image) -> Image.Image:
    """按高度等比缩放后居中贴合（iPad 兼容模式效果）。"""
    scale = canvas.height / src.height
    new_w = int(src.width * scale)
    resized = src.resize((new_w, canvas.height), Image.LANCZOS)
    x = (canvas.width - new_w) // 2
    canvas.paste(resized, (x, 0))
    return canvas


def generate():
    IPHONE66_DIR.mkdir(exist_ok=True)
    IPAD_DIR.mkdir(exist_ok=True)

    sources = sorted(SRC_DIR.glob("AppStore截图-*.png"))
    if not sources:
        raise RuntimeError("找不到 AppStore截图-*.png 源文件")

    for src_path in sources:
        stem = src_path.stem.replace("AppStore截图-", "")
        img = Image.open(src_path).convert("RGB")

        # 6.5" iPhone
        iphone66 = img.resize(IPHONE66_SIZE, Image.LANCZOS)
        iphone66.save(IPHONE66_DIR / f"{stem}.jpg", "JPEG", quality=95)

        # 13" iPad：深色背景 + 居中 fit-height
        ipad = Image.new("RGB", IPAD_SIZE, BG_COLOR)
        fit_center(ipad, img)
        ipad.save(IPAD_DIR / f"{stem}.jpg", "JPEG", quality=95)

        print(f"✓ {src_path.name} → 6.5\" + iPad 13\"")


if __name__ == "__main__":
    generate()
