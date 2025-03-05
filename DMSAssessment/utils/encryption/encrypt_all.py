import os
import sys
from encryptor import encrypt_file

def encrypt_all_txt_files(directory):
    """Encrypt all .txt files in the specified directory."""
    if not os.path.exists(directory):
        print(f"Error: Directory '{directory}' not found.")
        return

    for filename in os.listdir(directory):
        if filename.endswith(".txt"):
            txt_path = os.path.join(directory, filename)
            enc_path = os.path.join(directory, filename.replace(".txt", ".enc"))

            encrypt_file(txt_path, enc_path)
            print(f"Encrypted: {txt_path} → {enc_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python encrypt_all.py <path_to_config_directory>")
    else:
        encrypt_all_txt_files(sys.argv[1])
