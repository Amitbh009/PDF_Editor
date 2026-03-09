"""
PDFForge Backend v3 - OCR-Powered Word-like PDF Editor
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Pipeline:
  1. Upload PDF
  2. /ocr/{file_id}  → Tesseract OCR creates a searchable text layer
                       Returns per-word bounding boxes for click-to-edit
  3. /edit_text      → Redact original word region + write new text
  4. /insert_text    → Type new text anywhere (like Word blank doc)
  5. /find_replace   → Ctrl+H across all pages
  6. /delete_region  → Erase any rectangle
  7. /undo /redo     → Full undo history
  All other Word-like ops: annotate, rotate, watermark, protect, merge, split
"""

from fastapi import FastAPI, UploadFile, File, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel
from typing import Optional, List, Dict, Tuple
import os, uuid, shutil, base64, json, io, time

app = FastAPI(title="PDFForge API v3", version="3.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True,
                   allow_methods=["*"], allow_headers=["*"])

UPLOAD_DIR  = "uploads"
HISTORY_DIR = "history"
OCR_DIR     = "ocr_data"
for d in [UPLOAD_DIR, HISTORY_DIR, OCR_DIR]:
    os.makedirs(d, exist_ok=True)

# Undo / Redo stacks  {file_id: [snapshot_path, ...]}
_undo: Dict[str, List[str]] = {}
_redo: Dict[str, List[str]] = {}
# OCR cache  {file_id: { page: [WordBox,...] }}
_ocr_cache: Dict[str, Dict[int, list]] = {}
MAX_UNDO = 30


# ══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def fp(file_id: str) -> str:
    p = os.path.join(UPLOAD_DIR, f"{file_id}.pdf")
    if not os.path.exists(p):
        raise HTTPException(404, f"File not found: {file_id}")
    return p

def rgb(hex_color: str) -> Tuple[float,float,float]:
    h = hex_color.lstrip("#")
    return (int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255)

def snap(file_id: str) -> None:
    """Save undo snapshot before any mutation."""
    path = fp(file_id)
    sid = os.path.join(HISTORY_DIR, f"{file_id}_{uuid.uuid4()}.pdf")
    shutil.copy2(path, sid)
    _undo.setdefault(file_id, []).append(sid)
    if len(_undo[file_id]) > MAX_UNDO:
        old = _undo[file_id].pop(0)
        try: os.remove(old)
        except: pass
    # clear redo
    for p2 in _redo.pop(file_id, []):
        try: os.remove(p2)
        except: pass
    # invalidate OCR cache for this file so it re-runs after edits
    _ocr_cache.pop(file_id, None)


# ══════════════════════════════════════════════════════════════════════════════
# MODELS
# ══════════════════════════════════════════════════════════════════════════════

class TextEditReq(BaseModel):
    file_id: str
    page_number: int
    search_text: str
    replacement_text: str
    # tight region around the word (PDF coords)
    region_x0: Optional[float] = None
    region_y0: Optional[float] = None
    region_x1: Optional[float] = None
    region_y1: Optional[float] = None
    font_name:  Optional[str]   = "helv"
    font_size:  Optional[float] = None
    font_color: Optional[str]   = None
    bold:       Optional[bool]  = None
    italic:     Optional[bool]  = None

class InsertTextReq(BaseModel):
    file_id: str
    page_number: int
    text: str
    x: float; y: float
    width:  Optional[float] = 250
    height: Optional[float] = 60
    font_name:  Optional[str]   = "helv"
    font_size:  Optional[float] = 12
    font_color: Optional[str]   = "#000000"
    bg_color:   Optional[str]   = None
    bold:   Optional[bool] = False
    italic: Optional[bool] = False
    align:  Optional[str]  = "left"   # left|center|right

class FindReplaceReq(BaseModel):
    file_id: str
    find_text: str
    replace_text: str
    case_sensitive: Optional[bool] = False
    all_pages:  Optional[bool] = True
    page_number: Optional[int] = None

class DeleteRegionReq(BaseModel):
    file_id: str
    page_number: int
    x0: float; y0: float; x1: float; y1: float
    fill_color: Optional[str] = "#FFFFFF"

class AnnotateReq(BaseModel):
    file_id: str
    page_number: int
    annotation_type: str
    content:  Optional[str]   = None
    x: float; y: float
    width:  Optional[float] = None
    height: Optional[float] = None
    color:     Optional[str] = "#FFFF00"
    font_size: Optional[int] = 12

