#!/usr/bin/env python3
"""
CPU Inference Server for ARM64 Oracle Node - ONNX Optimized
Lightweight OpenAI-compatible API server for ARM deployment with ONNX Runtime for faster inference.
Requires: pip install onnxruntime transformers flask
Assumes ONNX model exported via optimum (e.g., optimum-cli export onnx --model microsoft/DialoGPT-small onnx_model/)
"""

import os
import json
import time
import uuid
from datetime import datetime
from flask import Flask, request, jsonify, Response
from transformers import AutoTokenizer
import onnxruntime as ort
import numpy as np

app = Flask(__name__)

# Configuration
MODEL_NAME = os.getenv("MODEL_NAME", "microsoft/DialoGPT-small")
ONNX_MODEL_PATH = os.getenv("ONNX_MODEL_PATH", f"./onnx_model/{MODEL_NAME}")
MAX_LENGTH = int(os.getenv("MAX_LENGTH", "512"))
DEVICE = os.getenv("DEVICE", "cpu")
PORT = int(os.getenv("PORT", "8000"))

print(f"🚀 Starting ONNX CPU Inference Server")
print(f"📱 Model: {MODEL_NAME}")
print(f"🖥️  Device: {DEVICE}")
print(f"🔢 Max Length: {MAX_LENGTH}")
print(f"📁 ONNX Path: {ONNX_MODEL_PATH}")

# Global model storage
session = None
tokenizer = None

def load_model():
    """Load the ONNX model and tokenizer"""
    global session, tokenizer
    
    try:
        print(f"📦 Loading tokenizer: {MODEL_NAME}")
        tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
        if tokenizer.pad_token is None:
            tokenizer.pad_token = tokenizer.eos_token
        
        print(f"📦 Loading ONNX model from {ONNX_MODEL_PATH}")
        # Use CPU provider for ARM optimization
        providers = ['CPUExecutionProvider']
        session = ort.InferenceSession(f"{ONNX_MODEL_PATH}/model.onnx", providers=providers)
        
        print(f"✅ ONNX model loaded successfully")
        return True
        
    except Exception as e:
        print(f"❌ Error loading ONNX model: {e}")
        return False

def generate_response(messages, max_tokens=150, temperature=0.7):
    """Generate response using ONNX model"""
    try:
        if not session or not tokenizer:
            return "Error: Model not loaded"
        
        # Convert messages to prompt
        prompt = ""
        for msg in messages:
            role = msg.get("role", "user")
            content = msg.get("content", "")
            if role == "user":
                prompt += f"User: {content}\n"
            elif role == "assistant":
                prompt += f"Assistant: {content}\n"
        
        prompt += "Assistant: "
        
        # Tokenize
        inputs = tokenizer(prompt, return_tensors="np", max_length=MAX_LENGTH, truncation=True)
        input_ids = inputs["input_ids"]
        
        # ONNX inference (simplified; for full generation, use loop for tokens)
        # Note: For autoregressive models, implement token-by-token generation
        outputs = session.run(None, {"input_ids": input_ids})[0]
        generated_ids = np.argmax(outputs, axis=-1)
        
        # Decode (take last max_tokens)
        response_ids = generated_ids[0][-max_tokens:]
        response = tokenizer.decode(response_ids, skip_special_tokens=True)
        
        # Extract assistant response
        if "Assistant: " in response:
            response = response.split("Assistant: ")[-1].strip()
        
        return response
        
    except Exception as e:
        print(f"❌ ONNX generation error: {e}")
        return f"Error generating response: {str(e)}"

