FROM python:3.12-slim

# System deps for weasyprint
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpango-1.0-0 libpangoft2-1.0-0 libpangocairo-1.0-0 \
    libgdk-pixbuf-2.0-0 libcairo2 libglib2.0-0 \
    libffi8 libharfbuzz0b libfontconfig1 shared-mime-info \
    fonts-noto fonts-noto-cjk fonts-noto-extra \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
