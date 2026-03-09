"""
PDFForge Backend v2 - FastAPI Server
Full Word-like PDF editing: inline text edit, find & replace,
insert text blocks, images, undo history, formatting controls.
"""

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
import os, uuid, shutil, base64, copy, json

app = FastAPI(title="PDFForge API v2", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = "uploads"
OUTPUT_DIR = "outputs"
HISTORY_DIR = "history"   # undo snapshots
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(HISTORY_DIR, exist_ok=True)

# In-memory undo stacks: { file_id: [path_snapshot, ...] }
_undo_stacks: Dict[str, List[str]] = {}
_redo_stacks: Dict[str, List[str]] = {}
MAX_UNDO = 30


# ═══════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════

def get_file_path(file_id: str) -> str:
    path = os.path.join(UPLOAD_DIR, f"{file_id}.pdf")
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail=f"File not found: {file_id}")
    return path

def hex_to_rgb(hex_color: str):
    h = hex_color.lstrip("#")
    return (int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255)

def _save_snapshot(file_id: str, file_path: str):
    """Save a snapshot for undo before mutating the file."""
    snap_id = str(uuid.uuid4())
    snap_path = os.path.join(HISTORY_DIR, f"{file_id}_{snap_id}.pdf")
    shutil.copy2(file_path, snap_path)
    if file_id not in _undo_stacks:
        _undo_stacks[file_id] = []
    _undo_stacks[file_id].append(snap_path)
    if len(_undo_stacks[file_id]) > MAX_UNDO:
        old = _undo_stacks[file_id].pop(0)
        try: os.remove(old)
        except: pass
    # Clear redo stack on new action
    if file_id in _redo_stacks:
        for p in _redo_stacks[file_id]:
            try: os.remove(p)
            except: pass
        _redo_stacks[file_id] = []


# ═══════════════════════════════════════════════════════════════════
# MODELS
# ═══════════════════════════════════════════════════════════════════

class AnnotationRequest(BaseModel):
    file_id: str
    page_number: int
    annotation_type: str
    content: Optional[str] = None
    x: float
    y: float
    width: Optional[float] = None
    height: Optional[float] = None
    color: Optional[str] = "#FFFF00"
    font_size: Optional[int] = 12

class InlineTextEditRequest(BaseModel):
    """Edit existing text directly on the PDF page (Word-style)."""
    file_id: str
    page_number: int
    # The word/block to find and replace
    search_text: str
    replacement_text: str
    # Optionally restrict to a region (PDF coords, 0,0 = bottom-left)
    region_x0: Optional[float] = None
    region_y0: Optional[float] = None
    region_x1: Optional[float] = None
    region_y1: Optional[float] = None
    # Formatting to apply to the replacement
    font_name: Optional[str] = "helv"   # helv=Helvetica, timr=Times, cour=Courier
    font_size: Optional[float] = None   # None = match original
    font_color: Optional[str] = None    # None = match original
    bold: Optional[bool] = None
    italic: Optional[bool] = None

class InsertTextBlockRequest(BaseModel):
    """Insert a new text block anywhere on a page (like typing in Word)."""
    file_id: str
    page_number: int
    text: str
    x: float
    y: float
    width: Optional[float] = 200
    height: Optional[float] = 50
    font_name: Optional[str] = "helv"
    font_size: Optional[float] = 12
    font_color: Optional[str] = "#000000"
    bg_color: Optional[str] = None   # None = transparent
    bold: Optional[bool] = False
    italic: Optional[bool] = False
    align: Optional[str] = "left"   # left | center | right

class FindReplaceRequest(BaseModel):
    """Find & Replace across entire document (like Ctrl+H in Word)."""
    file_id: str
    find_text: str
    replace_text: str
    case_sensitive: Optional[bool] = False
    whole_word: Optional[bool] = False
    all_pages: Optional[bool] = True
    page_number: Optional[int] = None   # used if all_pages=False

class InsertImageRequest(BaseModel):
    """Insert an image at a position on a page."""
    file_id: str
    page_number: int
    image_base64: str
    x: float
    y: float
    width: float
    height: float