@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint"""
    status = "healthy" if session is not None else "loading"
    return jsonify({
        "status": status,
        "model": MODEL_NAME,
        "device": DEVICE,
        "onnx": True,
        "timestamp": datetime.utcnow().isoformat()
    })

@app.route("/v1/models", methods=["GET"])
def list_models():
    """OpenAI-compatible models endpoint"""
    return jsonify({
        "object": "list",
        "data": [
            {
                "id": MODEL_NAME.split("/")[-1],
                "object": "model",
                "created": int(time.time()),
                "owned_by": "local",
                "permission": [],
                "root": MODEL_NAME,
                "parent": None
            }
        ]
    })

@app.route("/v1/chat/completions", methods=["POST"])
def chat_completions():
    """OpenAI-compatible chat completions endpoint"""
    try:
        data = request.get_json()
        
        messages = data.get("messages", [])
        max_tokens = data.get("max_tokens", 150)
        temperature = data.get("temperature", 0.7)
        stream = data.get("stream", False)
        
        if not messages:
            return jsonify({"error": "No messages provided"}), 400
        
        if not session:
            return jsonify({"error": "Model not loaded"}), 503
        
        # Generate response
        response_text = generate_response(messages, max_tokens, temperature)
        
        # Create OpenAI-compatible response
        response_data = {
            "id": f"chatcmpl-{uuid.uuid4().hex[:8]}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": MODEL_NAME.split("/")[-1],
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": response_text
                    },
                    "finish_reason": "stop"
                }
            ],
            "usage": {
                "prompt_tokens": len(tokenizer.encode(str(messages))),
                "completion_tokens": len(tokenizer.encode(response_text)),
                "total_tokens": len(tokenizer.encode(str(messages) + response_text))
            }
        }
        
        if stream:
            # Simple streaming response
            def generate_stream():
                yield f"data: {json.dumps(response_data)}\n\n"
                yield "data: [DONE]\n\n"
            
            return Response(generate_stream(), mimetype="text/plain")
        
        return jsonify(response_data)
        
    except Exception as e:
        print(f"❌ Chat completion error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/v1/completions", methods=["POST"])
def completions():
    """OpenAI-compatible completions endpoint"""
    try:
        data = request.get_json()
        
        prompt = data.get("prompt", "")
        max_tokens = data.get("max_tokens", 150)
        temperature = data.get("temperature", 0.7)
        
        if not prompt:
            return jsonify({"error": "No prompt provided"}), 400
        
        if not session:
            return jsonify({"error": "Model not loaded"}), 503
        
        # Convert to message format
        messages = [{"role": "user", "content": prompt}]
        response_text = generate_response(messages, max_tokens, temperature)
        
        return jsonify({
            "id": f"cmpl-{uuid.uuid4().hex[:8]}",
            "object": "text_completion",
            "created": int(time.time()),
            "model": MODEL_NAME.split("/")[-1],
            "choices": [
                {
                    "text": response_text,
                    "index": 0,
                    "logprobs": None,
                    "finish_reason": "stop"
                }
            ],
            "usage": {
                "prompt_tokens": len(tokenizer.encode(prompt)),
                "completion_tokens": len(tokenizer.encode(response_text)),
                "total_tokens": len(tokenizer.encode(prompt + response_text))
            }
        })
        
    except Exception as e:
        print(f"❌ Completion error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/", methods=["GET"])
def root():
    """Root endpoint"""
    return jsonify({
        "message": "ONNX CPU Inference Server for ARM64",
        "model": MODEL_NAME,
        "device": DEVICE,
        "onnx": True,
        "status": "running" if session else "loading",
        "endpoints": [
            "/health",
            "/v1/models",
            "/v1/chat/completions",
            "/v1/completions"
        ]
    })

if __name__ == "__main__":
    print(f"🔄 Starting ONNX model loading process...")
    
    # Load model in background
    import threading
    
    def load_model_background():
        success = load_model()
        if success:
            print(f"✅ ONNX model ready for inference")
        else:
            print(f"❌ ONNX model loading failed")
    
    # Start model loading in background
    loading_thread = threading.Thread(target=load_model_background)
    loading_thread.daemon = True
    loading_thread.start()
    
    print(f"🌐 Starting server on port {PORT}")
    app.run(host="0.0.0.0", port=PORT, debug=False)