class InsertImageReq(BaseModel):
    file_id: str; page_number: int
    image_base64: str
    x: float; y: float; width: float; height: float

class RotateReq(BaseModel):
    file_id: str; page_number: int; degrees: int

class MergeReq(BaseModel):
    file_ids: List[str]

class SplitReq(BaseModel):
    file_id: str; page_ranges: List[str]

class WatermarkReq(BaseModel):
    file_id: str; text: str
    opacity:   Optional[float] = 0.3
    font_size: Optional[int]   = 40
    color:     Optional[str]   = "#CC0000"

class PasswordReq(BaseModel):
    file_id: str; password: str

class AddPageReq(BaseModel):
    file_id: str; after_page: int

class DeletePageReq(BaseModel):
    file_id: str; page_number: int


# ══════════════════════════════════════════════════════════════════════════════
# OCR ENGINE
# ══════════════════════════════════════════════════════════════════════════════

def _ocr_page(file_id: str, page_number: int, dpi: int = 200) -> list:
    """
    Run Tesseract OCR on one page.
    Returns list of word dicts with PDF-coordinate bounding boxes.
    """
    import fitz, pytesseract
    from PIL import Image
    import numpy as np

    cache = _ocr_cache.setdefault(file_id, {})
    if page_number in cache:
        return cache[page_number]

    path = fp(file_id)
    doc  = fitz.open(path)
    page = doc[page_number - 1]

    # Render page to image at high DPI
    mat = fitz.Matrix(dpi / 72, dpi / 72)
    pix = page.get_pixmap(matrix=mat, alpha=False)
    img_bytes = pix.tobytes("png")
    pil_img = Image.open(io.BytesIO(img_bytes))

    pdf_w = page.rect.width
    pdf_h = page.rect.height
    img_w, img_h = pil_img.size
    doc.close()

    # Tesseract with bounding box data
    tsr = pytesseract.image_to_data(
        pil_img,
        lang="eng",
        config="--psm 6 --oem 3",
        output_type=pytesseract.Output.DICT
    )

    words = []
    n = len(tsr["text"])
    for i in range(n):
        word = tsr["text"][i].strip()
        if not word:
            continue
        conf = int(tsr["conf"][i])
        if conf < 20:   # skip very low-confidence hits
            continue

        # Tesseract gives pixel coords (top-left origin)
        px0 = tsr["left"][i]
        py0 = tsr["top"][i]
        pw  = tsr["width"][i]
        ph  = tsr["height"][i]
        px1 = px0 + pw
        py1 = py0 + ph

        # Convert pixel → PDF coords (PDF origin is bottom-left but fitz uses top-left internally)
        x0 = px0 * pdf_w / img_w
        y0 = py0 * pdf_h / img_h
        x1 = px1 * pdf_w / img_w
        y1 = py1 * pdf_h / img_h

        words.append({
            "text": word,
            "x0": round(x0, 2), "y0": round(y0, 2),
            "x1": round(x1, 2), "y1": round(y1, 2),
            "conf": conf,
            "block_num": tsr["block_num"][i],
            "par_num":   tsr["par_num"][i],
            "line_num":  tsr["line_num"][i],
            "word_num":  tsr["word_num"][i],
        })

    # Estimate font size from typical word height
    if words:
        heights = [w["y1"] - w["y0"] for w in words if w["y1"] > w["y0"]]
        med_h = sorted(heights)[len(heights)//2] if heights else 12
        # PDF points: typical body text height ≈ font_size * 1.2
        est_size = round(med_h / 1.2, 1)
        for w in words:
            w["est_size"] = est_size

    cache[page_number] = words
    return words


def _embed_text_layer(file_id: str) -> None:
    """
    Full OCR pass on all pages — embeds invisible text layer so
    the PDF becomes searchable (like Adobe Acrobat OCR).
    Uses PyMuPDF to write word boxes as invisible text spans.
    """
    import fitz, pytesseract
    from PIL import Image

    path = fp(file_id)
    doc  = fitz.open(path)
    DPI  = 200

    for page_idx in range(len(doc)):
        page = doc[page_idx]

        # Already has real text? skip
        existing = page.get_text("words")
        if len(existing) > 10:
            continue

        mat = fitz.Matrix(DPI/72, DPI/72)
        pix = page.get_pixmap(matrix=mat, alpha=False)
        from PIL import Image as PILImage
        pil_img = PILImage.open(io.BytesIO(pix.tobytes("png")))

        pdf_w = page.rect.width
        pdf_h = page.rect.height
        img_w, img_h = pil_img.size

        tsr = pytesseract.image_to_data(
            pil_img, lang="eng",
            config="--psm 6 --oem 3",
            output_type=pytesseract.Output.DICT
        )

        n = len(tsr["text"])
        for i in range(n):
            word = tsr["text"][i].strip()
            if not word or int(tsr["conf"][i]) < 30:
                continue
            px0 = tsr["left"][i];  py0 = tsr["top"][i]
            pw  = tsr["width"][i]; ph  = tsr["height"][i]

            x0 = px0 * pdf_w / img_w; y0 = py0 * pdf_h / img_h
            x1 = (px0+pw) * pdf_w / img_w; y1 = (py0+ph) * pdf_h / img_h
            rect = fitz.Rect(x0, y0, x1, y1)
            fs = max(6, round((y1-y0) / 1.2, 1))

            # Insert invisible text (render mode 3 = invisible)
            page.insert_text(
                fitz.Point(x0, y1 - 1),
                word,
                fontsize=fs,
                color=(0, 0, 0),
                render_mode=3,   # invisible but selectable/searchable
            )

    doc.save(path)
    doc.close()
    _ocr_cache.pop(file_id, None)   # invalidate so next /text call re-runs


# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — Basic
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/")
def root():
    return {"message": "PDFForge API v3 (OCR-powered)", "version": "3.0.0"}

@app.get("/health")
def health():
    return {"status": "healthy"}


# ── Upload ────────────────────────────────────────────────────────────────────

@app.post("/upload")
async def upload_pdf(file: UploadFile = File(...)):
    if not file.filename.lower().endswith(".pdf"):
        raise HTTPException(400, "Only PDF files accepted")
    file_id = str(uuid.uuid4())
    dest = os.path.join(UPLOAD_DIR, f"{file_id}.pdf")
    with open(dest, "wb") as f:
        shutil.copyfileobj(file.file, f)
    try:
        import fitz
        doc = fitz.open(dest)
        page_count = len(doc)
        meta = doc.metadata or {}
        doc.close()
    except Exception:
        page_count = 0; meta = {}
    return {
        "file_id": file_id, "filename": file.filename,
        "page_count": page_count,
        "title": meta.get("title","") or file.filename,
        "author": meta.get("author","") or "Unknown",
        "size_bytes": os.path.getsize(dest),
        "needs_ocr": True,   # client should call /ocr after upload
    }


# ── Info ──────────────────────────────────────────────────────────────────────

@app.get("/info/{file_id}")
def get_info(file_id: str):
    import fitz
    doc = fitz.open(fp(file_id))
    meta = doc.metadata or {}
    pages = [{"page": i+1, "width": p.rect.width, "height": p.rect.height}
             for i, p in enumerate(doc)]
    result = {
        "file_id": file_id,
        "page_count": len(doc),
        "title": meta.get("title",""),
        "author": meta.get("author",""),
        "pages": pages,
        "undo_available": len(_undo.get(file_id,[])) > 0,
        "redo_available": len(_redo.get(file_id,[])) > 0,
    }
    doc.close()
    return result


# ── Page render ───────────────────────────────────────────────────────────────

@app.get("/page/{file_id}/{page_number}")
def get_page(file_id: str, page_number: int, dpi: int = 150):
    import fitz
    doc = fitz.open(fp(file_id))
    if page_number < 1 or page_number > len(doc):
        raise HTTPException(400, "Invalid page number")
    page = doc[page_number - 1]
    mat = fitz.Matrix(dpi/72, dpi/72)
    pix = page.get_pixmap(matrix=mat, alpha=False)
    b64 = base64.b64encode(pix.tobytes("png")).decode()
    w, h = page.rect.width, page.rect.height
    rw, rh = pix.width, pix.height
    doc.close()
    return {
        "page": page_number, "image_base64": b64,
        "pdf_width": w, "pdf_height": h,
        "render_width": rw, "render_height": rh,
    }


# ══════════════════════════════════════════════════════════════════════════════
# ★★★ OCR — THE KEY ENDPOINT
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/ocr/{file_id}")
def run_ocr(file_id: str, embed: bool = True, page: Optional[int] = None):
    """
    Run Tesseract OCR on the PDF.
    - embed=True  : writes invisible text layer INTO the PDF (makes it searchable,
                    like Adobe Acrobat's "Make Searchable" feature).
    - page=N      : OCR only page N (faster), otherwise all pages.
    Returns word-level bounding boxes so Flutter can render click-to-edit overlays.
    """
    path = fp(file_id)
    import fitz

    doc = fitz.open(path)
    total_pages = len(doc)
    doc.close()

    pages_to_ocr = [page] if page else list(range(1, total_pages + 1))

    if embed:
        # Full embed pass — writes invisible text layer
        # We do this per-page to return per-page results too
        snap_done = False
        for pn in pages_to_ocr:
            if not snap_done:
                snap(file_id); snap_done = True
        _embed_text_layer(file_id)

    # Now return word boxes for each requested page
    all_pages_words = {}
    for pn in pages_to_ocr:
        words = _ocr_page(file_id, pn)
        all_pages_words[pn] = words

    total_words = sum(len(v) for v in all_pages_words.values())
    return {
        "success": True,
        "file_id": file_id,
        "pages_processed": len(pages_to_ocr),
        "total_words_found": total_words,
        "pages": all_pages_words,
    }


# ── Text blocks (for click-to-edit overlay) ──────────────────────────────────

@app.get("/text/{file_id}/{page_number}")
def get_text_blocks(file_id: str, page_number: int):
    """
    Returns word bounding boxes for the page.
    First tries the embedded text layer (post-OCR).
    Falls back to Tesseract OCR if no text layer exists.
    """
    import fitz
    path = fp(file_id)
    doc  = fitz.open(path)
    if page_number < 1 or page_number > len(doc):
        raise HTTPException(400, "Invalid page number")
    page = doc[page_number - 1]

    # Try native text extraction first (works on native/OCR-embedded PDFs)
    raw_words = page.get_text("words")  # [(x0,y0,x1,y1,text,block,line,word)]
    doc.close()

    if len(raw_words) > 5:
        blocks = [
            {
                "text": w[4], "x0": round(w[0],2), "y0": round(w[1],2),
                "x1": round(w[2],2), "y1": round(w[3],2),
                "font": "embedded", "size": round((w[3]-w[1])/1.2, 1),
                "color": 0, "flags": 0, "conf": 95,
            }
            for w in raw_words if w[4].strip()
        ]
    else:
        # No text layer — run Tesseract
        blocks = _ocr_page(file_id, page_number)

    return {"page": page_number, "blocks": blocks, "count": len(blocks)}


# ══════════════════════════════════════════════════════════════════════════════
# ★ INLINE TEXT EDIT  (click word → edit like Word)
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/edit_text")
def edit_text(req: TextEditReq):
    """
    Replace a word/phrase on a PDF page.
    Strategy:
      1. Find all visual occurrences using PyMuPDF search
         (works on both native text PDFs and OCR-embedded PDFs)
      2. White-out (redact) the original region
      3. Insert replacement text at the same baseline with matching style
    """
    path = fp(req.file_id)
    snap(req.file_id)
    import fitz

    doc  = fitz.open(path)
    page = doc[req.page_number - 1]
    replaced = 0

    # -- Find by text search (works after OCR embed)
    hits = page.search_for(req.search_text)

    # -- If search found nothing, try using OCR word boxes directly
    if not hits and req.region_x0 is not None:
        hits = [fitz.Rect(req.region_x0, req.region_y0, req.region_x1, req.region_y1)]

    for rect in hits:
        # Optional: restrict to a region
        if req.region_x0 is not None:
            region = fitz.Rect(req.region_x0, req.region_y0, req.region_x1, req.region_y1)
            if not rect.intersects(region):
                continue

        # Estimate style from surrounding text
        orig_size  = req.font_size or _estimate_font_size(page, rect)
        orig_color = rgb(req.font_color) if req.font_color else (0.0, 0.0, 0.0)
        font_name  = req.font_name or "helv"
        if req.bold and font_name == "helv":   font_name = "helvb"
        if req.italic and font_name == "helv": font_name = "helvi"

        # 1. Redact original
        page.add_redact_annot(rect, fill=(1, 1, 1))
        page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_NONE)

        # 2. Insert replacement at same baseline
        if req.replacement_text.strip():
            page.insert_text(
                fitz.Point(rect.x0, rect.y1 - 1),
                req.replacement_text,
                fontsize=orig_size,
                fontname=font_name,
                color=orig_color,
            )
        replaced += 1

    doc.save(path)
    doc.close()
    return {"success": True, "file_id": req.file_id, "replaced": replaced}