class DeleteTextRequest(BaseModel):
    """Delete/redact a text region from a page."""
    file_id: str
    page_number: int
    x0: float
    y0: float
    x1: float
    y1: float
    fill_color: Optional[str] = "#FFFFFF"  # white = invisible redaction

class FormatTextRequest(BaseModel):
    """Apply bold/italic/color/size to existing text in a region."""
    file_id: str
    page_number: int
    x0: float
    y0: float
    x1: float
    y1: float
    font_size: Optional[float] = None
    font_color: Optional[str] = None
    bold: Optional[bool] = None
    underline: Optional[bool] = None

class MergeRequest(BaseModel):
    file_ids: List[str]

class SplitRequest(BaseModel):
    file_id: str
    page_ranges: List[str]

class WatermarkRequest(BaseModel):
    file_id: str
    text: str
    opacity: Optional[float] = 0.3
    font_size: Optional[int] = 40
    color: Optional[str] = "#FF0000"

class PasswordRequest(BaseModel):
    file_id: str
    password: str

class RotateRequest(BaseModel):
    file_id: str
    page_number: int
    degrees: int

class AddPageRequest(BaseModel):
    file_id: str
    after_page: int   # insert blank page after this page (0 = prepend)

class DeletePageRequest(BaseModel):
    file_id: str
    page_number: int


# ═══════════════════════════════════════════════════════════════════
# BASIC ROUTES
# ═══════════════════════════════════════════════════════════════════

@app.get("/")
def root():
    return {"message": "PDFForge API v2 running", "version": "2.0.0"}

@app.get("/health")
def health():
    return {"status": "healthy"}


# ═══════════════════════════════════════════════════════════════════
# UPLOAD
# ═══════════════════════════════════════════════════════════════════

@app.post("/upload")
async def upload_pdf(file: UploadFile = File(...)):
    if not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files accepted")
    file_id = str(uuid.uuid4())
    file_path = os.path.join(UPLOAD_DIR, f"{file_id}.pdf")
    with open(file_path, "wb") as buf:
        shutil.copyfileobj(file.file, buf)
    try:
        import fitz
        doc = fitz.open(file_path)
        page_count = len(doc)
        meta = doc.metadata or {}
        doc.close()
        title = meta.get("title") or file.filename
        author = meta.get("author") or "Unknown"
    except Exception:
        page_count = 0; title = file.filename; author = "Unknown"
    return {
        "file_id": file_id, "filename": file.filename,
        "page_count": page_count, "title": title, "author": author,
        "size_bytes": os.path.getsize(file_path)
    }


# ═══════════════════════════════════════════════════════════════════
# INFO & PAGE RENDER
# ═══════════════════════════════════════════════════════════════════

@app.get("/info/{file_id}")
def get_pdf_info(file_id: str):
    file_path = get_file_path(file_id)
    import fitz
    doc = fitz.open(file_path)
    meta = doc.metadata or {}
    pages_info = []
    for i, page in enumerate(doc):
        r = page.rect
        pages_info.append({"page": i+1, "width": r.width, "height": r.height})
    result = {
        "file_id": file_id, "page_count": len(doc),
        "title": meta.get("title",""), "author": meta.get("author",""),
        "pages": pages_info,
        "undo_available": len(_undo_stacks.get(file_id,[])) > 0,
        "redo_available": len(_redo_stacks.get(file_id,[])) > 0,
    }
    doc.close()
    return result

@app.get("/page/{file_id}/{page_number}")
def get_page_image(file_id: str, page_number: int, dpi: int = 150):
    file_path = get_file_path(file_id)
    import fitz
    doc = fitz.open(file_path)
    if page_number < 1 or page_number > len(doc):
        raise HTTPException(status_code=400, detail="Invalid page number")
    page = doc[page_number - 1]
    mat = fitz.Matrix(dpi/72, dpi/72)
    pix = page.get_pixmap(matrix=mat, alpha=False)
    img_b64 = base64.b64encode(pix.tobytes("png")).decode()
    w, h = page.rect.width, page.rect.height
    doc.close()
    return {
        "page": page_number, "image_base64": img_b64,
        "format": "png", "pdf_width": w, "pdf_height": h,
        "render_width": pix.width, "render_height": pix.height
    }


