#!/usr/bin/env python3
"""
API Key Rotation Script for AI-SWARM-MIAMI-2025
Uses Vault for secure key management and rotation.
WARNING: This script updates Vault secrets; real API rotation requires provider-specific calls.
"""

import os
import sys
import hvac
from datetime import datetime

VAULT_ADDR = os.getenv('VAULT_ADDR', 'http://localhost:8200')
VAULT_TOKEN = os.getenv('VAULT_TOKEN')  # Use AppRole in production
VAULT_PATH = 'secret/api-keys'

def get_vault_client():
    client = hvac.Client(url=VAULT_ADDR)
    if VAULT_TOKEN:
        client.token = VAULT_TOKEN
    else:
        # AppRole auth
        role_id = os.getenv('VAULT_ROLE_ID')
        secret_id = os.getenv('VAULT_SECRET_ID')
        client.auth.approle.login(role_id=role_id, secret_id=secret_id)
    return client

def rotate_key(client, key_name, new_value=None):
    """Rotate a specific API key in Vault."""
    if new_value is None:
        # Generate placeholder new key (in production, call provider API)
        new_value = f"sk-new-{key_name}-{datetime.now().strftime('%Y%m%d%H%M%S')}-placeholder"
        print(f"Generated placeholder for {key_name}: {new_value}")
    
    data = {key_name: new_value}
    client.secrets.kv.v2.create_or_update_secret(path=VAULT_PATH, secret=data)
    print(f"Rotated {key_name} in Vault at {VAULT_PATH}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python key_rotation.py [openrouter|gemini|all]")
        sys.exit(1)
    
    key_type = sys.argv[1]
    client = get_vault_client()
    
    if key_type == 'all' or key_type == 'openrouter':
        rotate_key(client, 'openrouter', 'sk-or-v1-new-random-string')
    
    if key_type == 'all' or key_type == 'gemini':
        rotate_key(client, 'gemini_primary', 'AIzaSy-new-random-string')
        rotate_key(client, 'gemini_secondary', 'AIzaSy-new-random-string-alt')
    
    print("Key rotation complete. Update services and test.")

if __name__ == "__main__":
    main()