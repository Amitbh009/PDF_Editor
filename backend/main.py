"""
PDFForge Backend - FastAPI Server
Handles all PDF processing operations
"""

from fastapi import FastAPI, UploadFile, File, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel
from typing import Optional, List
import os
import uuid
import shutil
import base64

app = FastAPI(
    title="PDFForge API",
    description="Backend API for PDFForge - Cross-platform PDF Editor",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = "uploads"
OUTPUT_DIR = "outputs"
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)


# ─── Models ───────────────────────────────────────────────────────────────────

class AnnotationRequest(BaseModel):
    file_id: str
    page_number: int
    annotation_type: str  # "text" | "highlight" | "underline" | "strikethrough" | "draw"
    content: Optional[str] = None
    x: float
    y: float
    width: Optional[float] = None
    height: Optional[float] = None
    color: Optional[str] = "#FFFF00"
    font_size: Optional[int] = 12

class TextEditRequest(BaseModel):
    file_id: str
    page_number: int
    original_text: str
    new_text: str
    x: float
    y: float

class MergeRequest(BaseModel):
    file_ids: List[str]
    output_name: Optional[str] = "merged.pdf"

class SplitRequest(BaseModel):
    file_id: str
    page_ranges: List[str]  # e.g. ["1-3", "4-6"]

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
    degrees: int  # 90, 180, 270


# ─── Helpers ──────────────────────────────────────────────────────────────────

def get_file_path(file_id: str) -> str:
    path = os.path.join(UPLOAD_DIR, f"{file_id}.pdf")
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail=f"File not found: {file_id}")
    return path


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.get("/")
def root():
    return {"message": "PDFForge API is running 🚀", "version": "1.0.0"}


@app.get("/health")
def health():
    return {"status": "healthy"}


# ── Upload ────────────────────────────────────────────────────────────────────

@app.post("/upload")
async def upload_pdf(file: UploadFile = File(...)):
    """Upload a PDF file and return a file_id for future operations."""
    if not file.filename.endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are accepted")

    file_id = str(uuid.uuid4())
    file_path = os.path.join(UPLOAD_DIR, f"{file_id}.pdf")

    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    # Get basic info
    try:
        import pypdf
        reader = pypdf.PdfReader(file_path)
        page_count = len(reader.pages)
        metadata = reader.metadata or {}
        title = metadata.get("/Title", file.filename)
        author = metadata.get("/Author", "Unknown")
    except Exception:
        page_count = 0
        title = file.filename
        author = "Unknown"

    return {
        "file_id": file_id,
        "filename": file.filename,
        "page_count": page_count,
        "title": title,
        "author": author,
        "size_bytes": os.path.getsize(file_path)
    }


# ── Info & Preview ────────────────────────────────────────────────────────────