# ═══════════════════════════════════════════════════════════════════
# TEXT EXTRACTION (for click-to-edit)
# ═══════════════════════════════════════════════════════════════════

@app.get("/text/{file_id}/{page_number}")
def extract_page_text(file_id: str, page_number: int):
    """
    Returns all text blocks with their exact bounding boxes.
    Flutter uses this to draw clickable text overlays.
    """
    file_path = get_file_path(file_id)
    import fitz
    doc = fitz.open(file_path)
    if page_number < 1 or page_number > len(doc):
        raise HTTPException(status_code=400, detail="Invalid page number")
    page = doc[page_number - 1]
    blocks = []
    # dict level gives per-character info
    page_dict = page.get_text("rawdict", flags=fitz.TEXT_PRESERVE_WHITESPACE)
    for block in page_dict.get("blocks", []):
        if block.get("type") != 0:  # 0=text, 1=image
            continue
        for line in block.get("lines", []):
            for span in line.get("spans", []):
                text = span.get("text","").strip()
                if not text:
                    continue
                bbox = span.get("bbox", [0,0,0,0])
                blocks.append({
                    "text": text,
                    "x0": bbox[0], "y0": bbox[1],
                    "x1": bbox[2], "y1": bbox[3],
                    "font": span.get("font",""),
                    "size": span.get("size", 12),
                    "color": span.get("color", 0),   # int RGB
                    "flags": span.get("flags", 0),   # bold/italic flags
                })
    doc.close()
    return {"page": page_number, "blocks": blocks}


# ═══════════════════════════════════════════════════════════════════
# ★ INLINE TEXT EDITING (Word-style: click text → edit in place)
# ═══════════════════════════════════════════════════════════════════

@app.post("/edit_text")
def edit_text_inline(req: InlineTextEditRequest):
    """
    Replace existing text on a PDF page.
    Strategy:
      1. Find all matching text spans on the page
      2. Redact (white-out) the original text area
      3. Re-insert the replacement text with same or new formatting
    """
    file_path = get_file_path(req.file_id)
    _save_snapshot(req.file_id, file_path)
    import fitz

    doc = fitz.open(file_path)
    page = doc[req.page_number - 1]

    search = req.search_text
    replacement = req.replacement_text
    found_count = 0

    # Find all instances using PyMuPDF search
    instances = page.search_for(search)

    for rect in instances:
        # If region filter provided, skip out-of-region matches
        if req.region_x0 is not None:
            region = fitz.Rect(req.region_x0, req.region_y0, req.region_x1, req.region_y1)
            if not rect.intersects(region):
                continue

        # Get font info from the original span at this location
        orig_size = 12
        orig_color = (0, 0, 0)
        orig_font = req.font_name or "helv"
        page_dict = page.get_text("rawdict", flags=0)
        for block in page_dict.get("blocks",[]):
            if block.get("type") != 0: continue
            for line in block.get("lines",[]):
                for span in line.get("spans",[]):
                    span_rect = fitz.Rect(span["bbox"])
                    if span_rect.intersects(rect):
                        orig_size = span.get("size", 12)
                        c = span.get("color", 0)
                        orig_color = ((c>>16&0xFF)/255, (c>>8&0xFF)/255, (c&0xFF)/255)
                        break

        # Use overrides if provided
        font_size = req.font_size if req.font_size else orig_size
        font_color = hex_to_rgb(req.font_color) if req.font_color else orig_color
        font_name = req.font_name or orig_font

        # Step 1: White-out original text (redact)
        annot = page.add_redact_annot(rect, fill=(1,1,1))

        # Step 2: Apply the redaction
        page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_NONE)

        # Step 3: Insert replacement text at same position
        page.insert_text(
            fitz.Point(rect.x0, rect.y1 - 1),  # baseline point
            replacement,
            fontsize=font_size,
            fontname=font_name,
            color=font_color,
        )
        found_count += 1

    doc.save(file_path)
    doc.close()
    return {
        "success": True,
        "file_id": req.file_id,
        "matches_replaced": found_count,
        "message": f"Replaced {found_count} instance(s) of '{search}'"
    }


