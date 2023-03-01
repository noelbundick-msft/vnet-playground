import os
from fastapi import FastAPI

app = FastAPI()


@app.get("/")
async def root():
    return {"message": "Hello World v2"}

@app.get("/env")
async def env():
    return os.environ