def _estimate_font_size(page, rect) -> float:
    """Estimate font size from word height or nearby text."""
    h = rect.height
    if h > 3:
        return round(h / 1.2, 1)
    return 11.0


# ══════════════════════════════════════════════════════════════════════════════
# ★ INSERT NEW TEXT BLOCK
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/insert_text")
def insert_text(req: InsertTextReq):
    path = fp(req.file_id)
    snap(req.file_id)
    import fitz

    doc  = fitz.open(path)
    page = doc[req.page_number - 1]
    color = rgb(req.font_color or "#000000")
    rect  = fitz.Rect(req.x, req.y, req.x + (req.width or 250), req.y + (req.height or 60))

    if req.bg_color:
        page.draw_rect(rect, color=None, fill=rgb(req.bg_color))

    fn = req.font_name or "helv"
    if req.bold and req.italic: fn = "helvbi" if fn == "helv" else fn
    elif req.bold:   fn = "helvb"  if fn == "helv" else fn
    elif req.italic: fn = "helvi"  if fn == "helv" else fn

    align_map = {"left": 0, "center": 1, "right": 2}
    page.insert_textbox(
        rect, req.text,
        fontsize=req.font_size or 12,
        fontname=fn, color=color,
        align=align_map.get(req.align or "left", 0),
    )
    doc.save(path)
    doc.close()
    return {"success": True, "file_id": req.file_id}