# ═══════════════════════════════════════════════════════════════════
# ★ INSERT NEW TEXT BLOCK (like typing new text in Word)
# ═══════════════════════════════════════════════════════════════════

@app.post("/insert_text")
def insert_text_block(req: InsertTextBlockRequest):
    """Insert a new text block at any position on a page."""
    file_path = get_file_path(req.file_id)
    _save_snapshot(req.file_id, file_path)
    import fitz

    doc = fitz.open(file_path)
    page = doc[req.page_number - 1]

    color = hex_to_rgb(req.font_color or "#000000")
    rect = fitz.Rect(req.x, req.y, req.x + (req.width or 200), req.y + (req.height or 50))

    # Background fill
    if req.bg_color:
        bg = hex_to_rgb(req.bg_color)
        page.draw_rect(rect, color=None, fill=bg)

    # Determine font
    font_name = req.font_name or "helv"
    if req.bold and req.italic:
        font_name = "helv" if "helv" in font_name else font_name
    elif req.bold:
        font_name = "helvb" if font_name == "helv" else font_name
    elif req.italic:
        font_name = "helvi" if font_name == "helv" else font_name

    align_map = {"left": 0, "center": 1, "right": 2}
    align = align_map.get(req.align or "left", 0)

    # Insert text in a box (auto-wraps)
    rc = page.insert_textbox(
        rect,
        req.text,
        fontsize=req.font_size or 12,
        fontname=font_name,
        color=color,
        align=align,
    )

    doc.save(file_path)
    doc.close()
    return {"success": True, "file_id": req.file_id, "overflow": rc < 0}


# ═══════════════════════════════════════════════════════════════════
# ★ FIND & REPLACE (Ctrl+H — across whole document)
# ═══════════════════════════════════════════════════════════════════

@app.post("/find_replace")
def find_replace(req: FindReplaceRequest):
    """Find and replace text across the whole PDF (or a single page)."""
    file_path = get_file_path(req.file_id)
    _save_snapshot(req.file_id, file_path)
    import fitz

    doc = fitz.open(file_path)
    total_replaced = 0

    pages_to_process = range(len(doc)) if req.all_pages else [req.page_number - 1]

    for page_idx in pages_to_process:
        page = doc[page_idx]
        find = req.find_text
        replace = req.replacement_text
        flags = 0 if req.case_sensitive else fitz.TEXT_INHIBIT_SPACES

        instances = page.search_for(find, quads=False)
        for rect in instances:
            # Get original font info
            orig_size = 11
            orig_color = (0,0,0)
            page_dict = page.get_text("rawdict", flags=0)
            for block in page_dict.get("blocks",[]):
                if block.get("type") != 0: continue
                for line in block.get("lines",[]):
                    for span in line.get("spans",[]):
                        if fitz.Rect(span["bbox"]).intersects(rect):
                            orig_size = span.get("size", 11)
                            c = span.get("color", 0)
                            orig_color = ((c>>16&0xFF)/255,(c>>8&0xFF)/255,(c&0xFF)/255)
                            break

            page.add_redact_annot(rect, fill=(1,1,1))
            page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_NONE)
            page.insert_text(
                fitz.Point(rect.x0, rect.y1 - 1),
                replace,
                fontsize=orig_size,
                color=orig_color,
            )
            total_replaced += 1

    doc.save(file_path)
    doc.close()
    return {
        "success": True,
        "file_id": req.file_id,
        "total_replaced": total_replaced
    }


# ═══════════════════════════════════════════════════════════════════
# ★ DELETE / REDACT A TEXT REGION
# ═══════════════════════════════════════════════════════════════════

