#!/usr/bin/env python3
from cryptography.fernet import Fernet
print("This is provided to generate a predefined key for encrypting credentials sent between zmeventnotification and mlapi.")
print("You can run this as many times as you want, it does not 'remember' anything.")
print("See default configuration for description and example. Encryption key -->")
print("")
key = Fernet.generate_key()
print("{}".format(key.decode('utf-8')))