# ══════════════════════════════════════════════════════════════════════════════
# ★ FIND & REPLACE  (Ctrl+H)
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/find_replace")
def find_replace(req: FindReplaceReq):
    path = fp(req.file_id)
    snap(req.file_id)
    import fitz

    doc   = fitz.open(path)
    total = 0
    pages = range(len(doc)) if req.all_pages else [req.page_number - 1]

    for pi in pages:
        page = doc[pi]
        hits = page.search_for(req.find_text)
        for rect in hits:
            orig_size = _estimate_font_size(page, rect)
            page.add_redact_annot(rect, fill=(1, 1, 1))
            page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_NONE)
            if req.replace_text.strip():
                page.insert_text(
                    fitz.Point(rect.x0, rect.y1 - 1),
                    req.replace_text,
                    fontsize=orig_size,
                    color=(0, 0, 0),
                )
            total += 1

    doc.save(path)
    doc.close()
    return {"success": True, "file_id": req.file_id, "total_replaced": total}


# ══════════════════════════════════════════════════════════════════════════════
# ★ DELETE REGION
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/delete_region")
def delete_region(req: DeleteRegionReq):
    path = fp(req.file_id)
    snap(req.file_id)
    import fitz
    doc  = fitz.open(path)
    page = doc[req.page_number - 1]
    rect = fitz.Rect(req.x0, req.y0, req.x1, req.y1)
    page.add_redact_annot(rect, fill=rgb(req.fill_color or "#FFFFFF"))
    page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_NONE)
    doc.save(path)
    doc.close()
    return {"success": True}


