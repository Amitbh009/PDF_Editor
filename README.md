# PDFForge 📄✏️
### A cross-platform PDF editor for Desktop & Mobile

Built with **Flutter** (UI) + **FastAPI Python** (backend). One codebase targets iOS, Android, Windows, macOS, and Linux.

---

## 🏗️ Architecture

```
pdfeditor/
├── backend/                  ← Python FastAPI backend
│   ├── main.py               ← All PDF processing endpoints
│   └── requirements.txt      ← Python dependencies
│
└── flutter_app/              ← Flutter cross-platform UI
    ├── pubspec.yaml           ← Flutter dependencies
    └── lib/
        ├── main.dart          ← App entry point
        ├── theme/
        │   └── app_theme.dart ← Dark/light themes, colors, fonts
        ├── models/
        │   └── pdf_document.dart ← Data models
        ├── providers/
        │   └── app_providers.dart ← Riverpod state management
        ├── services/
        │   └── api_service.dart  ← HTTP client → backend
        ├── screens/
        │   ├── home_screen.dart  ← File browser / recent docs
        │   └── editor_screen.dart ← Main PDF editor
        └── widgets/
            ├── editor_toolbar.dart      ← Top toolbar
            ├── pdf_viewer_area.dart     ← PDF page rendering + annotations
            ├── page_thumbnail_panel.dart ← Left sidebar
            ├── annotation_tools_panel.dart ← Right panel
            ├── pdf_card.dart            ← File grid card
            ├── empty_state.dart         ← No files state
            ├── watermark_dialog.dart    ← Watermark settings
            └── password_dialog.dart     ← Password protection
```

---

## 🚀 Setup & Run

### Step 1: Backend (Python)

```bash
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate        # macOS/Linux
# venv\Scripts\activate          # Windows

# Install dependencies
pip install -r requirements.txt

# Start the server
python main.py
# Server runs at http://localhost:8000
# API docs at http://localhost:8000/docs
```

### Step 2: Flutter App

```bash
# Install Flutter SDK first: https://flutter.dev/docs/get-started/install

cd flutter_app

# Get dependencies
flutter pub get

# Run on different platforms:
flutter run -d chrome          # Web browser
flutter run -d windows         # Windows desktop
flutter run -d macos           # macOS desktop
flutter run -d linux           # Linux desktop
flutter run -d <device-id>     # iOS or Android device
```

---

## 🔌 API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/upload` | Upload a PDF file |
| GET | `/info/{file_id}` | Get PDF metadata & page count |
| GET | `/page/{file_id}/{page}` | Render page as PNG (base64) |
| GET | `/text/{file_id}/{page}` | Extract text from page |
| POST | `/annotate` | Add highlight/underline/text annotation |
| POST | `/merge` | Merge multiple PDFs |
| POST | `/split` | Split PDF by page ranges |
| POST | `/rotate` | Rotate a page |
| POST | `/watermark` | Add watermark to all pages |
| POST | `/protect` | Password protect PDF |
| GET | `/download/{file_id}` | Download processed PDF |

---

## ✨ Features

### Phase 1 (Included in this starter)
- [x] Open & view PDF files (page by page)
- [x] Page thumbnail sidebar navigation
- [x] Highlight, underline, strikethrough annotations
- [x] Add text notes to any position
- [x] Rotate pages (90°, 180°, 270°)
- [x] Add watermark to all pages
- [x] Password protect PDFs
- [x] Merge multiple PDFs
- [x] Split PDF by page range
- [x] Zoom in/out
- [x] Dark/light theme
- [x] Responsive for mobile + desktop

### Phase 2 (Build next)
- [ ] Real inline text editing (replace existing text)
- [ ] Insert images into pages
- [ ] Digital signatures / e-Sign
- [ ] OCR for scanned PDFs
- [ ] Form filling
- [ ] Cloud sync (Google Drive, Dropbox)
- [ ] Undo/redo history

---

## 📱 Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Android | ✅ Ready | API 21+ |
| iOS | ✅ Ready | iOS 13+ |
| Windows | ✅ Ready | Windows 10+ |
| macOS | ✅ Ready | macOS 10.14+ |
| Linux | ✅ Ready | GTK required |
| Web | ⚠️ Partial | Limited file access |

---

## 🛠️ Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| UI | Flutter 3.19+ | Cross-platform UI |
| State | Riverpod 2 | Reactive state management |
| HTTP | Dio | API communication |
| Backend | FastAPI | PDF processing API |
| PDF render | PyMuPDF (fitz) | Page rendering to images |
| PDF parse | pdfplumber | Text extraction |
| PDF write | pypdf | Merge/split/annotate |
| Watermark | PyMuPDF | Text overlay |
| Storage | Hive | Local document history |

---

## 🔧 Configuration

In `lib/services/api_service.dart`, change the backend URL:

```dart
static const String _baseUrl = 'http://localhost:8000';
// For production:
// static const String _baseUrl = 'https://your-api.com';
```

For mobile devices testing on real hardware, use your machine's local IP:
```dart
static const String _baseUrl = 'http://192.168.1.X:8000';
```

---

## 📦 Building for Production

```bash
# Android APK
flutter build apk --release

# Android App Bundle (for Play Store)
flutter build appbundle --release

# iOS (requires macOS + Xcode)
flutter build ios --release

# Windows EXE
flutter build windows --release

# macOS App
flutter build macos --release

# Linux
flutter build linux --release
```

---

## 🔐 Security Notes

- The backend stores uploaded PDFs in `/uploads` — add authentication for production
- Use HTTPS in production
- Consider adding JWT tokens to API calls
- Implement file cleanup cron jobs for old uploads
