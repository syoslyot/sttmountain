FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/
COPY scripts/ ./scripts/

RUN mkdir -p /app/app/static/gpx /app/app/static/maps

COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x entrypoint.sh

EXPOSE 8000
HEALTHCHECK --interval=5s --timeout=3s --retries=10 --start-period=15s \
  CMD python -c "import socket; s=socket.socket(); s.connect(('localhost',8000)); s.close()"

CMD ["./entrypoint.sh"]
