import os
from fastapi import FastAPI

app = FastAPI()


@app.get("/")
async def root():
    return {"message": "v2"}

@app.get("/env")
async def env():
    return os.environ
