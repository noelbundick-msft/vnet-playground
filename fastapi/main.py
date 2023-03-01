import os
from fastapi import FastAPI

app = FastAPI()


@app.get("/")
async def root():
    return {"message": "v3"}

@app.get("/env")
async def env():
    return os.environ
