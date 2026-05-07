FROM public.ecr.aws/docker/library/python:3.11-slim

WORKDIR /app

COPY risk-assessment/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY _shared /app/_shared
COPY risk-assessment/agent.py risk-assessment/server.py /app/

EXPOSE 8080

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8080"]
