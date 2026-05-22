# Banner image processing

Source files come straight from Pexels (often 5000–7000 px wide, 1–3 MB each).
For web serving they are crunched to:

- Max width 2400 px (preserves aspect ratio, only shrinks — never upscales)
- JPEG quality 80 (high but not visibly lossy for these photos)
- 4:2:0 chroma subsampling (standard web JPEG)
- Progressive (interlaced) JPEG so the image renders incrementally on slow links
- EXIF / colour-profile metadata stripped

Run from this directory (re-runnable; already-small files are left alone):

```sh
mogrify -resize '2400x2400>' -quality 80 -sampling-factor 4:2:0 -interlace Plane -strip *.jpg
```

Notes:

- `mogrify` rewrites files in place — commit before running if you want to compare.
- The `>` flag on the geometry means "only shrink if larger". A 7680 px source
  becomes 2400 px wide; a 1600 px source is untouched.
- Requires ImageMagick (`mogrify` / `magick mogrify`). On macOS: `brew install imagemagick`. On Debian/Ubuntu: `apt install imagemagick`.
- New banners: drop the original JPEG in this folder, add an entry to `banners.json`, run the command.
