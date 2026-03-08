#!/bin/bash
# PDFForge Backend Starter Script

echo "🚀 Starting PDFForge Backend..."
echo ""

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3 not found. Please install Python 3.9+"
    exit 1
fi

cd "$(dirname "$0")"

# Create venv if not exists
if [ ! -d "venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv venv
fi

# Activate venv
source venv/bin/activate

# Install dependencies
echo "📥 Installing dependencies..."
pip install -r requirements.txt -q

echo ""
echo "✅ Backend starting at http://localhost:8000"
echo "📖 API docs at http://localhost:8000/docs"
echo ""

# Start server
python main.py
