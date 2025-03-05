import os
from encryptor import encrypt_file

# Get the absolute path of the project root
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))  
CONFIG_DIR = os.path.join(BASE_DIR, "config")  

instances_file = os.path.join(CONFIG_DIR, "instances.txt")
encrypted_file = os.path.join(CONFIG_DIR, "instances.enc")

if not os.path.exists(instances_file):
    print(f"Error: {instances_file} not found.")
else:
    encrypt_file(instances_file, encrypted_file)
    print(f"File encrypted successfully: {encrypted_file}")