@app.post("/delete_region")
def delete_region(req: DeleteTextRequest):
    """White-out (delete) a rectangular area on a page."""
    file_path = get_file_path(req.file_id)
    _save_snapshot(req.file_id, file_path)
    import fitz

    doc = fitz.open(file_path)
    page = doc[req.page_number - 1]
    fill = hex_to_rgb(req.fill_color or "#FFFFFF")
    rect = fitz.Rect(req.x0, req.y0, req.x1, req.y1)
    page.add_redact_annot(rect, fill=fill)
    page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_NONE)
    doc.save(file_path)
    doc.close()
    return {"success": True, "file_id": req.file_id}


# ═══════════════════════════════════════════════════════════════════
# ★ INSERT IMAGE
# ═══════════════════════════════════════════════════════════════════

@app.post("/insert_image")
def insert_image(req: InsertImageRequest):
    """Insert a base64-encoded image onto a page."""
    file_path = get_file_path(req.file_id)
    _save_snapshot(req.file_id, file_path)
    import fitz

    doc = fitz.open(file_path)
    page = doc[req.page_number - 1]

    img_bytes = base64.b64decode(req.image_base64)
    rect = fitz.Rect(req.x, req.y, req.x + req.width, req.y + req.height)
    page.insert_image(rect, stream=img_bytes)

    doc.save(file_path)
    doc.close()
    return {"success": True, "file_id": req.file_id}


# ═══════════════════════════════════════════════════════════════════
# ★ UNDO / REDO
# ═══════════════════════════════════════════════════════════════════

@app.post("/undo/{file_id}")
def undo(file_id: str):
    """Undo the last edit."""
    file_path = get_file_path(file_id)
    stack = _undo_stacks.get(file_id, [])
    if not stack:
        raise HTTPException(status_code=400, detail="Nothing to undo")
    snap = stack.pop()
    # Save current state to redo
    redo_snap = os.path.join(HISTORY_DIR, f"{file_id}_redo_{uuid.uuid4()}.pdf")
    shutil.copy2(file_path, redo_snap)
    if file_id not in _redo_stacks: _redo_stacks[file_id] = []
    _redo_stacks[file_id].append(redo_snap)
    # Restore snapshot
    shutil.copy2(snap, file_path)
    try: os.remove(snap)
    except: pass
    return {"success": True, "undo_remaining": len(stack)}

@app.post("/redo/{file_id}")
def redo(file_id: str):
    """Redo the last undone edit."""
    file_path = get_file_path(file_id)
    stack = _redo_stacks.get(file_id, [])
    if not stack:
        raise HTTPException(status_code=400, detail="Nothing to redo")
    snap = stack.pop()
    _save_snapshot(file_id, file_path)
    shutil.copy2(snap, file_path)
    try: os.remove(snap)
    except: pass
    return {"success": True, "redo_remaining": len(stack)}


# ═══════════════════════════════════════════════════════════════════
# ANNOTATIONS
# ═══════════════════════════════════════════════════════════════════

@app.post("/annotate")
def add_annotation(req: AnnotationRequest):
    file_path = get_file_path(req.file_id)
    _save_snapshot(req.file_id, file_path)
    import fitz
    doc = fitz.open(file_path)
    page = doc[req.page_number - 1]
    if req.annotation_type == "highlight":
        rect = fitz.Rect(req.x, req.y, req.x+(req.width or 100), req.y+(req.height or 20))
        page.add_highlight_annot(rect)
    elif req.annotation_type == "underline":
        rect = fitz.Rect(req.x, req.y, req.x+(req.width or 100), req.y+(req.height or 20))
        page.add_underline_annot(rect)
    elif req.annotation_type == "strikethrough":
        rect = fitz.Rect(req.x, req.y, req.x+(req.width or 100), req.y+(req.height or 20))
        page.add_strikeout_annot(rect)
    elif req.annotation_type == "freetext":
        rect = fitz.Rect(req.x, req.y, req.x+(req.width or 150), req.y+(req.height or 30))
        page.add_freetext_annot(rect, req.content or "", fontsize=req.font_size or 12)
    doc.save(file_path)
    doc.close()
    return {"success": True, "file_id": req.file_id}


