from fastapi import FastAPI

app = FastAPI(title="Fides Testing Service")

@app.get("/")
def read_root():
    return {"status": "ok", "service": "fides-testing-service"}

@app.get("/healthz")
def health_check():
    return {"status": "healthy"}
