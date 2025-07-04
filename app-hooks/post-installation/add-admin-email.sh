#!/bin/bash

if [ -n "${NEXTCLOUD_ADMIN_EMAIL+x}" ] && [ -n "${NEXTCLOUD_ADMIN_USER+x}" ]; then
    echo "Setting admin user email to: $NEXTCLOUD_ADMIN_EMAIL"
  
    php occ user:setting "$NEXTCLOUD_ADMIN_USER" settings email "$NEXTCLOUD_ADMIN_EMAIL"
    
    if [ $? -eq 0 ]; then
        echo "Admin email set successfully"
    else
        echo "Failed to set admin email"
    fi
else
    echo "NEXTCLOUD_ADMIN_EMAIL not set, skipping admin email configuration"
fi