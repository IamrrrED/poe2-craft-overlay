# Промпт-пакет: макро гриба со спорами

Замысел: макро-кадр гриба в лесу, из-под шляпки вылетает облако спор, его подсвечивает контровой луч солнца,
есть движение, но шляпка остаётся резкой (глубина резкости малая, фокус на пластинках).

## Главный нюанс

**«8k» в промпте не даёт разрешения.** Модели генерируют 1024–1536 px по длинной стороне, а «8k» лишь
сдвигает стиль в сторону перенасыщенной «обоины». Настоящие 8k делаются двумя шагами: генерация → hires
fix/upscale (×2 дважды) → при необходимости тайловый апскейл. Поэтому слово «8k» из промпта убрано, а
разрешение задаётся в настройках.

**«National Geographic»** лучше работают как описание жанра (`editorial nature photography`), а не как бренд:
бренд-имена модели иногда цензурируют или выкидывают в водяные знаки.

## EN, для SDXL / Flux / ComfyUI (positive)

```
extreme macro photograph of a single forest mushroom, low angle at ground level,
a dense cloud of spores bursting from under the gills, backlit by a shaft of sunlight
through the canopy, spores glowing as bright specks,volumetric god rays, dust motes,
shallow depth of field, tack-sharp focus on the gills and cap edge, creamy bokeh of ferns
and moss behind, damp forest floor, dew droplets, dark green shadows, warm amber rim light,
editorial nature photography, natural colour, ultra detailed textures,
85mm macro lens, f/4, 1/500 s, iso 200, tripod, focus stacking look, high dynamic range
```

## EN (negative)

```
illustration, cartoon, cgi, plastic, waxy, oversaturated, hdr halos, watermark, text, logo,
blurry subject, focus miss, flat lighting, grey sky, studio backdrop, spider webs clutter,
extra mushrooms, human hands, insects swarming
```

## Midjourney v7

```
extreme macro of a forest mushroom, spores bursting from under the cap, backlit by a sunbeam,
god rays, glowing dust, shallow depth of field, sharp gills, bokeh ferns, damp moss floor,
editorial nature photography --ar 3:2 --style raw --v 7
```

## Параметры для локальной генерации (ComfyUI / A1111)

| Параметр | Значение | Почему |
|---|---|---|
| модель | SDXL-база или Flux.1-dev | лучше всех держат «фото-реализм» и макро-текстуры |
| шаг | 1024×768 → hires fix ×2 → 3072×2304 → upscale ×2.6 → ~8000 px | «8k» = апскейл, не промпт |
| sampler / steps | DPM++ 2M Karras, 30–40 шагов | стабильные макро-детали |
| CFG | 4–6 | выше — пластик и пересвет |
| denoise (hires) | 0.35–0.45 | больше — теряется рисунок пластинок |
| апскейлер | 4x-UltraSharp / RealESRGAN + tile | без размножения «шумовых» спор |
| seed | фиксировать после удачного кадра | воспроизводимость |

## Два технических предупреждения

1. **Движение и резкость конфликтуют.** Моушен-блюр на спорах почти всегда съедает резкость шляпки. Надёжный
   приём: сгенерировать резкий кадр, затем отдельный слой «спор в движении» и склеить их (или img2img только
   по области спор с маской).
2. **Споры как «искры»** получаются, только если свет именно контровой: слова `backlit`, `volumetric god rays`,
   `rim light` обязательны, иначе модель рисует просто пыль перед камерой.

## Если нужен результат без модели

Процедурно (Pillow/CSS) можно собрать **постер в стиле макро-силуэта**: тёмный кадр, шляпка с пластинками,
лучи и точки спор с размытием. Это будет честная стилизация, а не фото — могу сделать как отдельный вариант.
