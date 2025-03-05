import os
from cryptography.fernet import Fernet
from pathlib import Path

# Get the absolute path of the project root
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))  
CONFIG_DIR = os.path.join(BASE_DIR, "config")  
#configure the desired Path  
KEY_FILE = "C:\\Python\\DMSAssessment\\utils\\encryption\\encryption.key"

def generate_key():
    """Generate and save a key if it does not exist."""
    if not os.path.exists(KEY_FILE):
        key = Fernet.generate_key()
        with open(KEY_FILE, "wb") as key_file:
            key_file.write(key)
            print("Encryption key generated successfully.")

#generate_key()

def load_key():
    """Load the encryption key, generating it if missing."""
    if not os.path.exists(KEY_FILE):
        print("Key file missing! Generating a new one...")
        generate_key()
    with open(KEY_FILE, "rb") as key_file:
        return key_file.read()

def generate_key():
    """Generate and save an encryption key if it does not exist."""
    if not os.path.exists(KEY_FILE):
        key = Fernet.generate_key()
        with open(KEY_FILE, "wb") as key_file:
            key_file.write(key)

def load_key():
    """Load the encryption key from the file, generating it if missing."""
    if not os.path.exists(KEY_FILE):
        generate_key()
    with open(KEY_FILE, "rb") as key_file:
        return key_file.read()

def encrypt_file(input_file):
    """Encrypt a specified text file containing connection details."""
    # Convert input to a Path object
    input_path = Path(input_file)

    # Validate that the file exists
    if not input_path.exists():
        print(f"Error: File '{input_path}' not found.")
        return

    key = load_key()
    cipher = Fernet(key)

    # Read the plaintext file
    with open(input_path, "rb") as file:
        plaintext = file.read()
    
    encrypted_data = cipher.encrypt(plaintext)

    # Create encrypted file path with .enc extension
    output_file = input_path.with_suffix(".enc")

    with open(output_file, "wb") as file:
        file.write(encrypted_data)

    print(f"Encrypted: {input_path} → {output_file}")

    # Optional: Remove the original file
    os.remove(input_path)
    print(f"Deleted: {input_path}")

    return output_file


def decrypt_file(input_file, output_file=None):
    """Decrypt an encrypted file and return the plaintext content."""
    key = load_key()
    cipher = Fernet(key)

    with open(input_file, "rb") as file:
        encrypted_data = file.read()
    
    decrypted_data = cipher.decrypt(encrypted_data).decode()

    if output_file:
        with open(output_file, "w", encoding="utf-8") as file:  # Ensure correct text encoding
            file.write(decrypted_data)
        print(f"Decrypted content saved to: {output_file}")

    return decrypted_data


# Ensure the key exists when the script runs
if not os.path.exists(KEY_FILE):
        print("Key file missing! Generating a new one...")
        generate_key()