# ═══════════════════════════════════════════════════════════════════
# PAGE OPERATIONS
# ═══════════════════════════════════════════════════════════════════

@app.post("/add_page")
def add_blank_page(req: AddPageRequest):
    """Insert a blank page after the given page number."""
    file_path = get_file_path(req.file_id)
    _save_snapshot(req.file_id, file_path)
    import fitz
    doc = fitz.open(file_path)
    doc.new_page(pno=req.after_page)   # inserts after pno
    doc.save(file_path)
    doc.close()
    return {"success": True, "file_id": req.file_id, "page_count": len(doc)+1}

@app.post("/delete_page")
def delete_page(req: DeletePageRequest):
    """Delete a page from the PDF."""
    file_path = get_file_path(req.file_id)
    _save_snapshot(req.file_id, file_path)
    import fitz
    doc = fitz.open(file_path)
    if len(doc) <= 1:
        raise HTTPException(status_code=400, detail="Cannot delete the only page")
    doc.delete_page(req.page_number - 1)
    doc.save(file_path)
    doc.close()
    return {"success": True, "file_id": req.file_id}

@app.post("/rotate")
def rotate_page(req: RotateRequest):
    file_path = get_file_path(req.file_id)
    _save_snapshot(req.file_id, file_path)
    import fitz
    doc = fitz.open(file_path)
    page = doc[req.page_number - 1]
    page.set_rotation(req.degrees)
    doc.save(file_path)
    doc.close()
    return {"success": True, "file_id": req.file_id}

@app.post("/merge")
def merge_pdfs(req: MergeRequest):
    import fitz
    result = fitz.open()
    for fid in req.file_ids:
        src = fitz.open(get_file_path(fid))
        result.insert_pdf(src)
        src.close()
    out_id = str(uuid.uuid4())
    out_path = os.path.join(UPLOAD_DIR, f"{out_id}.pdf")
    result.save(out_path)
    result.close()
    return {"success": True, "file_id": out_id}

@app.post("/split")
def split_pdf(req: SplitRequest):
    file_path = get_file_path(req.file_id)
    import fitz
    src = fitz.open(file_path)
    result_ids = []
    for range_str in req.page_ranges:
        parts = range_str.split("-")
        start = int(parts[0]) - 1
        end = int(parts[1]) if len(parts) > 1 else int(parts[0])
        out = fitz.open()
        out.insert_pdf(src, from_page=start, to_page=end-1)
        out_id = str(uuid.uuid4())
        out.save(os.path.join(UPLOAD_DIR, f"{out_id}.pdf"))
        out.close()
        result_ids.append({"file_id": out_id, "pages": range_str})
    src.close()
    return {"success": True, "parts": result_ids}

@app.post("/watermark")
def add_watermark(req: WatermarkRequest):
    file_path = get_file_path(req.file_id)
    _save_snapshot(req.file_id, file_path)
    import fitz
    doc = fitz.open(file_path)
    color = hex_to_rgb(req.color or "#FF0000")
    for page in doc:
        rect = page.rect
        page.insert_text(
            fitz.Point(rect.width/4, rect.height/2),
            req.text, fontsize=req.font_size or 40,
            color=color, rotate=45
        )
    doc.save(file_path)
    doc.close()
    return {"success": True, "file_id": req.file_id}

@app.post("/protect")
def protect_pdf(req: PasswordRequest):
    file_path = get_file_path(req.file_id)
    import fitz
    doc = fitz.open(file_path)
    perm = fitz.PDF_PERM_PRINT | fitz.PDF_PERM_COPY
    doc.save(file_path, encryption=fitz.PDF_ENCRYPT_AES_256,
             user_pw=req.password, owner_pw=req.password, permissions=perm)
    doc.close()
    return {"success": True, "file_id": req.file_id}

@app.get("/download/{file_id}")
def download_pdf(file_id: str):
    file_path = get_file_path(file_id)
    return FileResponse(file_path, media_type="application/pdf",
                        filename=f"pdfforge_{file_id}.pdf")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)