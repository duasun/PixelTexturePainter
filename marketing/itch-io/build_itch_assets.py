"""Build itch.io images from the source art and real app screenshots beside this file."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "source"
BG = "#141a20"
WHITE = "#f5f2ec"
MUTED = "#aeb8bd"
ORANGE = "#eea765"
TEAL = "#54c8b4"
FONT = Path("C:/Windows/Fonts/segoeui.ttf")
BOLD = Path("C:/Windows/Fonts/segoeuib.ttf")


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(BOLD if bold else FONT), size)


def photo(name: str, size: tuple[int, int]) -> Image.Image:
    with Image.open(SOURCE / name) as image:
        return ImageOps.fit(image.convert("RGB"), size, Image.Resampling.LANCZOS)


def cover() -> Image.Image:
    image = Image.new("RGB", (630, 500), BG)
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 630, 7), fill=ORANGE)
    draw.text((27, 19), "3D PIXEL TEXTURE TOOL", font=font(15, True), fill=ORANGE)
    draw.text((25, 45), "Pixel texture painter", font=font(41, True), fill=WHITE)
    image.paste(photo("key_art.png", (630, 338)), (0, 108))
    draw.rectangle((0, 446, 630, 500), fill=BG)
    draw.rectangle((27, 465, 33, 483), fill=TEAL)
    draw.text((45, 460), "PAINT IN 3D  /  EDIT IN 2D", font=font(22, True), fill=WHITE)
    return image


def gallery(number: int, image_name: str, title: str, lines: list[str]) -> Image.Image:
    image = Image.new("RGB", (1280, 720), BG)
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 1280, 7), fill=ORANGE)
    draw.text((52, 27), f"PIXEL TEXTURE PAINTER  /  {number:02d}", font=font(18, True), fill=ORANGE)
    draw.text((50, 55), title, font=font(51, True), fill=WHITE)
    draw.rounded_rectangle((47, 142, 1018, 693), radius=9, fill="#0a0e11")
    image.paste(photo(image_name, (960, 540)), (52, 147))
    draw.line((1037, 171, 1037, 610), fill=ORANGE, width=3)
    y = 194
    for line in lines:
        draw.text((1056, y), line, font=font(27, True), fill=WHITE)
        y += 39
    draw.text((1057, 635), "REAL APP CAPTURE", font=font(14, True), fill=MUTED)
    return image


def banner() -> Image.Image:
    image = photo("paint_art.png", (1280, 720))
    tint = Image.new("RGBA", image.size, (0, 0, 0, 0))
    overlay = ImageDraw.Draw(tint)
    overlay.rectangle((0, 0, 1280, 8), fill=(238, 167, 101, 255))
    overlay.rounded_rectangle((37, 35, 702, 170), radius=18, fill=(13, 19, 24, 225))
    image = Image.alpha_composite(image.convert("RGBA"), tint)
    draw = ImageDraw.Draw(image)
    draw.text((63, 52), "Paint low-poly models", font=font(53, True), fill=WHITE)
    draw.text((65, 122), "3D model and UV canvas, side by side", font=font(24), fill=ORANGE)
    draw.rounded_rectangle((1075, 676, 1250, 704), radius=5, fill=(15, 21, 26, 215))
    draw.text((1086, 681), "PROMOTIONAL ART", font=font(14, True), fill=WHITE)
    return image.convert("RGB")


def gif_slide(title: str, screenshot: str) -> Image.Image:
    image = Image.new("RGB", (630, 500), BG)
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 630, 7), fill=TEAL)
    draw.text((26, 23), title, font=font(39, True), fill=WHITE)
    image.paste(photo(screenshot, (630, 354)), (0, 101))
    draw.rectangle((0, 455, 630, 500), fill=BG)
    draw.text((27, 466), "Pixel texture painter", font=font(20, True), fill=ORANGE)
    return image


def main() -> None:
    outputs = {
        "cover_630x500.png": cover(),
        "gallery_01_paint.png": gallery(1, "gradient_preview.png", "Paint on the model", ["3D MODEL", "+ UV MAP", "", "One painting", "workspace."]),
        "gallery_02_uv.png": gallery(2, "inspector_1.png", "Edit the UV layout", ["GENERATE", "& INSPECT", "", "Work with", "UV islands."]),
        "gallery_03_stamp.png": gallery(3, "inspector_2.png", "Crop and paint stamps", ["STAMP", "TOOLS", "", "Choose source", "pixels."]),
        "banner_1280x720.png": banner(),
    }
    for name, image in outputs.items():
        image.save(ROOT / name, optimize=True)

    frames = [
        outputs["cover_630x500.png"],
        gif_slide("Paint in 3D", "workspace.png"),
        gif_slide("Edit UVs", "inspector_1.png"),
        gif_slide("Use stamps", "inspector_2.png"),
    ]
    animation = []
    durations = []
    for index, frame in enumerate(frames):
        animation.append(frame)
        durations.append(1500 if index == 0 else 1150)
        next_frame = frames[(index + 1) % len(frames)]
        for step in (0.25, 0.5, 0.75):
            animation.append(Image.blend(frame, next_frame, step))
            durations.append(80)
    palette_frames = [frame.quantize(colors=96, method=Image.Quantize.MEDIANCUT) for frame in animation]
    palette_frames[0].save(
        ROOT / "preview_630x500.gif",
        save_all=True,
        append_images=palette_frames[1:],
        duration=durations,
        loop=0,
        optimize=True,
        disposal=2,
    )
    for name in (*outputs, "preview_630x500.gif"):
        print(f"{name}: {(ROOT / name).stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