# ══════════════════════════════════════════════════════════════════════════════
# ★ UNDO / REDO
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/undo/{file_id}")
def undo(file_id: str):
    path  = fp(file_id)
    stack = _undo.get(file_id, [])
    if not stack:
        raise HTTPException(400, "Nothing to undo")
    snap_path = stack.pop()
    # save current → redo
    rid = os.path.join(HISTORY_DIR, f"{file_id}_redo_{uuid.uuid4()}.pdf")
    shutil.copy2(path, rid)
    _redo.setdefault(file_id, []).append(rid)
    shutil.copy2(snap_path, path)
    try: os.remove(snap_path)
    except: pass
    _ocr_cache.pop(file_id, None)
    return {"success": True, "undo_remaining": len(stack)}

@app.post("/redo/{file_id}")
def redo(file_id: str):
    path  = fp(file_id)
    stack = _redo.get(file_id, [])
    if not stack:
        raise HTTPException(400, "Nothing to redo")
    snap_path = stack.pop()
    snap(file_id)   # save current state as undo
    shutil.copy2(snap_path, path)
    try: os.remove(snap_path)
    except: pass
    _ocr_cache.pop(file_id, None)
    return {"success": True, "redo_remaining": len(stack)}


# ══════════════════════════════════════════════════════════════════════════════
# ANNOTATIONS
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/annotate")
def annotate(req: AnnotateReq):
    path = fp(req.file_id)
    snap(req.file_id)
    import fitz
    doc  = fitz.open(path)
    page = doc[req.page_number - 1]
    t    = req.annotation_type
    r    = fitz.Rect(req.x, req.y,
                     req.x + (req.width or 100),
                     req.y + (req.height or 20))
    if   t == "highlight":     page.add_highlight_annot(r)
    elif t == "underline":     page.add_underline_annot(r)
    elif t == "strikethrough": page.add_strikeout_annot(r)
    elif t == "freetext":
        page.add_freetext_annot(
            fitz.Rect(req.x, req.y, req.x+(req.width or 150), req.y+(req.height or 30)),
            req.content or "", fontsize=req.font_size or 12)
    doc.save(path)
    doc.close()
    return {"success": True}


