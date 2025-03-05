import os
from encryptor import decrypt_file

# Get the absolute path of the project root
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))  
CONFIG_DIR = os.path.join(BASE_DIR, "config")  
encrypted_file = os.path.join(CONFIG_DIR, "instances.enc")

if not os.path.exists(encrypted_file):
    print(f"Error: {encrypted_file} not found.")
else:
    decrypt_file(encrypted_file)
    print(f"File encrypted successfully: {encrypted_file}")