@app.get("/info/{file_id}")
def get_pdf_info(file_id: str):
    """Get metadata and page count for a PDF."""
    file_path = get_file_path(file_id)
    try:
        import pypdf
        reader = pypdf.PdfReader(file_path)
        meta = reader.metadata or {}
        pages_info = []
        for i, page in enumerate(reader.pages):
            box = page.mediabox
            pages_info.append({
                "page": i + 1,
                "width": float(box.width),
                "height": float(box.height),
            })
        return {
            "file_id": file_id,
            "page_count": len(reader.pages),
            "title": meta.get("/Title", ""),
            "author": meta.get("/Author", ""),
            "subject": meta.get("/Subject", ""),
            "creator": meta.get("/Creator", ""),
            "pages": pages_info
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/page/{file_id}/{page_number}")
def get_page_image(file_id: str, page_number: int, dpi: int = 150):
    """Render a PDF page as a PNG image (base64 encoded)."""
    file_path = get_file_path(file_id)
    try:
        import fitz  # PyMuPDF
        doc = fitz.open(file_path)
        if page_number < 1 or page_number > len(doc):
            raise HTTPException(status_code=400, detail="Invalid page number")
        page = doc[page_number - 1]
        mat = fitz.Matrix(dpi / 72, dpi / 72)
        pix = page.get_pixmap(matrix=mat)
        img_bytes = pix.tobytes("png")
        img_b64 = base64.b64encode(img_bytes).decode("utf-8")
        doc.close()
        return {"page": page_number, "image_base64": img_b64, "format": "png"}
    except ImportError:
        raise HTTPException(status_code=501, detail="PyMuPDF not installed. Run: pip install pymupdf")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/text/{file_id}/{page_number}")
def extract_page_text(file_id: str, page_number: int):
    """Extract text from a specific page."""
    file_path = get_file_path(file_id)
    try:
        import pdfplumber
        with pdfplumber.open(file_path) as pdf:
            if page_number < 1 or page_number > len(pdf.pages):
                raise HTTPException(status_code=400, detail="Invalid page number")
            page = pdf.pages[page_number - 1]
            text = page.extract_text() or ""
            words = page.extract_words() or []
            return {
                "page": page_number,
                "text": text,
                "words": [{"text": w["text"], "x0": w["x0"], "y0": w["top"],
                           "x1": w["x1"], "y1": w["bottom"]} for w in words]
            }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Annotations ───────────────────────────────────────────────────────────────

@app.post("/annotate")
def add_annotation(req: AnnotationRequest):
    """Add a text annotation, highlight, or drawing to a PDF page."""
    file_path = get_file_path(req.file_id)
    output_id = str(uuid.uuid4())
    output_path = os.path.join(OUTPUT_DIR, f"{output_id}.pdf")

    try:
        import fitz
        doc = fitz.open(file_path)
        page = doc[req.page_number - 1]

        if req.annotation_type == "text":
            point = fitz.Point(req.x, req.y)
            annot = page.add_text_annot(point, req.content or "")
        elif req.annotation_type == "highlight":
            rect = fitz.Rect(req.x, req.y, req.x + (req.width or 100), req.y + (req.height or 20))
            annot = page.add_highlight_annot(rect)
        elif req.annotation_type == "underline":
            rect = fitz.Rect(req.x, req.y, req.x + (req.width or 100), req.y + (req.height or 20))
            annot = page.add_underline_annot(rect)
        elif req.annotation_type == "strikethrough":
            rect = fitz.Rect(req.x, req.y, req.x + (req.width or 100), req.y + (req.height or 20))
            annot = page.add_strikeout_annot(rect)
        elif req.annotation_type == "freetext":
            rect = fitz.Rect(req.x, req.y, req.x + (req.width or 150), req.y + (req.height or 30))
            annot = page.add_freetext_annot(rect, req.content or "", fontsize=req.font_size or 12)
        else:
            raise HTTPException(status_code=400, detail=f"Unknown annotation type: {req.annotation_type}")

        doc.save(output_path)
        doc.close()

        # Replace original
        shutil.move(output_path, file_path)
        return {"success": True, "file_id": req.file_id, "message": "Annotation added"}

    except ImportError:
        raise HTTPException(status_code=501, detail="PyMuPDF not installed. Run: pip install pymupdf")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Merge / Split ─────────────────────────────────────────────────────────────

@app.post("/merge")
def merge_pdfs(req: MergeRequest):
    """Merge multiple PDFs into one."""
    try:
        import pypdf
        writer = pypdf.PdfWriter()
        for fid in req.file_ids:
            path = get_file_path(fid)
            reader = pypdf.PdfReader(path)
            for page in reader.pages:
                writer.add_page(page)

        output_id = str(uuid.uuid4())
        output_path = os.path.join(OUTPUT_DIR, f"{output_id}.pdf")
        with open(output_path, "wb") as f:
            writer.write(f)

        # Register merged file as a new upload
        dest = os.path.join(UPLOAD_DIR, f"{output_id}.pdf")
        shutil.copy(output_path, dest)

        return {"success": True, "file_id": output_id, "page_count": len(writer.pages)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/split")
def split_pdf(req: SplitRequest):
    """Split a PDF into parts based on page ranges."""
    file_path = get_file_path(req.file_id)
    try:
        import pypdf
        reader = pypdf.PdfReader(file_path)
        result_ids = []

        for range_str in req.page_ranges:
            parts = range_str.split("-")
            start = int(parts[0]) - 1
            end = int(parts[1]) if len(parts) > 1 else int(parts[0])

            writer = pypdf.PdfWriter()
            for i in range(start, end):
                if i < len(reader.pages):
                    writer.add_page(reader.pages[i])

            out_id = str(uuid.uuid4())
            out_path = os.path.join(UPLOAD_DIR, f"{out_id}.pdf")
            with open(out_path, "wb") as f:
                writer.write(f)
            result_ids.append({"file_id": out_id, "pages": range_str})

        return {"success": True, "parts": result_ids}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Rotate ────────────────────────────────────────────────────────────────────

@app.post("/rotate")
def rotate_page(req: RotateRequest):
    """Rotate a specific page."""
    file_path = get_file_path(req.file_id)
    try:
        import pypdf
        reader = pypdf.PdfReader(file_path)
        writer = pypdf.PdfWriter()
        for i, page in enumerate(reader.pages):
            if i == req.page_number - 1:
                page.rotate(req.degrees)
            writer.add_page(page)
        with open(file_path, "wb") as f:
            writer.write(f)
        return {"success": True, "file_id": req.file_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Watermark ─────────────────────────────────────────────────────────────────

@app.post("/watermark")
def add_watermark(req: WatermarkRequest):
    """Add a text watermark to all pages."""
    file_path = get_file_path(req.file_id)
    try:
        import fitz
        doc = fitz.open(file_path)
        for page in doc:
            rect = page.rect
            # Parse color
            color_hex = req.color.lstrip("#")
            r = int(color_hex[0:2], 16) / 255
            g = int(color_hex[2:4], 16) / 255
            b = int(color_hex[4:6], 16) / 255
            page.insert_text(
                fitz.Point(rect.width / 4, rect.height / 2),
                req.text,
                fontsize=req.font_size,
                color=(r, g, b),
                rotate=45
            )
        doc.save(file_path)
        doc.close()
        return {"success": True, "file_id": req.file_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Password ──────────────────────────────────────────────────────────────────

@app.post("/protect")
def protect_pdf(req: PasswordRequest):
    """Password protect a PDF."""
    file_path = get_file_path(req.file_id)
    try:
        import pypdf
        reader = pypdf.PdfReader(file_path)
        writer = pypdf.PdfWriter()
        for page in reader.pages:
            writer.add_page(page)
        writer.encrypt(req.password)
        with open(file_path, "wb") as f:
            writer.write(f)
        return {"success": True, "file_id": req.file_id, "message": "PDF protected"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── Download ──────────────────────────────────────────────────────────────────

@app.get("/download/{file_id}")
def download_pdf(file_id: str):
    """Download a processed PDF file."""
    file_path = get_file_path(file_id)
    return FileResponse(
        file_path,
        media_type="application/pdf",
        filename=f"pdfforge_{file_id}.pdf"
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