# ══════════════════════════════════════════════════════════════════════════════
# PAGE OPERATIONS
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/rotate")
def rotate(req: RotateReq):
    path = fp(req.file_id); snap(req.file_id)
    import fitz
    doc = fitz.open(path)
    doc[req.page_number - 1].set_rotation(req.degrees)
    doc.save(path); doc.close()
    return {"success": True}

@app.post("/add_page")
def add_page(req: AddPageReq):
    path = fp(req.file_id); snap(req.file_id)
    import fitz
    doc = fitz.open(path)
    doc.new_page(pno=req.after_page)
    doc.save(path); doc.close()
    return {"success": True}

@app.post("/delete_page")
def delete_page(req: DeletePageReq):
    path = fp(req.file_id); snap(req.file_id)
    import fitz
    doc = fitz.open(path)
    if len(doc) <= 1: raise HTTPException(400, "Cannot delete the only page")
    doc.delete_page(req.page_number - 1)
    doc.save(path); doc.close()
    return {"success": True}


# ══════════════════════════════════════════════════════════════════════════════
# MERGE / SPLIT / WATERMARK / PROTECT / DOWNLOAD
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/merge")
def merge(req: MergeReq):
    import fitz
    out = fitz.open()
    for fid in req.file_ids:
        src = fitz.open(fp(fid)); out.insert_pdf(src); src.close()
    oid = str(uuid.uuid4())
    out.save(os.path.join(UPLOAD_DIR, f"{oid}.pdf")); out.close()
    return {"success": True, "file_id": oid}

@app.post("/split")
def split(req: SplitReq):
    import fitz
    src = fitz.open(fp(req.file_id)); result = []
    for rng in req.page_ranges:
        parts = rng.split("-")
        s = int(parts[0]) - 1; e = int(parts[1]) - 1 if len(parts) > 1 else s
        out = fitz.open(); out.insert_pdf(src, from_page=s, to_page=e)
        oid = str(uuid.uuid4())
        out.save(os.path.join(UPLOAD_DIR, f"{oid}.pdf")); out.close()
        result.append({"file_id": oid, "pages": rng})
    src.close()
    return {"success": True, "parts": result}

@app.post("/watermark")
def watermark(req: WatermarkReq):
    path = fp(req.file_id); snap(req.file_id)
    import fitz
    doc = fitz.open(path); c = rgb(req.color or "#CC0000")
    for page in doc:
        r = page.rect
        page.insert_text(fitz.Point(r.width/4, r.height/2),
                         req.text, fontsize=req.font_size or 40,
                         color=c, rotate=45)
    doc.save(path); doc.close()
    return {"success": True}

@app.post("/protect")
def protect(req: PasswordReq):
    path = fp(req.file_id)
    import fitz
    doc = fitz.open(path)
    perm = fitz.PDF_PERM_PRINT | fitz.PDF_PERM_COPY
    doc.save(path, encryption=fitz.PDF_ENCRYPT_AES_256,
             user_pw=req.password, owner_pw=req.password, permissions=perm)
    doc.close()
    return {"success": True}

@app.post("/insert_image")
def insert_image(req: InsertImageReq):
    path = fp(req.file_id); snap(req.file_id)
    import fitz
    doc  = fitz.open(path)
    page = doc[req.page_number - 1]
    img_bytes = base64.b64decode(req.image_base64)
    page.insert_image(fitz.Rect(req.x, req.y, req.x+req.width, req.y+req.height),
                      stream=img_bytes)
    doc.save(path); doc.close()
    return {"success": True}

@app.get("/download/{file_id}")
def download(file_id: str):
    return FileResponse(fp(file_id), media_type="application/pdf",
                        filename=f"pdfforge_{file_id}.pdf")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)