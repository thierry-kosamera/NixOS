#! /usr/bin/env nix-shell
#! nix-shell -i python3 --packages python3Packages.pynacl python3Packages.pyyaml

# ---- Import needed modules ----
import argparse
import os
import traceback
import yaml

from base64 import b64decode

# NaCL modules
import nacl # type: ignore
from nacl.encoding import RawEncoder # type: ignore
from nacl.public   import PrivateKey, SealedBox  # type: ignore
from nacl.secret   import SecretBox  # type: ignore
from nacl.signing  import SigningKey # type: ignore

from typing import Any, Dict


# ---- Useful variables ----

key_length: int = nacl.bindings.crypto_box_PUBLICKEYBYTES  #this is equal to 32
private_key_signature: bytes = b'\x00\x00\x00\x40'


def args_parser() -> argparse.ArgumentParser:
  parser = argparse.ArgumentParser()
  parser.add_argument("--server_name", type=str, required=True, dest='server_name',
                      help="name of the server we are running this script on")
  parser.add_argument("--secrets_path", type=str, required=True, dest='secrets_path',
                      help="path to the folder where we should look for the generated secrets")
  parser.add_argument("--output_path", type=str, required=True, dest='output_path',
                      help="path to the folder where we should output the secrets to")
  parser.add_argument("--private_key_file", type=str, required=True, dest='private_key_file',
                      help="private key file of the server")
  return parser


def decrypt(box: Any,
            ciphertext: str) -> bytes:
  return box.decrypt(b64decode(ciphertext)); # type: ignore

# Takes a b64-encoded string encrypted with the server's private key
# and returns the decrypted bytes.
def decrypt_shared_key(privkey: PrivateKey,
                       encrypted_string: str) -> bytes:
  box = SealedBox(privkey)
  return decrypt(box, encrypted_string)


# Takes a b64-encoded string encrypted with the given shared key and decrypts it.
def decrypt_server_secrets(box_key: bytes,
                           encrypted_secrets: str) -> str:
  box = SecretBox(box_key)
  return decrypt(box, encrypted_secrets).decode('utf-8')


# takes an ed25519 private key string
# returns an appropriately transformed PrivateKey object, usable to create a NaCl SealedBox
def extract_curve_private_key(priv_key) -> PrivateKey:
  # Strip off the first and last line
  openssh_priv_key = '\n'.join(priv_key.splitlines()[:-1][1:])
  openssh_priv_bytes = b64decode(openssh_priv_key)
  priv_bytes = bytes_after(private_key_signature, key_length, openssh_priv_bytes)
  nacl_priv_ed = SigningKey(seed=priv_bytes, encoder=RawEncoder)
  return nacl_priv_ed.to_curve25519_private_key()


# Extract length bytes counting from the first occurence of the given signature.
def bytes_after(signature: bytes,
                length: int,
                bytestr: bytes) -> bytes:
  start = bytestr.find(signature) + len(signature)
  return bytestr[start:start+length]


# ---- main script (Author : Aurélien Michon) ----

def do_write_file(output_path: str,
                  secret: Dict):
  with open(output_path, 'w') as f:
    f.write(secret['content'])
    print(f"Wrote {output_path}")


def write_files(output_path_prefix: str,
                secrets: Dict):
  for secret in secrets.values():
    output_path = os.path.join(output_path_prefix, secret['path'])
    try:
      do_write_file(output_path, secret)
    except:
      print(f"ERROR : failed to write to {secret['path']}")
      print(traceback.format_exc())


def validate_paths(private_key_file, secrets_path, output_path):
  if not os.path.isfile(private_key_file):
    raise Exception(f'Cannot open the private key file ({private_key_file})')
  if not os.path.isdir(secrets_path):
    raise Exception(f'The secrets path is not a directory ({secrets_path})')
  if not os.path.isdir(output_path):
    raise Exception(f'The output path is not a directory ({output_path})')


def main():
  args = args_parser().parse_args()
  validate_paths(args.private_key_file, args.secrets_path, args.output_path)

  key_file     = os.path.join(args.secrets_path,
                              f"{args.server_name}-key.enc")
  secrets_file = os.path.join(args.secrets_path,
                              f"{args.server_name}-secrets.yml.enc")

  if os.path.isfile(key_file) and os.path.isfile(secrets_file):
    with open(args.private_key_file, 'r') as f :
      server_privk = f.read()
    with open(key_file, 'r') as f:
      encrypted_box_key = f.read()
    with open(secrets_file, 'r') as f:
      encrypted_secrets = f.read()

    # decrypt the symmetric key using the server private key
    key = decrypt_shared_key(extract_curve_private_key(server_privk),
                             encrypted_box_key)
    # then use it to decrypt the secrets
    decrypted_secrets = yaml.safe_load(decrypt_server_secrets(key,
                                                              encrypted_secrets))
    write_files(args.output_path, decrypted_secrets)


if __name__ == "__main__":
  main()

