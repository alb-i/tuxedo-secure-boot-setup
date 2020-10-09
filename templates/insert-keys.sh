#!/bin/bash

sudo efi-updatevar -f db.auth db
sudo efi-updatevar -f KEK.auth KEK
sudo efi-updatevar -f PK.auth PK

