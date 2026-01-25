#!/bin/bash
# Ziti Access Revocation Tool (Short Pump IT)

TARGET_IDENTITY=$1
ACTION=$2

if [[ -z "$TARGET_IDENTITY" ]]; then
    echo "Usage: ./revoke-access.sh <identity_name> [disable|remove-role|delete]"
    exit 1
fi

case $ACTION in
  "disable")
    # Level 1: Temporary Suspension (Identity remains, but cannot connect)
    ziti edge update identity "$TARGET_IDENTITY" --is-disabled true
    echo "🛡️ Access suspended for $TARGET_IDENTITY"
    ;;

  "remove-role")
    # Level 2: Target Removal (Removes them from a specific group like #mobile-users)
    ziti edge update identity "$TARGET_IDENTITY" --remove-role-attributes "mobile-users"
    echo "✂️ Removed $TARGET_IDENTITY from the 'mobile-users' role."
    ;;

  "delete")
    # Level 3: Hard Revocation (Completely erases the identity from the fabric)
    ziti edge delete identity "$TARGET_IDENTITY"
    echo "🚫 Identity $TARGET_IDENTITY has been permanently deleted."
    ;;

  *)
    echo "Invalid action. Use: disable, remove-role, or delete."
    ;;
esac